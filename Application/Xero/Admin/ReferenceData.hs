module Application.Xero.Admin.ReferenceData
    ( markStaleXeroEarningsRateMappings
    , markStaleXeroPayrollCalendarSelection
    , markStaleXeroStaffMappings
    , upsertXeroEarningsRate
    , upsertXeroEmployee
    , upsertXeroPayrollCalendar
    ) where

import Application.Helper.ControllerContext
import Application.Helper.Xero
import Control.Monad (void)
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

markStaleXeroPayrollCalendarSelection ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    XeroConnection ->
    [XeroPayrollCalendarRef] ->
    IO ()
markStaleXeroPayrollCalendarSelection connection payrollCalendars = do
    let activePayrollCalendarIds = map (.xeroPayrollCalendarId) payrollCalendars
    maybeSelection <-
        query @XeroPayrollCalendarSelection
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> filterWhere (#calendarStatus, "verified" :: Text)
            |> fetchOneOrNothing
    case maybeSelection of
        Just selection ->
            case selection.xeroPayrollCalendarId of
                Just payrollCalendarId
                    | payrollCalendarId `notElem` activePayrollCalendarIds ->
                        selection
                            |> set #calendarStatus "stale"
                            |> set #lastVerifiedAt Nothing
                            |> updateRecord
                            |> void
                _ -> pure ()
        Nothing -> pure ()

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
                |> set #payrollCalendarId employee.xeroEmployeeCalendarId
                |> set #rawPayload employee.xeroEmployeeRaw
                |> set #syncedAt syncedAt
    case existing of
        Just record -> fillRecord record |> updateRecord
        Nothing     -> fillRecord (newRecord @XeroEmployee) |> createRecord

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
