module Application.Script.PublicHolidayRefreshSweep where

import Application.Async.Queue (EnqueueAppJobResult (..))
import Application.PublicHolidays.Job
import Application.PublicHolidays.OverrideIncident (reconcilePublicHolidayOverridesAt)
import Application.Script.Prelude
import Application.WageSourceAlert.Job (enqueueWageSourcePeriodicReconciliation)
import Application.WageSourceAlert.Types (WageSourceKind (DataVicWageSource))
import qualified Data.Text.IO as TextIO

run :: Script
run = do
    now <- getCurrentTime
    _ <- reconcilePublicHolidayOverridesAt now
    _ <- enqueueWageSourcePeriodicReconciliation DataVicWageSource
    enqueueResult <- enqueuePublicHolidayRefreshJob Nothing
    liftIO do
        case enqueueResult of
            EnqueuedAppJob appJob ->
                TextIO.putStrLn ("Public holiday refresh job enqueued: " <> tshow appJob.id)
            ExistingActiveAppJob appJob ->
                TextIO.putStrLn ("Public holiday refresh job already active: " <> tshow appJob.id)
