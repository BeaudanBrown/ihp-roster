module Web.Controller.Timesheets where

import Application.Error.Types (appErrorSafeMessage)
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError,
                                                            surfaceRequestFieldErrorsMessage)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Action as TimesheetsAction
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.SurfaceResource (LiveMutationResult (..))
import Application.Helper.TimeRules (calendarDayForOperationalClock,
                                     defaultShiftTimesForVenueConfig)
import Application.Helper.UserPreferences (upsertCurrentUserTimesheetShowApproved,
                                           upsertCurrentUserTimesheetShowSuggestions,
                                           upsertCurrentUserTimesheetShowWageEstimates)
import Application.Helper.WeekBoundaries (startOfWeekFor)
import Application.VenueTime.Model
import Network.HTTP.Types.Status (status409)
import qualified Network.Wai as Wai
import Web.Controller.Prelude
import Web.Timesheets.Filters (TimesheetViewFilters (..))
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       timesheetWeekScopeForAnchor)
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
import Web.View.Timesheets.Edit
import Web.View.Timesheets.New
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

requireCurrentTimesheetCalendar :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetSurfaceRequestState -> IO TimesheetWeekScopeValue
requireCurrentTimesheetCalendar state =
    requireCurrentTimesheetCalendarValues state.surfaceRequestAnchorDate state.surfaceRequestCalendarRevision

requireCurrentTimesheetMutationCalendar :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO TimesheetWeekScopeValue
requireCurrentTimesheetMutationCalendar =
    requireCurrentTimesheetCalendarValues (param @Day "anchorDate") (param @Int "rosterCalendarRevision")

markStaleTimesheetCalendarResponseForRefresh :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
markStaleTimesheetCalendarResponseForRefresh =
    when isHtmxRequest $
        forM_ (paramOrNothing @Int "rosterCalendarRevision") \expectedRevision -> do
            venueConfig <- fetchVenueConfig
            when (expectedRevision /= venueConfig.rosterCalendarRevision) do
                respondAndStop
                    ( Wai.responseLBS
                        status409
                        [("Content-Type", "text/plain"), ("HX-Refresh", "true")]
                        "The roster calendar changed. Review the refreshed window and try again."
                    )

requireCurrentTimesheetCalendarValues :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Day -> Int -> IO TimesheetWeekScopeValue
requireCurrentTimesheetCalendarValues anchorDate expectedRevision = do
    venueConfig <- fetchVenueConfig
    when (venueConfig.rosterCalendarRevision /= expectedRevision) do
        setErrorMessage "The roster calendar changed. Review the refreshed window and try again."
        redirectToPath (timesheetWindowUrl anchorDate timesheetFiltersFromRequest.filterStaffId)
    pure (timesheetWeekScopeForAnchor venueConfig anchorDate)

newTimesheetEntryForForm :: Day -> AuthoritativeBoundaries -> TimesheetEntry
newTimesheetEntryForForm operationalDate boundaries =
    newRecord @TimesheetEntry
        |> set #operationalDate operationalDate
        |> applyTimesheetEntryBoundaries boundaries

defaultTimesheetBoundaries :: VenueConfig -> Day -> TimeOfDay -> TimeOfDay -> Either BoundaryModelError AuthoritativeBoundaries
defaultTimesheetBoundaries venueConfig operationalDate startTime endTime =
    resolveShiftBoundaries venueConfig.timezone ShiftBoundaryInput
        { shiftBoundaryDate = calendarDayForOperationalClock operationalDate startTime
        , shiftBoundaryStartTime = startTime
        , shiftBoundaryStartOccurrence = Nothing
        , shiftBoundaryEndTime = endTime
        , shiftBoundaryEndOccurrence = Nothing
        , shiftBoundaryBreak = Nothing
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
                selectedStaffFilterId <- filterStaffId <$> canonicalTimesheetFilters (TimesheetViewFilters (surfaceFieldValue @Surface.StaffFilterId fields) (surfaceFieldValue @Surface.RosterGroupFilterId fields))
                upsertCurrentUserTimesheetShowApproved (not (surfaceFieldValue @Surface.HideApproved fields))
                if isHtmxRequest
                    then respondWithTimesheetPreferenceUpdate timesheetScope selectedStaffFilterId
                    else redirectToPath (timesheetWindowUrl anchorDate selectedStaffFilterId)

    action currentAction@ToggleTimesheetShowSuggestionsAction = runBepis currentAction BepisMutationAction do
        case TimesheetsAction.parseToggleTimesheetShowSuggestionsActionParams of
            Left errors -> do
                reportTimesheetSurfaceRequestErrors errors
                redirectTo TimesheetsAction
            Right fields -> do
                let anchorDate = surfaceFieldValue @Surface.AnchorDate fields
                timesheetScope <- requireCurrentTimesheetCalendarValues anchorDate (surfaceFieldValue @Surface.RosterCalendarRevision fields)
                selectedStaffFilterId <- filterStaffId <$> canonicalTimesheetFilters (TimesheetViewFilters (surfaceFieldValue @Surface.StaffFilterId fields) (surfaceFieldValue @Surface.RosterGroupFilterId fields))
                upsertCurrentUserTimesheetShowSuggestions (surfaceFieldValue @Surface.ShowTimesheetSuggestions fields)
                if isHtmxRequest
                    then respondWithTimesheetPreferenceUpdate timesheetScope selectedStaffFilterId
                    else redirectToPath (timesheetWindowUrl anchorDate selectedStaffFilterId)

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
                    then respondWithTimesheetPreferenceUpdate timesheetScope filters.filterStaffId
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
        formContext <- fetchTimesheetFormContext noReferencedTimesheetOptions selectedStaffFilterId
        let venueConfig = formContext.formVenueConfig
        let (defaultStartTime, defaultEndTime) = defaultShiftTimesForVenueConfig venueConfig

        case (formContext.formStaffMembers, formContext.formShiftTypes, maybeWorkedOn) of
            ([], _, _) -> do
                setErrorMessage "No staff record found. Contact an administrator."
                redirectToTimesheetWindow windowStart selectedStaffFilterId
            (_, [], _) -> do
                setErrorMessage "Add at least one shift type before creating a timesheet entry."
                redirectToTimesheetWindow windowStart selectedStaffFilterId
            (_, _, Nothing) -> do
                setErrorMessage "Please choose a day before creating a timesheet entry."
                redirectToTimesheetWindow windowStart selectedStaffFilterId
            (_, defaultShiftType : _, Just workedOn) ->
                case defaultTimesheetBoundaries venueConfig workedOn defaultStartTime defaultEndTime of
                    Left _ -> do
                        setErrorMessage "Timesheet creation is unavailable until the venue timezone configuration is repaired."
                        redirectToTimesheetWindow windowStart selectedStaffFilterId
                    Right boundaries -> do
                        hasRosterSuggestionForDay <- viewerHasTimesheetSuggestionOnDay selectedStaffFilterId workedOn
                        let timesheetEntry =
                                newTimesheetEntryForForm workedOn boundaries
                                    |> set #venueId (unpackId currentVenueId)
                                    |> (\entry -> maybe entry (\staffId -> set #staffId staffId entry) formContext.formCurrentViewerStaffId)
                                    |> set #shiftTypeId (unpackId (get #id defaultShiftType))
                        let timesheetFormInputs = timesheetFormInputsFor formContext timesheetEntry
                        let newTimesheetRenderModel = NewTimesheetRenderModel { .. }
                        if isHtmxRequest
                            then respondHtml (renderNewTimesheetDialog newTimesheetRenderModel)
                            else render NewView { .. }

    action currentAction@CreateTimesheetEntryAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        timesheetScope <- requireCurrentTimesheetMutationCalendar
        selectedStaffFilterId <- filterStaffId <$> canonicalTimesheetFilters timesheetFiltersFromRequest
        formContext <- fetchTimesheetFormContext noReferencedTimesheetOptions selectedStaffFilterId
        let venueConfig = formContext.formVenueConfig
        let currentViewerStaffId = formContext.formCurrentViewerStaffId
        let fallbackWorkedOn = timesheetScope.timesheetWindowStart
        let submittedWorkedOn = fromMaybe fallbackWorkedOn (paramOrNothing @Day "workedOn")
        let (defaultStartTime, defaultEndTime) = defaultShiftTimesForVenueConfig venueConfig
        case defaultTimesheetBoundaries venueConfig submittedWorkedOn defaultStartTime defaultEndTime of
            Left _ -> do
                setErrorMessage "Timesheet creation is unavailable until the venue timezone configuration is repaired."
                redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId
            Right boundaries -> do
                let timesheetEntryRecord =
                        newTimesheetEntryForForm submittedWorkedOn boundaries
                            |> set #venueId (unpackId currentVenueId)
                            |> buildTimesheetEntry venueConfig currentViewerStaffId
                hasRosterSuggestionForDay <- viewerHasTimesheetSuggestionOnDay selectedStaffFilterId submittedWorkedOn

                timesheetEntryRecord
                    |> ifValid \case
                        Left timesheetEntry -> do
                            let timesheetFormInputs = timesheetFormInputsFor formContext timesheetEntry
                            let newTimesheetRenderModel = NewTimesheetRenderModel { .. }
                            if isHtmxRequest
                                then respondHtml (renderNewTimesheetDialog newTimesheetRenderModel)
                                else render NewView { .. }
                        Right timesheetEntry -> do
                            ensureStaffAssignmentAllowed timesheetEntry.staffId
                            ensureShiftTypeAllowed timesheetEntry.shiftTypeId
                            mutationResult <- createTimesheetEntryMutation timesheetScope timesheetEntry
                            let createdEntry = mutationResult.liveMutationValue
                            if isHtmxRequest
                                then respondWithTimesheetMutationUpdate timesheetScope selectedStaffFilterId mutationResult.liveMutationTouchedResources "Timesheet entry created" True
                                else do
                                    setSuccessMessage "Timesheet entry created"
                                    redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId

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
        selectedStaffFilterId <- filterStaffId <$> canonicalTimesheetFilters (TimesheetViewFilters state.surfaceRequestStaffFilterId state.surfaceRequestRosterGroupFilterId)
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
                                then materializeAndApproveTimesheetSuggestionMutation timesheetScope suggestion validEntry >>= \case
                                    Left approvalError -> do
                                        setErrorMessage (appErrorSafeMessage approvalError)
                                        redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId
                                    Right Nothing -> do
                                        setErrorMessage "That rostered shift changed before the timesheet entry was approved. Review the current suggestion and try again."
                                        redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId
                                    Right (Just mutationResult) ->
                                        if isHtmxRequest
                                            then respondWithTimesheetMutationUpdate timesheetScope selectedStaffFilterId mutationResult.liveMutationTouchedResources "Rostered timesheet entry approved" True
                                            else do
                                                setSuccessMessage "Rostered timesheet entry approved"
                                                redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId
                                else do
                                    materializationResult <- materializeTimesheetSuggestionMutation timesheetScope suggestion validEntry
                                    case materializationResult of
                                        Nothing -> do
                                            setErrorMessage "That rostered shift changed before the timesheet entry was created. Review the current suggestion and try again."
                                            redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId
                                        Just mutationResult ->
                                            if isHtmxRequest
                                                then respondWithTimesheetMutationUpdate timesheetScope selectedStaffFilterId mutationResult.liveMutationTouchedResources "Rostered timesheet entry created" True
                                                else do
                                                    setSuccessMessage "Rostered timesheet entry created"
                                                    redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId

    action currentAction@EditTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisFormAction do
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        ensureTimesheetVisibility timesheetEntry
        let workedOn = timesheetEntryOperationalDate timesheetEntry
        ensureEditWindowOrManager workedOn

        let requestedStaffFilterId = timesheetFiltersFromRequest.filterStaffId
        selectedStaffFilterId <- filterStaffId <$> canonicalTimesheetFilters (TimesheetViewFilters requestedStaffFilterId Nothing)
        when (timesheetRequestNeedsCanonicalRedirect requestedStaffFilterId selectedStaffFilterId) do
            redirectToPath (editTimesheetEntryUrl timesheetEntryId workedOn selectedStaffFilterId)
        formContext <- fetchTimesheetFormContext (timesheetFormReferencesFor timesheetEntry) selectedStaffFilterId
        let timesheetFormInputs = timesheetFormInputsFor formContext timesheetEntry
        if isHtmxRequest
            then respondHtml (renderEditTimesheetDialog timesheetFormInputs)
            else render EditView { .. }

    action currentAction@UpdateTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        existingEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue existingEntry.venueId
        ensureTimesheetVisibility existingEntry
        let existingWorkedOn = timesheetEntryOperationalDate existingEntry
        ensureEditWindowOrManager existingWorkedOn

        timesheetScope <- requireCurrentTimesheetMutationCalendar
        selectedStaffFilterId <- filterStaffId <$> canonicalTimesheetFilters timesheetFiltersFromRequest
        formContext <- fetchTimesheetFormContext (timesheetFormReferencesFor existingEntry) selectedStaffFilterId
        let venueConfig = formContext.formVenueConfig
        let currentViewerStaffId = formContext.formCurrentViewerStaffId

        let wasApproved = existingEntry.isApproved
        existingEntry
            |> buildTimesheetEntry venueConfig currentViewerStaffId
            |> ifValid \case
                Left timesheetEntry -> do
                    let timesheetFormInputs = timesheetFormInputsFor formContext timesheetEntry
                    if isHtmxRequest
                        then respondHtml (renderEditTimesheetDialog timesheetFormInputs)
                        else render EditView { .. }
                Right timesheetEntry -> do
                    ensureRosterDerivedIdentityUnchanged existingEntry timesheetEntry
                    ensureStaffAssignmentAllowedForExisting existingEntry timesheetEntry.staffId
                    ensureShiftTypeAllowedForExisting existingEntry timesheetEntry.shiftTypeId
                    let coreChanged = timesheetCoreChanged existingEntry timesheetEntry
                    let successMessage =
                            if wasApproved && coreChanged
                                then "Timesheet entry updated (approval reset)"
                                else "Timesheet entry updated"
                    mutationResult <- updateTimesheetEntryMutation timesheetScope existingEntry timesheetEntry (wasApproved && coreChanged)
                    if isHtmxRequest
                        then respondWithTimesheetMutationUpdate timesheetScope selectedStaffFilterId mutationResult.liveMutationTouchedResources successMessage True
                        else do
                            setSuccessMessage successMessage
                            redirectToPath (timesheetWindowUrl timesheetScope.timesheetWindowStart selectedStaffFilterId)

    action currentAction@DeleteTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        ensureTimesheetVisibility timesheetEntry
        let workedOn = timesheetEntryOperationalDate timesheetEntry
        ensureEditWindowOrManager workedOn

        timesheetScope <- requireCurrentTimesheetMutationCalendar
        selectedStaffFilterId <- filterStaffId <$> canonicalTimesheetFilters timesheetFiltersFromRequest
        mutationResult <- deleteTimesheetEntryMutation timesheetScope timesheetEntry
        if isHtmxRequest
            then respondWithTimesheetMutationUpdate timesheetScope selectedStaffFilterId mutationResult.liveMutationTouchedResources "Timesheet entry removed" True
            else setSuccessMessage "Timesheet entry removed"
        unless isHtmxRequest do
            redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId

    action currentAction@ApproveTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
        ensureManagerRole
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        accessDeniedUnless (isNothing timesheetEntry.deletedAt)
        state <- requireTimesheetSurfaceState parseApproveTimesheetEntryState
        timesheetScope <- requireCurrentTimesheetCalendar state
        selectedStaffFilterId <- filterStaffId <$> canonicalTimesheetFilters (TimesheetViewFilters state.surfaceRequestStaffFilterId state.surfaceRequestRosterGroupFilterId)
        case decodeTimesheetTiming timesheetEntry of
            Left _ ->
                respondAndStop
                    (Wai.responseLBS status409 [("Content-Type", "text/plain")] "Repair the Timesheet timing before approval.")
            Right _ -> do
                approval <- approveTimesheetEntryMutation timesheetScope timesheetEntry
                case approval of
                    Left appError -> do
                        setErrorMessage (appErrorSafeMessage appError)
                        redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId
                    Right mutationResult ->
                        if isHtmxRequest
                            then respondWithTimesheetMutationUpdate timesheetScope selectedStaffFilterId mutationResult.liveMutationTouchedResources "Timesheet entry approved" False
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
        selectedStaffFilterId <- filterStaffId <$> canonicalTimesheetFilters (TimesheetViewFilters state.surfaceRequestStaffFilterId state.surfaceRequestRosterGroupFilterId)

        mutationResult <- unapproveTimesheetEntryMutation timesheetScope timesheetEntry
        if isHtmxRequest
            then respondWithTimesheetMutationUpdate timesheetScope selectedStaffFilterId mutationResult.liveMutationTouchedResources "Timesheet entry unapproved" False
            else do
                setSuccessMessage "Timesheet entry unapproved"
                redirectToTimesheetWindow timesheetScope.timesheetWindowStart selectedStaffFilterId
