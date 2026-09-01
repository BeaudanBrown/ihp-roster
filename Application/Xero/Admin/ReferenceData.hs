module Application.Xero.Admin.ReferenceData
    ( XeroReferenceDataSyncResult (..)
    , completeXeroAccountsReferenceDataSync
    , completeXeroPayItemsReferenceDataSync
    , completeXeroPayrollCalendarsReferenceDataSync
    , completeXeroReferenceDataSync
    , completeXeroReferenceSyncRun
    , completeXeroStaffReferenceDataSync
    , failXeroReferenceDataSync
    , startXeroReferenceDataSync
    , markStaleXeroEarningsRateMappings
    , reconcileXeroPayItemAccountCodeSelection
    , markStaleXeroStaffMappings
    , upsertXeroAccount
    , upsertXeroEarningsRate
    , upsertXeroEmployee
    , upsertXeroPayRun
    , upsertXeroPayrollCalendar
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Application.Helper.Audit (AuditEventType (XeroReferenceSyncFailedAudit, XeroReferenceSyncSucceededAudit),
                                 AuditSourceChannel (ApplicationAuditSource),
                                 recordAuditEvent)
import Application.Helper.FrontendContract.Surface.Admin.Resource (xeroReferenceSyncStateResource)
import Application.Helper.SurfaceResource (liveMutationResult,
                                           liveMutationValue)
import Application.Helper.Xero
import Application.Xero.WorkflowState (xeroAccountCodeSelectionIsVerified)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Functor ((<&>))
import qualified Data.List as List
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import Web.SurfaceInvalidation (withDurableLiveMutationWithoutContext)

data XeroReferenceDataSyncResult = XeroReferenceDataSyncResult
    { referenceDataSyncRun                  :: XeroSyncRun
    , referenceDataSyncConnection           :: XeroConnection
    , referenceDataSyncEmployeeCount        :: Int
    , referenceDataSyncEarningsRateCount    :: Int
    , referenceDataSyncPayrollCalendarCount :: Int
    , referenceDataSyncAccountCount         :: Int
    }

startXeroReferenceDataSync ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    IO XeroSyncRun
startXeroReferenceDataSync connection = do
    now <- getCurrentTime
    liveMutationValue <$> withDurableLiveMutationWithoutContext "xero.reference_sync.started" do
        interruptedRuns <-
            query @XeroSyncRun
                |> filterWhere (#xeroConnectionId, unpackId connection.id)
                |> filterWhere (#syncStatus, Running)
                |> fetch
        forM_ interruptedRuns \interruptedRun ->
            interruptedRun
                |> set #syncStatus XeroSyncStatusEnumFailed
                |> set #errorMessage (Just "Xero worker sync failed.")
                |> set #finishedAt (Just now)
                |> updateRecord
                |> void
        syncRun <- newRecord @XeroSyncRun
            |> set #venueId connection.venueId
            |> set #xeroConnectionId (unpackId connection.id)
            |> set #syncStatus Running
            |> set #syncKind PayrollReferenceData
            |> set #startedAt now
            |> createRecord
        pure (liveMutationResult syncRun [xeroReferenceSyncStateResource connection.venueId])

completeXeroReferenceDataSync ::
    (?modelContext :: ModelContext) =>
    Maybe UUID ->
    XeroSyncRun ->
    XeroConnection ->
    [XeroEmployeeRef] ->
    [XeroEarningsRateRef] ->
    [XeroPayrollCalendarRef] ->
    [XeroAccountRef] ->
    [XeroAccountRef] ->
    IO XeroReferenceDataSyncResult
completeXeroReferenceDataSync maybeActorUserId syncRun connection employees earningsRates payrollCalendars accounts payrollSettingsAccounts = do
    now <- getCurrentTime
    completedRun <- liveMutationValue <$> withDurableLiveMutationWithoutContext "xero.reference_sync.data_completed" do
        activeSyncRun <- fetch syncRun.id
        when (activeSyncRun.syncStatus /= Running) $
            externalRuntimeInvariantFailure ProviderRuntimeInvariant "Xero reference sync run is no longer active."
        mapM_ (upsertXeroEmployee connection now) employees
        mapM_ (upsertXeroEarningsRate connection now) earningsRates
        mapM_ (upsertXeroPayrollCalendar connection now) payrollCalendars
        mapM_ (upsertXeroAccount connection now) accounts
        reconcileXeroProviderAvailability connection now employees earningsRates payrollCalendars accounts
        markStaleXeroStaffMappings connection employees
        markXeroStaffMappingsReferenceRefreshed connection now
        markStaleXeroEarningsRateMappings connection earningsRates
        reconcileXeroPayItemAccountCodeSelection maybeActorUserId connection accounts payrollSettingsAccounts
        forM_ [XeroStaff, PayItems, PayrollCalendars, Accounts] (recordXeroReferenceCategorySuccess connection now)
        updatedSyncRun <-
            activeSyncRun
                |> set #syncStatus Succeeded
                |> set #employeesCount (length employees)
                |> set #earningsRatesCount (length earningsRates)
                |> set #payrollCalendarsCount (length payrollCalendars)
                |> set #finishedAt (Just now)
                |> updateRecord
        _ <-
            connection
                |> set #lastSyncAt (Just now)
                |> set #lastError Nothing
                |> updateRecord
        recordXeroReferenceSyncAudit maybeActorUserId connection XeroReferenceSyncSucceededAudit syncRun.id
            (Aeson.object
                [ "tenantId" Aeson..= connection.tenantId
                , "employeesCount" Aeson..= length employees
                , "earningsRatesCount" Aeson..= length earningsRates
                , "payrollCalendarsCount" Aeson..= length payrollCalendars
                , "accountsCount" Aeson..= length accounts
                ]
            )
        pure (liveMutationResult updatedSyncRun [xeroReferenceSyncStateResource connection.venueId])
    pure
        XeroReferenceDataSyncResult
            { referenceDataSyncRun = completedRun
            , referenceDataSyncConnection = connection
            , referenceDataSyncEmployeeCount = length employees
            , referenceDataSyncEarningsRateCount = length earningsRates
            , referenceDataSyncPayrollCalendarCount = length payrollCalendars
            , referenceDataSyncAccountCount = length accounts
            }

completeXeroReferenceSyncRun ::
    (?modelContext :: ModelContext) =>
    Maybe UUID ->
    XeroSyncRun ->
    XeroConnection ->
    Bool ->
    [Text] ->
    Int ->
    Int ->
    Int ->
    Int ->
    IO XeroReferenceDataSyncResult
completeXeroReferenceSyncRun maybeActorUserId syncRun connection completesAggregateSnapshot completedCategories employeeCount earningsRateCount payrollCalendarCount accountCount = do
    now <- getCurrentTime
    completedRun <- liveMutationValue <$> withDurableLiveMutationWithoutContext "xero.reference_sync.data_completed" do
        activeSyncRun <- fetch syncRun.id
        when (activeSyncRun.syncStatus /= Running) $
            externalRuntimeInvariantFailure ProviderRuntimeInvariant "Xero reference sync run is no longer active."
        updatedSyncRun <-
            activeSyncRun
                |> set #syncStatus Succeeded
                |> set #employeesCount employeeCount
                |> set #earningsRatesCount earningsRateCount
                |> set #payrollCalendarsCount payrollCalendarCount
                |> set #finishedAt (Just now)
                |> updateRecord
        when completesAggregateSnapshot $
            void $
                connection
                    |> set #lastSyncAt (Just now)
                    |> set #lastError Nothing
                    |> updateRecord
        recordXeroReferenceSyncAudit maybeActorUserId connection XeroReferenceSyncSucceededAudit syncRun.id
            (Aeson.object
                [ "tenantId" Aeson..= connection.tenantId
                , "categories" Aeson..= completedCategories
                , "aggregateSnapshot" Aeson..= completesAggregateSnapshot
                , "employeesCount" Aeson..= employeeCount
                , "earningsRatesCount" Aeson..= earningsRateCount
                , "payrollCalendarsCount" Aeson..= payrollCalendarCount
                , "accountsCount" Aeson..= accountCount
                ]
            )
        pure (liveMutationResult updatedSyncRun [xeroReferenceSyncStateResource connection.venueId])
    updatedConnection <- fetch connection.id
    pure
        XeroReferenceDataSyncResult
            { referenceDataSyncRun = completedRun
            , referenceDataSyncConnection = updatedConnection
            , referenceDataSyncEmployeeCount = employeeCount
            , referenceDataSyncEarningsRateCount = earningsRateCount
            , referenceDataSyncPayrollCalendarCount = payrollCalendarCount
            , referenceDataSyncAccountCount = accountCount
            }

completeXeroStaffReferenceDataSync ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    [XeroEmployeeRef] ->
    IO Int
completeXeroStaffReferenceDataSync connection employees =
    liveMutationValue <$> withDurableLiveMutationWithoutContext "xero.reference_sync.staff_completed" do
        now <- getCurrentTime
        mapM_ (upsertXeroEmployee connection now) employees
        reconcileXeroEmployeeProviderAvailability connection now employees
        markStaleXeroStaffMappings connection employees
        markXeroStaffMappingsReferenceRefreshed connection now
        recordXeroReferenceCategorySuccess connection now XeroStaff
        pure (liveMutationResult (length employees) [xeroReferenceSyncStateResource connection.venueId])

completeXeroPayItemsReferenceDataSync ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    [XeroEarningsRateRef] ->
    IO Int
completeXeroPayItemsReferenceDataSync connection earningsRates =
    liveMutationValue <$> withDurableLiveMutationWithoutContext "xero.reference_sync.pay_items_completed" do
        now <- getCurrentTime
        mapM_ (upsertXeroEarningsRate connection now) earningsRates
        reconcileXeroEarningsRateProviderAvailability connection now earningsRates
        markStaleXeroEarningsRateMappings connection earningsRates
        recordXeroReferenceCategorySuccess connection now PayItems
        pure (liveMutationResult (length earningsRates) [xeroReferenceSyncStateResource connection.venueId])

completeXeroPayrollCalendarsReferenceDataSync ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    [XeroPayrollCalendarRef] ->
    IO Int
completeXeroPayrollCalendarsReferenceDataSync connection payrollCalendars =
    liveMutationValue <$> withDurableLiveMutationWithoutContext "xero.reference_sync.payroll_calendars_completed" do
        now <- getCurrentTime
        mapM_ (upsertXeroPayrollCalendar connection now) payrollCalendars
        reconcileXeroPayrollCalendarProviderAvailability connection now payrollCalendars
        recordXeroReferenceCategorySuccess connection now PayrollCalendars
        pure (liveMutationResult (length payrollCalendars) [xeroReferenceSyncStateResource connection.venueId])

completeXeroAccountsReferenceDataSync ::
    (?modelContext :: ModelContext) =>
    Maybe UUID ->
    XeroConnection ->
    [XeroAccountRef] ->
    [XeroAccountRef] ->
    IO Int
completeXeroAccountsReferenceDataSync maybeActorUserId connection accounts payrollSettingsAccounts =
    liveMutationValue <$> withDurableLiveMutationWithoutContext "xero.reference_sync.accounts_completed" do
        now <- getCurrentTime
        mapM_ (upsertXeroAccount connection now) accounts
        reconcileXeroAccountProviderAvailability connection now accounts
        reconcileXeroPayItemAccountCodeSelection maybeActorUserId connection accounts payrollSettingsAccounts
        recordXeroReferenceCategorySuccess connection now Accounts
        pure (liveMutationResult (length accounts) [xeroReferenceSyncStateResource connection.venueId])

recordXeroReferenceCategorySuccess ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    UTCTime ->
    XeroReferenceSyncCategoryEnum ->
    IO ()
recordXeroReferenceCategorySuccess connection succeededAt category = do
    existing <-
        query @XeroReferenceSyncCategoryState
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#category, category)
            |> fetchOneOrNothing
    let prepared record =
            record
                |> set #venueId connection.venueId
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #category category
                |> set #lastSuccessAt succeededAt
    case existing of
        Just record -> prepared record |> updateRecord |> void
        Nothing -> prepared (newRecord @XeroReferenceSyncCategoryState) |> createRecord |> void

failXeroReferenceDataSync ::
    (?modelContext :: ModelContext) =>
    Maybe UUID ->
    XeroSyncRun ->
    XeroConnection ->
    Text ->
    IO (Either Text a)
failXeroReferenceDataSync maybeActorUserId syncRun connection message = do
    now <- getCurrentTime
    void $ withDurableLiveMutationWithoutContext "xero.reference_sync.failed" do
        _ <-
            syncRun
                |> set #syncStatus XeroSyncStatusEnumFailed
                |> set #errorMessage (Just message)
                |> set #finishedAt (Just now)
                |> updateRecord
        latestConnection <- fetch connection.id
        unless (latestConnection.connectionStatus == "reauthorization_required") $
            void $
                latestConnection
                    |> set #lastError (Just message)
                    |> updateRecord
        recordXeroReferenceSyncAudit maybeActorUserId connection XeroReferenceSyncFailedAudit syncRun.id
            (Aeson.object
                [ "tenantId" Aeson..= connection.tenantId
                , "failure" Aeson..= message
                ]
            )
        pure (liveMutationResult () [xeroReferenceSyncStateResource connection.venueId])
    pure (Left message)

recordXeroReferenceSyncAudit ::
    (?modelContext :: ModelContext) =>
    Maybe UUID ->
    XeroConnection ->
    AuditEventType ->
    Id XeroSyncRun ->
    Aeson.Value ->
    IO ()
recordXeroReferenceSyncAudit maybeActorUserId connection eventType syncRunId payload =
    forM_ maybeActorUserId \actorUserId ->
        void $
            recordAuditEvent
                connection.venueId
                actorUserId
                eventType
                "xero_sync_runs"
                (unpackId syncRunId)
                payload
                ApplicationAuditSource

markStaleXeroStaffMappings ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    [XeroEmployeeRef] ->
    IO ()
markStaleXeroStaffMappings connection employees = do
    let activeEmployeeIds = map (.xeroEmployeeId) (filter xeroEmployeeRefIsProviderAvailable employees)
    mappings <-
        query @XeroStaffMapping
            |> filterWhere (#venueId, connection.venueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#mappingStatus, XeroStaffMappingStatusEnumVerified)
            |> fetch
    forM_ mappings \mapping ->
        case mapping.xeroEmployeeId of
            Just employeeId | employeeId `elem` activeEmployeeIds -> pure ()
            _ ->
                mapping
                    |> set #mappingStatus XeroStaffMappingStatusEnumStale
                    |> set #lastVerifiedAt Nothing
                    |> updateRecord
                    |> void

markXeroStaffMappingsReferenceRefreshed ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    UTCTime ->
    IO ()
markXeroStaffMappingsReferenceRefreshed connection refreshedAt = do
    mappings <-
        query @XeroStaffMapping
            |> filterWhere (#venueId, connection.venueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> fetch
    forM_ mappings \mapping ->
        mapping
            |> set #referenceRefreshedAt (Just refreshedAt)
            |> updateRecord
            |> void

markStaleXeroEarningsRateMappings ::
    (?modelContext :: ModelContext) =>
    XeroConnection ->
    [XeroEarningsRateRef] ->
    IO ()
markStaleXeroEarningsRateMappings connection earningsRates = do
    let activeEarningsRateIds = map (.xeroEarningsRateId) (filter (.xeroEarningsRateIsActive) earningsRates)
    mappings <-
        query @XeroEarningsRateMapping
            |> filterWhere (#venueId, connection.venueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#mappingStatus, XeroEarningsRateMappingStatusEnumVerified)
            |> fetch
    forM_ mappings \mapping ->
        case mapping.xeroEarningsRateId of
            Just earningsRateId | earningsRateId `elem` activeEarningsRateIds -> pure ()
            _ ->
                mapping
                    |> set #mappingStatus XeroEarningsRateMappingStatusEnumStale
                    |> set #lastVerifiedAt Nothing
                    |> updateRecord
                    |> void
    requirements <-
        query @XeroPayItemRequirementRecord
            |> filterWhere (#venueId, connection.venueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhereIn (#requirementStatus, [Matched, XeroPayItemRequirementStatusEnumCreated])
            |> fetch
    forM_ requirements \requirement ->
        case requirement.xeroEarningsRateId of
            Just earningsRateId | earningsRateId `elem` activeEarningsRateIds -> pure ()
            _ ->
                requirement
                    |> set #requirementStatus XeroPayItemRequirementStatusEnumStale
                    |> set #lastVerifiedAt Nothing
                    |> updateRecord
                    |> void

reconcileXeroPayItemAccountCodeSelection ::
    (?modelContext :: ModelContext) =>
    Maybe UUID ->
    XeroConnection ->
    [XeroAccountRef] ->
    [XeroAccountRef] ->
    IO ()
reconcileXeroPayItemAccountCodeSelection maybeActorUserId connection accounts payrollSettingsAccounts = do
    let activeAccountCodes = activeExpenseAccountCodes accounts
        maybeWagesExpenseCode =
            payrollSettingsAccounts
                |> find (\account -> account.xeroAccountType == Just "WAGESEXPENSE")
                >>= (.xeroAccountCode)
                <&> Text.strip
                >>= \accountCode -> if Text.null accountCode then Nothing else Just accountCode
    maybeSelection <-
        query @XeroPayItemAccountCodeSelection
            |> filterWhere (#venueId, connection.venueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> fetchOneOrNothing
    case (maybeSelection, activeAccountCodes) of
        (Just selection, _)
            | xeroAccountCodeSelectionIsVerified selection.selectionStatus
            , maybe False (\accountCode -> Text.strip accountCode `elem` activeAccountCodes) selection.accountCode ->
                pure ()
        (_, _)
            | Just accountCode <- maybeWagesExpenseCode
            , accountCode `elem` activeAccountCodes ->
                upsertXeroPayItemAccountCodeSelection maybeActorUserId connection XeroPayItemAccountCodeSelectionStatusEnumVerified (Just accountCode)
        (_, [accountCode]) ->
            upsertXeroPayItemAccountCodeSelection maybeActorUserId connection XeroPayItemAccountCodeSelectionStatusEnumVerified (Just accountCode)
        (Just selection, _)
            | xeroAccountCodeSelectionIsVerified selection.selectionStatus ->
                selection
                    |> set #selectionStatus XeroPayItemAccountCodeSelectionStatusEnumStale
                    |> set #lastVerifiedAt Nothing
                    |> set #updatedByUserId maybeActorUserId
                    |> updateRecord
                    |> void
        _ -> pure ()

activeExpenseAccountCodes :: [XeroAccountRef] -> [Text]
activeExpenseAccountCodes accounts =
    accounts
        |> filter (\account -> account.xeroAccountType == Just "EXPENSE")
        |> filter (\account -> maybe False ((== "ACTIVE") . Text.toUpper . Text.strip) account.xeroAccountStatus)
        |> map (.xeroAccountCode)
        |> catMaybes
        |> map Text.strip
        |> filter (not . Text.null)
        |> List.nub
        |> List.sort

upsertXeroPayItemAccountCodeSelection ::
    (?modelContext :: ModelContext) =>
    Maybe UUID ->
    XeroConnection ->
    XeroPayItemAccountCodeSelectionStatusEnum ->
    Maybe Text ->
    IO ()
upsertXeroPayItemAccountCodeSelection maybeActorUserId connection selectionStatus maybeAccountCode = do
    now <- getCurrentTime
    existingSelection <-
        query @XeroPayItemAccountCodeSelection
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> fetchOneOrNothing
    let prepared record =
            record
                |> set #venueId connection.venueId
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #accountCode maybeAccountCode
                |> set #selectionStatus selectionStatus
                |> set #lastVerifiedAt (if xeroAccountCodeSelectionIsVerified selectionStatus then Just now else Nothing)
                |> set #updatedByUserId maybeActorUserId
    case existingSelection of
        Just existing -> prepared existing |> updateRecord |> void
        Nothing ->
            prepared (newRecord @XeroPayItemAccountCodeSelection)
                |> set #createdByUserId maybeActorUserId
                |> createRecord
                |> void

reconcileXeroProviderAvailability :: (?modelContext :: ModelContext) => XeroConnection -> UTCTime -> [XeroEmployeeRef] -> [XeroEarningsRateRef] -> [XeroPayrollCalendarRef] -> [XeroAccountRef] -> IO ()
reconcileXeroProviderAvailability connection reconciledAt employees earningsRates payrollCalendars accounts = do
    reconcileXeroEmployeeProviderAvailability connection reconciledAt employees
    reconcileXeroEarningsRateProviderAvailability connection reconciledAt earningsRates
    reconcileXeroPayrollCalendarProviderAvailability connection reconciledAt payrollCalendars
    reconcileXeroAccountProviderAvailability connection reconciledAt accounts

reconcileXeroEmployeeProviderAvailability :: (?modelContext :: ModelContext) => XeroConnection -> UTCTime -> [XeroEmployeeRef] -> IO ()
reconcileXeroEmployeeProviderAvailability connection reconciledAt employees = do
    let availableEmployeeIds = map (.xeroEmployeeId) (filter xeroEmployeeRefIsProviderAvailable employees)
    storedEmployees <- query @XeroEmployee |> filterWhere (#xeroConnectionId, unpackId connection.id) |> fetch
    forM_ storedEmployees \record ->
        setXeroEmployeeProviderAvailability reconciledAt (record.xeroEmployeeId `elem` availableEmployeeIds) record

reconcileXeroEarningsRateProviderAvailability :: (?modelContext :: ModelContext) => XeroConnection -> UTCTime -> [XeroEarningsRateRef] -> IO ()
reconcileXeroEarningsRateProviderAvailability connection reconciledAt earningsRates = do
    let availableEarningsRateIds = map (.xeroEarningsRateId) (filter (.xeroEarningsRateIsActive) earningsRates)
        seenEarningsRateIds = map (.xeroEarningsRateId) earningsRates
    storedEarningsRates <- query @XeroEarningsRate |> filterWhere (#xeroConnectionId, unpackId connection.id) |> fetch
    importedPayItems <- query @XeroImportedPayItem |> filterWhere (#xeroConnectionId, unpackId connection.id) |> fetch
    forM_ storedEarningsRates \record ->
        setXeroEarningsRateProviderAvailability reconciledAt (record.xeroEarningsRateId `elem` availableEarningsRateIds) record
    forM_ importedPayItems \record -> do
        let seen = record.xeroEarningsRateId `elem` seenEarningsRateIds
            available = record.xeroEarningsRateId `elem` availableEarningsRateIds
        record
            |> set #providerAvailable available
            |> set #providerUnavailableAt (nextProviderUnavailableAt reconciledAt available record.providerUnavailableAt)
            |> set #lastSeenAt (if seen then reconciledAt else record.lastSeenAt)
            |> updateRecord
            |> void

reconcileXeroPayrollCalendarProviderAvailability :: (?modelContext :: ModelContext) => XeroConnection -> UTCTime -> [XeroPayrollCalendarRef] -> IO ()
reconcileXeroPayrollCalendarProviderAvailability connection reconciledAt payrollCalendars = do
    let availablePayrollCalendarIds = map (.xeroPayrollCalendarId) payrollCalendars
    storedPayrollCalendars <- query @XeroPayrollCalendar |> filterWhere (#xeroConnectionId, unpackId connection.id) |> fetch
    forM_ storedPayrollCalendars \record ->
        setXeroPayrollCalendarProviderAvailability reconciledAt (record.xeroPayrollCalendarId `elem` availablePayrollCalendarIds) record

reconcileXeroAccountProviderAvailability :: (?modelContext :: ModelContext) => XeroConnection -> UTCTime -> [XeroAccountRef] -> IO ()
reconcileXeroAccountProviderAvailability connection reconciledAt accounts = do
    let availableAccountIds = map (.xeroAccountId) (filter xeroAccountRefIsProviderAvailable accounts)
    storedAccounts <- query @XeroAccount |> filterWhere (#xeroConnectionId, unpackId connection.id) |> fetch
    forM_ storedAccounts \record ->
        setXeroAccountProviderAvailability reconciledAt (record.xeroAccountId `elem` availableAccountIds) record

setXeroEmployeeProviderAvailability :: (?modelContext :: ModelContext) => UTCTime -> Bool -> XeroEmployee -> IO ()
setXeroEmployeeProviderAvailability reconciledAt available record =
    record
        |> set #providerAvailable available
        |> set #providerUnavailableAt (nextProviderUnavailableAt reconciledAt available record.providerUnavailableAt)
        |> updateRecord
        |> void

setXeroEarningsRateProviderAvailability :: (?modelContext :: ModelContext) => UTCTime -> Bool -> XeroEarningsRate -> IO ()
setXeroEarningsRateProviderAvailability reconciledAt available record =
    record
        |> set #providerAvailable available
        |> set #providerUnavailableAt (nextProviderUnavailableAt reconciledAt available record.providerUnavailableAt)
        |> updateRecord
        |> void

setXeroPayrollCalendarProviderAvailability :: (?modelContext :: ModelContext) => UTCTime -> Bool -> XeroPayrollCalendar -> IO ()
setXeroPayrollCalendarProviderAvailability reconciledAt available record =
    record
        |> set #providerAvailable available
        |> set #providerUnavailableAt (nextProviderUnavailableAt reconciledAt available record.providerUnavailableAt)
        |> updateRecord
        |> void

setXeroAccountProviderAvailability :: (?modelContext :: ModelContext) => UTCTime -> Bool -> XeroAccount -> IO ()
setXeroAccountProviderAvailability reconciledAt available record =
    record
        |> set #providerAvailable available
        |> set #providerUnavailableAt (nextProviderUnavailableAt reconciledAt available record.providerUnavailableAt)
        |> updateRecord
        |> void

nextProviderUnavailableAt :: UTCTime -> Bool -> Maybe UTCTime -> Maybe UTCTime
nextProviderUnavailableAt _ True _ = Nothing
nextProviderUnavailableAt reconciledAt False previous = previous <|> Just reconciledAt

xeroEmployeeRefIsProviderAvailable :: XeroEmployeeRef -> Bool
xeroEmployeeRefIsProviderAvailable employee =
    maybe True ((== "ACTIVE") . Text.toUpper . Text.strip) employee.xeroEmployeeStatus

xeroAccountRefIsProviderAvailable :: XeroAccountRef -> Bool
xeroAccountRefIsProviderAvailable account =
    maybe True ((== "ACTIVE") . Text.toUpper . Text.strip) account.xeroAccountStatus

upsertXeroEmployee :: (?modelContext :: ModelContext) => XeroConnection -> UTCTime -> XeroEmployeeRef -> IO XeroEmployee
upsertXeroEmployee connection syncedAt employee = do
    existing <-
        query @XeroEmployee
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#xeroEmployeeId, employee.xeroEmployeeId)
            |> fetchOneOrNothing
    let fillRecord record =
            record
                |> set #venueId connection.venueId
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #xeroEmployeeId employee.xeroEmployeeId
                |> set #displayName employee.xeroEmployeeName
                |> set #email employee.xeroEmployeeEmail
                |> set #status employee.xeroEmployeeStatus
                |> set #rawPayload employee.xeroEmployeeRaw
                |> set #syncedAt syncedAt
                |> set #providerAvailable (xeroEmployeeRefIsProviderAvailable employee)
                |> set #providerUnavailableAt (nextProviderUnavailableAt syncedAt (xeroEmployeeRefIsProviderAvailable employee) record.providerUnavailableAt)
    case existing of
        Just record -> fillRecord record |> updateRecord
        Nothing     -> fillRecord (newRecord @XeroEmployee) |> createRecord

upsertXeroAccount :: (?modelContext :: ModelContext) => XeroConnection -> UTCTime -> XeroAccountRef -> IO XeroAccount
upsertXeroAccount connection syncedAt account = do
    existing <-
        query @XeroAccount
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#xeroAccountId, account.xeroAccountId)
            |> fetchOneOrNothing
    let fillRecord record =
            record
                |> set #venueId connection.venueId
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #xeroAccountId account.xeroAccountId
                |> set #code account.xeroAccountCode
                |> set #name account.xeroAccountName
                |> set #accountType account.xeroAccountType
                |> set #status account.xeroAccountStatus
                |> set #rawPayload account.xeroAccountRaw
                |> set #syncedAt syncedAt
                |> set #providerAvailable (xeroAccountRefIsProviderAvailable account)
                |> set #providerUnavailableAt (nextProviderUnavailableAt syncedAt (xeroAccountRefIsProviderAvailable account) record.providerUnavailableAt)
    case existing of
        Just record -> fillRecord record |> updateRecord
        Nothing     -> fillRecord (newRecord @XeroAccount) |> createRecord

upsertXeroEarningsRate :: (?modelContext :: ModelContext) => XeroConnection -> UTCTime -> XeroEarningsRateRef -> IO XeroEarningsRate
upsertXeroEarningsRate connection syncedAt earningsRate = do
    existing <-
        query @XeroEarningsRate
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#xeroEarningsRateId, earningsRate.xeroEarningsRateId)
            |> fetchOneOrNothing
    let fillRecord record =
            record
                |> set #venueId connection.venueId
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #xeroEarningsRateId earningsRate.xeroEarningsRateId
                |> set #name earningsRate.xeroEarningsRateName
                |> set #earningsType earningsRate.xeroEarningsRateType
                |> set #rateType earningsRate.xeroEarningsRateRateType
                |> set #accountCode earningsRate.xeroEarningsRateAccountCode
                |> set #isActive earningsRate.xeroEarningsRateIsActive
                |> set #rawPayload earningsRate.xeroEarningsRateRaw
                |> set #syncedAt syncedAt
                |> set #providerAvailable earningsRate.xeroEarningsRateIsActive
                |> set #providerUnavailableAt (nextProviderUnavailableAt syncedAt earningsRate.xeroEarningsRateIsActive record.providerUnavailableAt)
    case existing of
        Just record -> fillRecord record |> updateRecord
        Nothing     -> fillRecord (newRecord @XeroEarningsRate) |> createRecord

upsertXeroPayrollCalendar :: (?modelContext :: ModelContext) => XeroConnection -> UTCTime -> XeroPayrollCalendarRef -> IO XeroPayrollCalendar
upsertXeroPayrollCalendar connection syncedAt payrollCalendar = do
    existing <-
        query @XeroPayrollCalendar
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#xeroPayrollCalendarId, payrollCalendar.xeroPayrollCalendarId)
            |> fetchOneOrNothing
    let fillRecord record =
            record
                |> set #venueId connection.venueId
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #xeroPayrollCalendarId payrollCalendar.xeroPayrollCalendarId
                |> set #name payrollCalendar.xeroPayrollCalendarName
                |> set #calendarType payrollCalendar.xeroPayrollCalendarType
                |> set #startDate payrollCalendar.xeroPayrollCalendarStartDate
                |> set #paymentDate payrollCalendar.xeroPayrollCalendarPaymentDate
                |> set #rawPayload payrollCalendar.xeroPayrollCalendarRaw
                |> set #syncedAt syncedAt
                |> set #providerAvailable True
                |> set #providerUnavailableAt Nothing
    case existing of
        Just record -> fillRecord record |> updateRecord
        Nothing     -> fillRecord (newRecord @XeroPayrollCalendar) |> createRecord

upsertXeroPayRun :: (?modelContext :: ModelContext) => XeroConnection -> UTCTime -> XeroPayRunRef -> IO XeroPayRun
upsertXeroPayRun connection syncedAt payRun = do
    existing <-
        query @XeroPayRun
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#xeroPayRunId, payRun.xeroPayRunId)
            |> fetchOneOrNothing
    let fillRecord record =
            record
                |> set #venueId connection.venueId
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #xeroPayRunId payRun.xeroPayRunId
                |> set #xeroPayrollCalendarId payRun.xeroPayRunCalendarId
                |> set #payPeriodStart payRun.xeroPayRunPeriodStart
                |> set #payPeriodEnd payRun.xeroPayRunPeriodEnd
                |> set #paymentDate payRun.xeroPayRunPaymentDate
                |> set #payRunStatus payRun.xeroPayRunStatus
                |> set #rawPayload payRun.xeroPayRunRaw
                |> set #syncedAt syncedAt
    case existing of
        Just record -> fillRecord record |> updateRecord
        Nothing     -> fillRecord (newRecord @XeroPayRun) |> createRecord
