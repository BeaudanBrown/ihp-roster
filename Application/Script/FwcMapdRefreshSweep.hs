module Application.Script.FwcMapdRefreshSweep where

import Application.Async.Queue (EnqueueAppJobResult (..))
import Application.FwcMapd.Job
import Application.Script.Prelude
import Application.WageSourceAlert.Job (enqueueWageSourcePeriodicReconciliation)
import Application.WageSourceAlert.Types (WageSourceKind (FwcWageSource))
import qualified Data.Text.IO as TextIO

run :: Script
run = do
    _ <- enqueueWageSourcePeriodicReconciliation FwcWageSource
    enqueueResult <- enqueueFwcMapdRefreshJob Nothing
    liftIO do
        case enqueueResult of
            EnqueuedAppJob appJob ->
                TextIO.putStrLn ("FWC MAPD refresh job enqueued: " <> tshow appJob.id)
            ExistingActiveAppJob appJob ->
                TextIO.putStrLn ("FWC MAPD refresh job already active: " <> tshow appJob.id)
