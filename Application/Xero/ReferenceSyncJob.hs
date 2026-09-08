module Application.Xero.ReferenceSyncJob
    ( XeroReferenceDataSource (..)
    , XeroReferenceSyncRuntime (..)
    , acquireXeroReferenceSyncLease
    , enqueueXeroReferenceSyncCategories
    , enqueueXeroReferenceSyncJob
    , performXeroReferenceSyncJob
    , requestXeroReferenceSyncCategories
    , requestXeroReferenceSyncJob
    , performXeroReferenceSyncJobWith
    , releaseXeroReferenceSyncLease
    , withXeroReferenceSyncRuntimeForTest
    , xeroReferenceSyncDedupeKey
    , xeroReferenceSyncJobKind
    , xeroReferenceSyncLeaseSeconds
    ) where

import Application.Async.Boundary (throwAppJobError)
import Application.Async.Error (AppJobError (..))
import Application.Async.Payload (decodeAppJobPayload)
import Application.Async.Queue
import Application.Error.Runtime (ExternalRuntimeCategory (CheckedConfigurationInvariant),
                                  throwExternalRuntimeMessage)
import Application.Helper.FrontendContract.Surface.Admin.Resource (xeroReferenceSyncStateResource)
import Application.Helper.SurfaceResource
import Application.Helper.Telemetry (addJobRetryExhaustedTelemetryEvent,
                                     addJobRetryScheduledTelemetryEvent)
import Application.Helper.Telemetry.Semantic (boundedRetryNumber,
                                              nextBoundedRetryNumber,
                                              retryNumberAtLimit)
import Application.Helper.Xero
import Application.Xero.Admin.ReferenceData
import Application.Xero.Admin.ReferenceSyncPolicy
import Application.Xero.Connection
import Application.Xero.ReferenceCategory
import Application.Xero.ReferenceSyncFence
import Control.Concurrent (threadDelay)
import qualified Control.Exception as Exception
import Control.Monad (join, void)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.IORef as IORef
import qualified Data.Set as Set
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.Job.Types
import IHP.ModelSupport (unsafeSqlExec, unsafeSqlQuery)
import System.IO.Unsafe (unsafePerformIO)
import System.Random (randomRIO)
import Web.SurfaceInvalidation (withDurableLiveMutationOutcomeWithoutContext,
                                withDurableLiveMutationWithoutContext)

data XeroReferenceDataSource = XeroReferenceDataSource
    { refreshReferenceAccess                 :: XeroConnection -> IO (Either XeroClientError (XeroConnection, Text))
    , fetchReferenceEmployees                :: Text -> Text -> IO (Either XeroClientError [XeroEmployeeRef])
    , fetchReferenceEarningsRatePage         :: Text -> Text -> Int -> IO (Either XeroClientError [XeroEarningsRateRef])
    , fetchReferencePayrollCalendars         :: Text -> Text -> IO (Either XeroClientError [XeroPayrollCalendarRef])
    , fetchReferenceAccounts                 :: Text -> Text -> IO (Either XeroClientError [XeroAccountRef])
    , fetchReferencePayrollSettingsAccounts  :: Text -> Text -> IO (Either XeroClientError [XeroAccountRef])
    }

data XeroReferenceSyncRuntime = XeroReferenceSyncRuntime
    { currentReferenceSyncTime       :: IO UTCTime
    , sleepForReferenceSyncMicros    :: Int -> IO ()
    , referenceSyncJitterSeconds     :: IO Int
    }

data XeroReferenceSyncJobPayload = XeroReferenceSyncJobPayload
    { payloadConnectionId   :: !Text
    , payloadTenantId       :: !Text
    , requestedAt           :: !UTCTime
    , retryNumber           :: !Int
    , requestedCategories   :: !(Set.Set XeroReferenceSyncCategoryEnum)
    , completesFullSnapshot :: !Bool
    }

instance Aeson.FromJSON XeroReferenceSyncJobPayload where
    parseJSON = Aeson.withObject "XeroReferenceSyncJobPayload" \object -> do
        payloadConnectionId <- object Aeson..: "xeroConnectionId"
        payloadTenantId <- object Aeson..: "tenantId"
        requestedAt <- object Aeson..: "requestedAt"
        retryNumber <- object Aeson..: "retryNumber"
        maybeCategoryValue <- object Aeson..:? "categories"
        requestedCategories <- maybe (pure allXeroReferenceSyncCategories) parseXeroReferenceSyncCategories maybeCategoryValue
        completesFullSnapshot <- object Aeson..:? "completesFullSnapshot" Aeson..!= (requestedCategories == allXeroReferenceSyncCategories)
        pure XeroReferenceSyncJobPayload { .. }

data XeroReferenceSyncCounts = XeroReferenceSyncCounts
    { employeeCount        :: !Int
    , earningsRateCount    :: !Int
    , payrollCalendarCount :: !Int
    , accountCount         :: !Int
    }
    deriving (Eq, Show)

emptyXeroReferenceSyncCounts :: XeroReferenceSyncCounts
emptyXeroReferenceSyncCounts = XeroReferenceSyncCounts 0 0 0 0

combineXeroReferenceSyncCounts :: XeroReferenceSyncCounts -> XeroReferenceSyncCounts -> XeroReferenceSyncCounts
combineXeroReferenceSyncCounts first second =
    XeroReferenceSyncCounts
        { employeeCount = first.employeeCount + second.employeeCount
        , earningsRateCount = first.earningsRateCount + second.earningsRateCount
        , payrollCalendarCount = first.payrollCalendarCount + second.payrollCalendarCount
        , accountCount = first.accountCount + second.accountCount
        }

data XeroReferenceCategoryOutcome
    = XeroReferenceCategorySucceeded !XeroReferenceSyncCategoryEnum !XeroReferenceSyncCounts
    | XeroReferenceCategoryFailed !XeroReferenceSyncCategoryEnum !XeroReferencePhaseFailure

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
enqueueXeroReferenceSyncJob requestedByUserId connection =
    enqueueXeroReferenceSyncCategories requestedByUserId connection allXeroReferenceSyncCategories

enqueueXeroReferenceSyncCategories ::
    (?modelContext :: ModelContext) =>
    Maybe (Id User) ->
    XeroConnection ->
    Set.Set XeroReferenceSyncCategoryEnum ->
    IO EnqueueAppJobResult
enqueueXeroReferenceSyncCategories requestedByUserId connection categories
    | Set.null categories = throwExternalRuntimeMessage CheckedConfigurationInvariant "Xero reference sync categories cannot be empty."
    | otherwise = do
        requestedAt <- getCurrentTime
        enqueueReferenceSyncAttempt requestedByUserId connection requestedAt 0 Nothing categories (categories == allXeroReferenceSyncCategories)

requestXeroReferenceSyncJob ::
    (?modelContext :: ModelContext) =>
    Maybe (Id User) ->
    XeroConnection ->
    IO EnqueueAppJobResult
requestXeroReferenceSyncJob requestedByUserId connection =
    requestXeroReferenceSyncCategories requestedByUserId connection allXeroReferenceSyncCategories

requestXeroReferenceSyncCategories ::
    (?modelContext :: ModelContext) =>
    Maybe (Id User) ->
    XeroConnection ->
    Set.Set XeroReferenceSyncCategoryEnum ->
    IO EnqueueAppJobResult
requestXeroReferenceSyncCategories requestedByUserId connection categories
    | Set.null categories = throwExternalRuntimeMessage CheckedConfigurationInvariant "Xero reference sync categories cannot be empty."
    | otherwise = do
        maybeContainingJob <- fetchContainingReferenceSyncJob connection categories
        case maybeContainingJob of
            Just activeJob -> pure (ExistingActiveAppJob activeJob)
            Nothing ->
                withDurableLiveMutationOutcomeWithoutContext publicationFor $
                    enqueueXeroReferenceSyncCategories requestedByUserId connection categories
  where
    publicationFor = \case
        EnqueuedAppJob _ -> Just ("xero.reference_sync.queued", Set.singleton (xeroReferenceSyncStateResource connection.venueId))
        ExistingActiveAppJob _ -> Nothing

fetchContainingReferenceSyncJob ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    Set.Set XeroReferenceSyncCategoryEnum ->
    IO (Maybe AppJob)
fetchContainingReferenceSyncJob connection requested = do
    activeJobs <-
        query @AppJob
            |> filterWhere (#jobKind, xeroReferenceSyncJobKind)
            |> filterWhere (#relatedId, Just (unpackId connection.id))
            |> filterWhereIn (#status, activeAppJobStatuses)
            |> orderByAsc #createdAt
            |> fetch
    categoryStates <-
        query @XeroReferenceSyncCategoryState
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> fetch
    pure $ find (jobContainsPendingCategories categoryStates requested) activeJobs
  where
    jobContainsPendingCategories categoryStates requestedCategories activeJob
        | activeJob.payloadSchemaVersion `notElem` [1, 2] = False
        | otherwise =
            case (Aeson.fromJSON activeJob.payload :: Aeson.Result XeroReferenceSyncJobPayload) of
                Aeson.Success payload ->
                    payload.requestedCategories `xeroReferenceSyncCategoriesContain` requestedCategories
                        && all (categoryIsPending payload categoryStates) (Set.toList requestedCategories)
                Aeson.Error _ -> False

    categoryIsPending payload categoryStates category =
        categoryStates
            |> find (\state -> state.category == category)
            |> maybe True (\state -> state.lastSuccessAt < payload.requestedAt)

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
performXeroReferenceSyncJobWith runtime source appJob = do
    when (appJob.relatedTable /= Just "xero_connections") do
        throwAppJobError JobInvalidProvenance
    connectionUuid <- maybe (throwAppJobError JobInvalidProvenance) pure appJob.relatedId
    payload <- decodeAppJobPayload [1, 2] appJob
    unless (payload.payloadConnectionId == tshow (Id connectionUuid :: Id XeroConnection)) (throwAppJobError JobInvalidProvenance)
    maybeConnection <- fetchOneOrNothing (Id connectionUuid :: Id XeroConnection)
    case maybeConnection of
        Nothing -> completeSkippedReferenceSyncJob appJob "missing_connection"
        Just connection
            | payload.payloadTenantId /= connection.tenantId -> throwAppJobError JobInvalidProvenance
            | connection.connectionStatus /= "active" -> completeSkippedReferenceSyncJob appJob "inactive_connection"
            | otherwise -> do
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
                                    else do
                                        snapshotCurrent <- referenceSnapshotSatisfiesRequest payload refreshedConnection
                                        if snapshotCurrent
                                            then completeSkippedReferenceSyncJob appJob "snapshot_already_current"
                                            else runLeasedReferenceSync runtime source appJob payload refreshedConnection
                            )
                            (releaseXeroReferenceSyncLease appJob connection.tenantId)

referenceSnapshotSatisfiesRequest ::
    (?modelContext :: ModelContext) =>
    XeroReferenceSyncJobPayload ->
    XeroConnection ->
    IO Bool
referenceSnapshotSatisfiesRequest payload connection
    | payload.completesFullSnapshot =
        pure (maybe False (>= payload.requestedAt) connection.lastSyncAt)
    | otherwise = do
        categoryStates <-
            query @XeroReferenceSyncCategoryState
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> filterWhereIn (#category, Set.toList payload.requestedCategories)
                |> fetch
        let currentCategories =
                categoryStates
                    |> filter (\state -> state.lastSuccessAt >= payload.requestedAt)
                    |> map (.category)
                    |> Set.fromList
        pure (currentCategories `xeroReferenceSyncCategoriesContain` payload.requestedCategories)

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
    let attempt = XeroReferenceSyncAttempt appJob syncRun runtime.currentReferenceSyncTime
        runAttempt = do
            previousRequestStart <- fetchXeroReferenceSyncLastRequestStart connection.tenantId
            pacer <- newXeroReferencePacerAfter previousRequestStart
            refreshResult <- runReferencePhase runtime pacer appJob connection "refresh_access" (source.refreshReferenceAccess connection)
            case refreshResult of
                Left err -> handleReferenceSyncFailure runtime appJob payload connection (Just syncRun) (XeroReferencePhaseFailure "refresh_access" err)
                Right (refreshedConnection, accessToken) -> (do
                    outcomes <- runRequestedReferenceCategories runtime source pacer appJob attempt refreshedConnection accessToken payload.requestedCategories
                    let failures = [failure | XeroReferenceCategoryFailed _ failure <- outcomes]
                        completedCategories = [category | XeroReferenceCategorySucceeded category _ <- outcomes]
                        counts = foldl combineXeroReferenceSyncCounts emptyXeroReferenceSyncCounts [categoryCounts | XeroReferenceCategorySucceeded _ categoryCounts <- outcomes]
                    case failures of
                        firstFailure : _ ->
                            handleReferenceSyncFailure
                                runtime
                                appJob
                                payload { requestedCategories = Set.fromList [category | XeroReferenceCategoryFailed category _ <- outcomes] }
                                refreshedConnection
                                (Just syncRun)
                                firstFailure
                        [] -> do
                            result <-
                                completeXeroReferenceSyncRun
                                    appJob.requestedByUserId
                                    attempt
                                    refreshedConnection
                                    payload.completesFullSnapshot
                                    (map xeroReferenceSyncCategoryLabel completedCategories)
                                    counts.employeeCount
                                    counts.earningsRateCount
                                    counts.payrollCalendarCount
                                    counts.accountCount
                            withReferenceSyncMutation "xero.reference_sync.completed" refreshedConnection.venueId (completeReferenceSyncJob appJob result completedCategories)
                    ) `Exception.onException` terminalizeInterruptedReferenceSyncRun runtime appJob syncRun refreshedConnection
    runAttempt `Exception.onException` terminalizeInterruptedReferenceSyncRun runtime appJob syncRun connection

terminalizeInterruptedReferenceSyncRun ::
    (?modelContext :: ModelContext) =>
    XeroReferenceSyncRuntime ->
    AppJob ->
    XeroSyncRun ->
    XeroConnection ->
    IO ()
terminalizeInterruptedReferenceSyncRun runtime appJob syncRun connection = do
    latestRun <- fetch syncRun.id
    when (latestRun.syncStatus == Running) do
        let interruption = XeroReferencePhaseFailure "worker" (XeroHttpError "Xero reference sync worker interrupted.")
            message = "Xero worker sync failed."
        updateReferenceSyncFailureProgress appJob interruption
        void (failXeroReferenceDataSync appJob.requestedByUserId (XeroReferenceSyncAttempt appJob latestRun runtime.currentReferenceSyncTime) connection message :: IO (Either Text ()))

runRequestedReferenceCategories ::
    (?modelContext :: ModelContext) =>
    XeroReferenceSyncRuntime ->
    XeroReferenceDataSource ->
    XeroReferencePacer ->
    AppJob ->
    XeroReferenceSyncAttempt ->
    XeroConnection ->
    Text ->
    Set.Set XeroReferenceSyncCategoryEnum ->
    IO [XeroReferenceCategoryOutcome]
runRequestedReferenceCategories runtime source pacer appJob attempt connection accessToken requestedCategories =
    forM (filter (`Set.member` requestedCategories) [XeroStaff, PayItems, PayrollCalendars, Accounts]) \category ->
        runReferenceCategory category
  where
    runReferenceCategory XeroStaff = do
        source.fetchReferenceEmployees accessToken connection.tenantId
            |> runReferencePhase runtime pacer appJob connection "employees"
            >>= \case
                Left err -> pure (categoryFailure XeroStaff "employees" err)
                Right employees -> do
                    count <- completeXeroStaffReferenceDataSync attempt connection employees
                    pure (XeroReferenceCategorySucceeded XeroStaff emptyXeroReferenceSyncCounts { employeeCount = count })
    runReferenceCategory PayItems = do
        fetchPacedXeroEarningsRates
            (\page -> updateReferenceSyncProgress appJob "pay_items" (Just (page - 1)))
            (\page -> runReferencePhase runtime pacer appJob connection "pay_items" (source.fetchReferenceEarningsRatePage accessToken connection.tenantId page))
            (\page -> updateReferenceSyncProgress appJob "pay_items" (Just page))
            >>= \case
                Left err -> pure (categoryFailure PayItems "pay_items" err)
                Right earningsRates -> do
                    count <- completeXeroPayItemsReferenceDataSync attempt connection earningsRates
                    pure (XeroReferenceCategorySucceeded PayItems emptyXeroReferenceSyncCounts { earningsRateCount = count })
    runReferenceCategory PayrollCalendars = do
        source.fetchReferencePayrollCalendars accessToken connection.tenantId
            |> runReferencePhase runtime pacer appJob connection "payroll_calendars"
            >>= \case
                Left err -> pure (categoryFailure PayrollCalendars "payroll_calendars" err)
                Right payrollCalendars -> do
                    count <- completeXeroPayrollCalendarsReferenceDataSync attempt connection payrollCalendars
                    pure (XeroReferenceCategorySucceeded PayrollCalendars emptyXeroReferenceSyncCounts { payrollCalendarCount = count })
    runReferenceCategory Accounts = do
        source.fetchReferenceAccounts accessToken connection.tenantId
            |> runReferencePhase runtime pacer appJob connection "accounts"
            >>= \case
                Left err -> pure (categoryFailure Accounts "accounts" err)
                Right accounts ->
                    source.fetchReferencePayrollSettingsAccounts accessToken connection.tenantId
                        |> runReferencePhase runtime pacer appJob connection "payroll_settings"
                        >>= \case
                            Left err -> pure (categoryFailure Accounts "payroll_settings" err)
                            Right payrollSettingsAccounts -> do
                                count <- completeXeroAccountsReferenceDataSync appJob.requestedByUserId attempt connection accounts payrollSettingsAccounts
                                pure (XeroReferenceCategorySucceeded Accounts emptyXeroReferenceSyncCounts { accountCount = count })

    categoryFailure category phase err =
        XeroReferenceCategoryFailed category (XeroReferencePhaseFailure phase err)

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
    forM_ maybeSyncRun \syncRun -> void (failXeroReferenceDataSync appJob.requestedByUserId (XeroReferenceSyncAttempt appJob syncRun runtime.currentReferenceSyncTime) connection message)
    now <- runtime.currentReferenceSyncTime
    jitterSeconds <- runtime.referenceSyncJitterSeconds
    case xeroReferenceSyncRetryDecision payload.requestedAt now payload.retryNumber jitterSeconds failure.cause of
        RetryXeroReferenceSyncAt retryAt
            | retryNumberAtLimit payload.retryNumber -> throwFinalReferenceSyncFailure payload failure
            | otherwise -> do
                addJobRetryScheduledTelemetryEvent xeroReferenceSyncJobKind (nextBoundedRetryNumber payload.retryNumber)
                scheduleReferenceSyncRetry appJob connection payload retryAt failure.phaseName message
        FailXeroReferenceSync -> throwFinalReferenceSyncFailure payload failure

throwFinalReferenceSyncFailure :: XeroReferenceSyncJobPayload -> XeroReferencePhaseFailure -> IO value
throwFinalReferenceSyncFailure payload failure = do
    addJobRetryExhaustedTelemetryEvent xeroReferenceSyncJobKind (boundedRetryNumber payload.retryNumber)
    throwAppJobError (xeroReferenceJobError failure.cause)

xeroReferenceJobError :: XeroClientError -> AppJobError
xeroReferenceJobError = \case
    XeroHttpResponseError { statusCode }
        | statusCode == 401 || statusCode == 403 -> JobAuthenticationRequired
        | statusCode == 409 -> JobRemoteConflict
        | statusCode == 429 -> JobRateLimited
        | statusCode == 400 || statusCode == 422 -> JobValidationRejected
        | otherwise -> JobTransportUnavailable
    XeroHttpError _ -> JobTransportUnavailable
    XeroSemanticError _ -> JobValidationRejected
    XeroDecodeError _ -> JobMalformedResponse
    XeroNoTenantsError -> JobAuthenticationRequired

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
    forM_ appJob.venueId \venueId ->
        withReferenceSyncMutation "xero.reference_sync.progress" venueId do
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
    withReferenceSyncMutation "xero.reference_sync.retry_wait" connection.venueId do
        latestJob <- fetch appJob.id
        let completedPageFields =
                maybe [] (\page -> ["completedPayItemsPage" Aeson..= page]) (completedPayItemsPageFromProgress latestJob.progress)
        _ <- latestJob
            |> set #status JobStatusSucceeded
            |> set #lastError Nothing
            |> set #progress (Aeson.object (["phase" Aeson..= ("retry_wait" :: Text), "failedPhase" Aeson..= failedPhase, "retryAt" Aeson..= retryAt] <> completedPageFields))
            |> set #result (Aeson.object ["status" Aeson..= ("retry_scheduled" :: Text), "message" Aeson..= message, "retryAt" Aeson..= retryAt])
            |> updateRecord
        void $
            enqueueReferenceSyncAttempt
                (Id <$> appJob.requestedByUserId)
                connection
                payload.requestedAt
                (nextBoundedRetryNumber payload.retryNumber)
                (Just retryAt)
                payload.requestedCategories
                payload.completesFullSnapshot

completedPayItemsPageFromProgress :: Aeson.Value -> Maybe Int
completedPayItemsPageFromProgress value =
    join (AesonTypes.parseMaybe (Aeson.withObject "Xero reference sync progress" (\object -> object Aeson..:? "completedPayItemsPage")) value)

completeReferenceSyncJob ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    XeroReferenceDataSyncResult ->
    [XeroReferenceSyncCategoryEnum] ->
    IO ()
completeReferenceSyncJob appJob result completedCategories = do
    latestJob <- fetch appJob.id
    void $
        latestJob
            |> set #status JobStatusSucceeded
            |> set #lastError Nothing
            |> set #progress (Aeson.object ["phase" Aeson..= ("completed" :: Text), "completedPayItemsPage" Aeson..= max 1 (referenceDataSyncEarningsRateCount result `div` xeroEarningsRatesPageSize + 1)])
            |> set #result
                (Aeson.object
                    [ "status" Aeson..= ("succeeded" :: Text)
                    , "categories" Aeson..= map xeroReferenceSyncCategoryLabel completedCategories
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
completeSkippedReferenceSyncJob appJob reason = do
    forM_ appJob.venueId \venueId ->
        withReferenceSyncMutation "xero.reference_sync.skipped" venueId do
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
        forM_ appJob.venueId \venueId ->
            withReferenceSyncMutation "xero.reference_sync.progress" venueId do
                void $ latestJob |> set #progress nextProgress |> updateRecord

enqueueReferenceSyncAttempt ::
    (?modelContext :: ModelContext) =>
    Maybe (Id User) ->
    XeroConnection ->
    UTCTime ->
    Int ->
    Maybe UTCTime ->
    Set.Set XeroReferenceSyncCategoryEnum ->
    Bool ->
    IO EnqueueAppJobResult
enqueueReferenceSyncAttempt requestedByUserId connection requestedAt retryNumber runAt categories completesFullSnapshot =
    enqueueAppJob
        AppJobRequest
            { jobKind = xeroReferenceSyncJobKind
            , payload = referenceSyncJobPayload connection requestedAt retryNumber categories completesFullSnapshot
            , payloadSchemaVersion = 2
            , requestedByUserId = unpackId <$> requestedByUserId
            , venueId = Just connection.venueId
            , relatedTable = Just "xero_connections"
            , relatedId = Just (unpackId connection.id)
            , dedupeKey = Just (xeroReferenceSyncDedupeKeyFor connection categories completesFullSnapshot)
            , runAt
            }

xeroReferenceSyncDedupeKeyFor :: XeroConnection -> Set.Set XeroReferenceSyncCategoryEnum -> Bool -> Text
xeroReferenceSyncDedupeKeyFor connection categories completesFullSnapshot
    | completesFullSnapshot || categories == allXeroReferenceSyncCategories = xeroReferenceSyncDedupeKey connection
    | otherwise =
        xeroReferenceSyncDedupeKey connection
            <> "-"
            <> Text.intercalate "-" (map xeroReferenceSyncCategoryLabel (Set.toAscList categories))

referenceSyncJobPayload :: XeroConnection -> UTCTime -> Int -> Set.Set XeroReferenceSyncCategoryEnum -> Bool -> Aeson.Value
referenceSyncJobPayload connection requestedAt retryNumber categories completesFullSnapshot =
    Aeson.object
        [ "xeroConnectionId" Aeson..= tshow connection.id
        , "tenantId" Aeson..= connection.tenantId
        , "requestedAt" Aeson..= requestedAt
        , "retryNumber" Aeson..= retryNumber
        , "categories" Aeson..= map xeroReferenceSyncCategoryLabel (Set.toAscList categories)
        , "completesFullSnapshot" Aeson..= completesFullSnapshot
        ]

acquireXeroReferenceSyncLease ::
    (?modelContext :: ModelContext) =>
    UTCTime ->
    AppJob ->
    Text ->
    IO Bool
acquireXeroReferenceSyncLease now appJob tenantId = do
    let expiresAt = addUTCTime xeroReferenceSyncLeaseSeconds now
    leases <- unsafeSqlQuery
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
    void $ unsafeSqlExec
        "UPDATE xero_reference_sync_leases SET next_request_not_before = ?, updated_at = NOW() WHERE tenant_id = ? AND app_job_id = ?"
        (nextRequestAt, tenantId, unpackId appJob.id)

releaseXeroReferenceSyncLease ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    Text ->
    IO ()
releaseXeroReferenceSyncLease appJob tenantId =
    void $ unsafeSqlExec
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

withReferenceSyncMutation :: (?modelContext :: ModelContext) => Text -> UUID -> ((?modelContext :: ModelContext) => IO value) -> IO value
withReferenceSyncMutation label venueId action =
    liveMutationValue <$> withDurableLiveMutationWithoutContext label do
        value <- action
        pure (liveMutationResult value [xeroReferenceSyncStateResource venueId])

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
