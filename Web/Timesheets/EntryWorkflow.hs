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
    ) where

import Application.Helper.SurfaceResource (LiveMutationResult)
import Application.Helper.TimeRules (calendarDayForOperationalClock,
                                     defaultShiftTimesForVenueConfig)
import Application.Helper.View.Timesheets (TimesheetFormInputs)
import Application.VenueTime.Model
import Web.Controller.Prelude
import Web.Timesheets.Filters (TimesheetViewFilters (..))
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..))
import Web.Timesheets.Mutations (createTimesheetEntryMutation,
                                 updateTimesheetEntryMutation)
import Web.Timesheets.Projection
import Web.Timesheets.Validation
import Web.View.Timesheets.New (NewTimesheetRenderModel (..))

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
fetchEditableTimesheetEntry :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id TimesheetEntry -> IO TimesheetEntry
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

createOrdinaryTimesheetEntry :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetRequestContext -> IO TimesheetCreateOutcome
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

editOrdinaryTimesheetEntry :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetRequestContext -> TimesheetEntry -> IO TimesheetEditOutcome
editOrdinaryTimesheetEntry context existingEntry = do
    formContext <- fetchTimesheetFormContext (timesheetFormReferencesFor existingEntry) context.timesheetFilters.filterStaffId
    prepareTimesheetEdit formContext.formVenueConfig formContext.formCurrentViewerStaffId existingEntry >>= \case
        Left timesheetEntry -> pure (TimesheetEditInvalid (timesheetFormInputsFor formContext timesheetEntry))
        Right intent -> TimesheetEditCompleted <$> updateTimesheetEntryMutation context.timesheetScope intent

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
