module Test.E2EWorkerMain (main) where

import Application.Script.Prelude
import qualified Config
import IHP.Job.Runner
import IHP.ScriptSupport
import qualified System.Environment as Env
import System.Exit (die)
import Test.E2EXero (seedXeroFixture, withE2EXero)
import WorkerMain ()

-- Match IHP 1.6's packaged RunJobs entry point; the E2E launcher supplies each
-- shard's disposable database and local mail/provider configuration.
main :: IO ()
main = Env.getArgs >>= \case
    [] -> withE2EXero (runScript Config.config (runJobWorkers (workers RootApplication)))
    ["seed-xero"] -> runScript Config.config seedXeroFixture
    _ -> die "Unknown E2E worker arguments"
