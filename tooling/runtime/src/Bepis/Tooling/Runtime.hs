module Bepis.Tooling.Runtime (runRuntimeCommand) where

import Bepis.Tooling.Runtime.Process
import Bepis.Tooling.Runtime.Resource (execInWorkspaceResource)
import Control.Concurrent (threadDelay)
import Control.Exception (catch)
import Control.Monad (void)
import qualified Data.Text as Text
import GHC.Clock (getMonotonicTimeNSec)
import System.Environment (getArgs)
import System.Exit (ExitCode (..), exitWith)
import System.IO (hPutStrLn, stderr)
import System.Process (readProcessWithExitCode)
import System.Timeout (timeout)
import Text.Read (readMaybe)

runRuntimeCommand :: IO ()
runRuntimeCommand = dispatch `catch` handleRuntime
  where
    handleRuntime (RuntimeError (status, message)) = hPutStrLn stderr message >> exitWith (ExitFailure status)

dispatch :: IO ()
dispatch = do
    arguments <- getArgs
    case arguments of
        "process":"start":pidFile:ownerFile:logFile:label:cwd:"--":command:rest ->
            startOwned pidFile ownerFile logFile cwd label command rest >>= print
        "process":"start-result":pidFile:ownerFile:logFile:label:cwd:"--":command:rest -> do
            (childPid, created) <- startOwnedResult pidFile ownerFile logFile cwd label command rest
            putStrLn ("pid=" <> show childPid <> " created=" <> boolean created)
        ["process", "adopt", pidFile, ownerFile, label, cwd, pidText] -> case readMaybe pidText of
            Just childPid | childPid > (0 :: Int) -> adoptOwned pidFile ownerFile cwd label childPid
            _ -> invalid
        ["process", "release", pidFile, ownerFile, label, cwd, pidText] -> case readMaybe pidText of
            Just childPid | childPid > (0 :: Int) -> void (releaseOwned pidFile ownerFile cwd label childPid)
            _ -> invalid
        ["process", "observe", pidFile, ownerFile, label, cwd] -> do
            observation <- observeOwned pidFile ownerFile cwd label
            putStrLn ("pid=" <> maybe "none" show (observedPid observation)
                <> " alive=" <> boolean (observedAlive observation)
                <> " owned=" <> boolean (observedOwned observation)
                <> " reason=" <> observedReason observation)
            if observedOwned observation then pure () else exitWith (ExitFailure 3)
        ["process", "stop-invocation", pidFile, ownerFile, label, cwd, invocation, graceText] -> case readMaybe graceText of
            Just grace | grace >= (0 :: Int) -> void (stopOwnedForInvocation pidFile ownerFile cwd label (Text.pack invocation) grace)
            _ -> invalid
        ["process", "stop", pidFile, ownerFile, label, cwd, graceText] -> case readMaybe graceText of
            Just grace | grace >= (0 :: Int) -> stopOwned pidFile ownerFile cwd label grace >>= \stopped -> putStrLn (if stopped then label <> " stopped" else label <> " not owned; not stopping")
            _ -> invalid
        "resource":"exec":commonDirectory:kind:slot:"--":command:rest -> execInWorkspaceResource commonDirectory kind slot command rest
        "wait-command":timeoutText:label:logFile:"--":command:rest -> case readMaybe timeoutText of
            Just timeoutValue | timeoutValue > (0 :: Int) -> waitCommand timeoutValue label logFile command rest
            _ -> invalid
        "wait-owned-command":timeoutText:label:logFile:pidFile:ownerFile:cwd:"--":command:rest -> case readMaybe timeoutText of
            Just timeoutValue | timeoutValue > (0 :: Int) -> waitOwnedCommand timeoutValue label logFile pidFile ownerFile cwd command rest
            _ -> invalid
        _ -> invalid
  where
    boolean True = "true"
    boolean False = "false"
    invalid = hPutStrLn stderr usage >> exitWith (ExitFailure 64)

waitCommand :: Int -> String -> FilePath -> FilePath -> [String] -> IO ()
waitCommand timeoutMilliseconds label logFile command arguments =
    waitLoop timeoutMilliseconds label logFile (pure True) command arguments

waitOwnedCommand :: Int -> String -> FilePath -> FilePath -> FilePath -> FilePath -> FilePath -> [String] -> IO ()
waitOwnedCommand timeoutMilliseconds label logFile pidFile ownerFile cwd command arguments =
    waitLoop timeoutMilliseconds label logFile ownerAlive command arguments
  where
    ownerAlive = observedOwned <$> observeOwned pidFile ownerFile cwd label

waitLoop :: Int -> String -> FilePath -> IO Bool -> FilePath -> [String] -> IO ()
waitLoop timeoutMilliseconds label logFile stillRunning command arguments = do
    started <- getMonotonicTimeNSec
    let deadline = started + fromIntegral timeoutMilliseconds * 1000000
        loop = do
            running <- stillRunning
            if not running
                then hPutStrLn stderr (label <> " exited before readiness; inspect " <> logFile) >> exitWith (ExitFailure 75)
                else do
                    now <- getMonotonicTimeNSec
                    if now >= deadline then timedOut else do
                        let remainingMicroseconds = max 1 (fromIntegral ((deadline - now) `div` 1000))
                        probe <- timeout remainingMicroseconds (readProcessWithExitCode command arguments "")
                        case probe of
                            Just (ExitSuccess, _, _) -> pure ()
                            Nothing -> timedOut
                            Just _ -> threadDelay 200000 >> loop
        timedOut = hPutStrLn stderr (label <> " did not become ready within " <> show timeoutMilliseconds <> "ms; inspect " <> logFile) >> exitWith (ExitFailure 75)
    loop

usage :: String
usage = "Usage: bepis-runtime process start PID OWNER LOG LABEL CWD -- COMMAND [ARGS...] | process start-result PID OWNER LOG LABEL CWD -- COMMAND [ARGS...] | process adopt PID OWNER LABEL CWD CHILD_PID | process observe PID OWNER LABEL CWD | process stop PID OWNER LABEL CWD GRACE_MS | wait-command TIMEOUT_MS LABEL LOG -- COMMAND [ARGS...]"
