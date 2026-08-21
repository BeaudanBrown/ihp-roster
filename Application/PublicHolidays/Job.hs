module Application.PublicHolidays.Job
    ( enqueuePublicHolidayRefreshJob
    , performPublicHolidayRefreshJob
    , performPublicHolidayRefreshJobWith
    , publicHolidayRefreshJobDedupeKey
    , publicHolidayRefreshJobKind
    , publishPublicHolidayRefresh
    ) where

import Application.Async.Queue
import Application.Helper.FrontendContract.Surface.Support.Resource (supportPublicHolidaysResource)
import Application.Helper.SurfaceResource
import qualified Application.PublicHolidays.Policy as PublicHolidayPolicy
import Application.PublicHolidays.Sync
import Application.WageSourceAlert.Job (enqueueWageSourceFreshnessCheck)
import Application.WageSourceAlert.Types (WageSourceKind (DataVicWageSource))
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (withTransaction)
import Web.SurfaceInvalidation (publishTouchedResourcesWithoutContext)

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
performPublicHolidayRefreshJob = performPublicHolidayRefreshJobWith runDataVicPublicHolidaySync

performPublicHolidayRefreshJobWith
    :: (?modelContext :: ModelContext)
    => IO PublicHolidaySyncSummary
    -> AppJob
    -> IO ()
performPublicHolidayRefreshJobWith syncAction appJob = do
    summary <- syncAction
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
    completedAt <- getCurrentTime
    withTransaction do
        completedJob <-
            appJob
                |> set #result resultPayload
                |> set #status JobStatusSucceeded
                |> updateRecord
        void (enqueueWageSourceFreshnessCheck DataVicWageSource completedJob completedAt)
    publishPublicHolidayRefresh

publishPublicHolidayRefresh :: (?modelContext :: ModelContext) => IO ()
publishPublicHolidayRefresh =
    void $
        publishTouchedResourcesWithoutContext "support.public_holidays.refresh" $
            liveMutationResult () [supportPublicHolidaysResource]
