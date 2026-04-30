module Web.Timesheets.Validation
    ( buildTimesheetEntry
    , ensureShiftTypeAllowed
    , ensureStaffAssignmentAllowed
    , ensureTimesheetEntryNotPayrollLocked
    , ensureTimesheetVisibility
    , resetApprovalOnEdit
    , timesheetEntryHasPayrollProvenance
    ) where

import Application.Helper.Url (appendQueryParams)
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.Timesheets.Paths (timesheetWeekUrl)
import Web.Timesheets.Responses (respondWithTimesheetDaySectionUpdate)

ensureTimesheetEntryNotPayrollLocked ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    TimesheetEntry ->
    Int ->
    Bool ->
    Bool ->
    IO ()
ensureTimesheetEntryNotPayrollLocked timesheetEntry weekOffset showApproved showAllStaff = do
    locked <- timesheetEntryHasPayrollProvenance timesheetEntry
    when locked do
        let message = "This approved timesheet entry is locked because it has been exported or submitted to Xero."
        if isHtmxRequest
            then respondWithTimesheetDaySectionUpdate weekOffset timesheetEntry.workedOn showApproved showAllStaff message True True
            else do
                setErrorMessage message
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff)

timesheetEntryHasPayrollProvenance :: (?modelContext :: ModelContext) => TimesheetEntry -> IO Bool
timesheetEntryHasPayrollProvenance timesheetEntry = do
    exportEntryCount <-
        query @ExportJobEntry
            |> filterWhere (#timesheetEntryId, unpackId (get #id timesheetEntry))
            |> fetchCount
    xeroEntryCount <-
        query @XeroTimesheetSubmissionEntry
            |> filterWhere (#timesheetEntryId, unpackId (get #id timesheetEntry))
            |> fetchCount
    pure (exportEntryCount > 0 || xeroEntryCount > 0)

ensureTimesheetVisibility :: (?context :: ControllerContext, ?modelContext :: ModelContext) => TimesheetEntry -> IO ()
ensureTimesheetVisibility entry =
    if isJust entry.deletedAt
        then accessDeniedUnless False
        else
            unless (hasRole ManagerRole') do
                maybeStaff <- fetchCurrentUserStaff
                let ownsEntry = maybe False (\staff -> unpackId (get #id staff) == entry.staffId) maybeStaff
                accessDeniedUnless ownsEntry

ensureStaffAssignmentAllowed :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID.UUID -> IO ()
ensureStaffAssignmentAllowed staffId =
    do
        ensureOptionalStaffInCurrentVenue (Just staffId)
        unless (hasRole ManagerRole') do
            maybeStaff <- fetchCurrentUserStaff
            let isOwnStaff = maybe False (\staff -> unpackId (get #id staff) == staffId) maybeStaff
            accessDeniedUnless isOwnStaff

ensureShiftTypeAllowed :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID.UUID -> IO ()
ensureShiftTypeAllowed shiftTypeId = do
    maybeShiftType <-
        query @ShiftType
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#id, Id shiftTypeId)
            |> filterWhere (#isActive, True)
            |> fetchOneOrNothing
    accessDeniedUnless (isJust maybeShiftType)

resetApprovalOnEdit :: Bool -> TimesheetEntry -> TimesheetEntry
resetApprovalOnEdit wasApproved entry
    | wasApproved =
        entry
            |> set #isApproved False
            |> set #staffPayVersionId Nothing
            |> set #shiftTypePayVersionId Nothing
            |> set #approvedAt Nothing
            |> set #approvedByUserId Nothing
    | otherwise = entry

buildTimesheetEntry :: (?context :: ControllerContext, ?request :: Request) => TimesheetEntry -> TimesheetEntry
buildTimesheetEntry entry =
    entry
        |> requireParam #staffId "staffId" "Please choose a staff member"
        |> requireParam #workedOn "workedOn" "Please choose a day"
        |> requireParam #shiftTypeId "shiftTypeId" "Please choose a shift type"
        |> fill @'["staffId", "workedOn"]
        |> fill @'["shiftTypeId"]
        |> parseAndSetStartTime
        |> parseAndSetEndTime
        |> set #hadBreak hadBreak
        |> applyBreakFields
        |> validateTimingConstraints
    where
        hadBreak = isJust (paramOrNothing @Text "hadBreak")

        parseAndSetStartTime record =
            case parseTimeParam (paramOrDefault "" "startTime") of
                Just tod ->
                    record
                        |> set #startTime tod
                        |> validateField #startTime
                            (\t ->
                                if isQuarterHourTime t
                                    then Success
                                    else Failure "Shift start must be on a 15-minute increment"
                            )
                Nothing -> record |> attachFailure #startTime "Please select a shift start time"

        parseAndSetEndTime record =
            case parseTimeParam (paramOrDefault "" "endTime") of
                Just tod ->
                    record
                        |> set #endTime tod
                        |> validateField #endTime
                            (\t ->
                                if isQuarterHourTime t
                                    then Success
                                    else Failure "Shift end must be on a 15-minute increment"
                            )
                Nothing -> record |> attachFailure #endTime "Please select a shift end time"

        applyBreakFields record
            | not hadBreak =
                record
                    |> set #breakStartTime Nothing
                    |> set #breakEndTime Nothing
                    |> set #breakMinutes 0
            | otherwise =
                record
                    |> set #breakMinutes 0
                    |> parseAndSetBreakStart
                    |> parseAndSetBreakEnd

        parseAndSetBreakStart record =
            case parseTimeParam (paramOrDefault "" "breakStartTime") of
                Just tod ->
                    record
                        |> set #breakStartTime (Just tod)
                        |> validateField #breakStartTime
                            (\case
                                Just t ->
                                    if isQuarterHourTime t
                                        then Success
                                        else Failure "Break start must be on a 15-minute increment"
                                Nothing -> Failure "Please select a break start time"
                            )
                Nothing ->
                    record
                        |> set #breakStartTime Nothing
                        |> attachFailure #breakStartTime "Please select a break start time"

        parseAndSetBreakEnd record =
            case parseTimeParam (paramOrDefault "" "breakEndTime") of
                Just tod ->
                    record
                        |> set #breakEndTime (Just tod)
                        |> validateField #breakEndTime
                            (\case
                                Just t ->
                                    if isQuarterHourTime t
                                        then Success
                                        else Failure "Break end must be on a 15-minute increment"
                                Nothing -> Failure "Please select a break end time"
                            )
                Nothing ->
                    record
                        |> set #breakEndTime Nothing
                        |> attachFailure #breakEndTime "Please select a break end time"

        validateTimingConstraints record =
            let shiftStart = normalizeShiftMinuteOfDay record.startTime
                shiftEnd = normalizeShiftMinuteOfDay record.endTime
                duration = shiftEnd - shiftStart
             in record
                    |> (\r ->
                            if duration <= 0
                                then r |> attachFailure #endTime "Shift end must be after shift start"
                                else r
                       )
                    |> (\r ->
                            if duration > 960
                                then r |> attachFailure #endTime "Shift cannot exceed 16 hours"
                                else r
                       )
                    |> validateBreakTiming shiftStart shiftEnd duration

        validateBreakTiming shiftStart shiftEnd shiftDuration record
            | not record.hadBreak =
                record
                    |> set #breakStartTime Nothing
                    |> set #breakEndTime Nothing
                    |> set #breakMinutes 0
            | otherwise =
                case (record.breakStartTime, record.breakEndTime) of
                    (Just breakStart, Just breakEnd) ->
                        let breakStartMinute = normalizeShiftMinuteOfDay breakStart
                            breakEndMinute = normalizeShiftMinuteOfDay breakEnd
                            breakDuration = breakEndMinute - breakStartMinute
                            withOrderValidation =
                                if breakDuration <= 0
                                    then record |> attachFailure #breakEndTime "Break end must be after break start"
                                    else record
                            withContainmentValidation =
                                if breakStartMinute <= shiftStart || breakEndMinute >= shiftEnd
                                    then
                                        withOrderValidation
                                            |> attachFailure #breakStartTime "Break must be strictly inside the shift"
                                            |> attachFailure #breakEndTime "Break must be strictly inside the shift"
                                    else withOrderValidation
                         in if breakDuration > 0 && breakDuration < shiftDuration && breakStartMinute > shiftStart && breakEndMinute < shiftEnd
                                then withContainmentValidation |> set #breakMinutes breakDuration
                                else withContainmentValidation
                    _ -> record
