{-# LANGUAGE TypeApplications #-}

module Application.FwcMapd.Job
    ( enqueueFwcMapdRefreshJob
    , fwcMapdRefreshJobDedupeKey
    , fwcMapdRefreshJobKind
    , performFwcMapdRefreshJob
    , performFwcMapdRefreshJobWith
    ) where

import Application.Async.Boundary (throwAppJobError, trySynchronousAppJobAction)
import Application.Async.Error (AppJobError (..))
import Application.Async.Payload (decodeAppJobPayloadV1, requireAppJobPayloadV1)
import Application.Async.Queue
import Application.FwcMapd.Error
import Application.FwcMapd.Sync
import Application.Helper.FrontendContract.Surface.Support.Resource (supportAwardRatesResource)
import Application.Helper.SurfaceResource
import Application.WageSourceAlert.Job (enqueueWageSourceFreshnessCheck)
import Application.WageSourceAlert.Types (WageSourceKind (FwcWageSource))
import qualified Control.Exception as Exception
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude
import Application.Helper.LiveUpdate.BackgroundMutation (withDurableLiveMutationWithoutContext)

data FwcMapdRefreshPayload = FwcMapdRefreshPayload

instance Aeson.FromJSON FwcMapdRefreshPayload where
    parseJSON = Aeson.withObject "FwcMapdRefreshPayload" (const (pure FwcMapdRefreshPayload))

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
    requireAppJobPayloadV1 appJob
    when (appJob.relatedTable /= Just "fwc_mapd_sync_runs" || isJust appJob.relatedId) do
        throwAppJobError JobInvalidProvenance
    void (decodeAppJobPayloadV1 @FwcMapdRefreshPayload appJob)
    syncAttempt <- trySynchronousAppJobAction syncAction
    case syncAttempt of
        Left exception -> throwAppJobError (mapdJobError exception)
        Right (Left _) -> throwAppJobError JobConfigurationUnavailable
        Right (Right summary) -> do
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

mapdJobError :: Exception.SomeException -> AppJobError
mapdJobError exception =
    case Exception.fromException exception of
        Just MapdProviderUnavailable -> JobTransportUnavailable
        Just MapdResponseMalformed   -> JobMalformedResponse
        Just MapdSnapshotInvalid     -> JobValidationRejected
        Nothing                      -> JobUnexpectedSynchronousFailure
