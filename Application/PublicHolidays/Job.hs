module Application.PublicHolidays.Job
    ( enqueuePublicHolidayRefreshJob
    , performPublicHolidayRefreshJob
    , publicHolidayRefreshJobDedupeKey
    , publicHolidayRefreshJobKind
    ) where

import Application.Async.Queue
import Application.Helper.LiveResource
import qualified Application.PublicHolidays.Policy as PublicHolidayPolicy
import Application.PublicHolidays.Sync
import Web.LiveResourceInvalidation (invalidateTouchedResourcesWithoutContext)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude

publicHolidayRefreshJobKind :: Text
publicHolidayRefreshJobKind = "public_holiday_refresh"

publicHolidayRefreshJobDedupeKey :: Text
publicHolidayRefreshJobDedupeKey = "public-holiday-refresh-vic"

enqueuePublicHolidayRefreshJob ::
    (?modelContext :: ModelContext) =>
    Maybe UUID ->
    IO EnqueueAppJobResult
enqueuePublicHolidayRefreshJob requestedByUserId =
    enqueueAppJob
        AppJobRequest
            { jobKind = publicHolidayRefreshJobKind
            , payload = Aeson.object ["jurisdiction" Aeson..= PublicHolidayPolicy.publicHolidayJurisdiction]
            , payloadSchemaVersion = 1
            , requestedByUserId
            , venueId = Nothing
            , relatedTable = Just "public_holidays"
            , relatedId = Nothing
            , dedupeKey = Just publicHolidayRefreshJobDedupeKey
            , runAt = Nothing
            }

performPublicHolidayRefreshJob ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
performPublicHolidayRefreshJob appJob = do
    summary <- runDataVicPublicHolidaySync
    let resultPayload =
            Aeson.object
                [ "targetYears" Aeson..= summary.targetYears
                , "fetchedCount" Aeson..= summary.fetchedCount
                , "importedCount" Aeson..= summary.importedCount
                , "insertedCount" Aeson..= summary.insertedCount
                , "updatedCount" Aeson..= summary.updatedCount
                , "skippedCount" Aeson..= summary.skippedCount
                , "invalidCount" Aeson..= summary.invalidCount
                , "prunedCount" Aeson..= summary.prunedCount
                ]
    void
        ( appJob
            |> set #result resultPayload
            |> set #status JobStatusSucceeded
            |> updateRecord
        )
    void $
        invalidateTouchedResourcesWithoutContext "support.public_holidays.refresh" $
            liveMutationResult summary [SupportPublicHolidaysResource]
