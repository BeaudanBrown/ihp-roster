{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE OverloadedStrings #-}

module Bepis.Tooling.Runners (runRunnersCommand, safeDatabase, validRunId) where

import Bepis.Tooling.Core.OwnedFile (tryWithExclusiveLock, writeFileAtomic)
import Control.Concurrent (threadDelay)
import Control.Exception (Exception, IOException, bracket, catch, throwIO)
import Control.Monad (unless, when)
import Crypto.Hash.SHA256 (hash)
import Data.Aeson (FromJSON, ToJSON, eitherDecodeStrict', encode, object, (.=))
import qualified Data.ByteString as ByteString
import qualified Data.ByteString.Char8 as ByteString8
import qualified Data.ByteString.Lazy.Char8 as Lazy
import Data.Char (isAlphaNum)
import Data.IORef (newIORef, readIORef, writeIORef)
import Data.Time.Clock.POSIX (getPOSIXTime)
import GHC.Generics (Generic)
import qualified Network.Socket as Socket
import Numeric (showHex)
import System.Directory
import System.Environment (getArgs, getEnvironment, lookupEnv)
import System.Exit (ExitCode (..), exitWith)
import System.FilePath (isAbsolute, normalise, splitDirectories, takeDirectory, (</>))
import qualified System.IO
import System.IO.Error (isDoesNotExistError)
import System.Posix.Files
import System.Posix.Process (getProcessID)
import System.Posix.Signals
import System.Posix.User (getEffectiveUserID)
import System.Process
import Text.Read (readMaybe)

newtype RunnerFailure = RunnerFailure (Int, String) deriving (Show)
instance Exception RunnerFailure

data RootMarker = RootMarker
    { version :: Int
    , uid :: Integer
    , workspace :: FilePath
    , family :: String
    } deriving (Eq, Show, Generic)
instance ToJSON RootMarker
instance FromJSON RootMarker

runRunnersCommand :: IO ()
runRunnersCommand = (getArgs >>= dispatch) `catch` handleFailure
  where
    handleFailure (RunnerFailure (status, message)) = putStrLnErr ("bepis-runners: " <> message) >> exitWith (ExitFailure status)

dispatch :: [String] -> IO ()
dispatch ["id"] = freshRunId >>= putStrLn
dispatch ("hspec-plan":arguments) = hspecPlan arguments
dispatch ("e2e-plan":arguments) = e2ePlan arguments
dispatch ("profile-plan":arguments) = profilePlan arguments
dispatch ("run":arguments) = parseRun arguments >>= runOwned
dispatch ["help"] = putStrLn usage
dispatch _ = reject 64 usage

usage :: String
usage = unlines
    [ "usage: bepis-runners id"
    , "       bepis-runners hspec-plan --lane LANE --feedback LANE --shards N --max-shards N --database NAME"
    , "       bepis-runners e2e-plan --run-id ID --shards N --max-shards N --pool-size N --database NAME"
    , "       bepis-runners profile-plan --kind KIND --scenario NAME --rate N --duration D --vus N [--max-vus N]"
    , "       bepis-runners run --family FAMILY --workspace PATH --run-id ID [--artifact-dir PATH] [--retain-success] -- COMMAND..."
    ]

freshRunId :: IO String
freshRunId = do
    epoch <- floor <$> getPOSIXTime :: IO Integer
    pid <- getProcessID
    nonce <- ByteString.readFile "/proc/sys/kernel/random/uuid" `catch` noNonce
    let suffix = take 8 (hex (hash (ByteString8.pack (show epoch <> ":" <> show pid) <> nonce)))
    pure (show epoch <> "-" <> show pid <> "-" <> suffix)
  where
    noNonce :: IOException -> IO ByteString.ByteString
    noNonce _ = pure "fallback"

hspecPlan :: [String] -> IO ()
hspecPlan arguments = do
    options <- parsePairs arguments
    lane <- required "lane" options
    feedback <- required "feedback" options
    shards <- positive "shards" options
    maximumShards <- positive "max-shards" options
    database <- required "database" options
    runId <- required "run-id" options
    validateRunId runId
    when (length runId > 28) (reject 64 "Hspec run id exceeds 28 characters")
    unless (lane `elem` ["all", "pure", "db"]) (reject 64 ("invalid Hspec lane: " <> lane))
    unless (feedback `elem` ["all", "routine", "acceptance"]) (reject 64 ("invalid Hspec feedback lane: " <> feedback))
    when (shards > maximumShards) (reject 64 "Hspec shard count exceeds configured maximum")
    unless (safeDatabase 16 database) (reject 64 "unsafe Hspec database base name")
    Lazy.putStrLn (encode (object ["lane" .= lane, "feedback" .= feedback, "shards" .= shards,
        "maxShards" .= maximumShards, "database" .= database, "runId" .= runId]))

e2ePlan :: [String] -> IO ()
e2ePlan arguments = do
    options <- parsePairs arguments
    runId <- required "run-id" options
    shards <- positive "shards" options
    maximumShards <- positive "max-shards" options
    pool <- positive "pool-size" options
    database <- required "database" options
    validateRunId runId
    when (maximumShards > 8 || shards > maximumShards) (reject 64 "E2E shards must fit the configured maximum of eight")
    when (pool > 20) (reject 64 "E2E pool size must be between 1 and 20")
    unless (safeDatabase 16 database) (reject 64 "unsafe E2E database base name")
    Lazy.putStrLn (encode (object ["runId" .= runId, "shards" .= shards, "maxShards" .= maximumShards,
        "poolSize" .= pool, "database" .= database]))

profilePlan :: [String] -> IO ()
profilePlan arguments = do
    options <- parsePairs arguments
    kind <- required "kind" options
    scenario <- required "scenario" options
    rate <- positive "rate" options
    vus <- positive "vus" options
    duration <- required "duration" options
    let allowed = case kind of
            "load" -> ["roster-hot", "roster-wide", "roster-overview", "roster-projections", "fragments", "timesheets", "leave", "admin", "profile", "staff", "support", "billing", "auth", "mixed-app"]
            "live" -> ["support", "mixed-live"]
            _ -> []
    unless (scenario `elem` allowed) (reject 64 ("unsupported " <> kind <> " profile scenario: " <> scenario))
    unless (safeDuration duration) (reject 64 "profile duration must be a positive bounded duration")
    maxVus <- case lookup "max-vus" options of
        Nothing -> pure vus
        Just value -> maybe (reject 64 "max-vus must be positive") pure (readPositive value)
    when (maxVus < vus || maxVus > 1000 || rate > 1000) (reject 64 "profile rate/VU bounds are invalid")
    Lazy.putStrLn (encode (object ["kind" .= kind, "scenario" .= scenario, "rate" .= rate,
        "duration" .= duration, "vus" .= vus, "maxVus" .= maxVus]))

parsePairs :: [String] -> IO [(String, String)]
parsePairs [] = pure []
parsePairs (option:value:rest) | "--" `prefix` option = ((drop 2 option, value) :) <$> parsePairs rest
parsePairs (option:rest) | "--" `prefix` option, Just (key, value) <- splitEquals (drop 2 option) = ((key, value) :) <$> parsePairs rest
parsePairs _ = reject 64 "expected --name VALUE or --name=VALUE options"

required :: String -> [(String, String)] -> IO String
required key options = maybe (reject 64 ("missing --" <> key)) pure (lookup key options)

positive :: String -> [(String, String)] -> IO Int
positive key options = required key options >>= maybe (reject 64 ("--" <> key <> " must be positive")) pure . readPositive

readPositive :: String -> Maybe Int
readPositive value = case readMaybe value of Just number | number > 0 -> Just number; _ -> Nothing

safeDatabase :: Int -> String -> Bool
safeDatabase limit value = case value of
    first:_ -> length value <= limit && first >= 'a' && first <= 'z'
        && all (\character -> isAlphaNum character || character == '_') value
    [] -> False

safeDuration :: String -> Bool
safeDuration value = case span (`elem` ['0'..'9']) value of
    (digits, suffix) -> maybe False (\number -> number > (0 :: Int) && number <= 3600 && suffix `elem` ["s", "m"]) (readMaybe digits)

prefix :: String -> String -> Bool
prefix expected value = take (length expected) value == expected

splitEquals :: String -> Maybe (String, String)
splitEquals value = case break (== '=') value of (key, '=':rest) | not (null key) -> Just (key, rest); _ -> Nothing

data RunOptions = RunOptions String FilePath String (Maybe FilePath) Bool [String]

parseRun :: [String] -> IO RunOptions
parseRun = go "" "" "" Nothing False
  where
    go _ workspacePath runId artifact retain ("--family":value:rest) = go value workspacePath runId artifact retain rest
    go familyPath _ runId artifact retain ("--workspace":value:rest) = go familyPath value runId artifact retain rest
    go familyPath workspacePath _ artifact retain ("--run-id":value:rest) = go familyPath workspacePath value artifact retain rest
    go familyPath workspacePath runId _ retain ("--artifact-dir":value:rest) = go familyPath workspacePath runId (Just value) retain rest
    go familyPath workspacePath runId artifact _ ("--retain-success":rest) = go familyPath workspacePath runId artifact True rest
    go familyPath workspacePath runId artifact retain ("--":command) = do
        unless (all (not . null) [familyPath, workspacePath, runId] && not (null command)) (reject 64 usage)
        validateFamily familyPath
        validateRunId runId
        pure (RunOptions familyPath workspacePath runId artifact retain command)
    go _ _ _ _ _ _ = reject 64 usage

validateFamily :: String -> IO ()
validateFamily value = unless (not (null value) && length value <= 24 && all (\character -> isAlphaNum character || character == '-') value)
    (reject 64 "unsafe runner family")

validateRunId :: String -> IO ()
validateRunId value = unless (validRunId value) (reject 64 "unsafe run id")

validRunId :: String -> Bool
validRunId value = case value of
    first:_ -> length value <= 64 && isAlphaNum first
        && all (\character -> isAlphaNum character || character `elem` ['.', '_', '-']) value
    [] -> False

runOwned :: RunOptions -> IO ()
runOwned (RunOptions familyPath workspacePath runId artifact retainSuccess command) = do
    canonicalWorkspace <- canonicalizePath workspacePath
    unless (canonicalWorkspace == normalise workspacePath) (reject 64 "workspace must be canonical")
    effectiveUid <- getEffectiveUserID
    configuredParent <- lookupEnv "BEPIS_RUNNER_PARENT"
    let parent = maybe ("/var/tmp/bepis-runners-" <> show effectiveUid) id configuredParent
    unless (isAbsolute parent && normalise parent == parent && parent /= "/") (reject 64 "runner parent must be a canonical absolute non-root path")
    let root = parent </> take 16 (hex (hash (ByteString8.pack canonicalWorkspace))) </> familyPath
        markerPath = root </> ".bepis-runner-root.json"
        marker = RootMarker 1 (fromIntegral effectiveUid) canonicalWorkspace familyPath
        runs = root </> "runs"
        locks = root </> "locks"
        ports = parent </> "ports"
        state = runs </> runId
        lock = locks </> runId <> ".lock"
    rejectSymlinks root
    ensureOwned parent
    ensureOwned (takeDirectory root)
    ensureOwned root
    ensureMarker markerPath marker
    ensureOwned runs
    ensureOwned locks
    ensureOwned ports
    result <- tryWithExclusiveLock lock $ do
        collision <- doesPathExist state
        when collision (reject 73 ("run id already exists: " <> runId))
        status <- withPortLease ports $ \port -> do
            createDirectory state
            setFileMode state 0o700
            execute canonicalWorkspace state familyPath runId port command `catch` commandStartupFailure state
        case status of
            ExitSuccess -> unless retainSuccess (retainSuccessTombstone state familyPath runId)
            _ -> retainFailure artifact state familyPath runId status
        pure status
    maybe (reject 75 ("run id is already active: " <> runId)) exitWith result

commandStartupFailure :: FilePath -> IOException -> IO ExitCode
commandStartupFailure state exception = do
    let message = take 2000 (show exception)
    writeFileAtomic (state </> "runner-startup-error.log") (ByteString8.pack (message <> "\n"))
    putStrLnErr ("bepis-runners: command startup failed: " <> message)
    pure (ExitFailure 74)

retainSuccessTombstone :: FilePath -> String -> String -> IO ()
retainSuccessTombstone state familyPath runId = do
    removePathForcibly state
    createDirectory state
    setFileMode state 0o700
    writeFileAtomic (state </> "runner-success.json") (Lazy.toStrict (encode (object
        ["exitCode" .= (0 :: Int), "family" .= familyPath, "runId" .= runId])))

withPortLease :: FilePath -> (Int -> IO value) -> IO value
withPortLease lockRoot action = select [0..199]
  where
    select [] = reject 75 "no runner port lease is available"
    select (slot:rest) = do
        acquired <- tryWithExclusiveLock (lockRoot </> show slot <> ".lock") $ do
            available <- portsAvailable slot
            if available then Just <$> action (20000 + slot) else pure Nothing
        case acquired of
            Just (Just value) -> pure value
            _ -> select rest

portsAvailable :: Int -> IO Bool
portsAvailable slot = and <$> mapM canBind [20000 + slot, 22000 + slot * 2, 22001 + slot * 2]
  where
    canBind port =
        (bracket
            (Socket.socket Socket.AF_INET Socket.Stream Socket.defaultProtocol)
            Socket.close
            (\socket -> Socket.bind socket (Socket.SockAddrInet (fromIntegral port) (Socket.tupleToHostAddress (127, 0, 0, 1))))
            >> pure True)
        `catch` unavailable
    unavailable :: IOException -> IO Bool
    unavailable _ = pure False

execute :: FilePath -> FilePath -> String -> String -> Int -> [String] -> IO ExitCode
execute cwd state familyPath runId port (executable:arguments) = do
    inherited <- filter ((`notElem` ["BEPIS_RUNNER_STATE_DIR", "BEPIS_RUNNER_FAMILY", "BEPIS_RUN_ID", "BEPIS_RUNNER_PORT", "BEPIS_RUNNER_PORT_SLOT", "BEPIS_RUNNER_E2E_PORT_BASE", "BEPIS_RUNNER_OTLP_GRPC_PORT", "BEPIS_RUNNER_OTLP_HTTP_PORT"]) . fst) <$> getEnvironment
    let slot = port - 20000
        environment = [("BEPIS_RUNNER_STATE_DIR", state), ("BEPIS_RUNNER_FAMILY", familyPath),
            ("BEPIS_RUN_ID", runId), ("BEPIS_RUNNER_PORT", show port),
            ("BEPIS_RUNNER_PORT_SLOT", show slot),
            ("BEPIS_RUNNER_E2E_PORT_BASE", show (10000 + slot * 300)),
            ("BEPIS_RUNNER_OTLP_GRPC_PORT", show (22000 + slot * 2)),
            ("BEPIS_RUNNER_OTLP_HTTP_PORT", show (22001 + slot * 2))] <> inherited
    bracket
        (createProcess (proc executable arguments) {cwd = Just cwd, env = Just environment, create_group = True})
        cleanup
        (\(_, _, _, handle) -> withSignalForwarding handle (waitPolling handle))
  where
    cleanup (_, _, _, handle) = do
        running <- getProcessExitCode handle
        case running of Nothing -> terminateProcess handle >> waitForProcess handle >> pure (); Just _ -> pure ()
execute _ _ _ _ _ [] = reject 64 "missing runner command"

waitPolling :: ProcessHandle -> IO ExitCode
waitPolling handle = do
    status <- getProcessExitCode handle
    case status of
        Just finished -> pure finished
        Nothing -> threadDelay 100000 >> waitPolling handle

withSignalForwarding :: ProcessHandle -> IO ExitCode -> IO ExitCode
withSignalForwarding handle action = do
    received <- newIORef Nothing
    let forward signal = do
            writeIORef received (Just signal)
            maybePid <- getPid handle
            case maybePid of Nothing -> pure (); Just pid -> signalProcessGroup signal (fromIntegral pid) `catch` ignored
        install = do
            oldInt <- installHandler sigINT (Catch (forward sigINT)) Nothing
            oldTerm <- installHandler sigTERM (Catch (forward sigTERM)) Nothing
            pure (oldInt, oldTerm)
        restore (oldInt, oldTerm) = do
            _ <- installHandler sigINT oldInt Nothing
            _ <- installHandler sigTERM oldTerm Nothing
            pure ()
    status <- bracket install restore (const action)
    signal <- readIORef received
    pure (case signal of Just selected | selected == sigINT -> ExitFailure 130
                                | selected == sigTERM -> ExitFailure 143
                         _ -> status)
  where
    ignored :: IOException -> IO ()
    ignored _ = pure ()

retainFailure :: Maybe FilePath -> FilePath -> String -> String -> ExitCode -> IO ()
retainFailure Nothing _ _ _ _ = pure ()
retainFailure (Just artifact) state familyPath runId status = do
    unless (isAbsolute artifact && normalise artifact == artifact) (reject 64 "artifact directory must be canonical and absolute")
    rejectSymlinks artifact
    createDirectoryIfMissing True artifact
    writeFileAtomic (artifact </> "runner-failure.json") (Lazy.toStrict (encode (object
        ["family" .= familyPath, "runId" .= runId, "state" .= state, "exitCode" .= exitNumber status])))
  where
    exitNumber ExitSuccess = 0 :: Int
    exitNumber (ExitFailure number) = number

ensureMarker :: FilePath -> RootMarker -> IO ()
ensureMarker path expected = do
    exists <- doesFileExist path
    if not exists then writeFileAtomic path (Lazy.toStrict (encode expected)) else do
        decoded <- eitherDecodeStrict' <$> ByteString.readFile path
        unless (decoded == Right expected) (reject 73 ("runner root marker mismatch: " <> path))

ensureOwned :: FilePath -> IO ()
ensureOwned path = do
    symbolic <- pathIsSymbolicLink path `catch` missing
    when symbolic (reject 73 ("owned runner path is symlinked: " <> path))
    createDirectoryIfMissing True path
    status <- getFileStatus path
    effectiveUid <- getEffectiveUserID
    unless (fileOwner status == effectiveUid) (reject 73 ("owned runner path belongs to another user: " <> path))
    setFileMode path 0o700
  where
    missing :: IOException -> IO Bool
    missing exception | isDoesNotExistError exception = pure False
    missing exception = throwIO exception

rejectSymlinks :: FilePath -> IO ()
rejectSymlinks path = go "/" (filter (`notElem` ["/", ""]) (splitDirectories path))
  where
    go _ [] = pure ()
    go parent (component:rest) = do
        let selected = parent </> component
        symbolic <- pathIsSymbolicLink selected `catch` missing
        when symbolic (reject 73 ("runner path traverses a symlink: " <> selected))
        exists <- doesDirectoryExist selected
        when exists (go selected rest)
    missing :: IOException -> IO Bool
    missing _ = pure False

hex :: ByteString.ByteString -> String
hex = concatMap (pad . (`showHex` "")) . ByteString.unpack
  where pad [character] = ['0', character]; pad value = value

reject :: Int -> String -> IO value
reject status message = throwIO (RunnerFailure (status, message))

putStrLnErr :: String -> IO ()
putStrLnErr = ByteString8.hPutStrLn System.IO.stderr . ByteString8.pack
