module Application.FwcMapd.Job
    ( enqueueFwcMapdRefreshJob
    , fwcMapdRefreshJobDedupeKey
    , fwcMapdRefreshJobKind
    , performFwcMapdRefreshJob
    , performFwcMapdRefreshJobWith
    ) where

import Application.Async.Queue
import Application.FwcMapd.Sync
import Application.Helper.FrontendContract.Surface.Support.Resource (supportAwardRatesResource)
import Application.Helper.SurfaceResource
import Application.WageSourceAlert.Job (enqueueWageSourceFreshnessCheck)
import Application.WageSourceAlert.Types (WageSourceKind (FwcWageSource))
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import Web.SurfaceInvalidation (withDurableLiveMutationWithoutContext)

fwcMapdRefreshJobKind :: Text
fwcMapdRefreshJobKind = "fwc_mapd_refresh"

fwcMapdRefreshJobDedupeKey :: Text
fwcMapdRefreshJobDedupeKey = "fwc-mapd-refresh"

enqueueFwcMapdRefreshJob ::
    (?modelContext :: ModelContext) =>
    Maybe UUID ->
    IO EnqueueAppJobResult
enqueueFwcMapdRefreshJob requestedByUserId =
    enqueueAppJob
        AppJobRequest
            { jobKind = fwcMapdRefreshJobKind
            , payload = Aeson.object []
            , payloadSchemaVersion = 1
            , requestedByUserId
            , venueId = Nothing
            , relatedTable = Just "fwc_mapd_sync_runs"
            , relatedId = Nothing
            , dedupeKey = Just fwcMapdRefreshJobDedupeKey
            , runAt = Nothing
            }

performFwcMapdRefreshJob ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
performFwcMapdRefreshJob = performFwcMapdRefreshJobWith runConfiguredMapdSync

performFwcMapdRefreshJobWith
    :: (?modelContext :: ModelContext)
    => IO (Either Text MapdSyncSummary)
    -> AppJob
    -> IO ()
performFwcMapdRefreshJobWith syncAction appJob = do
    syncResult <- syncAction
    case syncResult of
        Left err ->
            fail (Text.unpack err)
        Right summary -> do
            completedAt <- getCurrentTime
            void $ withDurableLiveMutationWithoutContext "support.award_rates.refresh" do
                let resultPayload =
                        Aeson.object
                            [ "syncedAwardFixedIds" Aeson..= summary.syncedAwardFixedIds
                            , "fetchedAwardCount" Aeson..= summary.fetchedAwardCount
                            , "fetchedClassificationCount" Aeson..= summary.fetchedClassificationCount
                            , "fetchedPayRateCount" Aeson..= summary.fetchedPayRateCount
                            ]
                completedJob <-
                    appJob
                        |> set #result resultPayload
                        |> set #status JobStatusSucceeded
                        |> updateRecord
                void (enqueueWageSourceFreshnessCheck FwcWageSource completedJob completedAt)
                pure (liveMutationResult () [supportAwardRatesResource])
