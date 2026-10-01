{-# LANGUAGE LambdaCase #-}

module Bepis.Tooling.Postgres.Rehearsal
    ( runRehearsalCommand
    ) where

import Bepis.Tooling.Core.OwnedFile (writeFileAtomic)
import Bepis.Tooling.Postgres.Lifecycle (PostgresError (..))
import Bepis.Tooling.Workspace.State (PathProblem (..), inspectCanonicalPath)
import Control.Concurrent (threadDelay)
import Control.Exception (IOException, bracket, catch, finally, onException, throwIO)
import Control.Monad (forM_, unless, void, when)
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Char8 as ByteString8
import Data.IORef (IORef, newIORef, readIORef, writeIORef)
import Data.List (intercalate, isPrefixOf)
import Data.Time.Clock.POSIX (getPOSIXTime)
import System.Directory
import System.Environment (getEnvironment)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath (normalise, (</>))
import System.IO (hPutStrLn, stderr)
import System.Posix.Files (fileOwner, getFileStatus, setFileMode)
import System.Posix.Process (getProcessGroupIDOf, getProcessID)
import System.Posix.Signals
import System.Posix.Types (ProcessID)
import System.Posix.User (getEffectiveUserID, getLoginName)
import System.Process

data Options = Options
    { workspace :: FilePath
    , predecessorRef :: String
    , runner :: FilePath
    , expectedRunner :: FilePath
    , candidateIhpSource :: FilePath
    , postgresManager :: FilePath
    , recipe :: FilePath
    , keepFailureArtifacts :: Bool
    }

runRehearsalCommand :: [String] -> IO ()
runRehearsalCommand arguments = parse arguments >>= run

parse :: [String] -> IO Options
parse = go (Options "" "" "" "" "" "" "" False)
  where
    go options [] = do
        unless (all (not . null)
            [ workspace options, predecessorRef options, runner options, expectedRunner options
            , candidateIhpSource options, postgresManager options, recipe options
            ]) (reject 64 usage)
        pure options
    go options ("--workspace":value:rest) = go options {workspace = value} rest
    go options ("--from-ref":value:rest) = go options {predecessorRef = value} rest
    go options ("--runner":value:rest) = go options {runner = value} rest
    go options ("--expected-runner":value:rest) = go options {expectedRunner = value} rest
    go options ("--candidate-ihp-source":value:rest) = go options {candidateIhpSource = value} rest
    go options ("--postgres-manager":value:rest) = go options {postgresManager = value} rest
    go options ("--recipe":value:rest) = go options {recipe = value} rest
    go options ("--keep-failure-artifacts":rest) = go options {keepFailureArtifacts = True} rest
    go _ _ = reject 64 usage

usage :: String
usage = "Usage: bepis-postgres rehearsal-run --workspace PATH --from-ref REF --runner PATH --expected-runner PATH --candidate-ihp-source PATH --postgres-manager PATH --recipe PATH [--keep-failure-artifacts]"

run :: Options -> IO ()
run options = do
    canonicalWorkspace <- canonicalizePath (workspace options)
    unless (canonicalWorkspace == normalise (workspace options)) $
        reject 65 "migration-rehearsal: candidate workspace must be canonical"
    canonicalRunner <- canonicalizeRequired "active migrate runner" (runner options)
    canonicalExpected <- canonicalizeRequired "candidate-pinned IHP runner" (expectedRunner options)
    unless (canonicalRunner == canonicalExpected) $ do
        hPutStrLn stderr "migration-rehearsal: active migrate does not match the candidate-pinned IHP runner"
        hPutStrLn stderr ("expected_runner=" <> canonicalExpected)
        hPutStrLn stderr ("active_runner=" <> canonicalRunner)
        reject 69 "migration-rehearsal: refusing unapproved migrate runner"
    canonicalRecipe <- canonicalizeRequired "rehearsal recipe" (recipe options)
    candidateCommit <- gitOutput canonicalWorkspace ["rev-parse", "--verify", "HEAD^{commit}"]
    predecessorCommit <- gitMaybe canonicalWorkspace ["rev-parse", "--verify", "--end-of-options", predecessorRef options <> "^{commit}"]
        >>= maybe (reject 65 ("migration-rehearsal: predecessor ref does not resolve to a commit: " <> predecessorRef options)) pure
    ancestor <- commandSucceeds canonicalWorkspace "git" ["merge-base", "--is-ancestor", predecessorCommit, candidateCommit]
    unless ancestor $ reject 65 "migration-rehearsal: predecessor must be an ancestor of candidate HEAD"
    dirty <- gitOutput canonicalWorkspace ["status", "--porcelain", "--untracked-files=normal"]
    unless (null dirty) $ reject 65 "migration-rehearsal: candidate checkout must be clean so reported HEAD matches executed migrations"
    forM_ ["Application/Schema.sql", "flake.lock"] $ \path -> do
        exists <- commandSucceeds canonicalWorkspace "git" ["cat-file", "-e", predecessorCommit <> ":" <> path]
        unless exists $ reject 65 ("migration-rehearsal: predecessor has no " <> path)
    (runId, databaseName) <- freshNames
    let workRoot = canonicalWorkspace </> ".pi" </> "tmp" </> "migration-rehearsal"
        runDirectory = workRoot </> runId
        freshDatabase = databaseName <> "_fresh"
    ensureOwnedRoot canonicalWorkspace workRoot
    createDirectory runDirectory
    setFileMode runDirectory 0o700
    inherited <- sanitizedEnvironment <$> getEnvironment
    let postgresEnvironment =
            [("TEST_POSTGRES_MODE", "managed"), ("TEST_POSTGRES_PROFILE", "migration-rehearsal"),
             ("TEST_POSTGRES_REPO_ROOT", canonicalWorkspace)]
            <> filter ((`notElem` ["TEST_POSTGRES_MODE", "TEST_POSTGRES_PROFILE", "TEST_POSTGRES_REPO_ROOT"]) . fst) inherited
    socket <- managerEnsure canonicalWorkspace postgresEnvironment (postgresManager options)
        `onException` unless (keepFailureArtifacts options) (removePathForcibly runDirectory)
    user <- getLoginName
    let additions =
            [ ("MIGRATION_REHEARSAL_WORKSPACE", canonicalWorkspace)
            , ("MIGRATION_REHEARSAL_FROM_REF", predecessorRef options)
            , ("MIGRATION_REHEARSAL_PREDECESSOR_COMMIT", predecessorCommit)
            , ("MIGRATION_REHEARSAL_CANDIDATE_COMMIT", candidateCommit)
            , ("MIGRATION_REHEARSAL_RUN_DIR", runDirectory)
            , ("MIGRATION_REHEARSAL_DATABASE", databaseName)
            , ("MIGRATION_REHEARSAL_FRESH_DATABASE", freshDatabase)
            , ("MIGRATION_REHEARSAL_SOCKET", socket)
            , ("MIGRATION_REHEARSAL_DATABASE_USER", user)
            , ("MIGRATION_REHEARSAL_RUNNER", canonicalRunner)
            , ("MIGRATION_REHEARSAL_CANDIDATE_IHP_SOURCE", candidateIhpSource options)
            ]
        recipeEnvironment = additions <> inherited
        cleanupDatabases = dropDatabases canonicalWorkspace inherited socket user [databaseName, freshDatabase]
        runBody caught = do
            allocation <- createDatabases canonicalWorkspace inherited socket user runDirectory [databaseName, freshDatabase]
            interruptedBeforeRecipe <- readIORef caught
            status <- case (allocation, interruptedBeforeRecipe) of
                (Left message, _) -> hPutStrLn stderr message >> boundedLog (runDirectory </> "setup.log") >> pure (ExitFailure 1)
                (Right (), Just signalStatus) -> pure (ExitFailure signalStatus)
                (Right (), Nothing) -> executeRecipe canonicalWorkspace recipeEnvironment canonicalRecipe caught
                    `catch` startupFailure runDirectory
            cleanupSucceeded <- cleanupDatabases
            interrupted <- readIORef caught
            pure (maybe status ExitFailure interrupted, cleanupSucceeded)
    (status, cleanupSucceeded) <- withRunSignalHandling
        (\caught -> runBody caught `onException` void cleanupDatabases)
    case status of
        ExitSuccess | cleanupSucceeded -> removePathForcibly runDirectory
        _ | keepFailureArtifacts options -> retainBoundedFailure runDirectory
          | otherwise -> removePathForcibly runDirectory
    unless cleanupSucceeded $ reject 1 "migration-rehearsal: failed to drop a disposable database"
    exitWith status

canonicalizeRequired :: String -> FilePath -> IO FilePath
canonicalizeRequired label path = canonicalizePath path `catch` missing
  where
    missing :: IOException -> IO FilePath
    missing _ = reject 69 ("migration-rehearsal: " <> label <> " is unavailable: " <> path)

freshNames :: IO (String, String)
freshNames = do
    epoch <- floor . (* 1000000) <$> getPOSIXTime :: IO Integer
    pid <- getProcessID
    uid <- getEffectiveUserID
    let runId = show epoch <> "-" <> show pid
        databaseName = "migration_rehearsal_" <> show uid <> "_" <> show pid <> "_" <> show epoch
    pure (runId, databaseName)

ensureOwnedRoot :: FilePath -> FilePath -> IO ()
ensureOwnedRoot canonicalWorkspace root = do
    inspectCanonicalPath root >>= \case
        Left (NonCanonicalPath path) -> reject 73 ("migration-rehearsal: artifact root must be canonical: " <> path)
        Left (SymlinkPathComponent path) -> reject 73 ("migration-rehearsal: refusing symlinked artifact path: " <> path)
        Right () -> pure ()
    createDirectoryIfMissing True root
    status <- getFileStatus root
    uid <- getEffectiveUserID
    unless (fileOwner status == uid) $ reject 73 "migration-rehearsal: artifact root ownership mismatch"
    setFileMode root 0o700
    let marker = root </> ".bepis-migration-rehearsal-v1"
        expected = "workspace=" <> canonicalWorkspace <> "\n"
    exists <- doesFileExist marker
    if exists
        then readFile marker >>= \actual -> unless (actual == expected) (reject 73 "migration-rehearsal: artifact root marker mismatch")
        else writeFileAtomic marker (ByteString8.pack expected)

managerEnsure :: FilePath -> [(String, String)] -> FilePath -> IO FilePath
managerEnsure cwd environment command = do
    (status, output, errors) <- readCreateProcessWithExitCode
        (proc command ["ensure"]) {cwd = Just cwd, env = Just environment} ""
    case status of
        ExitSuccess -> case filter (not . null) (lines output) of
            [socket] -> pure socket
            _ -> reject 69 "migration-rehearsal: managed PostgreSQL returned an invalid socket"
        _ -> hPutStrLn stderr (take 65536 errors) >> reject 69 "migration-rehearsal: managed PostgreSQL ensure failed"

createDatabases :: FilePath -> [(String, String)] -> FilePath -> String -> FilePath -> [String] -> IO (Either String ())
createDatabases cwd environment socket user runDirectory names = go names
  where
    setupLog = runDirectory </> "setup.log"
    go [] = pure (Right ())
    go (databaseName:rest) = do
        (status, output, errors) <- readCreateProcessWithExitCode
            (proc "createdb" ["-h", socket, "-p", "5432", "-U", user, databaseName])
                {cwd = Just cwd, env = Just environment} ""
        ByteString.appendFile setupLog (ByteString8.pack (output <> errors))
        case status of
            ExitSuccess -> go rest
            _ -> pure (Left (if null rest
                then "migration-rehearsal: failed to create fresh candidate database"
                else "migration-rehearsal: failed to create disposable database"))

boundedLog :: FilePath -> IO ()
boundedLog path = do
    exists <- doesFileExist path
    when exists $ do
        contents <- ByteString.readFile path
        unless (ByteString.null contents) $ do
            hPutStrLn stderr "--- bounded failure log ---"
            ByteString8.hPutStr stderr (ByteString.drop (max 0 (ByteString.length contents - 65536)) contents)
            hPutStrLn stderr "\n--- end failure log ---"

executeRecipe :: FilePath -> [(String, String)] -> FilePath -> IORef (Maybe Int) -> IO ExitCode
executeRecipe cwd environment command caught = bracket
    (createProcess (proc "bash" [command]) {cwd = Just cwd, env = Just environment, create_group = True})
    (\(_, _, _, handle) -> terminateOwnedGroup handle)
    (\(_, _, _, handle) -> waitWithSignals caught handle)

startupFailure :: FilePath -> IOException -> IO ExitCode
startupFailure runDirectory exception = do
    writeFileAtomic (runDirectory </> "setup.log") (ByteString8.pack (take 65536 (show exception) <> "\n"))
    pure (ExitFailure 69)

withRunSignalHandling :: (IORef (Maybe Int) -> IO value) -> IO value
withRunSignalHandling action = do
    caught <- newIORef Nothing
    let remember status = writeIORef caught (Just status)
    oldInt <- installHandler keyboardSignal (Catch (remember 130)) Nothing
    oldTerm <- installHandler softwareTermination (Catch (remember 143)) Nothing
    oldHup <- installHandler lostConnection (Catch (remember 129)) Nothing
    let restore = do
            _ <- installHandler keyboardSignal oldInt Nothing
            _ <- installHandler softwareTermination oldTerm Nothing
            _ <- installHandler lostConnection oldHup Nothing
            pure ()
    action caught `finally` restore

waitWithSignals :: IORef (Maybe Int) -> ProcessHandle -> IO ExitCode
waitWithSignals caught handle = readIORef caught >>= \case
    Just status -> terminateOwnedGroup handle >> pure (ExitFailure status)
    Nothing -> getProcessExitCode handle >>= maybe (threadDelay 100000 >> waitWithSignals caught handle) pure

terminateOwnedGroup :: ProcessHandle -> IO ()
terminateOwnedGroup handle = getProcessExitCode handle >>= \case
    Just _ -> pure ()
    Nothing -> do
        getPid handle >>= mapM_ terminate
        _ <- waitForProcess handle
        pure ()
  where
    terminate pid = do
        group <- getProcessGroupIDOf pid `catch` noGroup
        if group == pid
            then do
                signalProcessGroup softwareTermination group `catch` noProcess
                exited <- waitForExit handle 30
                unless exited (signalProcessGroup sigKILL group `catch` noProcess)
            else do
                terminateProcess handle
                exited <- waitForExit handle 30
                unless exited (signalProcess sigKILL pid `catch` noProcess)
    noGroup :: IOException -> IO ProcessID
    noGroup _ = pure 0
    noProcess :: IOException -> IO ()
    noProcess _ = pure ()

waitForExit :: ProcessHandle -> Int -> IO Bool
waitForExit handle remaining
    | remaining <= 0 = pure False
    | otherwise = getProcessExitCode handle >>= \case
        Just _ -> pure True
        Nothing -> threadDelay 100000 >> waitForExit handle (remaining - 1)

sanitizedEnvironment :: [(String, String)] -> [(String, String)]
sanitizedEnvironment = filter safe
  where
    safe (name, _) = name `notElem` databaseVariables && not ("MIGRATION_REHEARSAL_" `isPrefixOf` name)
    databaseVariables = ["DATABASE_URL", "PGHOST", "PGPORT", "PGDATABASE", "PGUSER", "PGSERVICE", "PGPASSFILE", "PGPASSWORD", "PGOPTIONS"]

dropDatabases :: FilePath -> [(String, String)] -> FilePath -> String -> [String] -> IO Bool
dropDatabases cwd environment socket user databases = and <$> mapM dropOne databases
  where
    dropOne databaseName = retry (50 :: Int)
      where
        retry remaining = do
            (status, _, _) <- readCreateProcessWithExitCode
                (proc "dropdb" ["--if-exists", "--force", "-h", socket, "-p", "5432", "-U", user, databaseName])
                    {cwd = Just cwd, env = Just environment} ""
            if status == ExitSuccess then pure True else if remaining <= 1 then pure False else threadDelay 50000 >> retry (remaining - 1)

retainBoundedFailure :: FilePath -> IO ()
retainBoundedFailure runDirectory = do
    forM_ ["setup.log", "migrate.log", "fixture.log", "verification.log", "schema.diff"] $ \name -> do
        let path = runDirectory </> name
        exists <- doesFileExist path
        when exists $ do
            contents <- ByteString.readFile path
            when (ByteString.length contents > 65536) $
                writeFileAtomic path (ByteString.drop (ByteString.length contents - 65536) contents)
    forM_ ["ApplicationSchema.sql", "predecessor-flake.lock", "schema-migrations.sql", "fresh-schema.dump", "upgraded-schema.dump", "schema.diff.full", "migrate.ready"] $ \name ->
        removeFile (runDirectory </> name) `catch` ignoreMissing
    hPutStrLn stderr ("artifact_dir=" <> runDirectory)
  where
    ignoreMissing :: IOException -> IO ()
    ignoreMissing _ = pure ()

gitOutput :: FilePath -> [String] -> IO String
gitOutput cwd arguments = do
    (status, output, _) <- readCreateProcessWithExitCode (proc "git" arguments) {cwd = Just cwd} ""
    case status of
        ExitSuccess -> pure (trim output)
        _ -> reject 65 ("migration-rehearsal: git command failed: git " <> intercalate " " arguments)

gitMaybe :: FilePath -> [String] -> IO (Maybe String)
gitMaybe cwd arguments = do
    (status, output, _) <- readCreateProcessWithExitCode (proc "git" arguments) {cwd = Just cwd} ""
    pure (if status == ExitSuccess then Just (trim output) else Nothing)

commandSucceeds :: FilePath -> FilePath -> [String] -> IO Bool
commandSucceeds cwd command arguments = do
    (status, _, _) <- readCreateProcessWithExitCode (proc command arguments) {cwd = Just cwd} ""
    pure (status == ExitSuccess)

trim :: String -> String
trim = reverse . dropWhile (`elem` ['\n', '\r']) . reverse

reject :: Int -> String -> IO value
reject status message = throwIO (PostgresError status message)
