module Application.Xero.Admin.ReferenceData
    ( XeroReferenceDataSyncResult (..)
    , markStaleXeroEarningsRateMappings
    , reconcileXeroPayItemAccountCodeSelection
    , markStaleXeroStaffMappings
    , upsertXeroAccount
    , upsertXeroEarningsRate
    , upsertXeroEmployee
    , upsertXeroPayRun
    , upsertXeroPayrollCalendar
    , syncCurrentVenueXeroReferenceData
    ) where

import Application.Helper.Audit (recordCurrentUserAuditEvent)
import Application.Helper.ControllerContext
import Application.Helper.Xero
import Application.Xero.Connection (refreshXeroConnectionAccessWithoutBroadcast,
                                    xeroClientErrorText)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Data.Functor ((<&>))
import qualified Data.List as List
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude

data XeroReferenceDataSyncResult = XeroReferenceDataSyncResult
    { referenceDataSyncRun                  :: XeroSyncRun
    , referenceDataSyncConnection           :: XeroConnection
    , referenceDataSyncEmployeeCount        :: Int
    , referenceDataSyncEarningsRateCount    :: Int
    , referenceDataSyncPayrollCalendarCount :: Int
    , referenceDataSyncAccountCount         :: Int
    }

syncCurrentVenueXeroReferenceData ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    IO (Either Text XeroReferenceDataSyncResult)
syncCurrentVenueXeroReferenceData connection
    | connection.venueId /= unpackId currentVenueId =
        pure (Left "Xero connection was not found for this venue.")
    | connection.connectionStatus /= "active" =
        pure (Left "Reconnect Xero before syncing payroll reference data.")
    | otherwise = do
        syncRun <- startReferenceDataSync connection
        readXeroConfig >>= \case
            Left message -> failReferenceDataSync syncRun connection message
            Right config ->
                refreshXeroConnectionAccessWithoutBroadcast config connection >>= \case
                    Left message -> failReferenceDataSync syncRun connection message
                    Right (refreshedConnection, accessToken) -> do
                        xeroClient <- currentXeroClient
                        employeesResult <- fetchPayrollEmployees xeroClient accessToken refreshedConnection.tenantId
                        earningsRatesResult <- fetchEarningsRates xeroClient accessToken refreshedConnection.tenantId
                        payrollCalendarsResult <- fetchPayrollCalendars xeroClient accessToken refreshedConnection.tenantId
                        accountsResult <- fetchAccounts xeroClient accessToken refreshedConnection.tenantId
                        payrollSettingsAccountsResult <- fetchPayrollSettingsAccounts xeroClient accessToken refreshedConnection.tenantId
                        case (employeesResult, earningsRatesResult, payrollCalendarsResult, accountsResult, payrollSettingsAccountsResult) of
                            (Right employees, Right earningsRates, Right payrollCalendars, Right accounts, Right payrollSettingsAccounts) ->
                                Right <$> completeReferenceDataSync syncRun refreshedConnection employees earningsRates payrollCalendars accounts payrollSettingsAccounts
                            (Left err, _, _, _, _) ->
                                failReferenceDataSync syncRun refreshedConnection ("Xero employee sync failed: " <> xeroClientErrorText err)
                            (_, Left err, _, _, _) ->
                                failReferenceDataSync syncRun refreshedConnection ("Xero earnings-rate sync failed: " <> xeroClientErrorText err)
                            (_, _, Left err, _, _) ->
                                failReferenceDataSync syncRun refreshedConnection ("Xero payroll-calendar sync failed: " <> xeroClientErrorText err)
                            (_, _, _, Left err, _) ->
                                failReferenceDataSync syncRun refreshedConnection ("Xero account sync failed: " <> xeroClientErrorText err)
                            (_, _, _, _, Left err) ->
                                failReferenceDataSync syncRun refreshedConnection ("Xero payroll-settings sync failed: " <> xeroClientErrorText err)

startReferenceDataSync ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    XeroConnection ->
    IO XeroSyncRun
startReferenceDataSync connection = do
    now <- getCurrentTime
    newRecord @XeroSyncRun
        |> set #venueId connection.venueId
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #syncStatus ("running" :: Text)
        |> set #syncKind ("payroll_reference_data" :: Text)
        |> set #startedAt now
        |> createRecord

completeReferenceDataSync ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroSyncRun ->
    XeroConnection ->
    [XeroEmployeeRef] ->
    [XeroEarningsRateRef] ->
    [XeroPayrollCalendarRef] ->
    [XeroAccountRef] ->
    [XeroAccountRef] ->
    IO XeroReferenceDataSyncResult
completeReferenceDataSync syncRun connection employees earningsRates payrollCalendars accounts payrollSettingsAccounts = do
    now <- getCurrentTime
    completedRun <- withTransaction do
        mapM_ (upsertXeroEmployee connection now) employees
        mapM_ (upsertXeroEarningsRate connection now) earningsRates
        mapM_ (upsertXeroPayrollCalendar connection now) payrollCalendars
        mapM_ (upsertXeroAccount connection now) accounts
        reconcileXeroProviderAvailability connection now employees earningsRates payrollCalendars accounts
        markStaleXeroStaffMappings connection employees
        markStaleXeroEarningsRateMappings connection earningsRates
        reconcileXeroPayItemAccountCodeSelection connection accounts payrollSettingsAccounts
        updatedSyncRun <-
            syncRun
                |> set #syncStatus ("succeeded" :: Text)
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
        void $
            recordCurrentUserAuditEvent
                "xero_reference_sync_succeeded"
                "xero_sync_runs"
                (unpackId syncRun.id)
                (Aeson.object
                    [ "tenantId" Aeson..= connection.tenantId
                    , "employeesCount" Aeson..= length employees
                    , "earningsRatesCount" Aeson..= length earningsRates
                    , "payrollCalendarsCount" Aeson..= length payrollCalendars
                    , "accountsCount" Aeson..= length accounts
                    ]
                )
        pure updatedSyncRun
    pure
        XeroReferenceDataSyncResult
            { referenceDataSyncRun = completedRun
            , referenceDataSyncConnection = connection
            , referenceDataSyncEmployeeCount = length employees
            , referenceDataSyncEarningsRateCount = length earningsRates
            , referenceDataSyncPayrollCalendarCount = length payrollCalendars
            , referenceDataSyncAccountCount = length accounts
            }

failReferenceDataSync ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroSyncRun ->
    XeroConnection ->
    Text ->
    IO (Either Text a)
failReferenceDataSync syncRun connection message = do
    now <- getCurrentTime
    withTransaction do
        _ <-
            syncRun
                |> set #syncStatus ("failed" :: Text)
                |> set #errorMessage (Just message)
                |> set #finishedAt (Just now)
                |> updateRecord
        latestConnection <- fetch connection.id
        _ <-
            latestConnection
                |> set #lastError (Just message)
                |> updateRecord
        void $
            recordCurrentUserAuditEvent
                "xero_reference_sync_failed"
                "xero_sync_runs"
                (unpackId syncRun.id)
                (Aeson.object
                    [ "tenantId" Aeson..= connection.tenantId
                    , "failure" Aeson..= message
                    ]
                )
    pure (Left message)

markStaleXeroStaffMappings ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    XeroConnection ->
    [XeroEmployeeRef] ->
    IO ()
markStaleXeroStaffMappings connection employees = do
    let activeEmployeeIds = map (.xeroEmployeeId) (filter xeroEmployeeRefIsProviderAvailable employees)
    mappings <-
        query @XeroStaffMapping
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#mappingStatus, "verified" :: Text)
            |> fetch
    forM_ mappings \mapping ->
        case mapping.xeroEmployeeId of
            Just employeeId | employeeId `elem` activeEmployeeIds -> pure ()
            _ ->
                mapping
                    |> set #mappingStatus "stale"
                    |> set #lastVerifiedAt Nothing
                    |> updateRecord
                    |> void

markStaleXeroEarningsRateMappings ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    XeroConnection ->
    [XeroEarningsRateRef] ->
    IO ()
markStaleXeroEarningsRateMappings connection earningsRates = do
    let activeEarningsRateIds = map (.xeroEarningsRateId) (filter (.xeroEarningsRateIsActive) earningsRates)
    mappings <-
        query @XeroEarningsRateMapping
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#mappingStatus, "verified" :: Text)
            |> fetch
    forM_ mappings \mapping ->
        case mapping.xeroEarningsRateId of
            Just earningsRateId | earningsRateId `elem` activeEarningsRateIds -> pure ()
            _ ->
                mapping
                    |> set #mappingStatus "stale"
                    |> set #lastVerifiedAt Nothing
                    |> updateRecord
                    |> void
    requirements <-
        query @XeroPayItemRequirementRecord
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhereIn (#requirementStatus, ["matched" :: Text, "created"])
            |> fetch
    forM_ requirements \requirement ->
        case requirement.xeroEarningsRateId of
            Just earningsRateId | earningsRateId `elem` activeEarningsRateIds -> pure ()
            _ ->
                requirement
                    |> set #requirementStatus "stale"
                    |> set #lastVerifiedAt Nothing
                    |> updateRecord
                    |> void

reconcileXeroPayItemAccountCodeSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    [XeroAccountRef] ->
    [XeroAccountRef] ->
    IO ()
reconcileXeroPayItemAccountCodeSelection connection accounts payrollSettingsAccounts = do
    let activeAccountCodes = activeExpenseAccountCodes accounts
        maybeWagesExpenseCode =
            payrollSettingsAccounts
                |> find (\account -> account.xeroAccountType == Just "WAGESEXPENSE")
                >>= (.xeroAccountCode)
                <&> Text.strip
                >>= \accountCode -> if Text.null accountCode then Nothing else Just accountCode
    maybeSelection <-
        query @XeroPayItemAccountCodeSelection
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> fetchOneOrNothing
    case (maybeSelection, activeAccountCodes) of
        (Just selection, _)
            | selection.selectionStatus == "verified"
            , maybe False (\accountCode -> Text.strip accountCode `elem` activeAccountCodes) selection.accountCode ->
                pure ()
        (_, _)
            | Just accountCode <- maybeWagesExpenseCode
            , accountCode `elem` activeAccountCodes ->
                upsertXeroPayItemAccountCodeSelection connection "verified" (Just accountCode)
        (_, [accountCode]) ->
            upsertXeroPayItemAccountCodeSelection connection "verified" (Just accountCode)
        (Just selection, _)
            | selection.selectionStatus == "verified" ->
                selection
                    |> set #selectionStatus ("stale" :: Text)
                    |> set #lastVerifiedAt Nothing
                    |> set #updatedByUserId (Just (unpackId currentUser.id))
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
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Text ->
    Maybe Text ->
    IO ()
upsertXeroPayItemAccountCodeSelection connection selectionStatus maybeAccountCode = do
    now <- getCurrentTime
    existingSelection <-
        query @XeroPayItemAccountCodeSelection
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> fetchOneOrNothing
    let prepared record =
            record
                |> set #venueId (unpackId currentVenueId)
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #accountCode maybeAccountCode
                |> set #selectionStatus selectionStatus
                |> set #lastVerifiedAt (if selectionStatus == "verified" then Just now else Nothing)
                |> set #updatedByUserId (Just (unpackId currentUser.id))
    case existingSelection of
        Just existing -> prepared existing |> updateRecord |> void
        Nothing ->
            prepared (newRecord @XeroPayItemAccountCodeSelection)
                |> set #createdByUserId (Just (unpackId currentUser.id))
                |> createRecord
                |> void

reconcileXeroProviderAvailability :: (?modelContext :: ModelContext) => XeroConnection -> UTCTime -> [XeroEmployeeRef] -> [XeroEarningsRateRef] -> [XeroPayrollCalendarRef] -> [XeroAccountRef] -> IO ()
reconcileXeroProviderAvailability connection reconciledAt employees earningsRates payrollCalendars accounts = do
    let availableEmployeeIds = map (.xeroEmployeeId) (filter xeroEmployeeRefIsProviderAvailable employees)
        availableEarningsRateIds = map (.xeroEarningsRateId) (filter (.xeroEarningsRateIsActive) earningsRates)
        seenEarningsRateIds = map (.xeroEarningsRateId) earningsRates
        availablePayrollCalendarIds = map (.xeroPayrollCalendarId) payrollCalendars
        availableAccountIds = map (.xeroAccountId) (filter xeroAccountRefIsProviderAvailable accounts)
    storedEmployees <- query @XeroEmployee |> filterWhere (#xeroConnectionId, unpackId connection.id) |> fetch
    storedEarningsRates <- query @XeroEarningsRate |> filterWhere (#xeroConnectionId, unpackId connection.id) |> fetch
    storedPayrollCalendars <- query @XeroPayrollCalendar |> filterWhere (#xeroConnectionId, unpackId connection.id) |> fetch
    storedAccounts <- query @XeroAccount |> filterWhere (#xeroConnectionId, unpackId connection.id) |> fetch
    importedPayItems <- query @XeroImportedPayItem |> filterWhere (#xeroConnectionId, unpackId connection.id) |> fetch
    forM_ storedEmployees \record ->
        setXeroEmployeeProviderAvailability reconciledAt (record.xeroEmployeeId `elem` availableEmployeeIds) record
    forM_ storedEarningsRates \record ->
        setXeroEarningsRateProviderAvailability reconciledAt (record.xeroEarningsRateId `elem` availableEarningsRateIds) record
    forM_ storedPayrollCalendars \record ->
        setXeroPayrollCalendarProviderAvailability reconciledAt (record.xeroPayrollCalendarId `elem` availablePayrollCalendarIds) record
    forM_ storedAccounts \record ->
        setXeroAccountProviderAvailability reconciledAt (record.xeroAccountId `elem` availableAccountIds) record
    forM_ importedPayItems \record -> do
        let seen = record.xeroEarningsRateId `elem` seenEarningsRateIds
            available = record.xeroEarningsRateId `elem` availableEarningsRateIds
        record
            |> set #providerAvailable available
            |> set #providerUnavailableAt (nextProviderUnavailableAt reconciledAt available record.providerUnavailableAt)
            |> set #lastSeenAt (if seen then reconciledAt else record.lastSeenAt)
            |> updateRecord
            |> void

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

upsertXeroEmployee :: (?context :: ControllerContext, ?modelContext :: ModelContext) => XeroConnection -> UTCTime -> XeroEmployeeRef -> IO XeroEmployee
upsertXeroEmployee connection syncedAt employee = do
    existing <-
        query @XeroEmployee
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#xeroEmployeeId, employee.xeroEmployeeId)
            |> fetchOneOrNothing
    let fillRecord record =
            record
                |> set #venueId (unpackId currentVenueId)
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

upsertXeroAccount :: (?context :: ControllerContext, ?modelContext :: ModelContext) => XeroConnection -> UTCTime -> XeroAccountRef -> IO XeroAccount
upsertXeroAccount connection syncedAt account = do
    existing <-
        query @XeroAccount
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#xeroAccountId, account.xeroAccountId)
            |> fetchOneOrNothing
    let fillRecord record =
            record
                |> set #venueId (unpackId currentVenueId)
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

upsertXeroEarningsRate :: (?context :: ControllerContext, ?modelContext :: ModelContext) => XeroConnection -> UTCTime -> XeroEarningsRateRef -> IO XeroEarningsRate
upsertXeroEarningsRate connection syncedAt earningsRate = do
    existing <-
        query @XeroEarningsRate
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#xeroEarningsRateId, earningsRate.xeroEarningsRateId)
            |> fetchOneOrNothing
    let fillRecord record =
            record
                |> set #venueId (unpackId currentVenueId)
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

upsertXeroPayrollCalendar :: (?context :: ControllerContext, ?modelContext :: ModelContext) => XeroConnection -> UTCTime -> XeroPayrollCalendarRef -> IO XeroPayrollCalendar
upsertXeroPayrollCalendar connection syncedAt payrollCalendar = do
    existing <-
        query @XeroPayrollCalendar
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#xeroPayrollCalendarId, payrollCalendar.xeroPayrollCalendarId)
            |> fetchOneOrNothing
    let fillRecord record =
            record
                |> set #venueId (unpackId currentVenueId)
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

upsertXeroPayRun :: (?context :: ControllerContext, ?modelContext :: ModelContext) => XeroConnection -> UTCTime -> XeroPayRunRef -> IO XeroPayRun
upsertXeroPayRun connection syncedAt payRun = do
    existing <-
        query @XeroPayRun
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#xeroPayRunId, payRun.xeroPayRunId)
            |> fetchOneOrNothing
    let fillRecord record =
            record
                |> set #venueId (unpackId currentVenueId)
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
