module Application.Xero.ReferenceTrust.ReadModel
    ( XeroReferenceTrustState (..)
    , fetchXeroReferenceSyncActivity
    , fetchXeroReferenceTrustState
    ) where

import Application.Xero.ReferenceSyncJob (xeroReferenceSyncJobKind)
import Application.Xero.ReferenceTrust
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import Generated.Types
import IHP.ControllerPrelude

data XeroReferenceTrustState = XeroReferenceTrustState
    { trustDecision      :: !XeroReferenceTrustDecision
    , syncActivity       :: !XeroReferenceSyncActivity
    , syncProgress       :: !XeroReferenceSyncProgressFacts
    , syncSanitizedError :: !(Maybe Text)
    }
    deriving (Eq, Show)

fetchXeroReferenceTrustState ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    XeroConnection ->
    XeroMissingReferenceDemand ->
    IO XeroReferenceTrustState
fetchXeroReferenceTrustState now connection missingReferenceDemand = do
    syncActivity <- fetchXeroReferenceSyncActivity now connection
    syncProgress <- fetchXeroReferenceSyncProgress syncActivity connection
    let syncSanitizedError = sanitizedReferenceSyncError syncActivity syncProgress
    let trustDecision = decideXeroReferenceTrust now connection.connectionStatus connection.lastSyncAt missingReferenceDemand syncActivity
    pure XeroReferenceTrustState { .. }

fetchXeroReferenceSyncActivity ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    XeroConnection ->
    IO XeroReferenceSyncActivity
fetchXeroReferenceSyncActivity now connection = do
    maybeActiveJob <-
        query @AppJob
            |> filterWhere (#jobKind, xeroReferenceSyncJobKind)
            |> filterWhere (#relatedId, Just (unpackId connection.id))
            |> filterWhereIn (#status, [JobStatusNotStarted, JobStatusRunning, JobStatusRetry])
            |> orderByDesc #createdAt
            |> fetchOneOrNothing
    case maybeActiveJob of
        Just job -> pure (activeJobActivity now job)
        Nothing -> do
            maybeLatestJob <-
                query @AppJob
                    |> filterWhere (#jobKind, xeroReferenceSyncJobKind)
                    |> filterWhere (#relatedId, Just (unpackId connection.id))
                    |> orderByDesc #createdAt
                    |> fetchOneOrNothing
            pure case maybeLatestJob of
                Just job | job.status == JobStatusFailed ->
                    XeroReferenceSyncFailed "Xero reference sync stopped safely."
                _ -> XeroReferenceSyncIdle

sanitizedReferenceSyncError :: XeroReferenceSyncActivity -> XeroReferenceSyncProgressFacts -> Maybe Text
sanitizedReferenceSyncError activity progress =
    case activity of
        XeroReferenceSyncFailed _ -> Just (failureCopy "stopped" progress)
        XeroReferenceSyncRetryWaiting _ -> Just (failureCopy "is waiting to retry" progress)
        _ -> Nothing
  where
    failureCopy state facts =
        "Xero reference sync " <> state <> maybe "." (\phase -> " after the " <> phase <> " phase failed.") (facts.progressFailedPhase <|> facts.progressPhase)

fetchXeroReferenceSyncProgress ::
    (?modelContext :: ModelContext) =>
    XeroReferenceSyncActivity ->
    XeroConnection ->
    IO XeroReferenceSyncProgressFacts
fetchXeroReferenceSyncProgress activity connection = do
    maybeLatestJob <-
        query @AppJob
            |> filterWhere (#jobKind, xeroReferenceSyncJobKind)
            |> filterWhere (#relatedId, Just (unpackId connection.id))
            |> orderByDesc #createdAt
            |> fetchOneOrNothing
    let latestProgress = maybe emptyProgressFacts (progressFactsFromValue . (.progress)) maybeLatestJob
    if activityIsRetryWaiting activity && progressFactsAreEmpty latestProgress
        then do
            maybePreviousAttempt <-
                query @AppJob
                    |> filterWhere (#jobKind, xeroReferenceSyncJobKind)
                    |> filterWhere (#relatedId, Just (unpackId connection.id))
                    |> filterWhere (#status, JobStatusSucceeded)
                    |> orderByDesc #createdAt
                    |> fetchOneOrNothing
            pure (maybe latestProgress (progressFactsFromValue . (.progress)) maybePreviousAttempt)
        else pure latestProgress

activityIsRetryWaiting :: XeroReferenceSyncActivity -> Bool
activityIsRetryWaiting (XeroReferenceSyncRetryWaiting _) = True
activityIsRetryWaiting _                                 = False

progressFactsAreEmpty :: XeroReferenceSyncProgressFacts -> Bool
progressFactsAreEmpty facts =
    isNothing facts.progressPhase
        && isNothing facts.progressCompletedPayItemsPage
        && isNothing facts.progressFailedPhase
        && isNothing facts.progressRetryAt

emptyProgressFacts :: XeroReferenceSyncProgressFacts
emptyProgressFacts =
    XeroReferenceSyncProgressFacts
        { progressPhase = Nothing
        , progressCompletedPayItemsPage = Nothing
        , progressFailedPhase = Nothing
        , progressRetryAt = Nothing
        }

progressFactsFromValue :: Aeson.Value -> XeroReferenceSyncProgressFacts
progressFactsFromValue value =
    fromMaybe emptyProgressFacts $
        AesonTypes.parseMaybe
            ( Aeson.withObject "Xero reference sync progress" \object ->
                XeroReferenceSyncProgressFacts
                    <$> object Aeson..:? "phase"
                    <*> object Aeson..:? "completedPayItemsPage"
                    <*> object Aeson..:? "failedPhase"
                    <*> object Aeson..:? "retryAt"
            )
            value

activeJobActivity :: UTCTime -> AppJob -> XeroReferenceSyncActivity
activeJobActivity now job =
    case job.status of
        JobStatusRunning -> XeroReferenceSyncRunning
        JobStatusRetry -> XeroReferenceSyncRetryWaiting job.runAt
        JobStatusNotStarted
            | job.runAt > now && appJobRetryNumber job > 0 -> XeroReferenceSyncRetryWaiting job.runAt
            | otherwise -> XeroReferenceSyncQueued
        _ -> XeroReferenceSyncIdle

appJobRetryNumber :: AppJob -> Int
appJobRetryNumber job =
    fromMaybe 0 $
        AesonTypes.parseMaybe
            (Aeson.withObject "Xero reference sync payload" (\object -> object Aeson..:? "retryNumber" AesonTypes..!= 0))
            job.payload
