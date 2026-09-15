{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Bepis.Tooling.Postgres.Lifecycle
    ( PostgresError (..)
    , runProfileCommand
    ) where

import Bepis.Tooling.Core.OwnedFile (tryWithExclusiveLock, withExclusiveLock,
                                     writeFileAtomic)
import Bepis.Tooling.Postgres.Config
import Bepis.Tooling.Workspace.State (PathProblem (..), inspectCanonicalPath)
import Control.Exception (Exception, IOException, catch, throwIO)
import Control.Monad (forM_, unless, when)
import qualified Data.ByteString.Char8 as ByteString
import Data.List (isPrefixOf)
import Data.Maybe (fromMaybe)
import qualified Data.Text as Text
import Data.Time.Clock.POSIX (getPOSIXTime)
import System.Directory (createDirectory, createDirectoryIfMissing,
                         doesDirectoryExist, doesFileExist, doesPathExist,
                         getDirectoryContents, pathIsSymbolicLink,
                         removeFile, removePathForcibly)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath ((</>))
import System.IO (hPutStrLn, stderr)
import System.IO.Error (isDoesNotExistError)
import System.Posix.Files (fileOwner, getFileStatus, setFileMode)
import System.Posix.Process (getProcessID)
import System.Posix.Signals (nullSignal, signalProcess)
import System.Process (StdStream (Inherit), createProcess,
                       proc, readProcessWithExitCode, std_err, std_in, std_out,
                       waitForProcess)
import Text.Read (readMaybe)

data PostgresError = PostgresError Int String deriving (Show)
instance Exception PostgresError

data Paths = Paths
    { markerFile :: FilePath
    , managerLock :: FilePath
    , dataDirectory :: FilePath
    , socketDirectory :: FilePath
    , postgresLog :: FilePath
    , serverLog :: FilePath
    , initdbLog :: FilePath
    , signatureFile :: FilePath
    , instanceFile :: FilePath
    }

data Expected = Expected
    { signature :: String
    , settingsLine :: String
    }

runProfileCommand :: Profile -> String -> [String] -> IO ()
runProfileCommand selectedProfile command arguments = do
    config <- loadInstanceConfig selectedProfile
    case mode config of
        External socket -> runExternal config socket command arguments
        Managed -> runManaged config command arguments

runExternal :: InstanceConfig -> FilePath -> String -> [String] -> IO ()
runExternal config socket command arguments = case (profile config, command) of
    (Development, "ensure") -> noArguments arguments >> healthyApp socket >> putStrLn socket
    (Development, "root") -> noArguments arguments >> putStrLn socket
    (Development, "status") -> noArguments arguments >> healthyApp socket >> putStrLn ("mode=external\nsocket=" <> socket <> "\nstate=running\ndatabase=app")
    (Development, "shell") -> externalShell "DEV_DATABASE_NAME" "app"
    (Development, "log") -> reject 64 "dev-postgres: external mode has no managed log"
    (Development, "stop") -> noArguments arguments >> putStrLn "dev-postgres: external server left running"
    (Development, "recreate") -> reject 73 "dev-postgres: refusing recreate in external mode"
    (E2E, name) | name `elem` ["ensure", "prepare-root", "root"] -> noArguments arguments >> putStrLn socket
    (E2E, "status") -> noArguments arguments >> healthyPostgres socket >> putStrLn ("mode=external\nsocket=" <> socket <> "\nstate=running")
    (E2E, "shell") -> externalShell "TEST_DATABASE_NAME" "postgres"
    (E2E, "log") -> reject 64 "e2e-postgres: external mode has no managed log"
    (E2E, name) | name `elem` ["stop", "recreate", "cleanup"] -> reject 73 ("e2e-postgres: refusing " <> name <> " in external mode")
    (Hspec, "ensure") -> noArguments arguments >> healthyPostgres socket >> putStrLn socket
    (Hspec, "root") -> noArguments arguments >> putStrLn socket
    (Hspec, "status") -> noArguments arguments >> healthyPostgres socket >> putStrLn ("mode=external\nsocket=" <> socket <> "\nstate=running")
    (Hspec, name) | name `elem` ["stop", "recreate", "prepare-root"] -> reject 73 ("test-postgres: refusing " <> name <> " in external mode")
    (_, name) | name `elem` ["-h", "--help", "help"] -> putStrLn (usage (profile config))
    _ -> reject 64 (usage (profile config))
  where
    externalShell variable fallback = do
        database <- fromMaybe fallback <$> lookupEnv variable
        inheritExit "psql" (["-X", "-h", socket, "-d", database] <> arguments)

runManaged :: InstanceConfig -> String -> [String] -> IO ()
runManaged config command arguments = do
    paths <- pathsFor config
    case command of
        "root" -> noArguments arguments >> putStrLn (stateRoot config)
        "prepare-root" -> noArguments arguments >> validateOrCreateRoot config paths True >> putStrLn (stateRoot config)
        "ensure" -> do
            noArguments arguments
            when (profile config == Development) (warnLegacy config)
            withManager config paths (ensureInstance config paths) >>= postEnsure config paths
        "recreate" -> noArguments arguments >> withManager config paths (recreateInstance config paths) >>= postEnsure config paths
        "stop" -> noArguments arguments >> stopCommand config paths
        "status" -> noArguments arguments >> statusCommand config paths
        "shell" -> do
            _ <- withManager config paths (ensureInstance config paths)
            when (profile config == Development) (ensureAppDatabase paths)
            database <- fromMaybe (if profile config == Development then "app" else "postgres") <$> lookupEnv (if profile config == Development then "DEV_DATABASE_NAME" else "TEST_DATABASE_NAME")
            inheritExit "psql" (["-X", "-h", socketDirectory paths, "-d", database] <> arguments)
        "log" -> logCommand config paths arguments
        "cleanup" | profile config == E2E -> cleanupE2E config paths arguments
        "legacy-status" | profile config == Development -> noArguments arguments >> legacyStatus config
        "acknowledge-legacy" | profile config == Development -> noArguments arguments >> acknowledgeLegacy config paths
        name | name `elem` ["-h", "--help", "help"] -> putStrLn (usage (profile config))
        _ -> reject 64 (usage (profile config))

postEnsure :: InstanceConfig -> Paths -> FilePath -> IO ()
postEnsure config paths socket = do
    when (profile config == Development) (ensureAppDatabase paths)
    putStrLn socket

pathsFor :: InstanceConfig -> IO Paths
pathsFor config = do
    validateCanonicalStatePath config
    let root = stateRoot config
        label = profileLabel config
    pure Paths
        { markerFile = root </> (".bepis-" <> label <> "-postgres")
        , managerLock = root </> "manager.lock"
        , dataDirectory = root </> "data"
        , socketDirectory = root </> "socket"
        , postgresLog = root </> "postgres.log"
        , serverLog = root </> "log" </> "postgresql.log"
        , initdbLog = root </> "initdb.log"
        , signatureFile = root </> "config.signature"
        , instanceFile = root </> "instance-id"
        }

validateCanonicalStatePath :: InstanceConfig -> IO ()
validateCanonicalStatePath config = inspectCanonicalPath (stateRoot config) >>= \case
    Left (NonCanonicalPath path) -> reject 73 (program config <> ": state root must be canonical: " <> path)
    Left (SymlinkPathComponent component) -> reject 73 (program config <> if component == stateRoot config
        then ": refusing symlink state root: " <> component
        else ": refusing symlinked state path component: " <> component)
    Right () -> pure ()

validateOrCreateRoot :: InstanceConfig -> Paths -> Bool -> IO ()
validateOrCreateRoot config paths allowCreate = do
    linked <- pathIsSymbolicLink (stateRoot config) `catch` absent
    when linked $ reject 73 (program config <> ": refusing symlink state root: " <> stateRoot config)
    exists <- doesDirectoryExist (stateRoot config)
    unless exists $ if allowCreate
        then createDirectoryIfMissing True (stateRoot config) >> setFileMode (stateRoot config) 0o700
        else reject 3 "state root absent"
    status <- getFileStatus (stateRoot config)
    unless (show (fileOwner status) == ownerUid config) $
        reject 73 (program config <> ": state root is not owned by uid " <> ownerUid config <> ": " <> stateRoot config)
    markerExists <- doesFileExist (markerFile paths)
    unless markerExists $ if allowCreate then do
        entries <- filter (`notElem` [".", ".."]) <$> getDirectoryContents (stateRoot config)
        unless (null entries) $ reject 73 (program config <> ": refusing non-empty unowned state root: " <> stateRoot config)
        writeFileAtomic (markerFile paths) (ByteString.pack (expectedMarker config))
      else reject 3 "state marker absent"
    actual <- readFile (markerFile paths)
    unless (actual == expectedMarker config) $
        reject 73 (program config <> ": state ownership marker does not match this checkout: " <> markerFile paths)
    setFileMode (stateRoot config) 0o700
  where
    absent :: IOException -> IO Bool
    absent errorValue = if isDoesNotExistError errorValue then pure False else throwIO errorValue

expectedMarker :: InstanceConfig -> String
expectedMarker config = "bepis-" <> profileLabel config <> "-postgres-v1\nuid=" <> ownerUid config <> "\nproject=" <> projectId config <> "\n"

validateNative :: InstanceConfig -> IO ()
validateNative config = do
    fileSystem <- runOutput 73 "stat" ["-f", "-c", "%T", stateRoot config] ""
    let nonNative = fileSystem `elem` ["virtiofs", "9p", "nfs", "nfs4", "cifs"] || "fuse" `isPrefixOf` fileSystem || "smb" `isPrefixOf` fileSystem
    when (nonNative && not (allowNonNative config)) $
        reject 78 (program config <> ": refusing " <> fileSystem <> " state storage at " <> stateRoot config)

withManager :: InstanceConfig -> Paths -> IO value -> IO value
withManager config paths action = do
    initialized <- doesFileExist (markerFile paths)
    if initialized
        then enter
        else withExclusiveLock (stateRoot config <> ".bootstrap.lock") enter
  where
    enter = do
        validateOrCreateRoot config paths True
        withExclusiveLock (managerLock paths) action

expectedFor :: InstanceConfig -> IO Expected
expectedFor config = do
    versionOutput <- runOutput 69 "postgres" ["--version"] ""
    let postgresVersion = case reverse (words versionOutput) of [] -> "unknown"; value : _ -> value
        settings = settingsForConfig config
        base = "postgres=" <> postgresVersion
            <> (if profileLabel config == "hspec" then "" else " profile=" <> profileLabel config)
            <> " durability=" <> durabilityName (durability config)
            <> " fsync=" <> Text.unpack (fsyncSetting settings)
            <> " synchronous_commit=" <> Text.unpack (synchronousCommitSetting settings)
            <> " full_page_writes=" <> Text.unpack (fullPageWritesSetting settings)
        capacity = maybe "" (\value -> " max_connections=" <> show value) (maxConnections settings)
        observed = unwords ([Text.unpack (fsyncSetting settings), Text.unpack (synchronousCommitSetting settings), Text.unpack (fullPageWritesSetting settings)] <> maybe [] (pure . show) (maxConnections settings))
    pure Expected {signature = base <> capacity, settingsLine = observed}

settingsForConfig :: InstanceConfig -> Settings
settingsForConfig = settings

durabilityName :: Durability -> String
durabilityName Disposable = "disposable"
durabilityName Durable = "durable"
durabilityName Custom = "custom"

serverRunning :: Paths -> IO Bool
serverRunning paths = do
    dataExists <- doesDirectoryExist (dataDirectory paths)
    if not dataExists then pure False else commandSucceeds "pg_ctl" ["-D", dataDirectory paths, "status"]

staleLivePid :: Paths -> IO Bool
staleLivePid paths = do
    let pidFile = dataDirectory paths </> "postmaster.pid"
    exists <- doesFileExist pidFile
    if not exists then pure False else do
        firstLine <- takeWhile (/= '\n') <$> readFile pidFile
        case readMaybe firstLine of
            Nothing -> pure False
            Just pid -> (signalProcess nullSignal pid >> pure True) `catch` noProcess
  where noProcess :: IOException -> IO Bool; noProcess _ = pure False

serverReady :: Paths -> IO Bool
serverReady paths = commandSucceeds "psql" ["-X", "-q", "-h", socketDirectory paths, "-d", "postgres", "-At", "-v", "ON_ERROR_STOP=1", "-c", "SELECT 1"]

healthyPostgres :: FilePath -> IO ()
healthyPostgres socket = do
    ready <- commandSucceeds "psql" ["-X", "-q", "-h", socket, "-d", "postgres", "-At", "-v", "ON_ERROR_STOP=1", "-c", "SELECT 1"]
    unless ready $ reject 70 ("PostgreSQL is not reachable at " <> socket)

healthyApp :: FilePath -> IO ()
healthyApp socket = do
    ready <- commandSucceeds "psql" ["-X", "-q", "-h", socket, "-d", "app", "-At", "-v", "ON_ERROR_STOP=1", "-c", "SELECT 1"]
    unless ready $ reject 70 ("PostgreSQL app database is not reachable at " <> socket)

actualSettings :: InstanceConfig -> Paths -> IO String
actualSettings config paths = do
    let capacity = if profile config == E2E then ", current_setting('max_connections')" else ""
    runOutput 70 "psql" ["-X", "-q", "-h", socketDirectory paths, "-d", "postgres", "-At", "-F", " ", "-v", "ON_ERROR_STOP=1", "-c",
        "SELECT current_setting('fsync'), current_setting('synchronous_commit'), current_setting('full_page_writes')" <> capacity] ""

ensureInstance :: InstanceConfig -> Paths -> IO FilePath
ensureInstance config paths = do
    validateOrCreateRoot config paths True
    validateNative config
    expected <- expectedFor config
    running <- serverRunning paths
    if running then do
        signatureMatches <- fileEquals (signatureFile paths) (signature expected <> "\n")
        ready <- serverReady paths
        observed <- if ready then actualSettings config paths else pure ""
        unless (signatureMatches && ready && observed == settingsLine expected) $
            reject 73 (program config <> ": running managed instance does not match the requested profile; refusing reconfiguration")
      else do
        stale <- staleLivePid paths
        when stale $ reject 73 (program config <> ": managed postmaster exists but is not healthy; refusing automatic deletion")
        initialized <- doesFileExist (dataDirectory paths </> "PG_VERSION")
        signatureMatches <- fileEquals (signatureFile paths) (signature expected <> "\n")
        if initialized && durability config == Durable && signatureMatches
            then startExisting config paths expected
            else initializeAndStart config paths expected
    pure (socketDirectory paths)

recreateInstance :: InstanceConfig -> Paths -> IO FilePath
recreateInstance config paths = do
    validateOrCreateRoot config paths True
    validateNative config
    stopRunningServer config paths
    expected <- expectedFor config
    initializeAndStart config paths expected
    pure (socketDirectory paths)

initializeAndStart :: InstanceConfig -> Paths -> Expected -> IO ()
initializeAndStart config paths expected = do
    removeDisposable config paths
    createDirectory (socketDirectory paths)
    setFileMode (socketDirectory paths) 0o700
    createDirectoryIfMissing True (stateRoot config </> "log")
    setFileMode (stateRoot config </> "log") 0o700
    (initStatus, initOutput, initError) <- runRaw "initdb" ["-D", dataDirectory paths, "--no-locale", "--encoding=UTF8", "--auth-local=trust", "--auth-host=reject", "--no-sync"] ""
    writeFileAtomic (initdbLog paths) (ByteString.pack (bounded (initOutput <> initError)))
    unless (initStatus == ExitSuccess) $ reject 70 (program config <> ": initdb failed; see " <> initdbLog paths)
    appendFile (dataDirectory paths </> "postgresql.conf") (postgresConfiguration config paths)
    writeFileAtomic (signatureFile paths) (ByteString.pack (signature expected <> "\n"))
    timestamp <- round <$> getPOSIXTime :: IO Integer
    pid <- getProcessID
    writeFileAtomic (instanceFile paths) (ByteString.pack (show timestamp <> "-" <> show pid <> "\n"))
    startPostgres config paths
    verifyStarted config paths expected

postgresConfiguration :: InstanceConfig -> Paths -> String
postgresConfiguration config paths =
    "\n# Managed exclusively by Bepis tooling (profile: " <> profileLabel config <> ").\n"
    <> "listen_addresses = ''\n"
    <> "logging_collector = on\n"
    <> "log_directory = '" <> stateRoot config <> "/log'\n"
    <> "log_filename = 'postgresql.log'\n"
    <> "log_rotation_age = 1\n"
    <> "log_rotation_size = 4096\n"
    <> "log_truncate_on_rotation = on\n"
    <> "unix_socket_directories = '" <> socketDirectory paths <> "'\n"
    <> "unix_socket_permissions = 0700\n"
    <> "fsync = " <> Text.unpack (fsyncSetting selected) <> "\n"
    <> "synchronous_commit = " <> Text.unpack (synchronousCommitSetting selected) <> "\n"
    <> "full_page_writes = " <> Text.unpack (fullPageWritesSetting selected) <> "\n"
    <> maybe "" (\capacity -> "max_connections = " <> show capacity <> "\n") (maxConnections selected)
  where selected = settingsForConfig config

startExisting :: InstanceConfig -> Paths -> Expected -> IO ()
startExisting config paths expected = do
    createDirectoryIfMissing True (socketDirectory paths)
    setFileMode (socketDirectory paths) 0o700
    createDirectoryIfMissing True (stateRoot config </> "log")
    setFileMode (stateRoot config </> "log") 0o700
    startPostgres config paths
    verifyStarted config paths expected

startPostgres :: InstanceConfig -> Paths -> IO ()
startPostgres config paths = do
    (status, _, _) <- runRaw "pg_ctl" ["-D", dataDirectory paths, "-l", postgresLog paths, "-w", "-t", "30", "start"] ""
    unless (status == ExitSuccess) $ reject 70 (program config <> ": PostgreSQL failed to start; see " <> postgresLog paths)

verifyStarted :: InstanceConfig -> Paths -> Expected -> IO ()
verifyStarted config paths expected = do
    ready <- serverReady paths
    observed <- if ready then actualSettings config paths else pure ""
    unless (ready && observed == settingsLine expected) $ do
        stopRunningServer config paths
        reject 70 (program config <> ": PostgreSQL started with unexpected health or settings")

stopRunningServer :: InstanceConfig -> Paths -> IO ()
stopRunningServer config paths = do
    running <- serverRunning paths
    if running then do
        (status, _, _) <- runRaw "pg_ctl" ["-D", dataDirectory paths, "stop", "-m", "fast", "-w", "-t", "30"] ""
        unless (status == ExitSuccess) $ reject 70 (program config <> ": PostgreSQL failed to stop")
      else do
        stale <- staleLivePid paths
        when stale $ reject 73 (program config <> ": a live process owns stale-looking data at " <> dataDirectory paths <> "; refusing to delete it")

removeDisposable :: InstanceConfig -> Paths -> IO ()
removeDisposable config paths = do
    validateOrCreateRoot config paths True
    removeIfExists (dataDirectory paths)
    removeIfExists (socketDirectory paths)
    removeIfExists (stateRoot config </> "log")
    forM_ [signatureFile paths, instanceFile paths, postgresLog paths, initdbLog paths] removeFileIfExists

stopCommand :: InstanceConfig -> Paths -> IO ()
stopCommand config paths = do
    exists <- doesDirectoryExist (stateRoot config)
    if not exists then putStrLn (program config <> ": stopped; next ensure will recreate " <> stateRoot config) else
        withManager config paths $ do
            stopRunningServer config paths
            if preserveOnStop config
                then putStrLn (program config <> ": stopped; preserved durable data at " <> stateRoot config)
                else removeDisposable config paths >> putStrLn (program config <> ": stopped; next ensure will recreate " <> stateRoot config)

statusCommand :: InstanceConfig -> Paths -> IO ()
statusCommand config paths = do
    exists <- doesDirectoryExist (stateRoot config)
    unless exists $ putStrLn ("state=absent\nroot=" <> stateRoot config) >> exitWith (ExitFailure 3)
    validateOrCreateRoot config paths False
    withExclusiveLock (managerLock paths) $ do
        fileSystem <- runOutput 73 "stat" ["-f", "-c", "%T", stateRoot config] ""
        putStrLn ("root=" <> stateRoot config <> "\ndata=" <> dataDirectory paths <> "\nsocket=" <> socketDirectory paths <> "\nfilesystem=" <> fileSystem)
        running <- serverRunning paths
        ready <- if running then serverReady paths else pure False
        if running && ready then do
            observed <- actualSettings config paths
            configured <- readFileIfExists (signatureFile paths)
            instanceId <- readFileIfExists (instanceFile paths)
            putStrLn ("state=running\ndurability=" <> signatureDurability configured <> "\nsettings=" <> observed <> "\ninstance=" <> trim instanceId)
          else putStrLn "state=stopped" >> exitWith (ExitFailure 3)
    when (profile config == Development) (putStrLn "mode=managed\ndatabase=app")
    when (profile config == E2E) (putStrLn "mode=managed")

signatureDurability :: String -> String
signatureDurability value = fromMaybe "unknown" $ do
    entry <- findPrefix "durability=" (words value)
    pure (drop 11 entry)

findPrefix :: String -> [String] -> Maybe String
findPrefix _ [] = Nothing
findPrefix prefix (value:rest) | prefix `isPrefixOf` value = Just value | otherwise = findPrefix prefix rest

ensureAppDatabase :: Paths -> IO ()
ensureAppDatabase paths = do
    healthy <- commandSucceeds "psql" ["-X", "-q", "-h", socketDirectory paths, "-d", "app", "-At", "-v", "ON_ERROR_STOP=1", "-c", "SELECT 1"]
    unless healthy $ do
        created <- commandSucceeds "psql" ["-X", "-q", "-h", socketDirectory paths, "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", "CREATE DATABASE app"]
        unless created (healthyApp (socketDirectory paths))

logCommand :: InstanceConfig -> Paths -> [String] -> IO ()
logCommand config paths arguments = do
    count <- case arguments of
        [] -> pure "80"
        [value] | maybe False (\parsed -> parsed > (0 :: Int) && parsed <= 1000) (readMaybe value) -> pure value
        _ -> reject 64 (program config <> ": log line count must be between 1 and 1000")
    collectorExists <- doesFileExist (serverLog paths)
    startupExists <- doesFileExist (postgresLog paths)
    let selectedLog = if collectorExists then serverLog paths else postgresLog paths
    unless (collectorExists || startupExists) $ reject 66 (program config <> ": log is not available: " <> selectedLog)
    inheritExit "tail" ["-n", count, selectedLog]

cleanupE2E :: InstanceConfig -> Paths -> [String] -> IO ()
cleanupE2E config paths arguments = do
    apply <- case arguments of [] -> pure False; ["--apply"] -> pure True; _ -> reject 64 (usage E2E)
    result <- withManager config paths $ do
        _ <- ensureInstance config paths
        tryWithExclusiveLock (stateRoot config </> "runs.lock") $ do
            output <- runOutput 70 "psql" ["-X", "-q", "-h", socketDirectory paths, "-d", "postgres", "-At", "-v", "ON_ERROR_STOP=1", "-c",
                "SELECT candidate.datname FROM pg_database AS candidate WHERE candidate.datname LIKE 'app_e2e_%' AND NOT EXISTS (SELECT 1 FROM pg_stat_activity AS activity WHERE activity.pid <> pg_backend_pid() AND activity.datname = candidate.datname) ORDER BY candidate.datname"] ""
            let databases = filter (not . null) (lines output)
            if null databases then putStrLn "e2e-postgres: no inactive shard databases" else do
                putStrLn ("inactive=" <> unwords databases)
                if not apply then putStrLn "e2e-postgres: dry run; repeat cleanup --apply" else
                    forM_ databases $ \database -> do
                        let quoted = concatMap (\value -> if value == '"' then "\"\"" else [value]) database
                        voidStatus <- inheritStatus "psql" ["-X", "-q", "-h", socketDirectory paths, "-d", "postgres", "-v", "ON_ERROR_STOP=1", "-c", "DROP DATABASE \"" <> quoted <> "\" WITH (FORCE)"]
                        unless (voidStatus == ExitSuccess) $ reject 70 "e2e-postgres: failed to clean inactive shard database"
    case result of Nothing -> reject 75 "e2e-postgres: active E2E run holds the lifecycle lock; refusing cleanup"; Just () -> pure ()

legacyPaths :: InstanceConfig -> [FilePath]
legacyPaths config = [repositoryRoot config </> ".devenv/postgres", repositoryRoot config </> ".devenv/state/postgres"]

existingLegacyPaths :: InstanceConfig -> IO [FilePath]
existingLegacyPaths config = filterMPath (legacyPaths config)
  where
    filterMPath [] = pure []
    filterMPath (path:rest) = do
        exists <- doesPathExist path
        remaining <- filterMPath rest
        pure (if exists then path : remaining else remaining)

warnLegacy :: InstanceConfig -> IO ()
warnLegacy config = do
    paths <- existingLegacyPaths config
    reviewed <- doesFileExist (stateRoot config </> "legacy-reviewed")
    when (not (null paths) && not reviewed) $ do
        putStrLnErr ("dev-postgres: existing checkout-backed data remains untouched: " <> unwords paths)
        putStrLnErr "dev-postgres: review README migration/rollback guidance, then run dev-postgres acknowledge-legacy"

legacyStatus :: InstanceConfig -> IO ()
legacyStatus config = do
    paths <- existingLegacyPaths config
    if null paths then putStrLn "legacy=absent" else do
        putStrLn "legacy=present"
        mapM_ (putStrLn . ("path=" <>)) paths
    reviewed <- doesFileExist (stateRoot config </> "legacy-reviewed")
    putStrLn ("reviewed=" <> if reviewed then "true" else "false")

acknowledgeLegacy :: InstanceConfig -> Paths -> IO ()
acknowledgeLegacy config paths = do
    _ <- withManager config paths (ensureInstance config paths)
    timestamp <- round <$> getPOSIXTime :: IO Integer
    writeFileAtomic (stateRoot config </> "legacy-reviewed") (ByteString.pack ("reviewed-at=" <> show timestamp <> "\n"))
    putStrLn "dev-postgres: legacy state acknowledged; no legacy data was changed"

putStrLnErr :: String -> IO ()
putStrLnErr = hPutStrLn stderr

program :: InstanceConfig -> String
program config = case profile config of Hspec -> "test-postgres"; Development -> "dev-postgres"; E2E -> "e2e-postgres"

usage :: Profile -> String
usage Hspec = "Usage: test-postgres ensure|status|recreate|stop|prepare-root|root"
usage Development = "Usage: dev-postgres ensure|status|stop|recreate|root|shell|log|legacy-status|acknowledge-legacy"
usage E2E = "Usage: e2e-postgres ensure|status|stop|recreate|prepare-root|root|shell|log|cleanup [--apply]"

noArguments :: [String] -> IO ()
noArguments arguments = unless (null arguments) (reject 64 "unexpected arguments")

fileEquals :: FilePath -> String -> IO Bool
fileEquals path expected = do exists <- doesFileExist path; if exists then (== expected) <$> readFile path else pure False

readFileIfExists :: FilePath -> IO String
readFileIfExists path = do exists <- doesFileExist path; if exists then readFile path else pure ""

removeIfExists :: FilePath -> IO ()
removeIfExists path = do exists <- doesPathExist path; when exists (removePathForcibly path)

removeFileIfExists :: FilePath -> IO ()
removeFileIfExists path = removeFile path `catch` absent
  where absent :: IOException -> IO (); absent errorValue = unless (isDoesNotExistError errorValue) (throwIO errorValue)

runOutput :: Int -> FilePath -> [String] -> String -> IO String
runOutput failureStatus executable arguments input = do
    (status, output, errors) <- runRaw executable arguments input
    case status of ExitSuccess -> pure (trim output); ExitFailure _ -> reject failureStatus (trimOr (executable <> " failed") errors)

runRaw :: FilePath -> [String] -> String -> IO (ExitCode, String, String)
runRaw executable arguments input = readProcessWithExitCode executable arguments input `catch` unavailable
  where unavailable :: IOException -> IO (ExitCode, String, String); unavailable _ = reject 69 ("required command is unavailable: " <> executable)

commandSucceeds :: FilePath -> [String] -> IO Bool
commandSucceeds executable arguments = do (status, _, _) <- runRaw executable arguments ""; pure (status == ExitSuccess)

inheritStatus :: FilePath -> [String] -> IO ExitCode
inheritStatus executable arguments = do
    (_, _, _, handle) <- createProcess (proc executable arguments) {std_in = Inherit, std_out = Inherit, std_err = Inherit}
    waitForProcess handle

inheritExit :: FilePath -> [String] -> IO ()
inheritExit executable arguments = inheritStatus executable arguments >>= exitWith

bounded :: String -> String
bounded value = take (1024 * 1024) value

trim :: String -> String
trim = reverse . dropWhile (`elem` ['\n', '\r']) . reverse

trimOr :: String -> String -> String
trimOr fallback value = let result = trim value in if null result then fallback else result

reject :: Int -> String -> IO value
reject status = throwIO . PostgresError status
