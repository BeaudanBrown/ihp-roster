module Web.Controller.Timesheets where

import Application.Error.Types (appErrorSafeMessage)
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError,
                                                            surfaceRequestFieldErrorsMessage)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Action as TimesheetsAction
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.UserPreferences (upsertCurrentUserTimesheetShowApproved,
                                           upsertCurrentUserTimesheetShowSuggestions,
                                           upsertCurrentUserTimesheetShowWageEstimates)
import Application.Helper.WeekBoundaries (startOfWeekFor)
import Application.VenueTime.Model
import Network.HTTP.Types.Status (status409)
import qualified Network.Wai as Wai
import Web.Controller.Prelude
import Web.Timesheets.EntryWorkflow
import Web.Timesheets.Filters (TimesheetViewFilters (..))
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       timesheetsMountStateForFilters)
import Web.Timesheets.Mutations
import Web.Timesheets.Paths (editTimesheetEntryUrl,
                             newTimesheetEntryFromSuggestionUrl,
                             newTimesheetEntryUrl,
                             timesheetDayColumnsFragmentUrl,
                             timesheetDaySectionFragmentUrl,
                             timesheetSidePanelFragmentUrl,
                             timesheetToolbarFragmentUrl, timesheetWindowUrl,
                             timesheetWindowUrlWithFilters)
import Web.Timesheets.Projection
import Web.Timesheets.Responses
import Web.Timesheets.Suggestion (newTimesheetEntryFromSuggestion,
                                  timesheetSuggestionOperationalDate)
import Web.Timesheets.Validation
import Web.Timesheets.WageEstimates (canViewTimesheetWageEstimates)
import Web.View.Timesheets.SuggestedNew

reportTimesheetSurfaceRequestErrors ::
    (?context :: ControllerContext, ?request :: Request) =>
    [SurfaceRequestFieldError] ->
    IO ()
reportTimesheetSurfaceRequestErrors errors =
    setErrorMessage ("Check the timesheet controls: " <> surfaceRequestFieldErrorsMessage errors)

staffFilterParamNeedsCanonicalRedirect :: (?request :: Request) => Maybe UUID -> Maybe UUID -> Bool
staffFilterParamNeedsCanonicalRedirect requested canonical =
    hasParam "staffFilterId" && (isNothing requested || requested /= canonical)

timesheetRequestNeedsCanonicalRedirect :: (?request :: Request) => Maybe UUID -> Maybe UUID -> Bool
timesheetRequestNeedsCanonicalRedirect requested canonical =
    staffFilterParamNeedsCanonicalRedirect requested canonical

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
            { surfaceRequestAnchorDate = ModifiedJulianDay 0
            , surfaceRequestCalendarRevision = 0
            , surfaceRequestStaffFilterId = Nothing
            , surfaceRequestRosterGroupFilterId = Nothing
            }

redirectToTimesheetWindow :: (?context :: ControllerContext, ?request :: Request) => Day -> Maybe UUID -> IO ()
redirectToTimesheetWindow windowStart staffFilterId =
    redirectToPath (timesheetWindowUrl windowStart staffFilterId)

timesheetWindowStartForAnchor :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Day -> IO Day
timesheetWindowStartForAnchor anchorDate = do
    venueConfig <- fetchVenueConfig
    pure (startOfWeekFor venueConfig.rosterWeekStartsOn anchorDate)

timesheetProjectionRequestForWindow :: Day -> Maybe UUID -> TimesheetProjectionRequest
timesheetProjectionRequestForWindow windowStart staffFilterId =
    TimesheetProjectionRequest
        { projectionWindowStart = windowStart
        , projectionWindowEnd = addDays 7 windowStart
        , projectionStaffFilterId = staffFilterId
        , projectionRosterGroupFilterId = Nothing
        }

ensureTimesheetCreationTimingAvailable :: (?context :: ControllerContext, ?request :: Request) => VenueConfig -> Day -> Maybe UUID -> IO ()
ensureTimesheetCreationTimingAvailable venueConfig windowStart staffFilterId =
    case validatePersistedTimezone venueConfig.timezone of
        Right () -> pure ()
        Left _ -> do
            setErrorMessage "Timesheet creation is unavailable until the venue timezone configuration is repaired."
            redirectToTimesheetWindow windowStart staffFilterId

instance Controller TimesheetsController where
    beforeAction = bepisBeforeAction BepisAuthenticatedVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted
        markStaleTimesheetCalendarResponseForRefresh

    action currentAction@TimesheetsAction = runBepis currentAction BepisPageAction do
        venueConfig <- fetchVenueConfig
        today <- currentOperationalDayForVenue venueConfig
        let windowStart = startOfWeekFor venueConfig.rosterWeekStartsOn today
        filters <- canonicalTimesheetFilters timesheetFiltersFromRequest
        if isHtmxRequest
            then renderTimesheetWindowPage windowStart filters
            else redirectToPath (timesheetWindowUrlWithFilters today filters)

    action currentAction@ShowTimesheetWindowAction { anchorDate = anchorDateParam } = runBepis currentAction BepisPageAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        venueConfig <- fetchVenueConfig
        let requestedFilters = timesheetFiltersFromRequest
        filters <- canonicalTimesheetFilters requestedFilters
        if timesheetRequestNeedsCanonicalRedirect requestedFilters.filterStaffId filters.filterStaffId
                || (hasParam "rosterGroupFilterId" && requestedFilters.filterRosterGroupId /= filters.filterRosterGroupId)
            then redirectToPath (timesheetWindowUrlWithFilters anchorDate filters)
            else renderTimesheetWindowPage (startOfWeekFor venueConfig.rosterWeekStartsOn anchorDate) filters

    action currentAction@ShowtimesheetToolbarLiveFragmentAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        windowStart <- timesheetWindowStartForAnchor anchorDate
        let requestedStaffFilterId = timesheetFiltersFromRequest.filterStaffId
        selectedStaffFilterId <- filterStaffId <$> canonicalTimesheetFilters (TimesheetViewFilters requestedStaffFilterId Nothing)
        when (timesheetRequestNeedsCanonicalRedirect requestedStaffFilterId selectedStaffFilterId) do
            redirectToPath (timesheetToolbarFragmentUrl anchorDate selectedStaffFilterId)
        let requestKey = timesheetProjectionRequestForWindow windowStart selectedStaffFilterId
        respondWithTimesheetFragment requestKey TimesheetProjectionToolbar

    action currentAction@ShowtimesheetSidePanelContentLiveFragmentAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        windowStart <- timesheetWindowStartForAnchor anchorDate
        let requestedStaffFilterId = timesheetFiltersFromRequest.filterStaffId
        selectedStaffFilterId <- filterStaffId <$> canonicalTimesheetFilters (TimesheetViewFilters requestedStaffFilterId Nothing)
        when (timesheetRequestNeedsCanonicalRedirect requestedStaffFilterId selectedStaffFilterId) do
            redirectToPath (timesheetSidePanelFragmentUrl anchorDate selectedStaffFilterId)
        let requestKey = timesheetProjectionRequestForWindow windowStart selectedStaffFilterId
        respondWithTimesheetFragment requestKey TimesheetProjectionSidePanel

    action currentAction@ShowtimesheetDayColumnsLiveFragmentAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        windowStart <- timesheetWindowStartForAnchor anchorDate
        let requestedStaffFilterId = timesheetFiltersFromRequest.filterStaffId
        selectedStaffFilterId <- filterStaffId <$> canonicalTimesheetFilters (TimesheetViewFilters requestedStaffFilterId Nothing)
        when (timesheetRequestNeedsCanonicalRedirect requestedStaffFilterId selectedStaffFilterId) do
            redirectToPath (timesheetDayColumnsFragmentUrl anchorDate selectedStaffFilterId)
        let requestKey = timesheetProjectionRequestForWindow windowStart selectedStaffFilterId
        respondWithTimesheetFragment requestKey TimesheetProjectionDayColumns

    action currentAction@ShowTimesheetDaySectionFragmentAction { anchorDate = anchorDateParam, operationalDate = operationalDateParam } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        operationalDate <- parseIsoDayRouteParam operationalDateParam
        venueConfig <- fetchVenueConfig
        let windowStart = startOfWeekFor venueConfig.rosterWeekStartsOn anchorDate
        let dayOffset = fromInteger (diffDays operationalDate windowStart)
        let requestedStaffFilterId = timesheetFiltersFromRequest.filterStaffId
        selectedStaffFilterId <- filterStaffId <$> canonicalTimesheetFilters (TimesheetViewFilters requestedStaffFilterId Nothing)
        when (timesheetRequestNeedsCanonicalRedirect requestedStaffFilterId selectedStaffFilterId) do
            redirectToPath (timesheetDaySectionFragmentUrl anchorDate operationalDate selectedStaffFilterId)
        let requestKey = timesheetProjectionRequestForWindow windowStart selectedStaffFilterId
        let fragment = TimesheetProjectionDaySection dayOffset
        respondWithTimesheetFragment requestKey fragment

    action currentAction@ToggleTimesheetHideApprovedAction = runBepis currentAction BepisMutationAction do
        case TimesheetsAction.parseToggleTimesheetHideApprovedActionParams of
            Left errors -> do
                reportTimesheetSurfaceRequestErrors errors
                redirectTo TimesheetsAction
            Right fields -> do
                let anchorDate = surfaceFieldValue @Surface.AnchorDate fields
                timesheetScope <- requireCurrentTimesheetCalendarValues anchorDate (surfaceFieldValue @Surface.RosterCalendarRevision fields)
                filters <- canonicalTimesheetFilters (TimesheetViewFilters (surfaceFieldValue @Surface.StaffFilterId fields) (surfaceFieldValue @Surface.RosterGroupFilterId fields))
                upsertCurrentUserTimesheetShowApproved (not (surfaceFieldValue @Surface.HideApproved fields))
                if isHtmxRequest
                    then respondWithTimesheetPreferenceUpdate timesheetScope (timesheetsMountStateForFilters filters)
                    else redirectToPath (timesheetWindowUrl anchorDate filters.filterStaffId)

    action currentAction@ToggleTimesheetShowSuggestionsAction = runBepis currentAction BepisMutationAction do
        case TimesheetsAction.parseToggleTimesheetShowSuggestionsActionParams of
            Left errors -> do
                reportTimesheetSurfaceRequestErrors errors
                redirectTo TimesheetsAction
            Right fields -> do
                let anchorDate = surfaceFieldValue @Surface.AnchorDate fields
                timesheetScope <- requireCurrentTimesheetCalendarValues anchorDate (surfaceFieldValue @Surface.RosterCalendarRevision fields)
                filters <- canonicalTimesheetFilters (TimesheetViewFilters (surfaceFieldValue @Surface.StaffFilterId fields) (surfaceFieldValue @Surface.RosterGroupFilterId fields))
                upsertCurrentUserTimesheetShowSuggestions (surfaceFieldValue @Surface.ShowTimesheetSuggestions fields)
                if isHtmxRequest
                    then respondWithTimesheetPreferenceUpdate timesheetScope (timesheetsMountStateForFilters filters)
                    else redirectToPath (timesheetWindowUrl anchorDate filters.filterStaffId)

    action currentAction@ToggleTimesheetWageEstimatesAction = runBepis currentAction BepisMutationAction do
        accessDeniedUnless canViewTimesheetWageEstimates
        case TimesheetsAction.parseToggleTimesheetWageEstimatesActionParams of
            Left errors -> do
                reportTimesheetSurfaceRequestErrors errors
                redirectTo TimesheetsAction
            Right fields -> do
                let anchorDate = surfaceFieldValue @Surface.AnchorDate fields
                timesheetScope <- requireCurrentTimesheetCalendarValues anchorDate (surfaceFieldValue @Surface.RosterCalendarRevision fields)
                filters <- canonicalTimesheetFilters (TimesheetViewFilters (surfaceFieldValue @Surface.StaffFilterId fields) (surfaceFieldValue @Surface.RosterGroupFilterId fields))
                upsertCurrentUserTimesheetShowWageEstimates (surfaceFieldValue @Surface.ShowTimesheetWageEstimates fields)
                if isHtmxRequest
                    then respondWithTimesheetPreferenceUpdate timesheetScope (timesheetsMountStateForFilters filters)
                    else redirectToPath (timesheetWindowUrlWithFilters anchorDate filters)

    action currentAction@NewTimesheetEntryAction = runBepis currentAction BepisFormAction do
        windowStart <- windowStartFromParamOrCurrent
        let requestedStaffFilterId = timesheetFiltersFromRequest.filterStaffId
        selectedStaffFilterId <- filterStaffId <$> canonicalTimesheetFilters (TimesheetViewFilters requestedStaffFilterId Nothing)
        let maybeWorkedOn = paramOrNothing @Day "workedOn"
        when (timesheetRequestNeedsCanonicalRedirect requestedStaffFilterId selectedStaffFilterId) do
            case maybeWorkedOn of
                Just workedOn -> redirectToPath (newTimesheetEntryUrl workedOn workedOn selectedStaffFilterId)
                Nothing       -> redirectToTimesheetWindow windowStart selectedStaffFilterId
        prepareNewTimesheetForm selectedStaffFilterId maybeWorkedOn
            >>= respondWithNewTimesheetForm windowStart selectedStaffFilterId

    action currentAction@CreateTimesheetEntryAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        context <- requireTimesheetMutationContext
        createOrdinaryTimesheetEntry context >>= respondWithTimesheetCreateOutcome context

    action currentAction@NewTimesheetEntryFromSuggestionAction { rosterSlotId } = runBepis currentAction BepisFormAction do
        let requestedStaffFilterId = timesheetFiltersFromRequest.filterStaffId
        selectedStaffFilterId <- filterStaffId <$> canonicalTimesheetFilters (TimesheetViewFilters requestedStaffFilterId Nothing)
        maybeSuggestion <- fetchTimesheetSuggestionForRosterSlot rosterSlotId
        case maybeSuggestion of
            Nothing -> do
                windowStart <- windowStartFromParamOrCurrent
                setErrorMessage "That rostered shift is no longer available as a timesheet suggestion."
                redirectToTimesheetWindow windowStart selectedStaffFilterId
            Just suggestion -> do
                when (timesheetRequestNeedsCanonicalRedirect requestedStaffFilterId selectedStaffFilterId) do
                    redirectToPath (newTimesheetEntryFromSuggestionUrl rosterSlotId (timesheetSuggestionOperationalDate suggestion) selectedStaffFilterId)
                formContext <- fetchTimesheetFormContext noReferencedTimesheetOptions selectedStaffFilterId
                ensureTimesheetCreationTimingAvailable formContext.formVenueConfig (timesheetSuggestionOperationalDate suggestion) selectedStaffFilterId
                let timesheetEntry = newTimesheetEntryFromSuggestion (unpackId currentVenueId) suggestion
                let timesheetFormInputs = timesheetFormInputsFor formContext timesheetEntry
                let suggestedTimesheetRenderModel = SuggestedTimesheetRenderModel { .. }
                if isHtmxRequest
                    then respondHtml (renderSuggestedTimesheetDialog suggestedTimesheetRenderModel)
                    else render SuggestedNewView { .. }

    action currentAction@CreateTimesheetEntryFromSuggestionAction { rosterSlotId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        state <- requireTimesheetSurfaceState parseCreateTimesheetEntryFromSuggestionState
        timesheetScope <- requireCurrentTimesheetCalendar state
        filters <- canonicalTimesheetFilters (TimesheetViewFilters state.surfaceRequestStaffFilterId state.surfaceRequestRosterGroupFilterId)
        let selectedStaffFilterId = filters.filterStaffId
        maybeSuggestion <- fetchTimesheetSuggestionForRosterSlot rosterSlotId
        case maybeSuggestion of
            Nothing -> do
                setErrorMessage "That rostered shift is no longer available as a timesheet suggestion."
                redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId
            Just suggestion -> do
                formContext <- fetchTimesheetFormContext noReferencedTimesheetOptions selectedStaffFilterId
                let venueConfig = formContext.formVenueConfig
                let currentViewerStaffId = formContext.formCurrentViewerStaffId
                ensureTimesheetCreationTimingAvailable venueConfig timesheetScope.timesheetWindowStart selectedStaffFilterId
                let suggestedEntry = newTimesheetEntryFromSuggestion (unpackId currentVenueId) suggestion
                let timesheetEntry =
                        if hasParam "startTime" || hasParam "hadBreak"
                            then buildTimesheetEntry venueConfig currentViewerStaffId suggestedEntry
                            else suggestedEntry
                timesheetEntry
                    |> ifValid \case
                        Left timesheetEntry -> do
                            let timesheetFormInputs = timesheetFormInputsFor formContext timesheetEntry
                            let suggestedTimesheetRenderModel = SuggestedTimesheetRenderModel { .. }
                            if isHtmxRequest
                                then respondHtml (renderSuggestedTimesheetDialog suggestedTimesheetRenderModel)
                                else render SuggestedNewView { .. }
                        Right validEntry -> do
                            accessDeniedUnless (validEntry.staffId == suggestion.suggestionStaffId)
                            accessDeniedUnless (validEntry.operationalDate == suggestion.suggestionOperationalDate)
                            ensureStaffAssignmentAllowed validEntry.staffId
                            ensureShiftTypeAllowed validEntry.shiftTypeId
                            let shouldApproveSuggestion = hasRole Manager && paramOrDefault @Bool False "approveSuggestion"
                            if shouldApproveSuggestion
                                then materializeAndApproveTimesheetSuggestionMutation timesheetScope suggestion validEntry >>= requireTimesheetCalendarResult >>= \case
                                    Left approvalError -> do
                                        setErrorMessage (appErrorSafeMessage approvalError)
                                        redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId
                                    Right Nothing -> do
                                        setErrorMessage "That rostered shift changed before the timesheet entry was approved. Review the current suggestion and try again."
                                        redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId
                                    Right (Just mutationResult) ->
                                        if isHtmxRequest
                                            then respondWithTimesheetMutationUpdate timesheetScope (timesheetsMountStateForFilters filters) mutationResult.liveMutationTouchedResources "Rostered timesheet entry approved" True
                                            else do
                                                setSuccessMessage "Rostered timesheet entry approved"
                                                redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId
                                else do
                                    materializationResult <- materializeTimesheetSuggestionMutation timesheetScope suggestion validEntry >>= requireTimesheetCalendarResult
                                    case materializationResult of
                                        Nothing -> do
                                            setErrorMessage "That rostered shift changed before the timesheet entry was created. Review the current suggestion and try again."
                                            redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId
                                        Just mutationResult ->
                                            if isHtmxRequest
                                                then respondWithTimesheetMutationUpdate timesheetScope (timesheetsMountStateForFilters filters) mutationResult.liveMutationTouchedResources "Rostered timesheet entry created" True
                                                else do
                                                    setSuccessMessage "Rostered timesheet entry created"
                                                    redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId

    action currentAction@EditTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisFormAction do
        timesheetEntry <- fetchEditableTimesheetEntry timesheetEntryId
        let workedOn = timesheetEntryOperationalDate timesheetEntry
        let requestedStaffFilterId = timesheetFiltersFromRequest.filterStaffId
        selectedStaffFilterId <- filterStaffId <$> canonicalTimesheetFilters (TimesheetViewFilters requestedStaffFilterId Nothing)
        when (timesheetRequestNeedsCanonicalRedirect requestedStaffFilterId selectedStaffFilterId) do
            redirectToPath (editTimesheetEntryUrl timesheetEntryId workedOn selectedStaffFilterId)
        prepareEditTimesheetForm selectedStaffFilterId timesheetEntry >>= respondWithEditTimesheetForm

    action currentAction@UpdateTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        existingEntry <- fetchEditableTimesheetEntry timesheetEntryId
        context <- requireTimesheetMutationContext
        editOrdinaryTimesheetEntry context existingEntry >>= respondWithTimesheetEditOutcome context

    action currentAction@DeleteTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        timesheetEntry <- fetchEditableTimesheetEntry timesheetEntryId
        context <- requireTimesheetMutationContext
        result <- deleteTimesheetEntryMutation context.timesheetScope timesheetEntry >>= requireTimesheetCalendarResult
        respondWithTimesheetCompletion context result "Timesheet entry removed" True

    action currentAction@ApproveTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        accessDeniedUnless (isNothing timesheetEntry.deletedAt)
        state <- requireTimesheetSurfaceState parseApproveTimesheetEntryState
        timesheetScope <- requireCurrentTimesheetCalendar state
        filters <- canonicalTimesheetFilters (TimesheetViewFilters state.surfaceRequestStaffFilterId state.surfaceRequestRosterGroupFilterId)
        let selectedStaffFilterId = filters.filterStaffId
        case decodeTimesheetTiming timesheetEntry of
            Left _ ->
                respondAndStop
                    (Wai.responseLBS status409 [("Content-Type", "text/plain")] "Repair the Timesheet timing before approval.")
            Right _ -> do
                approval <- approveTimesheetEntryMutation timesheetScope timesheetEntry >>= requireTimesheetCalendarResult
                case approval of
                    Left appError -> do
                        setErrorMessage (appErrorSafeMessage appError)
                        redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId
                    Right mutationResult ->
                        if isHtmxRequest
                            then respondWithTimesheetMutationUpdate timesheetScope (timesheetsMountStateForFilters filters) mutationResult.liveMutationTouchedResources "Timesheet entry approved" False
                            else do
                                setSuccessMessage "Timesheet entry approved"
                                redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId

    action currentAction@UnapproveTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisPageAction do
        ensureManagerRole
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        accessDeniedUnless (isNothing timesheetEntry.deletedAt)
        state <- requireTimesheetSurfaceState parseUnapproveTimesheetEntryState
        timesheetScope <- requireCurrentTimesheetCalendar state
        filters <- canonicalTimesheetFilters (TimesheetViewFilters state.surfaceRequestStaffFilterId state.surfaceRequestRosterGroupFilterId)
        let selectedStaffFilterId = filters.filterStaffId

        mutationResult <- unapproveTimesheetEntryMutation timesheetScope timesheetEntry >>= requireTimesheetCalendarResult
        if isHtmxRequest
            then respondWithTimesheetMutationUpdate timesheetScope (timesheetsMountStateForFilters filters) mutationResult.liveMutationTouchedResources "Timesheet entry unapproved" False
            else do
                setSuccessMessage "Timesheet entry unapproved"
                redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId
