module Bepis.Tooling.Postgres
    ( runPostgresCommand
    ) where

import Bepis.Tooling.Core.OwnedFile (tryWithExclusiveLock)
import Bepis.Tooling.Postgres.Config (ConfigError (..), Profile (..))
import Bepis.Tooling.Postgres.Lifecycle (PostgresError (..), runProfileCommand)
import Control.Concurrent (threadDelay)
import Control.Exception (catch)
import Control.Monad (unless)
import Data.Maybe (fromMaybe)
import System.Environment (getArgs, lookupEnv)
import System.Exit (ExitCode (..), exitWith)
import System.IO (hPutStrLn, stderr)
import System.Process (StdStream (Inherit), createProcess, proc, readProcessWithExitCode,
                       std_err, std_in, std_out, waitForProcess)
import Text.Read (readMaybe)

runPostgresCommand :: IO ()
runPostgresCommand = dispatch `catch` handleConfig `catch` handlePostgres
  where
    handleConfig (ConfigError status message) = hPutStrLn stderr message >> exitWith (ExitFailure status)
    handlePostgres (PostgresError status message) = hPutStrLn stderr message >> exitWith (ExitFailure status)

dispatch :: IO ()
dispatch = do
    arguments <- getArgs
    case arguments of
        "profile":"hspec":command:rest -> runProfileCommand Hspec command rest
        "profile":"dev":command:rest -> runProfileCommand Development command rest
        "profile":"e2e":command:rest -> runProfileCommand E2E command rest
        "maintenance-run":lockPath:message:"--":command:rest -> maintenanceRun lockPath message command rest
        ["app-running"] -> appRunning
        ["wait-app-recovery"] -> waitForAppRecovery
        _ -> hPutStrLn stderr usage >> exitWith (ExitFailure 64)

usage :: String
usage = "Usage: bepis-postgres profile hspec|dev|e2e COMMAND [ARGS...] | maintenance-run LOCK MESSAGE -- COMMAND [ARGS...]"

maintenanceRun :: FilePath -> String -> FilePath -> [String] -> IO ()
maintenanceRun lockPath busyMessage command arguments = do
    result <- tryWithExclusiveLock lockPath $ do
        (_, _, _, handle) <- createProcess (proc command arguments) {std_in = Inherit, std_out = Inherit, std_err = Inherit}
        waitForProcess handle
    case result of
        Nothing -> hPutStrLn stderr busyMessage >> exitWith (ExitFailure 75)
        Just status -> exitWith status

appRunning :: IO ()
appRunning = do
    port <- requiredEnvironment "PORT"
    (status, _, _) <- readProcessWithExitCode "lsof" ["-nP", "-iTCP:" <> port, "-sTCP:LISTEN"] ""
    putStrLn (if status == ExitSuccess then "1" else "0")

waitForAppRecovery :: IO ()
waitForAppRecovery = do
    wasRunning <- lookupEnv "BEPIS_DEV_DB_APP_WAS_RUNNING"
    if wasRunning /= Just "1" then pure () else do
        attemptsText <- fromMaybe "200" <$> lookupEnv "BEPIS_DEV_DB_RECOVERY_ATTEMPTS"
        attempts <- case readMaybe attemptsText of
            Just value | value > (0 :: Int) -> pure value
            _ -> failStatus 64 "BEPIS_DEV_DB_RECOVERY_ATTEMPTS must be positive"
        appUrl <- lookupEnv "APP_BASE_URL" >>= maybe defaultUrl pure
        socket <- requiredEnvironment "PGHOST"
        recovered <- loop attempts appUrl socket "unavailable"
        unless recovered $ failStatus 75 "dev-db-maintenance: database maintenance completed, but the running app did not recover"
  where
    defaultUrl = do port <- requiredEnvironment "PORT"; pure ("http://127.0.0.1:" <> port)
    loop remaining appUrl socket lastCount
        | remaining <= (0 :: Int) = hPutStrLn stderr ("Expected app health at " <> appUrl <> " and one durable listener; listener_count=" <> lastCount <> ".") >> pure False
        | otherwise = do
            (curlStatus, _, _) <- readProcessWithExitCode "curl" ["--connect-timeout", "1", "--max-time", "2", "-fsS", appUrl] ""
            (psqlStatus, countOutput, _) <- readProcessWithExitCode "psql" ["-X", "-h", socket, "-d", "app", "-At", "-v", "ON_ERROR_STOP=1", "-c", "SELECT COUNT(*)::INT FROM pg_stat_activity WHERE application_name = 'bepis-live-invalidation-listener'"] ""
            let count = trim countOutput
            if curlStatus == ExitSuccess && psqlStatus == ExitSuccess && count == "1"
                then putStrLn "dev-db-maintenance: running app recovered with exactly one durable listener" >> pure True
                else threadDelay 100000 >> loop (remaining - 1) appUrl socket count

requiredEnvironment :: String -> IO String
requiredEnvironment name = lookupEnv name >>= maybe (failStatus 69 ("dev-db-maintenance: " <> name <> " is not configured")) pure

trim :: String -> String
trim = reverse . dropWhile (`elem` ['\n', '\r']) . reverse

failStatus :: Int -> String -> IO value
failStatus status message = hPutStrLn stderr message >> exitWith (ExitFailure status)
