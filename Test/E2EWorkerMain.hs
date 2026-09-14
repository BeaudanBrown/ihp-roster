module Test.E2EWorkerMain (main) where

import Application.Script.Prelude
import qualified Config
import IHP.Job.Runner
import IHP.ScriptSupport
import WorkerMain ()

-- Match IHP 1.6's packaged RunJobs entry point; the E2E launcher supplies each
-- shard's disposable database and local mail/provider configuration.
main :: IO ()
main = runScript Config.config (runJobWorkers (workers RootApplication))
