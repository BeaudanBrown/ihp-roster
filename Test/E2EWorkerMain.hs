module Test.E2EWorkerMain (main) where

import Application.Script.Prelude
import qualified Config
import qualified Control.Concurrent as Concurrent
import qualified Control.Concurrent.Async as Async
import Control.Monad (void)
import Control.Monad.Trans.Resource (allocate)
import qualified Data.HashMap.Strict as HashMap
import Data.IORef (readIORef)
import qualified Data.Set as Set
import IHP.Job.Runner
import IHP.Job.Types (JobWorker (..))
import qualified IHP.PGListener as PGListener
import IHP.ScriptSupport
import qualified System.Environment as Env
import System.Exit (die)
import Test.E2EXero (seedXeroFixture, withE2EXero)
import Test.VerificationPhase (verificationReady)
import WorkerMain ()

-- Match IHP 1.6's packaged RunJobs entry point; the E2E launcher supplies each
-- shard's disposable database and local mail/provider configuration.
main :: IO ()
main = Env.getArgs >>= \case
    [] -> withE2EXero (runScript Config.config (runJobWorkers (observeReadiness (workers RootApplication))))
    ["seed-xero"] -> runScript Config.config seedXeroFixture
    _ -> die "Unknown E2E worker arguments"

-- Resource-scoped observation only: never add a startup gate or change job
-- order/concurrency. IHP registers subscriptions before acknowledging LISTEN;
-- watch its acknowledged set, not merely the constructor's return or PID life.
observeReadiness :: [JobWorker] -> [JobWorker]
observeReadiness [] = []
observeReadiness [JobWorker start] =
    [ JobWorker (\args -> do
        process <- start args
        target <- liftIO (Env.lookupEnv "BEPIS_VERIFICATION_EVENTS")
        case target of
            Just value | value /= "" -> do
                expected <- liftIO (Set.fromList . HashMap.keys <$> readIORef (PGListener.subscriptions args.pgListener))
                let awaitAcknowledgement = do
                        listening <- Concurrent.readMVar (PGListener.listeningTo args.pgListener)
                        if not (Set.null expected) && expected `Set.isSubsetOf` listening
                            then verificationReady "e2e-worker-startup"
                            else Concurrent.threadDelay verificationReadinessPollMicroseconds >> awaitAcknowledgement
                void $ allocate (Async.async awaitAcknowledgement) Async.cancel
            _ -> pure ()
        pure process)
    ]
observeReadiness (current : remaining) = current : observeReadiness remaining

verificationReadinessPollMicroseconds :: Int
verificationReadinessPollMicroseconds = 20000
