module Web.Timesheets.Validation
    ( TimesheetCalendarConflict (..)
    , TimesheetEditIntent
    , originalTimesheetEntry
    , submittedTimesheetEntry
    , prepareTimesheetEdit
    , buildTimesheetEntry
    , ensureRosterDerivedIdentityUnchanged
    , ensureShiftTypeAllowed
    , timesheetShiftTypeAllowed
    , timesheetStaffAssignmentAllowed
    , ensureShiftTypeAllowedForExisting
    , ensureStaffAssignmentAllowed
    , ensureStaffAssignmentAllowedForExisting
    , ensureTimesheetVisibility
    , resetApprovalOnEdit
    , timesheetCoreChanged
    ) where

import Application.Helper.Staff (isLinkedActiveStaff)
import Application.Helper.TimeRules (calendarDayForOperationalClock)
import Application.PayAssignment (ShiftPayAssignment (..),
                                  StaffPayAssignment (..),
                                  shiftAssignmentAllowsTimesheets,
                                  staffAssignmentAllowsTimesheets)
import Application.VenueTime (RepeatedTimeOccurrence (..), VenueTimeError (..))
import Application.VenueTime.Model
import qualified Control.Exception as Exception
import Data.Either (fromRight)
import qualified Data.Text as Text
import Data.Time.Calendar (addDays)
import Data.Time.LocalTime (LocalTime (..), TimeOfDay)
import qualified Data.UUID as UUID
import qualified Prelude
import Web.Controller.Prelude

-- Thrown under the calendar lock; mutation owners catch only after their
-- transaction unwinds. Returning Left inside that transaction would not roll back.
data TimesheetCalendarConflict = TimesheetCalendarChanged
    deriving stock (Eq, Show)

instance Exception.Exception TimesheetCalendarConflict

-- Constructed only after ordinary form validation and identity/eligibility checks.
-- The mutation derives approval reset; callers cannot supply that decision.
data TimesheetEditIntent = TimesheetEditIntent TimesheetEntry TimesheetEntry

originalTimesheetEntry :: TimesheetEditIntent -> TimesheetEntry
originalTimesheetEntry (TimesheetEditIntent original _) = original

submittedTimesheetEntry :: TimesheetEditIntent -> TimesheetEntry
submittedTimesheetEntry (TimesheetEditIntent _ submitted) = submitted

prepareTimesheetEdit :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueConfig -> Maybe UUID.UUID -> TimesheetEntry -> IO (Either TimesheetEntry TimesheetEditIntent)
prepareTimesheetEdit venueConfig viewerStaffId existingEntry =
    buildTimesheetEntry venueConfig viewerStaffId existingEntry |> ifValid \case
        Left invalidEntry -> pure (Left invalidEntry)
        Right submittedEntry -> do
            ensureRosterDerivedIdentityUnchanged existingEntry submittedEntry
            ensureStaffAssignmentAllowedForExisting existingEntry submittedEntry.staffId
            ensureShiftTypeAllowedForExisting existingEntry submittedEntry.shiftTypeId
            pure (Right (TimesheetEditIntent existingEntry submittedEntry))

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
        accessDeniedUnless (timesheetEntryOperationalDate updatedEntry == timesheetEntryOperationalDate existingEntry)
        accessDeniedUnless (updatedEntry.timezone == existingEntry.timezone)
        accessDeniedUnless (updatedEntry.sourceRosterSlotId == existingEntry.sourceRosterSlotId)

ensureStaffAssignmentAllowed :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID.UUID -> IO ()
ensureStaffAssignmentAllowed staffId = timesheetStaffAssignmentAllowed staffId >>= accessDeniedUnless

timesheetStaffAssignmentAllowed :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID.UUID -> IO Bool
timesheetStaffAssignmentAllowed staffId = do
    maybeStaff <- query @Staff
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#id, Id staffId)
        |> fetchOneOrNothing
    let eligible = maybe False (\staff -> isLinkedActiveStaff staff && staffAssignmentAllowsTimesheets (staffPayAssignment staff)) maybeStaff
    if not eligible || hasRole Manager
        then pure eligible
        else do
            maybeCurrentStaff <- fetchCurrentUserStaff
            pure (maybe False (\staff -> unpackId (get #id staff) == staffId) maybeCurrentStaff)

ensureStaffAssignmentAllowedForExisting :: (?context :: ControllerContext, ?modelContext :: ModelContext) => TimesheetEntry -> UUID.UUID -> IO ()
ensureStaffAssignmentAllowedForExisting existingEntry staffId
    | existingEntry.staffId == staffId = pure ()
    | otherwise = ensureStaffAssignmentAllowed staffId

ensureShiftTypeAllowed :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID.UUID -> IO ()
ensureShiftTypeAllowed shiftTypeId = timesheetShiftTypeAllowed shiftTypeId >>= accessDeniedUnless

timesheetShiftTypeAllowed :: (?context :: ControllerContext, ?modelContext :: ModelContext) => UUID.UUID -> IO Bool
timesheetShiftTypeAllowed shiftTypeId = do
    maybeShiftType <-
        query @ShiftType
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhere (#id, Id shiftTypeId)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetchOneOrNothing
    pure (maybe False (shiftAssignmentAllowsTimesheets . shiftPayAssignment) maybeShiftType)

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
        || previous.operationalDate /= next.operationalDate
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
    existingStartTime = fmap (.localTimeOfDay) (recoverStoredInstantLocalTime entry.timezone (Just entry.startsAt))
    existingEndTime = fmap (.localTimeOfDay) (recoverStoredInstantLocalTime entry.timezone (Just entry.endsAt))
    existingBreakStartTime = fmap (.localTimeOfDay) (recoverStoredInstantLocalTime entry.timezone entry.breakStartsAt)
    existingBreakEndTime = fmap (.localTimeOfDay) (recoverStoredInstantLocalTime entry.timezone entry.breakEndsAt)

    baseEntry =
        entry
            |> requireParam #staffId "staffId" "Please choose a staff member"
            |> requireParam #startsAt "workedOn" "Please choose a day"
            |> requireParam #shiftTypeId "shiftTypeId" "Please choose a shift type"
            |> fill @'["staffId", "shiftTypeId"]
            |> maybe Prelude.id (set #operationalDate) parsedWorkedOn
            |> validateParsedFields

    validateParsedFields record =
        record
            |> attachWhen (isNothing parsedWorkedOn) #startsAt "Please choose a day"
            |> attachWhen (isNothing parsedStartTime) #startsAt "Please select a shift start time"
            |> attachWhen (isNothing parsedEndTime) #endsAt "Please select a shift end time"
            |> attachWhen (maybe False (not . submittedTimeAllowed existingStartTime) parsedStartTime) #startsAt intervalValidationMessage
            |> attachWhen (maybe False (not . submittedTimeAllowed existingEndTime) parsedEndTime) #endsAt intervalValidationMessage
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
                |> attachWhen (maybe False (not . submittedTimeAllowed existingBreakStartTime) parsedBreakStartTime) #breakStartsAt intervalValidationMessage
                |> attachWhen (maybe False (not . submittedTimeAllowed existingBreakEndTime) parsedBreakEndTime) #breakEndsAt intervalValidationMessage
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
        let startDate = calendarDateForSubmittedStart workedOn startTime
        let shiftEndSharesDate = repeatedEndpointPairCanShareDate startDate startTime endTime
        let resolvedShiftEndDate = shiftEndDate startDate startTime endTime
        breakInput <-
            if hadBreak
                then do
                    breakStartTime <- parsedBreakStartTime
                    breakEndTime <- parsedBreakEndTime
                    breakStartOccurrence <- rightToMaybe parsedBreakStartOccurrence
                    breakEndOccurrence <- rightToMaybe parsedBreakEndOccurrence
                    let resolvedBreakStartDate = breakStartDate startDate startTime breakStartTime
                    let resolvedBreakEndDate = breakEndDate startDate startTime breakStartTime breakEndTime
                    let breakStartUsesSecondOccurrence = breakStartTime < startTime && repeatedEndpointPairCanShareDate startDate startTime breakStartTime
                    let breakEndUsesSecondOccurrence = repeatedEndpointPairCanShareDate resolvedBreakStartDate breakStartTime breakEndTime
                    pure (Just BreakBoundaryInput
                        { breakBoundaryStartTime = breakStartTime
                        , breakBoundaryStartOccurrence = provisionalOccurrence (if breakStartUsesSecondOccurrence then SecondOccurrence else FirstOccurrence) resolvedBreakStartDate breakStartTime breakStartOccurrence
                        , breakBoundaryEndTime = breakEndTime
                        , breakBoundaryEndOccurrence = provisionalOccurrence (if breakEndUsesSecondOccurrence then SecondOccurrence else FirstOccurrence) resolvedBreakEndDate breakEndTime breakEndOccurrence
                        })
                else pure Nothing
        let input = ShiftBoundaryInput
                { shiftBoundaryDate = startDate
                , shiftBoundaryStartTime = startTime
                , shiftBoundaryStartOccurrence = provisionalOccurrence FirstOccurrence startDate startTime startOccurrence
                , shiftBoundaryEndTime = endTime
                , shiftBoundaryEndOccurrence = provisionalOccurrence (if shiftEndSharesDate then SecondOccurrence else FirstOccurrence) resolvedShiftEndDate endTime endOccurrence
                , shiftBoundaryBreak = breakInput
                }
            missingOccurrenceFields =
                [ field
                | (field, date, timeOfDay, occurrence) <-
                    [ (StartOccurrenceField, startDate, startTime, startOccurrence)
                    , (EndOccurrenceField, resolvedShiftEndDate, endTime, endOccurrence)
                    ]
                        <> case breakInput of
                            Nothing -> []
                            Just _ ->
                                [ (BreakStartOccurrenceField, breakStartDate startDate startTime (fromMaybe startTime parsedBreakStartTime), fromMaybe startTime parsedBreakStartTime, fromRight Nothing parsedBreakStartOccurrence)
                                , (BreakEndOccurrenceField, breakEndDate startDate startTime (fromMaybe startTime parsedBreakStartTime) (fromMaybe endTime parsedBreakEndTime), fromMaybe endTime parsedBreakEndTime, fromRight Nothing parsedBreakEndOccurrence)
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
            BoundaryShiftShapeInvalid -> record |> attachFailure #startsAt "Shift start and end are both required."
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
        | resolvedStartDate == Just localTime.localDay && parsedStartTime == Just localTime.localTimeOfDay = record |> attachFailure #startsAt message
        | parsedEndTime == Just localTime.localTimeOfDay = record |> attachFailure #endsAt message
        | parsedBreakStartTime == Just localTime.localTimeOfDay = record |> attachFailure #breakStartsAt message
        | otherwise = record |> attachFailure #breakEndsAt message

    resolvedStartDate = calendarDateForSubmittedStart <$> parsedWorkedOn <*> parsedStartTime

    calendarDateForSubmittedStart operationalDate startTime =
        case recoverStoredInstantLocalTime entry.timezone (Just entry.startsAt) of
            Just existingStartLocal
                | isNothing entry.sourceRosterSlotId
                , entry.operationalDate == operationalDate
                , operationalDayForLocalTime existingStartLocal /= operationalDate -> existingStartLocal.localDay
            _ -> calendarDayForOperationalClock operationalDate startTime

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
