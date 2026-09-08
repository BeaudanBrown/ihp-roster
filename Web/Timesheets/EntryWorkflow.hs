module Web.Timesheets.EntryWorkflow
    ( TimesheetRequestContext (..)
    , TimesheetCreationBlocker (..)
    , TimesheetCreateOutcome (..)
    , TimesheetEditOutcome (..)
    , fetchEditableTimesheetEntry
    , prepareNewTimesheetForm
    , prepareEditTimesheetForm
    , createOrdinaryTimesheetEntry
    , editOrdinaryTimesheetEntry
    , TimesheetSuggestionIntent (..)
    , TimesheetSuggestionOutcome (..)
    , TimesheetSuggestionFormOutcome (..)
    , TimesheetReviewIntent (..)
    , TimesheetReviewOutcome (..)
    , prepareSuggestedTimesheetForm
    , createSuggestedTimesheetEntry
    , reviewTimesheetEntry
    ) where

import Application.Error.Types (AppError)
import Application.Helper.SurfaceResource (LiveMutationResult)
import Application.Helper.TimeRules (calendarDayForOperationalClock,
                                     defaultShiftTimesForVenueConfig)
import Application.Helper.View.Timesheets (TimesheetFormInputs)
import Application.VenueTime.Model
import Web.Controller.Prelude
import Web.Timesheets.Filters (TimesheetViewFilters (..))
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..))
import Web.Timesheets.Mutations
import Web.Timesheets.Paths (newTimesheetEntryFromSuggestionUrl)
import Web.Timesheets.Projection
import Web.Timesheets.Suggestion (newTimesheetEntryFromSuggestion,
                                  timesheetSuggestionOperationalDate)
import Web.Timesheets.Validation
import Web.View.Timesheets.New (NewTimesheetRenderModel (..))
import Web.View.Timesheets.SuggestedNew (SuggestedTimesheetRenderModel (..))

-- Canonical response context, not authorization evidence. Existing-entry scope
-- checks must precede reading the mutation calendar and canonicalizing filters.
data TimesheetRequestContext = TimesheetRequestContext
    { timesheetScope   :: TimesheetWeekScopeValue
    , timesheetFilters :: TimesheetViewFilters
    }

data TimesheetCreationBlocker = NoTimesheetStaff | NoTimesheetShiftTypes | NoTimesheetDay | TimesheetTimingUnavailable

data TimesheetCreateOutcome
    = TimesheetCreateBlocked TimesheetCreationBlocker
    | TimesheetCreateInvalid NewTimesheetRenderModel
    | TimesheetCreateCompleted (Either TimesheetCalendarConflict (LiveMutationResult TimesheetEntry))

data TimesheetEditOutcome
    = TimesheetEditInvalid TimesheetFormInputs
    | TimesheetEditCompleted (Either TimesheetCalendarConflict (Bool, LiveMutationResult TimesheetEntry))

-- Preserve the existing lookup/venue/visibility/window precedence. This snapshot
-- does not introduce a new row lock or change the mutation's calendar lock.
fetchEditableTimesheetEntry :: (?request :: Request, ?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext) => Id TimesheetEntry -> IO TimesheetEntry
fetchEditableTimesheetEntry entryId = do
    entry <- fetch entryId
    ensureRecordInCurrentVenue entry.venueId
    ensureTimesheetVisibility entry
    ensureEditWindowOrManager (timesheetEntryOperationalDate entry)
    pure entry

prepareEditTimesheetForm :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe UUID -> TimesheetEntry -> IO TimesheetFormInputs
prepareEditTimesheetForm selectedStaffFilterId entry = do
    formContext <- fetchTimesheetFormContext (timesheetFormReferencesFor entry) selectedStaffFilterId
    pure (timesheetFormInputsFor formContext entry)

prepareNewTimesheetForm :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe UUID -> Maybe Day -> IO (Either TimesheetCreationBlocker NewTimesheetRenderModel)
prepareNewTimesheetForm selectedStaffFilterId maybeWorkedOn = do
    formContext <- fetchTimesheetFormContext noReferencedTimesheetOptions selectedStaffFilterId
    let venueConfig = formContext.formVenueConfig
    case (formContext.formStaffMembers, formContext.formShiftTypes, maybeWorkedOn) of
        ([], _, _) -> pure (Left NoTimesheetStaff)
        (_, [], _) -> pure (Left NoTimesheetShiftTypes)
        (_, _, Nothing) -> pure (Left NoTimesheetDay)
        (_, defaultShiftType : _, Just workedOn) ->
            case defaultTimesheetEntry venueConfig workedOn of
                Left _ -> pure (Left TimesheetTimingUnavailable)
                Right entry -> do
                    hasRosterSuggestionForDay <- viewerHasTimesheetSuggestionOnDay selectedStaffFilterId workedOn
                    let timesheetEntry = entry
                            |> set #venueId (unpackId currentVenueId)
                            |> (\record -> maybe record (\staffId -> set #staffId staffId record) formContext.formCurrentViewerStaffId)
                            |> set #shiftTypeId (unpackId defaultShiftType.id)
                    let timesheetFormInputs = timesheetFormInputsFor formContext timesheetEntry
                    pure (Right NewTimesheetRenderModel { .. })

createOrdinaryTimesheetEntry :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetRequestContext -> IO TimesheetCreateOutcome
createOrdinaryTimesheetEntry context = do
    let selectedStaffFilterId = context.timesheetFilters.filterStaffId
    formContext <- fetchTimesheetFormContext noReferencedTimesheetOptions selectedStaffFilterId
    let venueConfig = formContext.formVenueConfig
    let submittedWorkedOn = fromMaybe context.timesheetScope.timesheetWindowStart (paramOrNothing @Day "workedOn")
    case defaultTimesheetEntry venueConfig submittedWorkedOn of
        Left _ -> pure (TimesheetCreateBlocked TimesheetTimingUnavailable)
        Right entry -> do
            let timesheetEntryRecord = entry
                    |> set #venueId (unpackId currentVenueId)
                    |> buildTimesheetEntry venueConfig formContext.formCurrentViewerStaffId
            hasRosterSuggestionForDay <- viewerHasTimesheetSuggestionOnDay selectedStaffFilterId submittedWorkedOn
            timesheetEntryRecord |> ifValid \case
                Left timesheetEntry -> do
                    let timesheetFormInputs = timesheetFormInputsFor formContext timesheetEntry
                    pure (TimesheetCreateInvalid NewTimesheetRenderModel { .. })
                Right timesheetEntry -> do
                    ensureStaffAssignmentAllowed timesheetEntry.staffId
                    ensureShiftTypeAllowed timesheetEntry.shiftTypeId
                    TimesheetCreateCompleted <$> createTimesheetEntryMutation context.timesheetScope timesheetEntry

editOrdinaryTimesheetEntry :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetRequestContext -> TimesheetEntry -> IO TimesheetEditOutcome
editOrdinaryTimesheetEntry context existingEntry = do
    formContext <- fetchTimesheetFormContext (timesheetFormReferencesFor existingEntry) context.timesheetFilters.filterStaffId
    prepareTimesheetEdit formContext.formVenueConfig formContext.formCurrentViewerStaffId existingEntry >>= \case
        Left timesheetEntry -> pure (TimesheetEditInvalid (timesheetFormInputsFor formContext timesheetEntry))
        Right intent -> TimesheetEditCompleted <$> updateTimesheetEntryMutation context.timesheetScope intent

data TimesheetSuggestionIntent = CreateSuggestedTimesheet | ApproveSuggestedTimesheet

data TimesheetSuggestionFormOutcome
    = SuggestedTimesheetMissing
    | SuggestedTimesheetCanonicalRedirect Text
    | SuggestedTimesheetTimingUnavailable Day
    | SuggestedTimesheetForm SuggestedTimesheetRenderModel

data TimesheetSuggestionOutcome
    = SuggestionUnavailable
    | SuggestionTimingUnavailable
    | SuggestionInvalid SuggestedTimesheetRenderModel
    | SuggestionAccessDenied
    | SuggestionCalendarConflict TimesheetCalendarConflict
    | SuggestionChanged TimesheetSuggestionIntent
    | SuggestionApprovalFailed AppError
    | SuggestionCompleted TimesheetSuggestionIntent TimesheetMaterializationKind (LiveMutationResult TimesheetEntry)

data TimesheetReviewIntent = ApproveTimesheet | UnapproveTimesheet

data TimesheetReviewOutcome
    = TimesheetReviewTimingInvalid
    | TimesheetReviewFailed AppError
    | TimesheetReviewCalendarConflict TimesheetCalendarConflict
    | TimesheetReviewCompleted TimesheetReviewIntent (LiveMutationResult TimesheetEntry)

prepareSuggestedTimesheetForm :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterSlot -> Maybe UUID -> Bool -> IO TimesheetSuggestionFormOutcome
prepareSuggestedTimesheetForm rosterSlotId selectedStaffFilterId needsCanonicalRedirect = do
    fetchTimesheetSuggestionForRosterSlot rosterSlotId >>= \case
        Nothing -> pure SuggestedTimesheetMissing
        Just suggestion -> do
            let workedOn = timesheetSuggestionOperationalDate suggestion
            if needsCanonicalRedirect
                then pure (SuggestedTimesheetCanonicalRedirect (newTimesheetEntryFromSuggestionUrl rosterSlotId workedOn selectedStaffFilterId))
                else do
                    formContext <- fetchTimesheetFormContext noReferencedTimesheetOptions selectedStaffFilterId
                    case validatePersistedTimezone formContext.formVenueConfig.timezone of
                        Left _ -> pure (SuggestedTimesheetTimingUnavailable workedOn)
                        Right () -> do
                            let timesheetEntry = newTimesheetEntryFromSuggestion (unpackId currentVenueId) suggestion
                            let timesheetFormInputs = timesheetFormInputsFor formContext timesheetEntry
                            pure (SuggestedTimesheetForm SuggestedTimesheetRenderModel { .. })

createSuggestedTimesheetEntry :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetRequestContext -> Id RosterSlot -> IO TimesheetSuggestionOutcome
createSuggestedTimesheetEntry context rosterSlotId = do
    fetchTimesheetSuggestionForRosterSlot rosterSlotId >>= \case
        Nothing -> pure SuggestionUnavailable
        Just suggestion -> do
            formContext <- fetchTimesheetFormContext noReferencedTimesheetOptions context.timesheetFilters.filterStaffId
            let venueConfig = formContext.formVenueConfig
            case validatePersistedTimezone venueConfig.timezone of
                Left _ -> pure SuggestionTimingUnavailable
                Right () -> do
                    let suggestedEntry = newTimesheetEntryFromSuggestion (unpackId currentVenueId) suggestion
                    let timesheetEntry =
                            if hasParam "startTime" || hasParam "hadBreak"
                                then buildTimesheetEntry venueConfig formContext.formCurrentViewerStaffId suggestedEntry
                                else suggestedEntry
                    timesheetEntry |> ifValid \case
                        Left invalidEntry -> do
                            let timesheetFormInputs = timesheetFormInputsFor formContext invalidEntry
                            pure (SuggestionInvalid SuggestedTimesheetRenderModel { .. })
                        Right validEntry ->
                            if validEntry.staffId /= suggestion.suggestionStaffId || validEntry.operationalDate /= suggestion.suggestionOperationalDate
                                then pure SuggestionAccessDenied
                                else do
                                    staffAllowed <- timesheetStaffAssignmentAllowed validEntry.staffId
                                    shiftAllowed <- if staffAllowed then timesheetShiftTypeAllowed validEntry.shiftTypeId else pure False
                                    if not shiftAllowed
                                        then pure SuggestionAccessDenied
                                        else
                                            -- Preserve late, role-gated optional approval parsing.
                                            if hasRole Manager && paramOrDefault @Bool False "approveSuggestion"
                                                then materializeAndApproveTimesheetSuggestionMutation context.timesheetScope suggestion validEntry >>= \case
                                                    Left conflict -> pure (SuggestionCalendarConflict conflict)
                                                    Right (Left failure) -> pure (SuggestionApprovalFailed failure)
                                                    Right (Right result) -> pure (suggestionCompletion ApproveSuggestedTimesheet result)
                                                else materializeTimesheetSuggestionMutation context.timesheetScope suggestion validEntry >>= \case
                                                    Left conflict -> pure (SuggestionCalendarConflict conflict)
                                                    Right result -> pure (suggestionCompletion CreateSuggestedTimesheet result)
  where
    suggestionCompletion intent = \case
        Nothing -> SuggestionChanged intent
        Just (kind, result) -> SuggestionCompleted intent kind result

-- Controller invokes manager/writability/venue/deleted-row policy before reading
-- the shared request context. Timing and approval decisions stay here.
reviewTimesheetEntry :: (?respond :: Respond, ?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetRequestContext -> TimesheetReviewIntent -> TimesheetEntry -> IO TimesheetReviewOutcome
reviewTimesheetEntry context intent entry = case intent of
    ApproveTimesheet -> case decodeTimesheetTiming entry of
        Left _ -> pure TimesheetReviewTimingInvalid
        Right _ -> approveTimesheetEntryMutation context.timesheetScope entry >>= \case
            Left conflict -> pure (TimesheetReviewCalendarConflict conflict)
            Right (Left failure) -> pure (TimesheetReviewFailed failure)
            Right (Right result) -> pure (TimesheetReviewCompleted intent result)
    UnapproveTimesheet -> unapproveTimesheetEntryMutation context.timesheetScope entry >>= \case
        Left conflict -> pure (TimesheetReviewCalendarConflict conflict)
        Right result -> pure (TimesheetReviewCompleted intent result)

defaultTimesheetEntry :: VenueConfig -> Day -> Either BoundaryModelError TimesheetEntry
defaultTimesheetEntry venueConfig operationalDate = do
    let (startTime, endTime) = defaultShiftTimesForVenueConfig venueConfig
    boundaries <- resolveShiftBoundaries venueConfig.timezone ShiftBoundaryInput
        { shiftBoundaryDate = calendarDayForOperationalClock operationalDate startTime
        , shiftBoundaryStartTime = startTime
        , shiftBoundaryStartOccurrence = Nothing
        , shiftBoundaryEndTime = endTime
        , shiftBoundaryEndOccurrence = Nothing
        , shiftBoundaryBreak = Nothing
        }
    pure (newRecord @TimesheetEntry |> set #operationalDate operationalDate |> applyTimesheetEntryBoundaries boundaries)
