module Main (main) where

import Bepis.Tooling.Runtime.Process
import Control.Concurrent (threadDelay)
import Control.Monad (unless, when)
import System.Exit (die)
import System.FilePath ((</>))
import System.IO.Temp (withSystemTempDirectory)

main :: IO ()
main = withSystemTempDirectory "bepis-runtime" $ \root -> do
    let pidFile = root </> "service.pid"
        ownerFile = root </> "service.owner.json"
        logFile = root </> "service.log"
    child <- startOwned pidFile ownerFile logFile root "fixture" "sleep" ["30"]
    observation <- observeOwned pidFile ownerFile root "fixture"
    unless (observedOwned observation && observedPid observation == Just child) (die "started child was not owned")
    stopped <- stopOwned pidFile ownerFile root "fixture" 1000
    unless stopped (die "owned child was not stopped")
    threadDelay 100000
    absent <- observeOwned pidFile ownerFile root "fixture"
    when (observedAlive absent) (die "stopped child remained alive")
