module Application.Xero.Admin.ReferenceData
    ( markStaleXeroEarningsRateMappings
    , reconcileXeroPayItemAccountCodeSelection
    , reconcileXeroPayrollCalendarSelection
    , markStaleXeroStaffMappings
    , upsertXeroAccount
    , upsertXeroEarningsRate
    , upsertXeroEmployee
    , upsertXeroPayRun
    , upsertXeroPayrollCalendar
    ) where

import Application.Helper.ControllerContext
import Application.Helper.Xero
import Control.Monad (void)
import qualified Data.List as List
import Data.Functor ((<&>))
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude

markStaleXeroStaffMappings ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    XeroConnection ->
    [XeroEmployeeRef] ->
    IO ()
markStaleXeroStaffMappings connection employees = do
    let activeEmployeeIds = map (.xeroEmployeeId) employees
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
    let activeEarningsRateIds = map (.xeroEarningsRateId) earningsRates
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

reconcileXeroPayrollCalendarSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    [XeroPayrollCalendarRef] ->
    IO ()
reconcileXeroPayrollCalendarSelection connection payrollCalendars = do
    let activePayrollCalendars = List.sortOn (.xeroPayrollCalendarName) payrollCalendars
        activePayrollCalendarIds = map (.xeroPayrollCalendarId) activePayrollCalendars
    maybeSelection <-
        query @XeroPayrollCalendarSelection
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> fetchOneOrNothing
    case (maybeSelection, activePayrollCalendars) of
        (Just selection, _)
            | selection.calendarStatus == "verified"
            , maybe False (`elem` activePayrollCalendarIds) selection.xeroPayrollCalendarId ->
                pure ()
        (_, [payrollCalendar]) ->
            upsertXeroPayrollCalendarSelection connection "verified" payrollCalendar
        (Just selection, _)
            | selection.calendarStatus == "verified" ->
                selection
                    |> set #calendarStatus ("stale" :: Text)
                    |> set #lastVerifiedAt Nothing
                    |> set #updatedByUserId (Just (unpackId currentUser.id))
                    |> updateRecord
                    |> void
        _ -> pure ()

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

upsertXeroPayrollCalendarSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    XeroConnection ->
    Text ->
    XeroPayrollCalendarRef ->
    IO ()
upsertXeroPayrollCalendarSelection connection calendarStatus payrollCalendar = do
    now <- getCurrentTime
    existingSelection <-
        query @XeroPayrollCalendarSelection
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> fetchOneOrNothing
    let prepared record =
            record
                |> set #venueId (unpackId currentVenueId)
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #xeroPayrollCalendarId (Just payrollCalendar.xeroPayrollCalendarId)
                |> set #xeroPayrollCalendarName (Just payrollCalendar.xeroPayrollCalendarName)
                |> set #calendarStatus calendarStatus
                |> set #lastVerifiedAt (if calendarStatus == "verified" then Just now else Nothing)
                |> set #updatedByUserId (Just (unpackId currentUser.id))
    case existingSelection of
        Just existing -> prepared existing |> updateRecord |> void
        Nothing ->
            prepared (newRecord @XeroPayrollCalendarSelection)
                |> set #createdByUserId (Just (unpackId currentUser.id))
                |> createRecord
                |> void

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
