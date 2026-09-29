module Application.Script.PublicHolidayShadowSweep where

import Application.Async.Queue (EnqueueAppJobResult (..))
import Application.PublicHolidays.OverrideIncident (reconcilePublicHolidayOverridesAt)
import Application.PublicHolidays.Shadow (enqueuePublicHolidayShadowJob)
import Application.Script.Prelude
import Application.WageSourceAlert.Job (enqueueWageSourcePeriodicReconciliation)
import Application.WageSourceAlert.Types (WageSourceKind (DataVicWageSource))
import qualified Data.Text.IO as TextIO

run :: Script
run = do
    -- Keep review/expiry and stale-source monitoring when the legacy timer is
    -- disabled. This reconciliation does not renew provider freshness.
    now <- getCurrentTime
    _ <- reconcilePublicHolidayOverridesAt now
    _ <- enqueueWageSourcePeriodicReconciliation DataVicWageSource
    result <- enqueuePublicHolidayShadowJob Nothing
    liftIO $ TextIO.putStrLn $ case result of
        EnqueuedAppJob job -> "Public holiday shadow fetch queued (no import): " <> tshow job.id
        ExistingActiveAppJob job -> "Public holiday shadow fetch already active: " <> tshow job.id
