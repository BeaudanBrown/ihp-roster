module Web.Controller.Timesheets where

import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError,
                                                            surfaceActionParamsComplete,
                                                            surfaceRequestFieldErrorsMessage)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.TimeRules (defaultShiftTimesForVenueConfig,
                                     venueTimePickerFinalSelectableTimeText,
                                     venueTimePickerStartTimeText)
import Web.Controller.Prelude
import Web.Timesheets.Mutations
import Web.Timesheets.Paths (timesheetWeekUrl)
import Web.Timesheets.Projection
import Web.Timesheets.Responses
import Web.Timesheets.Suggestion (newTimesheetEntryFromSuggestion)
import Web.Timesheets.Validation
import Web.View.Timesheets.Edit
import Web.View.Timesheets.New
import Web.View.Timesheets.SuggestedNew

timesheetSurfaceFilters :: TimesheetSurfaceRequestState -> (Bool, Bool, Bool, Maybe UUID)
timesheetSurfaceFilters state =
    ( state.surfaceRequestShowApproved
    , state.surfaceRequestShowAllStaff
    , state.surfaceRequestShowSuggestions
    , state.surfaceRequestStaffFilterId
    )

reportTimesheetSurfaceRequestErrors ::
    (?context :: ControllerContext, ?request :: Request) =>
    [SurfaceRequestFieldError] ->
    IO ()
reportTimesheetSurfaceRequestErrors errors =
    setErrorMessage ("Check the timesheet controls: " <> surfaceRequestFieldErrorsMessage errors)

requireTimesheetSurfaceState ::
    (?context :: ControllerContext, ?request :: Request) =>
    Either [SurfaceRequestFieldError] TimesheetSurfaceRequestState ->
    IO TimesheetSurfaceRequestState
requireTimesheetSurfaceState = \case
    Right state -> pure state
    Left errors -> do
        reportTimesheetSurfaceRequestErrors errors
        redirectTo TimesheetsAction
        pure TimesheetSurfaceRequestState
            { surfaceRequestWeekOffset = 0
            , surfaceRequestShowApproved = False
            , surfaceRequestShowAllStaff = True
            , surfaceRequestShowSuggestions = True
            , surfaceRequestStaffFilterId = Nothing
            }

instance Controller TimesheetsController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted

    action currentAction@TimesheetsAction = runBepis currentAction BepisPageAction do
        currentOffset <- currentTimesheetWeekOffset
        (weekOffset, showApproved, showAllStaff, showSuggestions, selectedStaffFilterId) <-
            if not (surfaceActionParamsComplete @Surface.TimesheetsSurface @Surface.NavigateTimesheetWeek)
                then do
                    let (showApproved, showAllStaff, showSuggestions, selectedStaffFilterId) = timesheetViewFiltersFromRequest
                    pure (currentOffset, showApproved, showAllStaff, showSuggestions, selectedStaffFilterId)
                else case parseNavigateTimesheetWeekState of
                    Left errors -> do
                        reportTimesheetSurfaceRequestErrors errors
                        pure (currentOffset, False, True, True, Nothing)
                    Right state -> do
                        let (showApproved, showAllStaff, showSuggestions, selectedStaffFilterId) = timesheetSurfaceFilters state
                        pure (state.surfaceRequestWeekOffset, showApproved, showAllStaff, showSuggestions, selectedStaffFilterId)
        if isHtmxRequest
            then respondWithTimesheetWeekFragmentsUpdate weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId
            else redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)

    action currentAction@ShowTimesheetWeekAction { weekOffset } = runBepis currentAction BepisPageAction do
        (showApproved, showAllStaff, showSuggestions, selectedStaffFilterId) <-
            if not (surfaceActionParamsComplete @Surface.TimesheetsSurface @Surface.UpdateTimesheetFilters)
                then pure (timesheetViewFiltersFromRequest)
                else case parseUpdateTimesheetFiltersState of
                    Left errors -> do
                        reportTimesheetSurfaceRequestErrors errors
                        pure (False, True, True, Nothing)
                    Right state -> pure (timesheetSurfaceFilters state)
        renderTimesheetWeekPage weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId

    action currentAction@ShowtimesheetToolbarLiveFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        let (showApproved, showAllStaff, showSuggestions, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        let requestKey = TimesheetProjectionRequest weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId
        respondWithTimesheetFragment requestKey TimesheetProjectionToolbar

    action currentAction@ShowtimesheetDayColumnsLiveFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        let (showApproved, showAllStaff, showSuggestions, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        let requestKey = TimesheetProjectionRequest weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId
        respondWithTimesheetFragment requestKey TimesheetProjectionDayColumns

    action currentAction@ShowTimesheetDaySectionFragmentAction { weekOffset, dayOffset } = runBepis currentAction BepisFragmentAction do
        let (showApproved, showAllStaff, showSuggestions, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        let requestKey = TimesheetProjectionRequest weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId
        let fragment = TimesheetProjectionDaySection dayOffset
        respondWithTimesheetFragment requestKey fragment

    action currentAction@NewTimesheetEntryAction = runBepis currentAction BepisFormAction do
        weekOffset <- weekOffsetFromParamOrCurrent
        let (showApproved, showAllStaff, showSuggestions, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        staffMembers <- fetchStaffForForm
        shiftTypes <- fetchShiftTypesForForm
        currentUserStaff <- fetchCurrentUserStaff
        let currentViewerStaffId = unpackId . get #id <$> currentUserStaff
        let maybeWorkedOn = paramOrNothing @Day "workedOn"
        venueConfig <- fetchVenueConfig
        let pickerStart = venueTimePickerStartTimeText venueConfig
        let pickerEnd = venueTimePickerFinalSelectableTimeText venueConfig
        let (defaultStartTime, defaultEndTime) = defaultShiftTimesForVenueConfig venueConfig

        case (staffMembers, shiftTypes, maybeWorkedOn) of
            ([], _, _) -> do
                setErrorMessage "No staff record found. Contact an administrator."
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)
            (_, [], _) -> do
                setErrorMessage "Add at least one shift type before creating a timesheet entry."
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)
            (_, _, Nothing) -> do
                setErrorMessage "Please choose a day before creating a timesheet entry."
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)
            (_, defaultShiftType : _, Just workedOn) -> do
                hasRosterSuggestionForDay <- viewerHasTimesheetSuggestionOnDay weekOffset showAllStaff selectedStaffFilterId workedOn
                let timesheetEntry =
                        newRecord @TimesheetEntry
                            |> set #venueId (unpackId currentVenueId)
                            |> (\entry -> maybe entry (\staff -> set #staffId (unpackId (get #id staff)) entry) currentUserStaff)
                            |> set #shiftTypeId (unpackId (get #id defaultShiftType))
                            |> set #workedOn workedOn
                            |> set #startTime defaultStartTime
                            |> set #endTime defaultEndTime
                            |> set #hadBreak False
                            |> set #breakStartTime Nothing
                            |> set #breakEndTime Nothing
                            |> set #breakMinutes 0
                if isHtmxRequest
                    then respondHtml (renderNewTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions hasRosterSuggestionForDay selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd)
                    else render NewView { .. }

    action currentAction@CreateTimesheetEntryAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        weekOffset <- weekOffsetFromParamOrCurrent
        let (showApproved, showAllStaff, showSuggestions, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        staffMembers <- fetchStaffForForm
        shiftTypes <- fetchShiftTypesForForm
        currentUserStaff <- fetchCurrentUserStaff
        let currentViewerStaffId = unpackId . get #id <$> currentUserStaff
        venueConfig <- fetchVenueConfig
        let pickerStart = venueTimePickerStartTimeText venueConfig
        let pickerEnd = venueTimePickerFinalSelectableTimeText venueConfig
        let timesheetEntryRecord =
                newRecord @TimesheetEntry
                    |> set #venueId (unpackId currentVenueId)
                    |> buildTimesheetEntry currentViewerStaffId
        hasRosterSuggestionForDay <- viewerHasTimesheetSuggestionOnDay weekOffset showAllStaff selectedStaffFilterId timesheetEntryRecord.workedOn

        timesheetEntryRecord
            |> ifValid \case
                Left timesheetEntry -> do
                    if isHtmxRequest
                        then respondHtml (renderNewTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions hasRosterSuggestionForDay selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd)
                        else render NewView { .. }
                Right timesheetEntry -> do
                    ensureStaffAssignmentAllowed timesheetEntry.staffId
                    ensureShiftTypeAllowed timesheetEntry.shiftTypeId
                    mutationResult <- createTimesheetEntryMutation weekOffset timesheetEntry
                    let createdEntry = mutationResult.liveMutationValue
                    if isHtmxRequest
                        then respondWithTimesheetMutationUpdate weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId mutationResult.liveMutationTouchedResources "Timesheet entry created" True
                        else do
                            setSuccessMessage "Timesheet entry created"
                            redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)

    action currentAction@NewTimesheetEntryFromSuggestionAction { rosterSlotId } = runBepis currentAction BepisFormAction do
        let (showApproved, showAllStaff, showSuggestions, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        maybeSuggestion <- fetchTimesheetSuggestionForRosterSlot rosterSlotId
        case maybeSuggestion of
            Nothing -> do
                weekOffset <- weekOffsetFromParamOrCurrent
                setErrorMessage "That rostered shift is no longer available as a timesheet suggestion."
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)
            Just suggestion -> do
                weekOffset <- weekOffsetFromParamOrEntry suggestion.suggestionWorkedOn
                staffMembers <- fetchStaffForForm
                shiftTypes <- fetchShiftTypesForForm
                currentUserStaff <- fetchCurrentUserStaff
                let currentViewerStaffId = unpackId . get #id <$> currentUserStaff
                venueConfig <- fetchVenueConfig
                let pickerStart = venueTimePickerStartTimeText venueConfig
                let pickerEnd = venueTimePickerFinalSelectableTimeText venueConfig
                let timesheetEntry = newTimesheetEntryFromSuggestion (unpackId currentVenueId) suggestion
                if isHtmxRequest
                    then respondHtml (renderSuggestedTimesheetDialog rosterSlotId timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd)
                    else render SuggestedNewView { .. }

    action currentAction@CreateTimesheetEntryFromSuggestionAction { rosterSlotId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        state <- requireTimesheetSurfaceState parseCreateTimesheetEntryFromSuggestionState
        let weekOffset = state.surfaceRequestWeekOffset
        let (showApproved, showAllStaff, showSuggestions, selectedStaffFilterId) = timesheetSurfaceFilters state
        maybeSuggestion <- fetchTimesheetSuggestionForRosterSlot rosterSlotId
        case maybeSuggestion of
            Nothing -> do
                setErrorMessage "That rostered shift is no longer available as a timesheet suggestion."
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)
            Just suggestion -> do
                staffMembers <- fetchStaffForForm
                shiftTypes <- fetchShiftTypesForForm
                currentUserStaff <- fetchCurrentUserStaff
                let currentViewerStaffId = unpackId . get #id <$> currentUserStaff
                venueConfig <- fetchVenueConfig
                let pickerStart = venueTimePickerStartTimeText venueConfig
                let pickerEnd = venueTimePickerFinalSelectableTimeText venueConfig
                let suggestedEntry = newTimesheetEntryFromSuggestion (unpackId currentVenueId) suggestion
                let timesheetEntry =
                        if hasParam "startTime" || hasParam "hadBreak"
                            then buildTimesheetEntry currentViewerStaffId suggestedEntry
                            else suggestedEntry
                timesheetEntry
                    |> ifValid \case
                        Left invalidEntry -> do
                            let timesheetEntry = invalidEntry
                            if isHtmxRequest
                                then respondHtml (renderSuggestedTimesheetDialog rosterSlotId timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd)
                                else render SuggestedNewView { .. }
                        Right validEntry -> do
                            accessDeniedUnless (validEntry.staffId == suggestion.suggestionStaffId)
                            accessDeniedUnless (validEntry.workedOn == suggestion.suggestionWorkedOn)
                            ensureStaffAssignmentAllowed validEntry.staffId
                            ensureShiftTypeAllowed validEntry.shiftTypeId
                            materializationResult <- materializeTimesheetSuggestionMutation weekOffset suggestion validEntry
                            case materializationResult of
                                Nothing -> do
                                    setErrorMessage "That rostered shift changed before the timesheet entry was created. Review the current suggestion and try again."
                                    redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)
                                Just mutationResult ->
                                    if isHtmxRequest
                                        then respondWithTimesheetMutationUpdate weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId mutationResult.liveMutationTouchedResources "Rostered timesheet entry created" True
                                        else do
                                            setSuccessMessage "Rostered timesheet entry created"
                                            redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)

    action currentAction@EditTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisFormAction do
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        ensureTimesheetVisibility timesheetEntry
        ensureEditWindowOrManager timesheetEntry.workedOn

        weekOffset <- weekOffsetFromParamOrEntry timesheetEntry.workedOn
        let (showApproved, showAllStaff, showSuggestions, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        staffMembers <- fetchStaffForForm
        shiftTypes <- fetchShiftTypesForForm
        currentUserStaff <- fetchCurrentUserStaff
        let currentViewerStaffId = unpackId . get #id <$> currentUserStaff
        venueConfig <- fetchVenueConfig
        let pickerStart = venueTimePickerStartTimeText venueConfig
        let pickerEnd = venueTimePickerFinalSelectableTimeText venueConfig
        if isHtmxRequest
            then respondHtml (renderEditTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd)
            else render EditView { .. }

    action currentAction@UpdateTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        existingEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue existingEntry.venueId
        ensureTimesheetVisibility existingEntry
        ensureEditWindowOrManager existingEntry.workedOn

        weekOffset <- weekOffsetFromParamOrEntry existingEntry.workedOn
        let (showApproved, showAllStaff, showSuggestions, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        staffMembers <- fetchStaffForForm
        shiftTypes <- fetchShiftTypesForForm
        currentUserStaff <- fetchCurrentUserStaff
        let currentViewerStaffId = unpackId . get #id <$> currentUserStaff
        venueConfig <- fetchVenueConfig
        let pickerStart = venueTimePickerStartTimeText venueConfig
        let pickerEnd = venueTimePickerFinalSelectableTimeText venueConfig

        let wasApproved = existingEntry.isApproved
        existingEntry
            |> buildTimesheetEntry currentViewerStaffId
            |> ifValid \case
                Left timesheetEntry -> do
                    if isHtmxRequest
                        then respondHtml (renderEditTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd)
                        else render EditView { .. }
                Right timesheetEntry -> do
                    ensureRosterDerivedIdentityUnchanged existingEntry timesheetEntry
                    ensureStaffAssignmentAllowed timesheetEntry.staffId
                    ensureShiftTypeAllowed timesheetEntry.shiftTypeId
                    let coreChanged = timesheetCoreChanged existingEntry timesheetEntry
                    when (wasApproved && coreChanged) do
                        ensureTimesheetEntryNotPayrollLocked existingEntry weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId
                    let successMessage =
                            if wasApproved && coreChanged
                                then "Timesheet entry updated (approval reset)"
                                else "Timesheet entry updated"
                    mutationResult <- updateTimesheetEntryMutation weekOffset existingEntry timesheetEntry (wasApproved && coreChanged)
                    if isHtmxRequest
                        then respondWithTimesheetMutationUpdate weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId mutationResult.liveMutationTouchedResources successMessage True
                        else do
                            setSuccessMessage successMessage
                            redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)

    action currentAction@DeleteTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        ensureTimesheetVisibility timesheetEntry
        ensureEditWindowOrManager timesheetEntry.workedOn

        weekOffset <- weekOffsetFromParamOrEntry timesheetEntry.workedOn
        let (showApproved, showAllStaff, showSuggestions, selectedStaffFilterId) = timesheetViewFiltersFromRequest
        ensureTimesheetEntryNotPayrollLocked timesheetEntry weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId
        mutationResult <- deleteTimesheetEntryMutation weekOffset timesheetEntry
        if isHtmxRequest
            then respondWithTimesheetMutationUpdate weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId mutationResult.liveMutationTouchedResources "Timesheet entry removed" True
            else setSuccessMessage "Timesheet entry removed"
        unless isHtmxRequest do
            redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)

    action currentAction@ApproveTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        accessDeniedUnless (isNothing timesheetEntry.deletedAt)
        state <- requireTimesheetSurfaceState parseApproveTimesheetEntryState
        let weekOffset = state.surfaceRequestWeekOffset
        let (showApproved, showAllStaff, showSuggestions, selectedStaffFilterId) = timesheetSurfaceFilters state

        mutationResult <- approveTimesheetEntryMutation weekOffset timesheetEntry
        if isHtmxRequest
            then respondWithTimesheetMutationUpdate weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId mutationResult.liveMutationTouchedResources "Timesheet entry approved" False
            else do
                setSuccessMessage "Timesheet entry approved"
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)

    action currentAction@UnapproveTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisPageAction do
        ensureManagerRole
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        accessDeniedUnless (isNothing timesheetEntry.deletedAt)
        state <- requireTimesheetSurfaceState parseUnapproveTimesheetEntryState
        let weekOffset = state.surfaceRequestWeekOffset
        let (showApproved, showAllStaff, showSuggestions, selectedStaffFilterId) = timesheetSurfaceFilters state
        ensureTimesheetEntryNotPayrollLocked timesheetEntry weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId

        mutationResult <- unapproveTimesheetEntryMutation weekOffset timesheetEntry
        if isHtmxRequest
            then respondWithTimesheetMutationUpdate weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId mutationResult.liveMutationTouchedResources "Timesheet entry unapproved" False
            else do
                setSuccessMessage "Timesheet entry unapproved"
                redirectToPath (timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)
