module Bepis.Tooling.Workspace.Reclaim (runtimeAbsent) where

import Bepis.Tooling.Workspace.State (RuntimeReservation (..), inspectCanonicalPath, runtimePorts)
import Control.Exception (IOException, catch)
import qualified Data.ByteString.Char8 as Bytes
import Data.Char (isDigit, isSpace)
import Data.List (isPrefixOf, isSuffixOf)
import Numeric (readHex)
import System.Directory (listDirectory)
import System.FilePath ((</>))
import System.IO.Error (isDoesNotExistError)
import System.Posix.Files (fileOwner, getFileStatus, getSymbolicLinkStatus, isDirectory, readSymbolicLink)
import System.Posix.Types (UserID)
import System.Posix.User (getEffectiveUserID)

-- Called under the registry lock only after a successful Git inventory has
-- positively excluded this path. Read-only evidence; nothing is stopped,
-- unlinked, or reclaimed on ambiguous observation.
runtimeAbsent :: RuntimeReservation -> IO Bool
runtimeAbsent reservation = prove `catch` unknown
  where
    prove = do
        missing <- absentPath (runtimePath reservation)
        if not missing || null (runtimeStateDirs reservation) then pure False else do
            uid <- getEffectiveUserID
            cleanState <- allIO (stateClear uid) (runtimeStateDirs reservation)
            cleanPostgres <- allIO (postgresClear uid) (runtimePostgresRoots reservation)
            if not (cleanState && cleanPostgres) then pure False else do
                ps <- processClear uid (runtimePath reservation : runtimeStateDirs reservation <> runtimePostgresRoots reservation)
                sockets <- allIO (portsClear (runtimePorts (runtimeSlot reservation) (runtimePortOffset reservation)))
                    ["tcp", "tcp6", "udp", "udp6"]
                pure (ps && sockets)
    unknown :: IOException -> IO Bool
    unknown _ = pure False

allIO :: (a -> IO Bool) -> [a] -> IO Bool
allIO _ [] = pure True
allIO predicate (value:rest) = do
    ok <- predicate value
    if ok then allIO predicate rest else pure False

absentPath :: FilePath -> IO Bool
absentPath path = do
    canonical <- inspectCanonicalPath path
    case canonical of
        Left _ -> pure False
        Right () -> absentOnENOENT (False <$ getSymbolicLinkStatus path) True

absentOnENOENT :: IO a -> a -> IO a
absentOnENOENT action fallback = action `catch` handler
  where
    handler err | isDoesNotExistError err = pure fallback
                | otherwise = ioError err

ownedDirectoryClear :: UserID -> FilePath -> IO Bool -> IO Bool
ownedDirectoryClear uid path inspect = do
    missing <- absentPath path
    if missing then pure True else do
        canonical <- inspectCanonicalPath path
        info <- getSymbolicLinkStatus path
        if canonical == Right () && isDirectory info && fileOwner info == uid then inspect else pure False

stateClear :: UserID -> FilePath -> IO Bool
stateClear uid path = ownedDirectoryClear uid path $ do
    entries <- listDirectory path
    pure (not (any (\name -> ".pid" `isSuffixOf` name || ".owner.json" `isSuffixOf` name) entries))

postgresClear :: UserID -> FilePath -> IO Bool
postgresClear uid root = ownedDirectoryClear uid root $ do
    noPid <- absentPath (root </> "data/postmaster.pid")
    noSocket <- ownedDirectoryClear uid (root </> "socket") $
        not . any (".s.PGSQL." `isPrefixOf`) <$> listDirectory (root </> "socket")
    pure (noPid && noSocket)

processClear :: UserID -> [FilePath] -> IO Bool
processClear uid roots = do
    localProc <- getFileStatus "/proc/self"
    pidEntries <- filter (\entry -> not (null entry) && all isDigit entry) <$> listDirectory "/proc"
    if fileOwner localProc /= uid || null pidEntries then pure False else allIO inspectProcess pidEntries
  where
    inspectProcess pid = do
        let proc = "/proc" </> pid
        absentOnENOENT (inspect proc) True
    inspect proc = do
        info <- getFileStatus proc
        if fileOwner info /= uid then pure True else do
            -- Zombies can have no cwd. For a still listed live process do not
            -- count an unreadable cwd/environment as proof of absence.
            cwd <- absentOnENOENT (Just <$> readSymbolicLink (proc </> "cwd")) Nothing
            case cwd of
                Nothing -> do
                    status <- Bytes.readFile (proc </> "status")
                    pure (any (Bytes.isPrefixOf (Bytes.pack "State:\tZ")) (Bytes.lines status))
                Just directory -> do
                    env <- Bytes.readFile (proc </> "environ")
                    args <- Bytes.readFile (proc </> "cmdline")
                    let within directoryPath root = directoryPath == root || (root <> "/") `isPrefixOf` directoryPath || directoryPath == root <> " (deleted)"
                        referenced root = within directory root || Bytes.pack root `Bytes.isInfixOf` env || Bytes.pack root `Bytes.isInfixOf` args
                    pure (not (any referenced roots))

portsClear :: [Int] -> FilePath -> IO Bool
portsClear reserved table = do
    entries <- lines . Bytes.unpack <$> Bytes.readFile ("/proc/net" </> table)
    case entries of
        header:rows | "local_address" `elem` words header -> pure (all clear rows)
        _ -> pure False
  where
    clear row | all isSpace row = True
    clear row = case words row of
        _index:address:_remote:socketState:_ -> case break (== ':') address of
            (_, ':':hexPort) -> case readHex hexPort of
                [(port, "")] -> socketState == "06" || port `notElem` reserved -- TCP TIME_WAIT is not a live owner.
                _ -> False
            _ -> False
        _ -> False
