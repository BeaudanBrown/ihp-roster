module Bepis.Tooling.Runtime.Resource (execInWorkspaceResource) where

import Bepis.Tooling.Runtime.Process (RuntimeError (..))
import Control.Exception (throwIO)
import Control.Monad (unless)
import Data.Char (isSpace)
import Data.List (isInfixOf)
import Data.Maybe (fromMaybe, isJust)
import System.Directory (findExecutable)
import System.Environment (lookupEnv)
import System.Exit (ExitCode (..))
import System.IO (hPutStrLn, stderr)
import System.Posix.Process (executeFile)
import System.Process (readProcessWithExitCode)

execInWorkspaceResource :: FilePath -> String -> String -> FilePath -> [String] -> IO ()
execInWorkspaceResource commonDirectory kind slot command arguments = do
    sharing <- fromMaybe "on" <$> lookupEnv "BEPIS_WORKSPACE_CPU_SHARING"
    if sharing == "off" then fallback "CPU sharing explicitly disabled" else do
        repositoryId <- hashPrefix commonDirectory
        workspaceId <- case kind of
            "primary" -> pure "primary"
            "epic" | validSlot slot -> pure ("epic" <> slot)
            _ -> failWith "invalid workspace resource identity"
        let parentSlice = "bepis-" <> repositoryId <> ".slice"
            workspaceSlice = "bepis-" <> repositoryId <> "-" <> workspaceId <> ".slice"
        available <- resourceAvailable
        if not available then fallback "cgroup v2 user-systemd unavailable" else do
            systemctl <- fromMaybe "systemctl" <$> lookupEnv "BEPIS_SYSTEMCTL_COMMAND"
            prepared <- succeeds systemctl ["--user", "start", parentSlice, workspaceSlice]
            weighted <- if prepared then succeeds systemctl ["--user", "set-property", "--runtime", workspaceSlice, "CPUWeight=100"] else pure False
            if not weighted then fallback "cannot prepare equal-weight workspace slice" else do
                current <- readFile "/proc/self/cgroup"
                if ("/" <> workspaceSlice <> "/") `isInfixOf` ("/" <> cgroupPath current <> "/")
                    then execute command arguments
                    else do
                        systemdRun <- fromMaybe "systemd-run" <$> lookupEnv "BEPIS_SYSTEMD_RUN_COMMAND"
                        execute systemdRun (["--user", "--scope", "--quiet", "--collect", "--slice=" <> workspaceSlice, "--", command] <> arguments)
  where
    fallback reason = hPutStrLn stderr ("workspace-cpu: warning: " <> reason <> "; launching uncontained") >> execute command arguments
    execute executable argv = executeFile executable True argv Nothing

resourceAvailable :: IO Bool
resourceAvailable = do
    (status, output, _) <- readProcessWithExitCode "stat" ["-fc", "%T", "/sys/fs/cgroup"] ""
    systemctl <- fromMaybe "systemctl" <$> lookupEnv "BEPIS_SYSTEMCTL_COMMAND"
    systemdRun <- fromMaybe "systemd-run" <$> lookupEnv "BEPIS_SYSTEMD_RUN_COMMAND"
    commands <- (&&) <$> (isJust <$> findExecutable systemctl) <*> (isJust <$> findExecutable systemdRun)
    healthy <- if commands then succeeds systemctl ["--user", "is-system-running"] else pure False
    pure (status == ExitSuccess && trim output == "cgroup2fs" && healthy)

succeeds :: FilePath -> [String] -> IO Bool
succeeds command arguments = do
    (status, _, _) <- readProcessWithExitCode command arguments ""
    pure (status == ExitSuccess)

hashPrefix :: String -> IO String
hashPrefix value = do
    (status, output, _) <- readProcessWithExitCode "sha256sum" [] value
    unless (status == ExitSuccess) (failWith "sha256sum failed")
    pure (take 12 output)

validSlot :: String -> Bool
validSlot (first : rest) = first /= '0' && all (`elem` ['0'..'9']) (first : rest)
validSlot [] = False

cgroupPath :: String -> String
cgroupPath contents = case [drop 3 line | line <- lines contents, take 2 line == "0:"] of value : _ -> value; [] -> ""

trim :: String -> String
trim = reverse . dropWhile isSpace . reverse . dropWhile isSpace

failWith :: String -> IO a
failWith message = throwIO (RuntimeError (64, "bepis-runtime: " <> message))
