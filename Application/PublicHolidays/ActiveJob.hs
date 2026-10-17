module Application.PublicHolidays.ActiveJob
    ( activePublicHolidayJobKind
    , enqueueActivePublicHolidayJob
    , performActivePublicHolidayJob
    ) where

import Application.Async.Boundary (throwAppJobError)
import Application.Async.Error (AppJobError (..))
import Application.Async.Payload (requireAppJobPayloadV1)
import Application.Async.Queue
import Application.PublicHolidays.ActiveImport
import Application.PublicHolidays.Sync (PublicHolidaySyncSummary (..))
import Application.WageSourceAlert.Job (enqueueWageSourceFreshnessCheck)
import Application.WageSourceAlert.Types (WageSourceKind (DataVicWageSource))
import qualified Data.Aeson as Aeson
import Control.Monad (void)
import Generated.Types
import IHP.ControllerPrelude

activePublicHolidayJobKind :: Text
activePublicHolidayJobKind = "public_holiday_active_import"

enqueueActivePublicHolidayJob :: (?modelContext :: ModelContext) => IO EnqueueAppJobResult
enqueueActivePublicHolidayJob = do
    enabled <- activeImportEnabled
    unless enabled (throwAppJobError JobConfigurationUnavailable)
    enqueueAppJob AppJobRequest
        { jobKind = activePublicHolidayJobKind
        , payload = Aeson.object ["jurisdiction" Aeson..= ("VIC" :: Text)]
        , payloadSchemaVersion = 1
        , requestedByUserId = Nothing, venueId = Nothing
        , relatedTable = Just "public_holidays", relatedId = Nothing
        , dedupeKey = Just "public-holiday-active-import-vic", runAt = Nothing
        }

performActivePublicHolidayJob :: (?modelContext :: ModelContext) => AppJob -> IO ()
performActivePublicHolidayJob job = do
    requireAppJobPayloadV1 job
    unless (job.relatedTable == Just "public_holidays" && isNothing job.relatedId
        && job.payload == Aeson.object ["jurisdiction" Aeson..= ("VIC" :: Text)])
        (throwAppJobError JobInvalidProvenance)
    void $ refreshPublicHolidaysWith \summary now -> do
        completed <- job
            |> set #status JobStatusSucceeded
            |> set #result (Aeson.object
                [ "targetYears" Aeson..= summary.targetYears
                , "importedCount" Aeson..= summary.importedCount
                , "prunedCount" Aeson..= summary.prunedCount ])
            |> updateRecord
        void (enqueueWageSourceFreshnessCheck DataVicWageSource completed now)
