{-# LANGUAGE DeriveGeneric #-}
{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedStrings #-}

module Bepis.Tooling.Runtime.Process
    ( Observation (..)
    , adoptOwned
    , RuntimeError (..)
    , observeOwned
    , releaseOwned
    , startOwned
    , startOwnedResult
    , stopOwned
    , stopOwnedForInvocation
    ) where

import Bepis.Tooling.Core.OwnedFile (withExclusiveLock, writeFileAtomic)
import Bepis.Tooling.Workspace.State (PathProblem (..), inspectCanonicalPath)
import Control.Concurrent (threadDelay)
import Control.Exception (Exception, IOException, catch, throwIO)
import Control.Monad (unless, when)
import Data.Aeson (FromJSON, ToJSON, decodeStrict', encode)
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.ByteString.Lazy as Lazy
import Data.Char (isDigit)
import Data.Maybe (fromMaybe)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import GHC.Generics (Generic)
import System.Directory (canonicalizePath, createDirectoryIfMissing, doesFileExist,
                         listDirectory, pathIsSymbolicLink, removeFile)
import System.Environment (getEnvironment)
import System.FilePath (takeDirectory)
import System.IO (Handle, hClose)
import System.IO.Error (isDoesNotExistError)
import System.Posix.IO (OpenFileFlags (append, cloexec, creat, nofollow), OpenMode (ReadOnly, WriteOnly), defaultFileFlags, fdToHandle, openFd)
import System.Posix.Files (deviceID, fileID, getFileStatus, ownerReadMode, ownerWriteMode, unionFileModes)
import System.Posix.Process (getProcessGroupIDOf)
import System.Posix.User (getEffectiveUserID)
import System.Posix.Signals (Signal, sigKILL, sigTERM, signalProcess, signalProcessGroup)
import System.Process (CreateProcess (..), StdStream (..), createProcess, getPid,
                       proc)
import Text.Read (readMaybe)

newtype RuntimeError = RuntimeError (Int, String) deriving (Show)
instance Exception RuntimeError

data Owner = Owner
    { version :: Int
    , pid :: Int
    , startTicks :: String
    , workingDirectory :: FilePath
    , processGroup :: Int
    , ownershipToken :: Text.Text
    , ownershipKind :: String
    , invocationToken :: Text.Text
    , label :: String
    } deriving (Eq, Show, Generic)
instance ToJSON Owner
instance FromJSON Owner

data DirectoryIdentity = DirectoryIdentity Integer Integer deriving (Eq, Show)

data Observation = Observation
    { observedPid :: Maybe Int
    , observedAlive :: Bool
    , observedOwned :: Bool
    , observedReason :: String
    } deriving (Eq, Show)

adoptOwned :: FilePath -> FilePath -> FilePath -> String -> Int -> IO ()
adoptOwned pidFile ownerFile cwd service numericPid = do
    directoryIdentity <- validateStatePaths pidFile ownerFile
    withExclusiveLock (pidFile <> ".manager.lock") $ do
        assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)
        canonicalCwd <- validatedWorkspacePath cwd
        ticks <- processStartTicks numericPid >>= maybe (reject 75 (service <> ": process exited before ownership publication")) pure
        pathMatches <- processInPath numericPid canonicalCwd
        unless pathMatches (reject 73 (service <> ": refusing process outside workspace path"))
        writeFileAtomic ownerFile (Lazy.toStrict (encode Owner
            { version = 1, pid = numericPid, startTicks = ticks
            , workingDirectory = canonicalCwd, processGroup = 0, ownershipToken = "", ownershipKind = "adopted", invocationToken = "", label = service
            }))
        writeFileAtomic pidFile (ByteString.pack (show numericPid <> "\n"))
        assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)

startOwned :: FilePath -> FilePath -> FilePath -> FilePath -> String -> FilePath -> [String] -> IO Int
startOwned pidFile ownerFile logFile cwd service executable arguments =
    fst <$> startOwnedResult pidFile ownerFile logFile cwd service executable arguments

startOwnedResult :: FilePath -> FilePath -> FilePath -> FilePath -> String -> FilePath -> [String] -> IO (Int, Bool)
startOwnedResult pidFile ownerFile logFile cwd service executable arguments = do
    directoryIdentity <- validateArtifactPaths pidFile ownerFile logFile
    withExclusiveLock (pidFile <> ".manager.lock") $ do
        assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)
        observation <- observeOwnedWithIdentity directoryIdentity pidFile ownerFile cwd service
        if observedOwned observation
            then pure (fromMaybe 0 (observedPid observation), False)
            else do
                assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)
                retained <- hasRetainedOwner ownerFile service observation
                when (retained && observedAlive observation) $
                    reject 75 (service <> ": live ownership evidence could not be revalidated; refusing competing start")
                assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)
                clearState pidFile ownerFile
                createDirectoryIfMissing True (takeDirectory pidFile)
                canonicalCwd <- validatedWorkspacePath cwd
                logHandle <- openLogNoFollow logFile
                token <- runtimeOwnershipToken
                inheritedEnvironment <- getEnvironment
                let invocation = Text.pack (fromMaybe "" (lookup "BEPIS_RUNTIME_INVOCATION_TOKEN" inheritedEnvironment))
                (_, _, _, processHandle) <- createProcess (proc executable arguments)
                    { cwd = Just canonicalCwd
                    , std_in = NoStream
                    , std_out = UseHandle logHandle
                    , std_err = UseHandle logHandle
                    , close_fds = True
                    , new_session = True
                    , env = Just (("BEPIS_RUNTIME_OWNER_TOKEN", Text.unpack token) : inheritedEnvironment)
                    }
                childPid <- getPid processHandle >>= maybe (hClose logHandle >> reject 70 (service <> ": child PID unavailable")) pure
                hClose logHandle
                let numericPid = fromIntegral childPid
                ticks <- processStartTicks numericPid >>= maybe (reject 70 (service <> ": child exited during startup")) pure
                group <- fromIntegral <$> getProcessGroupIDOf childPid
                writeFileAtomic ownerFile (Lazy.toStrict (encode Owner
                    { version = 1, pid = numericPid, startTicks = ticks
                    , workingDirectory = canonicalCwd, processGroup = group, ownershipToken = token, ownershipKind = "started", invocationToken = invocation, label = service
                    }))
                writeFileAtomic pidFile (ByteString.pack (show numericPid <> "\n"))
                threadDelay 100000
                healthy <- (||) <$> ownerMatches numericPid ticks canonicalCwd <*> ownedGroupExists group token canonicalCwd
                unless healthy $ clearState pidFile ownerFile >> assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile) >> reject 75 (service <> " failed to start")
                assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)
                pure (numericPid, True)

observeOwned :: FilePath -> FilePath -> FilePath -> String -> IO Observation
observeOwned pidFile ownerFile cwd service = do
    directoryIdentity <- validateStatePaths pidFile ownerFile
    observeOwnedWithIdentity directoryIdentity pidFile ownerFile cwd service

observeOwnedWithIdentity :: DirectoryIdentity -> FilePath -> FilePath -> FilePath -> String -> IO Observation
observeOwnedWithIdentity directoryIdentity pidFile ownerFile cwd service = do
    assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)
    pidValue <- readPid pidFile
    assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)
    case pidValue of
        Nothing -> pure (Observation Nothing False False "absent")
        Just numericPid -> do
            alive <- processExists numericPid
            canonicalCwd <- validatedWorkspacePath cwd
            assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)
            owner <- readOwner ownerFile
            assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)
            case owner of
                Just evidence | pid evidence == numericPid && label evidence == service -> do
                    baseMatches <- ownerMatches numericPid (startTicks evidence) (workingDirectory evidence)
                    leaderMatches <- case ownershipKind evidence of
                        "started" | not (Text.null (ownershipToken evidence)) ->
                            (baseMatches &&) <$> processHasOwnershipToken numericPid (ownershipToken evidence)
                        "adopted" -> pure (baseMatches && processGroup evidence == 0 && Text.null (ownershipToken evidence))
                        _ -> pure False
                    groupMatches <- ownedGroupExists (processGroup evidence) (ownershipToken evidence) (workingDirectory evidence)
                    groupAlive <- processGroupExists (processGroup evidence)
                    let owned = workingDirectory evidence == canonicalCwd && (leaderMatches || groupMatches)
                    pure (Observation (Just numericPid) (alive || groupAlive) owned (if leaderMatches then "owner-evidence" else if groupMatches then "owner-group-evidence" else "reused-pid"))
                _ -> pure (Observation (Just numericPid) alive False (if alive then "missing-or-invalid-owner-evidence" else "stale-pid"))

releaseOwned :: FilePath -> FilePath -> FilePath -> String -> Int -> IO Bool
releaseOwned pidFile ownerFile cwd service expectedPid = do
    directoryIdentity <- validateStatePaths pidFile ownerFile
    withExclusiveLock (pidFile <> ".manager.lock") $ do
        assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)
        observation <- observeOwnedWithIdentity directoryIdentity pidFile ownerFile cwd service
        if observedOwned observation && observedPid observation == Just expectedPid
            then clearState pidFile ownerFile >> assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile) >> pure True
            else pure False

stopOwnedForInvocation :: FilePath -> FilePath -> FilePath -> String -> Text.Text -> Int -> IO Bool
stopOwnedForInvocation pidFile ownerFile cwd service expectedInvocation graceMilliseconds
    | Text.null expectedInvocation = reject 64 "runtime invocation token must not be empty"
    | otherwise = do
        directoryIdentity <- validateStatePaths pidFile ownerFile
        assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)
        evidence <- readOwner ownerFile
        assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)
        case evidence of
            Just ownerEvidence | invocationToken ownerEvidence == expectedInvocation ->
                stopOwned pidFile ownerFile cwd service graceMilliseconds
            _ -> pure False

stopOwned :: FilePath -> FilePath -> FilePath -> String -> Int -> IO Bool
stopOwned pidFile ownerFile cwd service graceMilliseconds = do
    directoryIdentity <- validateStatePaths pidFile ownerFile
    withExclusiveLock (pidFile <> ".manager.lock") $ do
        assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)
        observation <- observeOwnedWithIdentity directoryIdentity pidFile ownerFile cwd service
        if not (observedOwned observation)
            then do
                assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)
                retainedOwner <- hasRetainedOwner ownerFile service observation
                if retainedOwner && observedAlive observation
                    then reject 75 (service <> ": ownership could not be revalidated; retained ownership state")
                    else clearState pidFile ownerFile >> assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile) >> pure False
            else case observedPid observation of
                Nothing -> pure False
                Just numericPid -> do
                    signalIfStillOwned directoryIdentity sigTERM numericPid
                    exited <- waitOwnershipGone directoryIdentity graceMilliseconds
                    unless exited (signalIfStillOwned directoryIdentity sigKILL numericPid)
                    gone <- waitOwnershipGone directoryIdentity (1000 :: Int)
                    if gone then clearState pidFile ownerFile >> assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile) >> pure True
                        else reject 75 (service <> ": process survived termination; retained ownership state")
  where
    signalIfStillOwned directoryIdentity signal numericPid = do
        confirmation <- observeOwnedWithIdentity directoryIdentity pidFile ownerFile cwd service
        assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)
        evidence <- readOwner ownerFile
        assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)
        if not (observedOwned confirmation && observedPid confirmation == Just numericPid)
            then pure ()
            else case evidence of
                Just ownerEvidence -> do
                    groupOwned <- ownedGroupExists (processGroup ownerEvidence) (ownershipToken ownerEvidence) (workingDirectory ownerEvidence)
                    assertStateDirectoryIdentity directoryIdentity (takeDirectory pidFile)
                    if groupOwned then signalProcessGroup signal (fromIntegral (processGroup ownerEvidence))
                        else signalValidated signal numericPid
                Nothing -> pure ()
    waitOwnershipGone directoryIdentity milliseconds = loop (max 0 (milliseconds `div` 50))
      where
        loop 0 = not . observedAlive <$> observeOwnedWithIdentity directoryIdentity pidFile ownerFile cwd service
        loop remaining = do
            alive <- observedAlive <$> observeOwnedWithIdentity directoryIdentity pidFile ownerFile cwd service
            if not alive then pure True else threadDelay 50000 >> loop (remaining - 1)

hasRetainedOwner :: FilePath -> String -> Observation -> IO Bool
hasRetainedOwner ownerFile service observation = do
    evidence <- readOwner ownerFile
    pure $ case (evidence, observedPid observation) of
        (Just ownerEvidence, Just numericPid) -> pid ownerEvidence == numericPid && label ownerEvidence == service
        _ -> False

signalValidated :: Signal -> Int -> IO ()
signalValidated signal numericPid = signalProcess signal (fromIntegral numericPid)

processGroupExists :: Int -> IO Bool
processGroupExists group
    | group <= 0 = pure False
    | otherwise = do
        entries <- listDirectory "/proc"
        or <$> mapM inLiveGroup [numericPid | entry <- entries, Just numericPid <- [readMaybe entry]]
  where
    inLiveGroup numericPid = do
        fields <- processStatFields numericPid
        pure $ case fields of
            stateValue : _ : groupValue : _ -> stateValue /= "Z" && readMaybe groupValue == Just group
            _ -> False

ownedGroupExists :: Int -> Text.Text -> FilePath -> IO Bool
ownedGroupExists group token cwd
    | group <= 0 || Text.null token = pure False
    | otherwise = do
        entries <- listDirectory "/proc"
        members <- groupMembers [numericPid | entry <- entries, Just numericPid <- [readMaybe entry]]
        ownership <- mapM memberOwned members
        pure (not (null members) && and ownership)
  where
    groupMembers [] = pure []
    groupMembers (numericPid : rest) = do
        fields <- processStatFields numericPid
        let sameGroup = case fields of
                stateValue : _ : groupValue : _ -> stateValue /= "Z" && readMaybe groupValue == Just group
                _ -> False
        remaining <- groupMembers rest
        pure (if sameGroup then numericPid : remaining else remaining)
    memberOwned numericPid = do
        pathAndUidOwned <- (&&) <$> processInPath numericPid cwd <*> processOwnedByCaller numericPid
        tokenOwned <- if pathAndUidOwned then processHasOwnershipToken numericPid token else pure False
        pure (pathAndUidOwned && tokenOwned)

runtimeOwnershipToken :: IO Text.Text
runtimeOwnershipToken = Text.strip . TextEncoding.decodeUtf8 <$> ByteString.readFile "/proc/sys/kernel/random/uuid"

processHasOwnershipToken :: Int -> Text.Text -> IO Bool
processHasOwnershipToken numericPid token = do
    contents <- ByteString.readFile ("/proc/" <> show numericPid <> "/environ") `catch` missingEnvironment
    let expected = ByteString.pack ("BEPIS_RUNTIME_OWNER_TOKEN=" <> Text.unpack token)
    pure (expected `elem` ByteString.split '\0' contents)
  where
    missingEnvironment :: IOException -> IO ByteString.ByteString
    missingEnvironment _ = pure ByteString.empty

ownerMatches :: Int -> String -> FilePath -> IO Bool
ownerMatches numericPid ticks cwd = do
    currentTicks <- processStartTicks numericPid
    pathMatches <- processInPath numericPid cwd
    uidMatches <- processOwnedByCaller numericPid
    pure (currentTicks == Just ticks && pathMatches && uidMatches)

validatedWorkspacePath :: FilePath -> IO FilePath
validatedWorkspacePath path = do
    inspectCanonicalPath path >>= \case
        Left (NonCanonicalPath invalidPath) -> reject 73 ("runtime workspace path is not canonical: " <> invalidPath)
        Left (SymlinkPathComponent component) -> reject 73 ("runtime workspace path contains a symlink: " <> component)
        Right () -> canonicalizePath path

processExists :: Int -> IO Bool
processExists numericPid = do
    state <- processState numericPid
    pure (maybe False (/= "Z") state)

processOwnedByCaller :: Int -> IO Bool
processOwnedByCaller numericPid = do
    contents <- ByteString.unpack <$> (ByteString.readFile ("/proc/" <> show numericPid <> "/status") `catch` missingStatus)
    caller <- getEffectiveUserID
    pure $ case [value | line <- lines contents, "Uid:" `prefixOf` line, value : _ <- [drop 1 (words line)]] of
        value : _ -> readMaybe value == Just caller
        [] -> False
  where
    missingStatus :: IOException -> IO ByteString.ByteString
    missingStatus _ = pure ByteString.empty
    prefixOf prefix value = take (length prefix) value == prefix

processInPath :: Int -> FilePath -> IO Bool
processInPath numericPid expected = do
    result <- canonicalizePath ("/proc/" <> show numericPid <> "/cwd") `catch` missingPath
    pure (result == expected || (expected <> "/") `prefixOf` result)
  where
    missingPath :: IOException -> IO FilePath
    missingPath _ = pure ""
    prefixOf prefix value = take (length prefix) value == prefix

processState :: Int -> IO (Maybe String)
processState numericPid = do
    fields <- processStatFields numericPid
    pure $ case fields of value : _ -> Just value; [] -> Nothing

processStartTicks :: Int -> IO (Maybe String)
processStartTicks numericPid = do
    fields <- processStatFields numericPid
    pure $ case drop 19 fields of value : _ -> Just value; [] -> Nothing

processStatFields :: Int -> IO [String]
processStatFields numericPid = do
    contents <- ByteString.unpack <$> (ByteString.readFile ("/proc/" <> show numericPid <> "/stat") `catch` missingStat)
    pure (words (drop 2 (dropWhile (/= ')') contents)))
  where
    missingStat :: IOException -> IO ByteString.ByteString
    missingStat _ = pure ByteString.empty

readPid :: FilePath -> IO (Maybe Int)
readPid path = do
    exists <- doesFileExist path
    if not exists then pure Nothing else do
        value <- ByteString.unpack <$> readFileNoFollow path
        pure $ case readMaybe value of
            Just numericPid | numericPid > (0 :: Int) && all (\character -> isDigit character || character == '\n') value -> Just numericPid
            _ -> Nothing

readOwner :: FilePath -> IO (Maybe Owner)
readOwner path = do
    exists <- doesFileExist path
    if not exists then pure Nothing else decodeStrict' <$> readFileNoFollow path

validateArtifactPaths :: FilePath -> FilePath -> FilePath -> IO DirectoryIdentity
validateArtifactPaths pidFile ownerFile logFile = do
    identity <- validateStatePaths pidFile ownerFile
    unless (takeDirectory logFile == takeDirectory pidFile) $
        reject 73 "runtime PID, owner, and log files must share one state directory"
    rejectArtifactLink logFile
    pure identity

validateStatePaths :: FilePath -> FilePath -> IO DirectoryIdentity
validateStatePaths pidFile ownerFile = do
    let parent = takeDirectory pidFile
    unless (takeDirectory ownerFile == parent) $
        reject 73 "runtime PID and owner files must share one state directory"
    inspectCanonicalPath parent >>= \case
        Left (NonCanonicalPath invalidPath) -> reject 73 ("runtime state path is not canonical: " <> invalidPath)
        Left (SymlinkPathComponent component) -> reject 73 ("runtime state path contains a symlink: " <> component)
        Right () -> pure ()
    mapM_ rejectArtifactLink [pidFile, ownerFile, pidFile <> ".manager.lock"]
    stateDirectoryIdentity parent

stateDirectoryIdentity :: FilePath -> IO DirectoryIdentity
stateDirectoryIdentity parent = do
    status <- getFileStatus parent
    pure (DirectoryIdentity (fromIntegral (deviceID status)) (fromIntegral (fileID status)))

assertStateDirectoryIdentity :: DirectoryIdentity -> FilePath -> IO ()
assertStateDirectoryIdentity expected parent = do
    inspectCanonicalPath parent >>= \case
        Left _ -> reject 73 "runtime state directory identity changed"
        Right () -> pure ()
    actual <- stateDirectoryIdentity parent
    unless (actual == expected) (reject 73 "runtime state directory identity changed")

rejectArtifactLink :: FilePath -> IO ()
rejectArtifactLink path = do
    linked <- pathIsSymbolicLink path `catch` missingLink
    when linked (reject 73 ("runtime state artifact is a symlink: " <> path))
  where
    missingLink :: IOException -> IO Bool
    missingLink errorValue | isDoesNotExistError errorValue = pure False
                           | otherwise = throwIO errorValue

openLogNoFollow :: FilePath -> IO Handle
openLogNoFollow path = openFd path WriteOnly defaultFileFlags
    { append = True, creat = Just (ownerReadMode `unionFileModes` ownerWriteMode)
    , cloexec = True, nofollow = True
    } >>= fdToHandle

readFileNoFollow :: FilePath -> IO ByteString.ByteString
readFileNoFollow path = do
    handle <- openFd path ReadOnly defaultFileFlags {cloexec = True, nofollow = True} >>= fdToHandle
    contents <- ByteString.hGetContents handle
    hClose handle
    pure contents

clearState :: FilePath -> FilePath -> IO ()
clearState pidFile ownerFile = mapM_ removeIfExists [pidFile, ownerFile]

removeIfExists :: FilePath -> IO ()
removeIfExists path = removeFile path `catch` missing
  where
    missing :: IOException -> IO ()
    missing errorValue | isDoesNotExistError errorValue = pure ()
                       | otherwise = throwIO errorValue

reject :: Int -> String -> IO a
reject status message = throwIO (RuntimeError (status, message))
