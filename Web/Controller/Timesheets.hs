module Web.Controller.Timesheets where

import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError,
                                                            surfaceRequestFieldErrorsMessage)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Action as TimesheetsAction
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.TimeRules (defaultShiftTimesForVenueConfig,
                                     venueShiftTimeIntervalMinutes,
                                     venueTimePickerFinalSelectableTimeText,
                                     venueTimePickerStartTimeText)
import Application.Helper.UserPreferences (upsertCurrentUserTimesheetHideApproved,
                                           upsertCurrentUserTimesheetShowSuggestions)
import Application.VenueTime.Model
import Web.Controller.Prelude
import Web.Timesheets.Mutations
import Web.Timesheets.Paths (timesheetWeekUrl)
import Web.Timesheets.Projection
import Web.Timesheets.Responses
import Web.Timesheets.Suggestion (newTimesheetEntryFromSuggestion,
                                  timesheetSuggestionWorkedOn)
import Web.Timesheets.Validation
import Web.View.Timesheets.Edit
import Web.View.Timesheets.New
import Web.View.Timesheets.SuggestedNew

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
            , surfaceRequestStaffFilterId = Nothing
            }

newTimesheetEntryForForm :: VenueConfig -> Day -> TimeOfDay -> TimeOfDay -> TimesheetEntry
newTimesheetEntryForForm venueConfig workedOn startTime endTime =
    case resolveShiftBoundaries venueConfig.timezone ShiftBoundaryInput
        { shiftBoundaryDate = workedOn
        , shiftBoundaryStartTime = startTime
        , shiftBoundaryStartOccurrence = Nothing
        , shiftBoundaryEndTime = endTime
        , shiftBoundaryEndOccurrence = Nothing
        , shiftBoundaryBreak = Nothing
        } of
        Left failure -> error ("Cannot build default timesheet boundaries: " <> show failure)
        Right boundaries -> applyTimesheetEntryBoundaries boundaries (newRecord @TimesheetEntry)

instance Controller TimesheetsController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted

    action currentAction@TimesheetsAction = runBepis currentAction BepisPageAction do
        weekOffset <- currentTimesheetWeekOffset
        let selectedStaffFilterId = timesheetStaffFilterFromRequest
        if isHtmxRequest
            then respondWithTimesheetWeekFragmentsUpdate weekOffset selectedStaffFilterId
            else redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)

    action currentAction@ShowTimesheetWeekAction { weekOffset } = runBepis currentAction BepisPageAction do
        let selectedStaffFilterId = timesheetStaffFilterFromRequest
        if any hasParam ["showApproved", "showAllStaff", "showSuggestions", "hideApproved", "showTimesheetSuggestions"]
            then redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)
            else renderTimesheetWeekPage weekOffset selectedStaffFilterId

    action currentAction@ShowtimesheetToolbarLiveFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        let requestKey = TimesheetProjectionRequest weekOffset timesheetStaffFilterFromRequest
        respondWithTimesheetFragment requestKey TimesheetProjectionToolbar

    action currentAction@ShowtimesheetDayColumnsLiveFragmentAction { weekOffset } = runBepis currentAction BepisFragmentAction do
        let requestKey = TimesheetProjectionRequest weekOffset timesheetStaffFilterFromRequest
        respondWithTimesheetFragment requestKey TimesheetProjectionDayColumns

    action currentAction@ShowTimesheetDaySectionFragmentAction { weekOffset, dayOffset } = runBepis currentAction BepisFragmentAction do
        let requestKey = TimesheetProjectionRequest weekOffset timesheetStaffFilterFromRequest
        let fragment = TimesheetProjectionDaySection dayOffset
        respondWithTimesheetFragment requestKey fragment

    action currentAction@ToggleTimesheetHideApprovedAction = runBepis currentAction BepisMutationAction do
        case TimesheetsAction.parseToggleTimesheetHideApprovedActionParams of
            Left errors -> do
                reportTimesheetSurfaceRequestErrors errors
                redirectTo TimesheetsAction
            Right fields -> do
                let weekOffset = surfaceFieldValue @Surface.WeekOffset fields
                let selectedStaffFilterId = surfaceFieldValue @Surface.StaffFilterId fields
                upsertCurrentUserTimesheetHideApproved (surfaceFieldValue @Surface.HideApproved fields)
                if isHtmxRequest
                    then respondWithTimesheetPreferenceUpdate weekOffset selectedStaffFilterId
                    else redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)

    action currentAction@ToggleTimesheetShowSuggestionsAction = runBepis currentAction BepisMutationAction do
        case TimesheetsAction.parseToggleTimesheetShowSuggestionsActionParams of
            Left errors -> do
                reportTimesheetSurfaceRequestErrors errors
                redirectTo TimesheetsAction
            Right fields -> do
                let weekOffset = surfaceFieldValue @Surface.WeekOffset fields
                let selectedStaffFilterId = surfaceFieldValue @Surface.StaffFilterId fields
                upsertCurrentUserTimesheetShowSuggestions (surfaceFieldValue @Surface.ShowTimesheetSuggestions fields)
                if isHtmxRequest
                    then respondWithTimesheetPreferenceUpdate weekOffset selectedStaffFilterId
                    else redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)

    action currentAction@NewTimesheetEntryAction = runBepis currentAction BepisFormAction do
        weekOffset <- weekOffsetFromParamOrCurrent
        let selectedStaffFilterId = timesheetStaffFilterFromRequest
        staffMembers <- fetchStaffForForm
        shiftTypes <- fetchShiftTypesForForm
        currentUserStaff <- fetchCurrentUserStaff
        let currentViewerStaffId = unpackId . get #id <$> currentUserStaff
        let maybeWorkedOn = paramOrNothing @Day "workedOn"
        venueConfig <- fetchVenueConfig
        let pickerStart = venueTimePickerStartTimeText venueConfig
        let pickerEnd = venueTimePickerFinalSelectableTimeText venueConfig
        let pickerStep = venueShiftTimeIntervalMinutes venueConfig
        let (defaultStartTime, defaultEndTime) = defaultShiftTimesForVenueConfig venueConfig

        case (staffMembers, shiftTypes, maybeWorkedOn) of
            ([], _, _) -> do
                setErrorMessage "No staff record found. Contact an administrator."
                redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)
            (_, [], _) -> do
                setErrorMessage "Add at least one shift type before creating a timesheet entry."
                redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)
            (_, _, Nothing) -> do
                setErrorMessage "Please choose a day before creating a timesheet entry."
                redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)
            (_, defaultShiftType : _, Just workedOn) -> do
                hasRosterSuggestionForDay <- viewerHasTimesheetSuggestionOnDay weekOffset selectedStaffFilterId workedOn
                let timesheetEntry =
                        newTimesheetEntryForForm venueConfig workedOn defaultStartTime defaultEndTime
                            |> set #venueId (unpackId currentVenueId)
                            |> (\entry -> maybe entry (\staff -> set #staffId (unpackId (get #id staff)) entry) currentUserStaff)
                            |> set #shiftTypeId (unpackId (get #id defaultShiftType))
                if isHtmxRequest
                    then respondHtml (renderNewTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset hasRosterSuggestionForDay selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep)
                    else render NewView { .. }

    action currentAction@CreateTimesheetEntryAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        weekOffset <- weekOffsetFromParamOrCurrent
        let selectedStaffFilterId = timesheetStaffFilterFromRequest
        staffMembers <- fetchStaffForForm
        shiftTypes <- fetchShiftTypesForForm
        currentUserStaff <- fetchCurrentUserStaff
        let currentViewerStaffId = unpackId . get #id <$> currentUserStaff
        venueConfig <- fetchVenueConfig
        let pickerStart = venueTimePickerStartTimeText venueConfig
        let pickerEnd = venueTimePickerFinalSelectableTimeText venueConfig
        let pickerStep = venueShiftTimeIntervalMinutes venueConfig
        let fallbackWorkedOn = venueWeekStartDate venueConfig weekOffset
        let submittedWorkedOn = fromMaybe fallbackWorkedOn (paramOrNothing @Day "workedOn")
        let (defaultStartTime, defaultEndTime) = defaultShiftTimesForVenueConfig venueConfig
        let timesheetEntryRecord =
                newTimesheetEntryForForm venueConfig submittedWorkedOn defaultStartTime defaultEndTime
                    |> set #venueId (unpackId currentVenueId)
                    |> buildTimesheetEntry venueConfig currentViewerStaffId
        hasRosterSuggestionForDay <- viewerHasTimesheetSuggestionOnDay weekOffset selectedStaffFilterId submittedWorkedOn

        timesheetEntryRecord
            |> ifValid \case
                Left timesheetEntry -> do
                    if isHtmxRequest
                        then respondHtml (renderNewTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset hasRosterSuggestionForDay selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep)
                        else render NewView { .. }
                Right timesheetEntry -> do
                    ensureStaffAssignmentAllowed timesheetEntry.staffId
                    ensureShiftTypeAllowed timesheetEntry.shiftTypeId
                    mutationResult <- createTimesheetEntryMutation weekOffset timesheetEntry
                    let createdEntry = mutationResult.liveMutationValue
                    if isHtmxRequest
                        then respondWithTimesheetMutationUpdate weekOffset selectedStaffFilterId mutationResult.liveMutationTouchedResources "Timesheet entry created" True
                        else do
                            setSuccessMessage "Timesheet entry created"
                            redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)

    action currentAction@NewTimesheetEntryFromSuggestionAction { rosterSlotId } = runBepis currentAction BepisFormAction do
        let selectedStaffFilterId = timesheetStaffFilterFromRequest
        maybeSuggestion <- fetchTimesheetSuggestionForRosterSlot rosterSlotId
        case maybeSuggestion of
            Nothing -> do
                weekOffset <- weekOffsetFromParamOrCurrent
                setErrorMessage "That rostered shift is no longer available as a timesheet suggestion."
                redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)
            Just suggestion -> do
                weekOffset <- weekOffsetFromParamOrEntry (timesheetSuggestionWorkedOn suggestion)
                staffMembers <- fetchStaffForForm
                shiftTypes <- fetchShiftTypesForForm
                currentUserStaff <- fetchCurrentUserStaff
                let currentViewerStaffId = unpackId . get #id <$> currentUserStaff
                venueConfig <- fetchVenueConfig
                let pickerStart = venueTimePickerStartTimeText venueConfig
                let pickerEnd = venueTimePickerFinalSelectableTimeText venueConfig
                let pickerStep = venueShiftTimeIntervalMinutes venueConfig
                let timesheetEntry = newTimesheetEntryFromSuggestion (unpackId currentVenueId) suggestion
                if isHtmxRequest
                    then respondHtml (renderSuggestedTimesheetDialog rosterSlotId timesheetEntry staffMembers shiftTypes weekOffset selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep)
                    else render SuggestedNewView { .. }

    action currentAction@CreateTimesheetEntryFromSuggestionAction { rosterSlotId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        state <- requireTimesheetSurfaceState parseCreateTimesheetEntryFromSuggestionState
        let weekOffset = state.surfaceRequestWeekOffset
        let selectedStaffFilterId = state.surfaceRequestStaffFilterId
        maybeSuggestion <- fetchTimesheetSuggestionForRosterSlot rosterSlotId
        case maybeSuggestion of
            Nothing -> do
                setErrorMessage "That rostered shift is no longer available as a timesheet suggestion."
                redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)
            Just suggestion -> do
                staffMembers <- fetchStaffForForm
                shiftTypes <- fetchShiftTypesForForm
                currentUserStaff <- fetchCurrentUserStaff
                let currentViewerStaffId = unpackId . get #id <$> currentUserStaff
                venueConfig <- fetchVenueConfig
                let pickerStart = venueTimePickerStartTimeText venueConfig
                let pickerEnd = venueTimePickerFinalSelectableTimeText venueConfig
                let pickerStep = venueShiftTimeIntervalMinutes venueConfig
                let suggestedEntry = newTimesheetEntryFromSuggestion (unpackId currentVenueId) suggestion
                let timesheetEntry =
                        if hasParam "startTime" || hasParam "hadBreak"
                            then buildTimesheetEntry venueConfig currentViewerStaffId suggestedEntry
                            else suggestedEntry
                timesheetEntry
                    |> ifValid \case
                        Left invalidEntry -> do
                            let timesheetEntry = invalidEntry
                            if isHtmxRequest
                                then respondHtml (renderSuggestedTimesheetDialog rosterSlotId timesheetEntry staffMembers shiftTypes weekOffset selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep)
                                else render SuggestedNewView { .. }
                        Right validEntry -> do
                            accessDeniedUnless (validEntry.staffId == suggestion.suggestionStaffId)
                            accessDeniedUnless (timesheetEntryWorkedOn validEntry == timesheetSuggestionWorkedOn suggestion)
                            ensureStaffAssignmentAllowed validEntry.staffId
                            ensureShiftTypeAllowed validEntry.shiftTypeId
                            let shouldApproveSuggestion = hasRole Manager && paramOrDefault @Bool False "approveSuggestion"
                            if shouldApproveSuggestion
                                then materializeAndApproveTimesheetSuggestionMutation weekOffset suggestion validEntry >>= \case
                                    Left approvalError -> do
                                        setErrorMessage approvalError
                                        redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)
                                    Right Nothing -> do
                                        setErrorMessage "That rostered shift changed before the timesheet entry was approved. Review the current suggestion and try again."
                                        redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)
                                    Right (Just mutationResult) ->
                                        if isHtmxRequest
                                            then respondWithTimesheetMutationUpdate weekOffset selectedStaffFilterId mutationResult.liveMutationTouchedResources "Rostered timesheet entry approved" True
                                            else do
                                                setSuccessMessage "Rostered timesheet entry approved"
                                                redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)
                                else do
                                    materializationResult <- materializeTimesheetSuggestionMutation weekOffset suggestion validEntry
                                    case materializationResult of
                                        Nothing -> do
                                            setErrorMessage "That rostered shift changed before the timesheet entry was created. Review the current suggestion and try again."
                                            redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)
                                        Just mutationResult ->
                                            if isHtmxRequest
                                                then respondWithTimesheetMutationUpdate weekOffset selectedStaffFilterId mutationResult.liveMutationTouchedResources "Rostered timesheet entry created" True
                                                else do
                                                    setSuccessMessage "Rostered timesheet entry created"
                                                    redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)

    action currentAction@EditTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisFormAction do
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        ensureTimesheetVisibility timesheetEntry
        let workedOn = timesheetEntryWorkedOn timesheetEntry
        ensureEditWindowOrManager workedOn

        weekOffset <- weekOffsetFromParamOrEntry workedOn
        let selectedStaffFilterId = timesheetStaffFilterFromRequest
        staffMembers <- fetchStaffForFormIncluding timesheetEntry.staffId
        shiftTypes <- fetchShiftTypesForFormIncluding timesheetEntry.shiftTypeId
        currentUserStaff <- fetchCurrentUserStaff
        let currentViewerStaffId = unpackId . get #id <$> currentUserStaff
        venueConfig <- fetchVenueConfig
        let pickerStart = venueTimePickerStartTimeText venueConfig
        let pickerEnd = venueTimePickerFinalSelectableTimeText venueConfig
        let pickerStep = venueShiftTimeIntervalMinutes venueConfig
        if isHtmxRequest
            then respondHtml (renderEditTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep)
            else render EditView { .. }

    action currentAction@UpdateTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        existingEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue existingEntry.venueId
        ensureTimesheetVisibility existingEntry
        let existingWorkedOn = timesheetEntryWorkedOn existingEntry
        ensureEditWindowOrManager existingWorkedOn

        weekOffset <- weekOffsetFromParamOrEntry existingWorkedOn
        let selectedStaffFilterId = timesheetStaffFilterFromRequest
        staffMembers <- fetchStaffForFormIncluding existingEntry.staffId
        shiftTypes <- fetchShiftTypesForFormIncluding existingEntry.shiftTypeId
        currentUserStaff <- fetchCurrentUserStaff
        let currentViewerStaffId = unpackId . get #id <$> currentUserStaff
        venueConfig <- fetchVenueConfig
        let pickerStart = venueTimePickerStartTimeText venueConfig
        let pickerEnd = venueTimePickerFinalSelectableTimeText venueConfig
        let pickerStep = venueShiftTimeIntervalMinutes venueConfig

        let wasApproved = existingEntry.isApproved
        existingEntry
            |> buildTimesheetEntry venueConfig currentViewerStaffId
            |> ifValid \case
                Left timesheetEntry -> do
                    if isHtmxRequest
                        then respondHtml (renderEditTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep)
                        else render EditView { .. }
                Right timesheetEntry -> do
                    ensureRosterDerivedIdentityUnchanged existingEntry timesheetEntry
                    ensureStaffAssignmentAllowedForExisting existingEntry timesheetEntry.staffId
                    ensureShiftTypeAllowedForExisting existingEntry timesheetEntry.shiftTypeId
                    let coreChanged = timesheetCoreChanged existingEntry timesheetEntry
                    when (wasApproved && coreChanged) do
                        ensureTimesheetEntryNotPayrollLocked existingEntry weekOffset selectedStaffFilterId
                    let successMessage =
                            if wasApproved && coreChanged
                                then "Timesheet entry updated (approval reset)"
                                else "Timesheet entry updated"
                    mutationResult <- updateTimesheetEntryMutation weekOffset existingEntry timesheetEntry (wasApproved && coreChanged)
                    if isHtmxRequest
                        then respondWithTimesheetMutationUpdate weekOffset selectedStaffFilterId mutationResult.liveMutationTouchedResources successMessage True
                        else do
                            setSuccessMessage successMessage
                            redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)

    action currentAction@DeleteTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        ensureTimesheetVisibility timesheetEntry
        let workedOn = timesheetEntryWorkedOn timesheetEntry
        ensureEditWindowOrManager workedOn

        weekOffset <- weekOffsetFromParamOrEntry workedOn
        let selectedStaffFilterId = timesheetStaffFilterFromRequest
        ensureTimesheetEntryNotPayrollLocked timesheetEntry weekOffset selectedStaffFilterId
        mutationResult <- deleteTimesheetEntryMutation weekOffset timesheetEntry
        if isHtmxRequest
            then respondWithTimesheetMutationUpdate weekOffset selectedStaffFilterId mutationResult.liveMutationTouchedResources "Timesheet entry removed" True
            else setSuccessMessage "Timesheet entry removed"
        unless isHtmxRequest do
            redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)

    action currentAction@ApproveTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        accessDeniedUnless (isNothing timesheetEntry.deletedAt)
        state <- requireTimesheetSurfaceState parseApproveTimesheetEntryState
        let weekOffset = state.surfaceRequestWeekOffset
        let selectedStaffFilterId = state.surfaceRequestStaffFilterId

        approval <- approveTimesheetEntryMutation weekOffset timesheetEntry
        case approval of
            Left reason -> do
                setErrorMessage reason
                redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)
            Right mutationResult ->
                if isHtmxRequest
                    then respondWithTimesheetMutationUpdate weekOffset selectedStaffFilterId mutationResult.liveMutationTouchedResources "Timesheet entry approved" False
                    else do
                        setSuccessMessage "Timesheet entry approved"
                        redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)

    action currentAction@UnapproveTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisPageAction do
        ensureManagerRole
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        accessDeniedUnless (isNothing timesheetEntry.deletedAt)
        state <- requireTimesheetSurfaceState parseUnapproveTimesheetEntryState
        let weekOffset = state.surfaceRequestWeekOffset
        let selectedStaffFilterId = state.surfaceRequestStaffFilterId
        ensureTimesheetEntryNotPayrollLocked timesheetEntry weekOffset selectedStaffFilterId

        mutationResult <- unapproveTimesheetEntryMutation weekOffset timesheetEntry
        if isHtmxRequest
            then respondWithTimesheetMutationUpdate weekOffset selectedStaffFilterId mutationResult.liveMutationTouchedResources "Timesheet entry unapproved" False
            else do
                setSuccessMessage "Timesheet entry unapproved"
                redirectToPath (timesheetWeekUrl weekOffset selectedStaffFilterId)
