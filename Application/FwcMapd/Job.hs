module Application.FwcMapd.Job
    ( enqueueFwcMapdRefreshJob
    , fwcMapdRefreshJobDedupeKey
    , fwcMapdRefreshJobKind
    , performFwcMapdRefreshJob
    ) where

import Application.Async.Queue
import Application.FwcMapd.Sync
import Application.Helper.LiveResource
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import Web.LiveResourceInvalidation (invalidateTouchedResourcesWithoutContext)

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
performFwcMapdRefreshJob appJob = do
    syncResult <- runConfiguredMapdSync
    case syncResult of
        Left err ->
            fail (Text.unpack err)
        Right summary -> do
            let resultPayload =
                    Aeson.object
                        [ "syncedAwardFixedIds" Aeson..= summary.syncedAwardFixedIds
                        , "fetchedAwardCount" Aeson..= summary.fetchedAwardCount
                        , "fetchedClassificationCount" Aeson..= summary.fetchedClassificationCount
                        , "fetchedPayRateCount" Aeson..= summary.fetchedPayRateCount
                        ]
            void
                ( appJob
                    |> set #result resultPayload
                    |> set #status JobStatusSucceeded
                    |> updateRecord
                )
            void $
                invalidateTouchedResourcesWithoutContext "support.award_rates.refresh" $
                    liveMutationResult summary [supportAwardRatesResource]
