module Web.Timesheets.Validation
    ( buildTimesheetEntry
    , ensureRosterDerivedIdentityUnchanged
    , ensureShiftTypeAllowed
    , ensureShiftTypeAllowedForExisting
    , ensureStaffAssignmentAllowed
    , ensureStaffAssignmentAllowedForExisting
    , ensureTimesheetEntryNotPayrollLocked
    , ensureTimesheetVisibility
    , resetApprovalOnEdit
    , timesheetCoreChanged
    , timesheetEntryHasPayrollProvenance
    ) where

import Application.Helper.Staff (isLinkedActiveStaff)
import Application.Helper.Url (appendQueryParams)
import Application.PayAssignment (ShiftPayAssignment (..),
                                  StaffPayAssignment (..),
                                  shiftAssignmentAllowsTimesheets,
                                  staffAssignmentAllowsTimesheets)
import Application.VenueTime (RepeatedTimeOccurrence (..), VenueTimeError (..))
import Application.VenueTime.Model
import Data.Either (fromRight)
import qualified Data.Text as Text
import Data.Time.Calendar (addDays)
import Data.Time.LocalTime (LocalTime (..), TimeOfDay)
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
    Bool ->
    Maybe UUID.UUID ->
    IO ()
ensureTimesheetEntryNotPayrollLocked timesheetEntry weekOffset showApproved showAllStaff showSuggestions staffFilterId = do
    locked <- timesheetEntryHasPayrollProvenance timesheetEntry
    when locked do
        let message = "This approved timesheet entry is locked because it has been exported or submitted to Xero."
        if isHtmxRequest
            then respondWithTimesheetDaySectionUpdate weekOffset (timesheetEntryWorkedOn timesheetEntry) showApproved showAllStaff showSuggestions staffFilterId message True
            else do
                setErrorMessage message
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions staffFilterId)

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
            unless (hasRole Manager) do
                maybeStaff <- fetchCurrentUserStaff
                let ownsEntry = maybe False (\staff -> unpackId (get #id staff) == entry.staffId) maybeStaff
                accessDeniedUnless ownsEntry

ensureRosterDerivedIdentityUnchanged :: (?context :: ControllerContext) => TimesheetEntry -> TimesheetEntry -> IO ()
ensureRosterDerivedIdentityUnchanged existingEntry updatedEntry =
    when (isJust existingEntry.sourceRosterSlotId) do
        accessDeniedUnless (timesheetEntryWorkedOn updatedEntry == timesheetEntryWorkedOn existingEntry)
        accessDeniedUnless (updatedEntry.timezone == existingEntry.timezone)
        accessDeniedUnless (updatedEntry.sourceRosterSlotId == existingEntry.sourceRosterSlotId)

ensureStaffAssignmentAllowed :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID.UUID -> IO ()
ensureStaffAssignmentAllowed staffId = do
    maybeStaff <- query @Staff
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#id, Id staffId)
        |> fetchOneOrNothing
    accessDeniedUnless (maybe False (\staff -> isLinkedActiveStaff staff && staffAssignmentAllowsTimesheets (staffPayAssignment staff)) maybeStaff)
    unless (hasRole Manager) do
        maybeCurrentStaff <- fetchCurrentUserStaff
        let isOwnStaff = maybe False (\staff -> unpackId (get #id staff) == staffId) maybeCurrentStaff
        accessDeniedUnless isOwnStaff

ensureStaffAssignmentAllowedForExisting :: (?context :: ControllerContext, ?modelContext :: ModelContext) => TimesheetEntry -> UUID.UUID -> IO ()
ensureStaffAssignmentAllowedForExisting existingEntry staffId
    | existingEntry.staffId == staffId = pure ()
    | otherwise = ensureStaffAssignmentAllowed staffId

ensureShiftTypeAllowed :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID.UUID -> IO ()
ensureShiftTypeAllowed shiftTypeId = do
    maybeShiftType <-
        query @ShiftType
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#id, Id shiftTypeId)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetchOneOrNothing
    accessDeniedUnless (maybe False (shiftAssignmentAllowsTimesheets . shiftPayAssignment) maybeShiftType)

staffPayAssignment :: Staff -> StaffPayAssignment
staffPayAssignment staff =
    StaffPayAssignment staff.payAssignmentMode staff.defaultAwardLevelId staff.importedXeroPayItemId

shiftPayAssignment :: ShiftType -> ShiftPayAssignment
shiftPayAssignment shiftType =
    ShiftPayAssignment shiftType.payAssignmentMode shiftType.overrideAwardLevelId shiftType.importedXeroPayItemId

ensureShiftTypeAllowedForExisting :: (?context :: ControllerContext, ?modelContext :: ModelContext) => TimesheetEntry -> UUID.UUID -> IO ()
ensureShiftTypeAllowedForExisting existingEntry shiftTypeId
    | existingEntry.shiftTypeId == shiftTypeId = pure ()
    | otherwise = ensureShiftTypeAllowed shiftTypeId

resetApprovalOnEdit :: Bool -> TimesheetEntry -> TimesheetEntry
resetApprovalOnEdit wasApproved entry
    | wasApproved =
        entry
            |> set #isApproved False
            |> set #activePayCalculationId Nothing
            |> set #legacyPayBackfillPending False
            |> set #staffPayVersionId Nothing
            |> set #shiftTypePayVersionId Nothing
            |> set #approvedAt Nothing
            |> set #approvedByUserId Nothing
    | otherwise = entry

timesheetCoreChanged :: TimesheetEntry -> TimesheetEntry -> Bool
timesheetCoreChanged previous next =
    previous.staffId /= next.staffId
        || previous.shiftTypeId /= next.shiftTypeId
        || previous.startsAt /= next.startsAt
        || previous.endsAt /= next.endsAt
        || previous.breakStartsAt /= next.breakStartsAt
        || previous.breakEndsAt /= next.breakEndsAt
        || previous.timezone /= next.timezone

buildTimesheetEntry :: (?context :: ControllerContext, ?request :: Request) => VenueConfig -> Maybe UUID.UUID -> TimesheetEntry -> TimesheetEntry
buildTimesheetEntry venueConfig currentViewerStaffId entry =
    builtWithComments
  where
    parsedWorkedOn = paramOrNothing @Day "workedOn"
    parsedStartTime = parseTimeParam (paramOrDefault "" "startTime")
    parsedEndTime = parseTimeParam (paramOrDefault "" "endTime")
    parsedHadBreak =
        case paramOrNothing @Text "hadBreak" of
            Nothing      -> Right False
            Just "true"  -> Right True
            Just "false" -> Right False
            Just _       -> Left "Had break must be true or false"
    hadBreak = fromRight False parsedHadBreak
    parsedBreakStartTime = if hadBreak then parseTimeParam (paramOrDefault "" "breakStartTime") else Nothing
    parsedBreakEndTime = if hadBreak then parseTimeParam (paramOrDefault "" "breakEndTime") else Nothing
    parsedStartOccurrence = parseOccurrenceParam (paramOrDefault "" "startOccurrence")
    parsedEndOccurrence = parseOccurrenceParam (paramOrDefault "" "endOccurrence")
    parsedBreakStartOccurrence = parseOccurrenceParam (paramOrDefault "" "breakStartOccurrence")
    parsedBreakEndOccurrence = parseOccurrenceParam (paramOrDefault "" "breakEndOccurrence")

    baseEntry =
        entry
            |> requireParam #staffId "staffId" "Please choose a staff member"
            |> requireParam #startsAt "workedOn" "Please choose a day"
            |> requireParam #shiftTypeId "shiftTypeId" "Please choose a shift type"
            |> fill @'["staffId", "shiftTypeId"]
            |> validateParsedFields

    validateParsedFields record =
        record
            |> attachWhen (isNothing parsedWorkedOn) #startsAt "Please choose a day"
            |> attachWhen (isNothing parsedStartTime) #startsAt "Please select a shift start time"
            |> attachWhen (isNothing parsedEndTime) #endsAt "Please select a shift end time"
            |> attachWhen (maybe False (not . submittedTimeAllowed (Just (timesheetEntryStartTime entry))) parsedStartTime) #startsAt intervalValidationMessage
            |> attachWhen (maybe False (not . submittedTimeAllowed (Just (timesheetEntryEndTime entry))) parsedEndTime) #endsAt intervalValidationMessage
            |> attachEitherError parsedStartOccurrence #startsAt
            |> attachEitherError parsedEndOccurrence #endsAt
            |> validateBreakTransport
            |> validateBreakInputs
            |> resolveAndApplyBoundaries

    validateBreakTransport record =
        case parsedHadBreak of
            Left message -> record |> attachFailure #breakStartsAt message
            Right _      -> record

    validateBreakInputs record
        | not hadBreak = record
        | otherwise =
            record
                |> attachWhen (isNothing parsedBreakStartTime) #breakStartsAt "Please select a break start time"
                |> attachWhen (isNothing parsedBreakEndTime) #breakEndsAt "Please select a break end time"
                |> attachWhen (maybe False (not . submittedTimeAllowed (timesheetEntryBreakStartTime entry)) parsedBreakStartTime) #breakStartsAt intervalValidationMessage
                |> attachWhen (maybe False (not . submittedTimeAllowed (timesheetEntryBreakEndTime entry)) parsedBreakEndTime) #breakEndsAt intervalValidationMessage
                |> attachEitherError parsedBreakStartOccurrence #breakStartsAt
                |> attachEitherError parsedBreakEndOccurrence #breakEndsAt

    resolveAndApplyBoundaries record =
        case completeBoundaryInput of
            Nothing ->
                if hadBreak
                    then record
                    else record |> set #breakStartsAt Nothing |> set #breakEndsAt Nothing
            Just (input, missingOccurrenceFields) ->
                case resolveShiftBoundaries venueConfig.timezone input of
                    Left failure -> attachBoundaryFailure failure record
                    Right boundaries ->
                        record
                            |> applyTimesheetEntryBoundaries boundaries
                            |> validateElapsedDuration boundaries
                            |> attachMissingOccurrenceFailures missingOccurrenceFields

    completeBoundaryInput = do
        workedOn <- parsedWorkedOn
        startTime <- parsedStartTime
        endTime <- parsedEndTime
        startOccurrence <- rightToMaybe parsedStartOccurrence
        endOccurrence <- rightToMaybe parsedEndOccurrence
        let shiftEndSharesDate = repeatedEndpointPairCanShareDate workedOn startTime endTime
        let resolvedShiftEndDate = shiftEndDate workedOn startTime endTime
        breakInput <-
            if hadBreak
                then do
                    breakStartTime <- parsedBreakStartTime
                    breakEndTime <- parsedBreakEndTime
                    breakStartOccurrence <- rightToMaybe parsedBreakStartOccurrence
                    breakEndOccurrence <- rightToMaybe parsedBreakEndOccurrence
                    let resolvedBreakStartDate = breakStartDate workedOn startTime breakStartTime
                    let resolvedBreakEndDate = breakEndDate workedOn startTime breakStartTime breakEndTime
                    let breakStartUsesSecondOccurrence = breakStartTime < startTime && repeatedEndpointPairCanShareDate workedOn startTime breakStartTime
                    let breakEndUsesSecondOccurrence = repeatedEndpointPairCanShareDate resolvedBreakStartDate breakStartTime breakEndTime
                    pure (Just BreakBoundaryInput
                        { breakBoundaryStartTime = breakStartTime
                        , breakBoundaryStartOccurrence = provisionalOccurrence (if breakStartUsesSecondOccurrence then SecondOccurrence else FirstOccurrence) resolvedBreakStartDate breakStartTime breakStartOccurrence
                        , breakBoundaryEndTime = breakEndTime
                        , breakBoundaryEndOccurrence = provisionalOccurrence (if breakEndUsesSecondOccurrence then SecondOccurrence else FirstOccurrence) resolvedBreakEndDate breakEndTime breakEndOccurrence
                        })
                else pure Nothing
        let input = ShiftBoundaryInput
                { shiftBoundaryDate = workedOn
                , shiftBoundaryStartTime = startTime
                , shiftBoundaryStartOccurrence = provisionalOccurrence FirstOccurrence workedOn startTime startOccurrence
                , shiftBoundaryEndTime = endTime
                , shiftBoundaryEndOccurrence = provisionalOccurrence (if shiftEndSharesDate then SecondOccurrence else FirstOccurrence) resolvedShiftEndDate endTime endOccurrence
                , shiftBoundaryBreak = breakInput
                }
            missingOccurrenceFields =
                [ field
                | (field, date, timeOfDay, occurrence) <-
                    [ (StartOccurrenceField, workedOn, startTime, startOccurrence)
                    , (EndOccurrenceField, resolvedShiftEndDate, endTime, endOccurrence)
                    ]
                        <> case breakInput of
                            Nothing -> []
                            Just _ ->
                                [ (BreakStartOccurrenceField, breakStartDate workedOn startTime (fromMaybe startTime parsedBreakStartTime), fromMaybe startTime parsedBreakStartTime, fromRight Nothing parsedBreakStartOccurrence)
                                , (BreakEndOccurrenceField, breakEndDate workedOn startTime (fromMaybe startTime parsedBreakStartTime) (fromMaybe endTime parsedBreakEndTime), fromMaybe endTime parsedBreakEndTime, fromRight Nothing parsedBreakEndOccurrence)
                                ]
                , isNothing occurrence
                , civilBoundaryIsRepeated date timeOfDay
                ]
        pure (input, missingOccurrenceFields)

    provisionalOccurrence defaultOccurrence date timeOfDay occurrence
        | isNothing occurrence && civilBoundaryIsRepeated date timeOfDay = Just defaultOccurrence
        | otherwise = occurrence

    shiftEndDate day startTime endTime =
        addDays (if endTime <= startTime && not (repeatedEndpointPairCanShareDate day startTime endTime) then 1 else 0) day
    breakStartDate day startTime breakStartTime =
        addDays (if breakStartTime < startTime && not (repeatedEndpointPairCanShareDate day startTime breakStartTime) then 1 else 0) day
    breakEndDate day startTime breakStartTime breakEndTime =
        let resolvedBreakStartDate = breakStartDate day startTime breakStartTime
         in addDays (if breakEndTime <= breakStartTime && not (repeatedEndpointPairCanShareDate resolvedBreakStartDate breakStartTime breakEndTime) then 1 else 0) resolvedBreakStartDate

    validateElapsedDuration boundaries record
        | authoritativeElapsedSeconds boundaries > 16 * 60 * 60 = record |> attachFailure #endsAt "Shift cannot exceed 16 elapsed hours"
        | otherwise = record

    attachBoundaryFailure failure record =
        case failure of
            BoundaryUnsupportedTimezone _ -> record |> attachFailure #startsAt "This venue timezone is not supported for roster and timesheet entry."
            BoundaryBreakShapeInvalid -> record |> attachFailure #breakStartsAt "Break start and end are both required."
            BoundaryBreakNotContained ->
                record
                    |> attachFailure #breakStartsAt "Break must be within the shift"
                    |> attachFailure #breakEndsAt "Break must be within the shift"
            BoundaryCivilTimeError venueFailure ->
                case venueFailure of
                    NonexistentCivilTime localTime -> attachCivilFailure localTime "This local time does not exist because clocks move forward." record
                    RepeatedCivilTimeRequiresOccurrence localTime -> attachCivilFailure localTime "Choose whether this is the first or second occurrence." record
                    RepeatedTimeOccurrenceNotApplicable localTime _ -> attachCivilFailure localTime "First/second occurrence applies only while clocks repeat." record
                    InvalidCivilTimeOfDay _ -> record |> attachFailure #startsAt "Choose a valid local time."
                    NonPositiveResolvedInterval _ _ -> record |> attachFailure #endsAt "Shift end must be after shift start."

    attachCivilFailure localTime message record
        | parsedWorkedOn == Just localTime.localDay && parsedStartTime == Just localTime.localTimeOfDay = record |> attachFailure #startsAt message
        | parsedEndTime == Just localTime.localTimeOfDay = record |> attachFailure #endsAt message
        | parsedBreakStartTime == Just localTime.localTimeOfDay = record |> attachFailure #breakStartsAt message
        | otherwise = record |> attachFailure #breakEndsAt message

    intervalValidationMessage = venueShiftTimeValidationMessage venueConfig
    submittedTimeAllowed existingTime submittedTime =
        venueShiftTimeAllows venueConfig submittedTime || Just submittedTime == existingTime

    builtWithComments = applyCommentFields entry baseEntry

    normalizedTextParam paramName =
        let value = Text.strip (paramOrDefault "" paramName)
         in if Text.null value then Nothing else Just value

    applyCommentFields originalEntry record =
        let ownsEntry = currentViewerStaffId == Just record.staffId
            staffComment = if ownsEntry then normalizedTextParam "staffComment" else originalEntry.staffComment
            managerNote = if hasRole Manager then normalizedTextParam "managerNote" else originalEntry.managerNote
         in record
                |> set #staffComment staffComment
                |> set #managerNote managerNote
                |> validateOptionalTextLength #staffComment "Staff comment cannot exceed 1000 characters"
                |> validateOptionalTextLength #managerNote "Manager note cannot exceed 1000 characters"

    validateOptionalTextLength field message record =
        record
            |> validateField field
                (\case
                    Just value | Text.length value > 1000 -> Failure message
                    _ -> Success
                )

    attachWhen condition field message record = if condition then attachFailure field message record else record
    attachEitherError parsed field record = either (\message -> attachFailure field message record) (const record) parsed
    rightToMaybe = either (const Nothing) Just

data MissingOccurrenceField
    = StartOccurrenceField
    | EndOccurrenceField
    | BreakStartOccurrenceField
    | BreakEndOccurrenceField

attachMissingOccurrenceFailures :: [MissingOccurrenceField] -> TimesheetEntry -> TimesheetEntry
attachMissingOccurrenceFailures fields entry = foldl' attach entry fields
  where
    message = "Choose whether this is the first or second occurrence."
    attach record StartOccurrenceField = record |> attachFailure #startsAt message
    attach record EndOccurrenceField = record |> attachFailure #endsAt message
    attach record BreakStartOccurrenceField = record |> attachFailure #breakStartsAt message
    attach record BreakEndOccurrenceField = record |> attachFailure #breakEndsAt message
