module Application.Xero.ReferenceSyncJob
    ( XeroReferenceDataSource (..)
    , XeroReferenceSyncRuntime (..)
    , acquireXeroReferenceSyncLease
    , enqueueXeroReferenceSyncJob
    , performXeroReferenceSyncJob
    , performXeroReferenceSyncJobWith
    , releaseXeroReferenceSyncLease
    , withXeroReferenceSyncRuntimeForTest
    , xeroReferenceSyncDedupeKey
    , xeroReferenceSyncJobKind
    , xeroReferenceSyncLeaseSeconds
    ) where

import Application.Async.Queue
import Application.Helper.FrontendContract.Surface.Admin.Resource (xeroConnectionResource)
import Application.Helper.SurfaceResource
import Application.Helper.Xero
import Application.Xero.Admin.ReferenceData
import Application.Xero.Admin.ReferenceSyncPolicy
import Application.Xero.Connection
import Control.Concurrent (threadDelay)
import qualified Control.Exception as Exception
import Control.Monad (join, void)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.IORef as IORef
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.Job.Types
import IHP.ModelSupport (sqlExec, sqlQuery)
import System.IO.Unsafe (unsafePerformIO)
import System.Random (randomRIO)
import Web.SurfaceInvalidation (invalidateTouchedResourcesWithoutContext)

data XeroReferenceDataSource = XeroReferenceDataSource
    { refreshReferenceAccess                 :: XeroConnection -> IO (Either XeroClientError (XeroConnection, Text))
    , fetchReferenceEmployees                :: Text -> Text -> IO (Either XeroClientError [XeroEmployeeRef])
    , fetchReferenceEarningsRatePage         :: Text -> Text -> Int -> IO (Either XeroClientError [XeroEarningsRateRef])
    , fetchReferencePayrollCalendars         :: Text -> Text -> IO (Either XeroClientError [XeroPayrollCalendarRef])
    , fetchReferenceAccounts                 :: Text -> Text -> IO (Either XeroClientError [XeroAccountRef])
    , fetchReferencePayrollSettingsAccounts  :: Text -> Text -> IO (Either XeroClientError [XeroAccountRef])
    }

data XeroReferenceSyncRuntime = XeroReferenceSyncRuntime
    { currentReferenceSyncTime    :: IO UTCTime
    , sleepForReferenceSyncMicros :: Int -> IO ()
    , referenceSyncJitterSeconds  :: IO Int
    }

data XeroReferenceSyncJobPayload = XeroReferenceSyncJobPayload
    { requestedAt :: !UTCTime
    , retryNumber :: !Int
    }

data XeroReferenceSnapshot = XeroReferenceSnapshot
    { employees               :: ![XeroEmployeeRef]
    , earningsRates           :: ![XeroEarningsRateRef]
    , payrollCalendars        :: ![XeroPayrollCalendarRef]
    , accounts                :: ![XeroAccountRef]
    , payrollSettingsAccounts :: ![XeroAccountRef]
    }

data XeroReferencePhaseFailure = XeroReferencePhaseFailure
    { phaseName :: !Text
    , cause     :: !XeroClientError
    }

xeroReferenceSyncJobKind :: Text
xeroReferenceSyncJobKind = "xero_reference_sync"

xeroReferenceSyncLeaseSeconds :: NominalDiffTime
xeroReferenceSyncLeaseSeconds = 10 * 60

xeroReferenceSyncDedupeKey :: XeroConnection -> Text
xeroReferenceSyncDedupeKey connection =
    "xero-reference-sync-" <> tshow connection.id

enqueueXeroReferenceSyncJob ::
    (?modelContext :: ModelContext) =>
    Maybe (Id User) ->
    XeroConnection ->
    IO EnqueueAppJobResult
enqueueXeroReferenceSyncJob requestedByUserId connection = do
    requestedAt <- getCurrentTime
    enqueueReferenceSyncAttempt requestedByUserId connection requestedAt 0 Nothing

performXeroReferenceSyncJob ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
performXeroReferenceSyncJob appJob = do
    runtime <- currentXeroReferenceSyncRuntime
    performXeroReferenceSyncJobWith runtime defaultXeroReferenceDataSource appJob

performXeroReferenceSyncJobWith ::
    (?modelContext :: ModelContext) =>
    XeroReferenceSyncRuntime ->
    XeroReferenceDataSource ->
    AppJob ->
    IO ()
performXeroReferenceSyncJobWith runtime source appJob =
    case appJob.relatedId of
        Nothing -> fail "Xero reference sync job is missing its related connection id."
        Just connectionUuid -> do
            maybeConnection <- fetchOneOrNothing (Id connectionUuid :: Id XeroConnection)
            case maybeConnection of
                Nothing -> completeSkippedReferenceSyncJob appJob "missing_connection"
                Just connection
                    | connection.connectionStatus /= "active" -> completeSkippedReferenceSyncJob appJob "inactive_connection"
                    | otherwise -> do
                        payload <- either (fail . cs) pure (parseReferenceSyncJobPayload appJob.payload)
                        now <- runtime.currentReferenceSyncTime
                        acquired <- acquireXeroReferenceSyncLease now appJob connection.tenantId
                        if not acquired
                            then handleReferenceSyncFailure runtime appJob payload connection Nothing (XeroReferencePhaseFailure "tenant_lease" (XeroHttpError "Another reference sync is already running for this Xero tenant."))
                            else
                                Exception.finally
                                    (do
                                        refreshedConnection <- fetch connection.id
                                        if refreshedConnection.connectionStatus /= "active" || refreshedConnection.tenantId /= connection.tenantId
                                            then completeSkippedReferenceSyncJob appJob "connection_changed"
                                            else runLeasedReferenceSync runtime source appJob payload refreshedConnection
                                    )
                                    (releaseXeroReferenceSyncLease appJob connection.tenantId)

runLeasedReferenceSync ::
    (?modelContext :: ModelContext) =>
    XeroReferenceSyncRuntime ->
    XeroReferenceDataSource ->
    AppJob ->
    XeroReferenceSyncJobPayload ->
    XeroConnection ->
    IO ()
runLeasedReferenceSync runtime source appJob payload connection = do
    syncRun <- startXeroReferenceDataSync connection
    previousRequestStart <- fetchXeroReferenceSyncLastRequestStart connection.tenantId
    pacer <- newXeroReferencePacerAfter previousRequestStart
    refreshResult <- runReferencePhase runtime pacer appJob connection "refresh_access" (source.refreshReferenceAccess connection)
    case refreshResult of
        Left err -> handleReferenceSyncFailure runtime appJob payload connection (Just syncRun) (XeroReferencePhaseFailure "refresh_access" err)
        Right (refreshedConnection, accessToken) ->
            fetchReferenceSnapshot runtime source pacer appJob refreshedConnection accessToken >>= \case
                Left failure -> handleReferenceSyncFailure runtime appJob payload refreshedConnection (Just syncRun) failure
                Right snapshot -> do
                    result <- completeXeroReferenceDataSync appJob.requestedByUserId syncRun refreshedConnection snapshot.employees snapshot.earningsRates snapshot.payrollCalendars snapshot.accounts snapshot.payrollSettingsAccounts
                    completeReferenceSyncJob appJob result
                    void $ invalidateTouchedResourcesWithoutContext "xero.reference_sync.completed" $
                        liveMutationResult refreshedConnection [xeroConnectionResource refreshedConnection.venueId]

fetchReferenceSnapshot ::
    (?modelContext :: ModelContext) =>
    XeroReferenceSyncRuntime ->
    XeroReferenceDataSource ->
    XeroReferencePacer ->
    AppJob ->
    XeroConnection ->
    Text ->
    IO (Either XeroReferencePhaseFailure XeroReferenceSnapshot)
fetchReferenceSnapshot runtime source pacer appJob connection accessToken = do
    employeesResult <- runReferencePhase runtime pacer appJob connection "employees" $
        source.fetchReferenceEmployees accessToken connection.tenantId
    case employeesResult of
        Left err -> pure (Left (XeroReferencePhaseFailure "employees" err))
        Right employees -> do
            earningsRatesResult <- fetchPacedXeroEarningsRates
                (\page -> updateReferenceSyncProgress appJob "pay_items" (Just (page - 1)))
                (\page -> runReferencePhase runtime pacer appJob connection "pay_items" (source.fetchReferenceEarningsRatePage accessToken connection.tenantId page))
                (\page -> updateReferenceSyncProgress appJob "pay_items" (Just page))
            case earningsRatesResult of
                Left err -> pure (Left (XeroReferencePhaseFailure "pay_items" err))
                Right earningsRates -> do
                    payrollCalendarsResult <- runReferencePhase runtime pacer appJob connection "payroll_calendars" $
                        source.fetchReferencePayrollCalendars accessToken connection.tenantId
                    case payrollCalendarsResult of
                        Left err -> pure (Left (XeroReferencePhaseFailure "payroll_calendars" err))
                        Right payrollCalendars -> do
                            accountsResult <- runReferencePhase runtime pacer appJob connection "accounts" $
                                source.fetchReferenceAccounts accessToken connection.tenantId
                            case accountsResult of
                                Left err -> pure (Left (XeroReferencePhaseFailure "accounts" err))
                                Right accounts -> do
                                    payrollSettingsResult <- runReferencePhase runtime pacer appJob connection "payroll_settings" $
                                        source.fetchReferencePayrollSettingsAccounts accessToken connection.tenantId
                                    pure case payrollSettingsResult of
                                        Left err -> Left (XeroReferencePhaseFailure "payroll_settings" err)
                                        Right payrollSettingsAccounts -> Right (XeroReferenceSnapshot employees earningsRates payrollCalendars accounts payrollSettingsAccounts)

runReferencePhase ::
    (?modelContext :: ModelContext) =>
    XeroReferenceSyncRuntime ->
    XeroReferencePacer ->
    AppJob ->
    XeroConnection ->
    Text ->
    IO (Either XeroClientError value) ->
    IO (Either XeroClientError value)
runReferencePhase runtime pacer appJob connection phase action = do
    when (phase /= "pay_items") (updateReferenceSyncProgress appJob phase Nothing)
    now <- runtime.currentReferenceSyncTime
    leaseRenewed <- acquireXeroReferenceSyncLease now appJob connection.tenantId
    if not leaseRenewed
        then pure (Left (XeroHttpError "Xero reference sync tenant lease was lost."))
        else do
            result <- runPacedXeroReferenceRequest pacer runtime.currentReferenceSyncTime runtime.sleepForReferenceSyncMicros action
            requestFinishedAt <- runtime.currentReferenceSyncTime
            recordXeroReferenceSyncNextRequestTime (addUTCTime 1.2 requestFinishedAt) appJob connection.tenantId
            pure result

handleReferenceSyncFailure ::
    (?modelContext :: ModelContext) =>
    XeroReferenceSyncRuntime ->
    AppJob ->
    XeroReferenceSyncJobPayload ->
    XeroConnection ->
    Maybe XeroSyncRun ->
    XeroReferencePhaseFailure ->
    IO ()
handleReferenceSyncFailure runtime appJob payload connection maybeSyncRun failure = do
    let message = durableXeroReferenceSyncFailureMessage failure
    updateReferenceSyncFailureProgress appJob failure
    forM_ maybeSyncRun \syncRun -> void (failXeroReferenceDataSync appJob.requestedByUserId syncRun connection message)
    when (isJust maybeSyncRun) $
        void $ invalidateTouchedResourcesWithoutContext "xero.reference_sync.failed" $
            liveMutationResult connection [xeroConnectionResource connection.venueId]
    now <- runtime.currentReferenceSyncTime
    jitterSeconds <- runtime.referenceSyncJitterSeconds
    case xeroReferenceSyncRetryDecision payload.requestedAt now payload.retryNumber jitterSeconds failure.cause of
        RetryXeroReferenceSyncAt retryAt -> scheduleReferenceSyncRetry appJob connection payload retryAt failure.phaseName message
        FailXeroReferenceSync -> fail (cs message)

durableXeroReferenceSyncFailureMessage :: XeroReferencePhaseFailure -> Text
durableXeroReferenceSyncFailureMessage failure =
    "Xero " <> failure.phaseName <> " sync failed: " <> case failure.cause of
        XeroHttpResponseError { statusCode } -> "provider request returned status " <> tshow statusCode <> "."
        XeroHttpError message
            | "pagination repeated" `Text.isInfixOf` Text.toLower message -> "provider repeated an earnings-rate page."
            | "configured safety limit" `Text.isInfixOf` Text.toLower message -> "earnings-rate pagination reached its configured safety limit."
            | "xero_earnings_rates_max_pages" `Text.isInfixOf` Text.toLower message -> "earnings-rate pagination configuration is invalid."
            | otherwise -> "provider request could not be completed."
        XeroSemanticError _ -> "provider rejected the request."
        XeroDecodeError _ -> "provider response could not be read."
        XeroNoTenantsError -> "no connected tenant was available."

updateReferenceSyncFailureProgress :: (?modelContext :: ModelContext) => AppJob -> XeroReferencePhaseFailure -> IO ()
updateReferenceSyncFailureProgress appJob failure = do
    latestJob <- fetch appJob.id
    let completedPageFields =
            maybe [] (\page -> ["completedPayItemsPage" Aeson..= page]) (completedPayItemsPageFromProgress latestJob.progress)
    void $
        latestJob
            |> set #progress
                (Aeson.object
                    ( [ "phase" Aeson..= failure.phaseName
                      , "failureCode" Aeson..= xeroReferenceSyncFailureCode failure.cause
                      ]
                        <> completedPageFields
                    )
                )
            |> updateRecord

xeroReferenceSyncFailureCode :: XeroClientError -> Text
xeroReferenceSyncFailureCode = \case
    XeroHttpResponseError { statusCode } -> "http_" <> tshow statusCode
    XeroHttpError message
        | "pagination repeated" `Text.isInfixOf` Text.toLower message -> "repeated_page"
        | "configured safety limit" `Text.isInfixOf` Text.toLower message -> "page_limit"
        | "xero_earnings_rates_max_pages" `Text.isInfixOf` Text.toLower message -> "invalid_configuration"
        | otherwise -> "transport_error"
    XeroSemanticError _ -> "provider_error"
    XeroDecodeError _ -> "decode_error"
    XeroNoTenantsError -> "no_tenant"

scheduleReferenceSyncRetry ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    XeroConnection ->
    XeroReferenceSyncJobPayload ->
    UTCTime ->
    Text ->
    Text ->
    IO ()
scheduleReferenceSyncRetry appJob connection payload retryAt failedPhase message = do
    withTransaction do
        latestJob <- fetch appJob.id
        let completedPageFields =
                maybe [] (\page -> ["completedPayItemsPage" Aeson..= page]) (completedPayItemsPageFromProgress latestJob.progress)
        _ <- latestJob
            |> set #status JobStatusSucceeded
            |> set #lastError Nothing
            |> set #progress (Aeson.object (["phase" Aeson..= ("retry_wait" :: Text), "failedPhase" Aeson..= failedPhase, "retryAt" Aeson..= retryAt] <> completedPageFields))
            |> set #result (Aeson.object ["status" Aeson..= ("retry_scheduled" :: Text), "message" Aeson..= message, "retryAt" Aeson..= retryAt])
            |> updateRecord
        void $ enqueueReferenceSyncAttempt (Id <$> appJob.requestedByUserId) connection payload.requestedAt (payload.retryNumber + 1) (Just retryAt)
    invalidateReferenceSyncProgress "xero.reference_sync.retry_wait" appJob

completedPayItemsPageFromProgress :: Aeson.Value -> Maybe Int
completedPayItemsPageFromProgress value =
    join (Aeson.parseMaybe (Aeson.withObject "Xero reference sync progress" (\object -> object Aeson..:? "completedPayItemsPage")) value)

completeReferenceSyncJob ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    XeroReferenceDataSyncResult ->
    IO ()
completeReferenceSyncJob appJob result = do
    latestJob <- fetch appJob.id
    void $
        latestJob
            |> set #status JobStatusSucceeded
            |> set #lastError Nothing
            |> set #progress (Aeson.object ["phase" Aeson..= ("completed" :: Text), "completedPayItemsPage" Aeson..= max 1 (referenceDataSyncEarningsRateCount result `div` xeroEarningsRatesPageSize + 1)])
            |> set #result
                (Aeson.object
                    [ "status" Aeson..= ("succeeded" :: Text)
                    , "employeesCount" Aeson..= result.referenceDataSyncEmployeeCount
                    , "earningsRatesCount" Aeson..= result.referenceDataSyncEarningsRateCount
                    , "payrollCalendarsCount" Aeson..= result.referenceDataSyncPayrollCalendarCount
                    , "accountsCount" Aeson..= result.referenceDataSyncAccountCount
                    ]
                )
            |> updateRecord

completeSkippedReferenceSyncJob ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    Text ->
    IO ()
completeSkippedReferenceSyncJob appJob reason =
    void $
        appJob
            |> set #status JobStatusSucceeded
            |> set #result (Aeson.object ["status" Aeson..= ("skipped" :: Text), "reason" Aeson..= reason])
            |> updateRecord

updateReferenceSyncProgress ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    Text ->
    Maybe Int ->
    IO ()
updateReferenceSyncProgress appJob phase maybeCompletedPage = do
    latestJob <- fetch appJob.id
    let retainedCompletedPage = maybeCompletedPage <|> completedPayItemsPageFromProgress latestJob.progress
    let nextProgress =
            Aeson.object
                ( ["phase" Aeson..= phase]
                    <> maybe [] (\page -> ["completedPayItemsPage" Aeson..= page]) retainedCompletedPage
                )
    when (nextProgress /= latestJob.progress) do
        void $ latestJob |> set #progress nextProgress |> updateRecord
        invalidateReferenceSyncProgress "xero.reference_sync.progress" appJob

invalidateReferenceSyncProgress :: (?modelContext :: ModelContext) => Text -> AppJob -> IO ()
invalidateReferenceSyncProgress reason appJob =
    forM_ appJob.venueId \venueId ->
        void $ invalidateTouchedResourcesWithoutContext reason $
            liveMutationResult () [xeroConnectionResource venueId]

enqueueReferenceSyncAttempt ::
    (?modelContext :: ModelContext) =>
    Maybe (Id User) ->
    XeroConnection ->
    UTCTime ->
    Int ->
    Maybe UTCTime ->
    IO EnqueueAppJobResult
enqueueReferenceSyncAttempt requestedByUserId connection requestedAt retryNumber runAt =
    enqueueAppJob
        AppJobRequest
            { jobKind = xeroReferenceSyncJobKind
            , payload = referenceSyncJobPayload connection requestedAt retryNumber
            , payloadSchemaVersion = 1
            , requestedByUserId = unpackId <$> requestedByUserId
            , venueId = Just connection.venueId
            , relatedTable = Just "xero_connections"
            , relatedId = Just (unpackId connection.id)
            , dedupeKey = Just (xeroReferenceSyncDedupeKey connection)
            , runAt
            }

referenceSyncJobPayload :: XeroConnection -> UTCTime -> Int -> Aeson.Value
referenceSyncJobPayload connection requestedAt retryNumber =
    Aeson.object
        [ "xeroConnectionId" Aeson..= tshow connection.id
        , "tenantId" Aeson..= connection.tenantId
        , "requestedAt" Aeson..= requestedAt
        , "retryNumber" Aeson..= retryNumber
        ]

parseReferenceSyncJobPayload :: Aeson.Value -> Either Text XeroReferenceSyncJobPayload
parseReferenceSyncJobPayload value =
    case Aeson.parseEither parser value of
        Left message -> Left ("Invalid Xero reference sync job payload: " <> cs message)
        Right payload -> Right payload
    where
        parser = Aeson.withObject "XeroReferenceSyncJobPayload" \object ->
            XeroReferenceSyncJobPayload
                <$> object Aeson..: "requestedAt"
                <*> object Aeson..: "retryNumber"

acquireXeroReferenceSyncLease ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    AppJob ->
    Text ->
    IO Bool
acquireXeroReferenceSyncLease now appJob tenantId = do
    let expiresAt = addUTCTime xeroReferenceSyncLeaseSeconds now
    leases <- sqlQuery
        "INSERT INTO xero_reference_sync_leases (tenant_id, app_job_id, lease_expires_at) VALUES (?, ?, ?) ON CONFLICT (tenant_id) DO UPDATE SET app_job_id = EXCLUDED.app_job_id, lease_expires_at = EXCLUDED.lease_expires_at, updated_at = NOW() WHERE xero_reference_sync_leases.app_job_id IS NULL OR xero_reference_sync_leases.lease_expires_at <= ? OR xero_reference_sync_leases.app_job_id = EXCLUDED.app_job_id RETURNING id, tenant_id, app_job_id, lease_expires_at, next_request_not_before, created_at, updated_at"
        (tenantId, unpackId appJob.id, expiresAt, now)
    pure (not (null (leases :: [XeroReferenceSyncLease])))

fetchXeroReferenceSyncLastRequestStart ::
    (?modelContext :: ModelContext) =>
    Text ->
    IO (Maybe UTCTime)
fetchXeroReferenceSyncLastRequestStart tenantId =
    query @XeroReferenceSyncLease
        |> filterWhere (#tenantId, tenantId)
        |> fetchOneOrNothing
        |> fmap (\maybeLease -> addUTCTime (negate 1.2) <$> (maybeLease >>= (.nextRequestNotBefore)))

recordXeroReferenceSyncNextRequestTime ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    AppJob ->
    Text ->
    IO ()
recordXeroReferenceSyncNextRequestTime nextRequestAt appJob tenantId =
    void $ sqlExec
        "UPDATE xero_reference_sync_leases SET next_request_not_before = ?, updated_at = NOW() WHERE tenant_id = ? AND app_job_id = ?"
        (nextRequestAt, tenantId, unpackId appJob.id)

releaseXeroReferenceSyncLease ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    Text ->
    IO ()
releaseXeroReferenceSyncLease appJob tenantId =
    void $ sqlExec
        "UPDATE xero_reference_sync_leases SET app_job_id = NULL, lease_expires_at = NOW(), updated_at = NOW() WHERE tenant_id = ? AND app_job_id = ?"
        (tenantId, unpackId appJob.id)

xeroReferenceSyncRuntimeOverrideRef :: IORef.IORef (Maybe XeroReferenceSyncRuntime)
xeroReferenceSyncRuntimeOverrideRef = unsafePerformIO (IORef.newIORef Nothing)
{-# NOINLINE xeroReferenceSyncRuntimeOverrideRef #-}

currentXeroReferenceSyncRuntime :: IO XeroReferenceSyncRuntime
currentXeroReferenceSyncRuntime =
    fromMaybe defaultXeroReferenceSyncRuntime <$> IORef.readIORef xeroReferenceSyncRuntimeOverrideRef

withXeroReferenceSyncRuntimeForTest :: XeroReferenceSyncRuntime -> IO value -> IO value
withXeroReferenceSyncRuntimeForTest runtime action =
    Exception.bracket
        (IORef.atomicModifyIORef' xeroReferenceSyncRuntimeOverrideRef (\old -> (Just runtime, old)))
        (IORef.writeIORef xeroReferenceSyncRuntimeOverrideRef)
        (const action)

defaultXeroReferenceSyncRuntime :: XeroReferenceSyncRuntime
defaultXeroReferenceSyncRuntime =
    XeroReferenceSyncRuntime
        { currentReferenceSyncTime = getCurrentTime
        , sleepForReferenceSyncMicros = threadDelay
        , referenceSyncJitterSeconds = randomRIO (0, 30)
        }

defaultXeroReferenceDataSource :: (?modelContext :: ModelContext) => XeroReferenceDataSource
defaultXeroReferenceDataSource =
    XeroReferenceDataSource
        { refreshReferenceAccess = refreshAccess
        , fetchReferenceEmployees = \accessToken tenantId -> currentXeroClient >>= \client -> client.fetchPayrollEmployees accessToken tenantId
        , fetchReferenceEarningsRatePage = \accessToken tenantId page -> currentXeroClient >>= \client -> client.fetchEarningsRatesPage accessToken tenantId page
        , fetchReferencePayrollCalendars = \accessToken tenantId -> currentXeroClient >>= \client -> client.fetchPayrollCalendars accessToken tenantId
        , fetchReferenceAccounts = \accessToken tenantId -> currentXeroClient >>= \client -> client.fetchAccounts accessToken tenantId
        , fetchReferencePayrollSettingsAccounts = \accessToken tenantId -> currentXeroClient >>= \client -> client.fetchPayrollSettingsAccounts accessToken tenantId
        }
    where
        refreshAccess connection =
            readXeroConfig >>= \case
                Left message -> pure (Left (XeroDecodeError message))
                Right config ->
                    case decryptXeroToken config.tokenEncryptionKey connection.encryptedRefreshToken of
                        Left _ -> do
                            markXeroConnectionReauthorizationRequired connection "Stored Xero credentials could not be read. Reconnect Xero to continue."
                            pure (Left (XeroDecodeError "Stored Xero credentials require reconnection."))
                        Right refreshToken -> do
                            client <- currentXeroClient
                            client.refreshXeroToken config refreshToken >>= \case
                                Left err
                                    | isXeroRefreshTokenExpiredError err -> do
                                        markXeroConnectionReauthorizationRequired connection "Xero needs to be reconnected because the refresh token expired or was revoked."
                                        pure (Left (XeroDecodeError "Stored Xero credentials require reconnection."))
                                    | otherwise -> pure (Left err)
                                Right tokenResponse -> do
                                    now <- getCurrentTime
                                    updated <- persistXeroRefreshedTokens now config connection tokenResponse
                                    pure (Right (updated, tokenResponse.accessToken))
