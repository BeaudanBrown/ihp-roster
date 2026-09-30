module Web.Controller.Timesheets where

import Application.Helper.FrontendContract.AppShell (OpenTimesheetDeleteConfirmationDialog)
import Application.Helper.FrontendContract.AppShell.Request (parseAppShellActionParams)
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError,
                                                            surfaceRequestFieldErrorsMessage)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Action as TimesheetsAction
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.Helper.UserPreferences (upsertCurrentUserTimesheetShowApproved,
                                           upsertCurrentUserTimesheetWageDisplayMode)
import Application.VenueTime.Model
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.Timesheets.EntryWorkflow
import Web.Timesheets.Filters (TimesheetViewFilters (..),
                               emptyTimesheetViewFilters)
import Web.Timesheets.FrontendSurface (timesheetsMountStateForFilters)
import Web.Timesheets.Mutations
import Web.Timesheets.Paths (editTimesheetEntryUrl, newTimesheetEntryUrl,
                             timesheetDayColumnsFragmentUrl,
                             timesheetDaySectionFragmentUrl,
                             timesheetSidePanelFragmentUrl,
                             timesheetStaffContentFragmentUrl,
                             timesheetToolbarFragmentUrl, timesheetWindowUrl,
                             timesheetWindowUrlWithFilters,
                             withTimesheetFilters)
import Web.Timesheets.Projection
import Web.Timesheets.Responses
import Web.Timesheets.Validation (requireBlankTimesheetClassification)
import Web.Timesheets.WageEstimates (canConfigureTimesheetWageEstimates)
import Web.View.Timesheets.Edit (renderTimesheetDeleteConfirmation)
import Web.View.Timesheets.Index (TimesheetFiltersView (..),
                                  renderTimesheetFiltersDialog)

reportTimesheetSurfaceRequestErrors ::
    (?context :: ControllerContext, ?request :: Request) =>
    [SurfaceRequestFieldError] ->
    IO ()
reportTimesheetSurfaceRequestErrors errors =
    setErrorMessage ("Check the timesheet controls: " <> surfaceRequestFieldErrorsMessage errors)

timesheetRequestNeedsCanonicalRedirect :: TimesheetViewFilters -> TimesheetViewFilters -> Bool
timesheetRequestNeedsCanonicalRedirect = (/=)

requireTimesheetSurfaceState ::
    (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) =>
    Either [SurfaceRequestFieldError] TimesheetSurfaceRequestState ->
    IO TimesheetSurfaceRequestState
requireTimesheetSurfaceState = \case
    Right state -> pure state
    Left errors -> do
        reportTimesheetSurfaceRequestErrors errors
        earlyReturn (redirectTo TimesheetsAction)

redirectToTimesheetWindow :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => Day -> Maybe UUID -> IO ResponseReceived
redirectToTimesheetWindow windowStart staffFilterId =
    redirectToPath (timesheetWindowUrl windowStart staffFilterId)

timesheetWindowStartForAnchor :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Day -> IO Day
timesheetWindowStartForAnchor anchorDate = do
    venueConfig <- fetchVenueConfig
    pure (startOfWeekFor venueConfig.rosterWeekStartsOn anchorDate)

canonicalTimesheetFragmentFilters :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => (Maybe UUID -> Text) -> IO TimesheetViewFilters
canonicalTimesheetFragmentFilters fragmentUrl = do
    let requested = timesheetFiltersFromRequest
    anchorDate <- windowStartFromParamOrCurrent
    filters <- canonicalTimesheetFilters anchorDate requested
    when (timesheetRequestNeedsCanonicalRedirect requested filters) do
        earlyReturn $ redirectToPath (withTimesheetFilters filters (fragmentUrl Nothing))
    pure filters

timesheetProjectionRequestForWindow :: Day -> TimesheetViewFilters -> TimesheetProjectionRequest
timesheetProjectionRequestForWindow windowStart filters =
    TimesheetProjectionRequest
        { projectionWindowStart = windowStart
        , projectionWindowEnd = addDays 7 windowStart
        , projectionFilters = filters
        }

filtersFromFields fields = TimesheetViewFilters
    (fromMaybe [] (surfaceFieldValue @Surface.StaffFilterIds fields))
    (fromMaybe [] (surfaceFieldValue @Surface.RosterGroupFilterIds fields))
    (fromMaybe [] (surfaceFieldValue @Surface.ShiftTypeFilterIds fields))

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
        filters <- canonicalTimesheetFilters windowStart timesheetFiltersFromRequest
        if isHtmxRequest
            then renderTimesheetWindowPage windowStart filters
            else redirectToPath (timesheetWindowUrlWithFilters today filters)

    action currentAction@ShowTimesheetWindowAction { anchorDate = anchorDateParam } = runBepis currentAction BepisPageAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        venueConfig <- fetchVenueConfig
        let requestedFilters = timesheetFiltersFromRequest
        filters <- canonicalTimesheetFilters anchorDate requestedFilters
        if timesheetRequestNeedsCanonicalRedirect requestedFilters filters
            then redirectToPath (timesheetWindowUrlWithFilters anchorDate filters)
            else renderTimesheetWindowPage (startOfWeekFor venueConfig.rosterWeekStartsOn anchorDate) filters

    action currentAction@ShowTimesheetFiltersAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFormAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        windowStart <- timesheetWindowStartForAnchor anchorDate
        projection <- fetchTimesheetWeekProjection (timesheetProjectionRequestForWindow windowStart timesheetFiltersFromRequest)
        let view = timesheetIndexView projection
        if isHtmxRequest
            then respondHtml (renderTimesheetFiltersDialog view)
            else render (TimesheetFiltersView view)

    action currentAction@ShowtimesheetToolbarLiveFragmentAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        windowStart <- timesheetWindowStartForAnchor anchorDate
        filters <- canonicalTimesheetFragmentFilters (timesheetToolbarFragmentUrl anchorDate)
        let requestKey = timesheetProjectionRequestForWindow windowStart filters
        respondWithTimesheetFragment requestKey TimesheetProjectionToolbar

    action currentAction@ShowtimesheetSidePanelContentLiveFragmentAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        windowStart <- timesheetWindowStartForAnchor anchorDate
        filters <- canonicalTimesheetFragmentFilters (timesheetSidePanelFragmentUrl anchorDate)
        let requestKey = timesheetProjectionRequestForWindow windowStart filters
        respondWithTimesheetFragment requestKey TimesheetProjectionSidePanel

    action currentAction@ShowTimesheetStaffContentFragmentAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFragmentAction do
        ensureManagerRole
        ensureManagementMode
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        windowStart <- timesheetWindowStartForAnchor anchorDate
        filters <- canonicalTimesheetFragmentFilters (timesheetStaffContentFragmentUrl anchorDate)
        let requestKey = timesheetProjectionRequestForWindow windowStart filters
        respondWithTimesheetFragment requestKey TimesheetProjectionStaffContent

    action currentAction@ShowtimesheetDayColumnsLiveFragmentAction { anchorDate = anchorDateParam } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        windowStart <- timesheetWindowStartForAnchor anchorDate
        filters <- canonicalTimesheetFragmentFilters (timesheetDayColumnsFragmentUrl anchorDate)
        let requestKey = timesheetProjectionRequestForWindow windowStart filters
        respondWithTimesheetFragment requestKey TimesheetProjectionDayColumns

    action currentAction@ShowTimesheetDaySectionFragmentAction { anchorDate = anchorDateParam, operationalDate = operationalDateParam } = runBepis currentAction BepisFragmentAction do
        anchorDate <- parseIsoDayRouteParam anchorDateParam
        operationalDate <- parseIsoDayRouteParam operationalDateParam
        venueConfig <- fetchVenueConfig
        let windowStart = startOfWeekFor venueConfig.rosterWeekStartsOn anchorDate
        let dayOffset = fromInteger (diffDays operationalDate windowStart)
        filters <- canonicalTimesheetFragmentFilters (timesheetDaySectionFragmentUrl anchorDate operationalDate)
        let requestKey = timesheetProjectionRequestForWindow windowStart filters
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
                filters <- canonicalTimesheetFilters anchorDate (filtersFromFields fields)
                upsertCurrentUserTimesheetShowApproved (not (surfaceFieldValue @Surface.HideApproved fields))
                if isHtmxRequest
                    then respondWithTimesheetPreferenceUpdate timesheetScope (timesheetsMountStateForFilters filters)
                    else redirectToPath (timesheetWindowUrlWithFilters anchorDate filters)

    action currentAction@ToggleTimesheetWageEstimatesAction = runBepis currentAction BepisMutationAction do
        accessDeniedUnless canConfigureTimesheetWageEstimates
        case TimesheetsAction.parseToggleTimesheetWageEstimatesActionParams of
            Left errors -> do
                reportTimesheetSurfaceRequestErrors errors
                redirectTo TimesheetsAction
            Right fields -> do
                let anchorDate = surfaceFieldValue @Surface.AnchorDate fields
                timesheetScope <- requireCurrentTimesheetCalendarValues anchorDate (surfaceFieldValue @Surface.RosterCalendarRevision fields)
                filters <- canonicalTimesheetFilters anchorDate (filtersFromFields fields)
                accessDeniedUnless canConfigureTimesheetWageEstimates
                upsertCurrentUserTimesheetWageDisplayMode (surfaceFieldValue @Surface.TimesheetWageDisplayMode fields)
                if isHtmxRequest
                    then respondWithTimesheetPreferenceUpdate timesheetScope (timesheetsMountStateForFilters filters)
                    else redirectToPath (timesheetWindowUrlWithFilters anchorDate filters)

    action currentAction@ToggleTimesheetManagerModeAction = runBepis currentAction BepisPreferenceAction do
        case TimesheetsAction.parseToggleTimesheetManagerModeActionParams of
            Left errors -> do
                reportTimesheetSurfaceRequestErrors errors
                redirectTo TimesheetsAction
            Right fields -> do
                let anchorDate = surfaceFieldValue @Surface.AnchorDate fields
                updated <- upsertCurrentUserManagerMode (surfaceFieldValue @Surface.ManagerModeEnabled fields)
                accessDeniedUnless updated
                let canonicalUrl = timesheetWindowUrlWithFilters anchorDate emptyTimesheetViewFilters { filterShiftTypeIds = fromMaybe [] (surfaceFieldValue @Surface.ShiftTypeFilterIds fields) }
                if isHtmxRequest
                    then do
                        setHeader ("HX-Redirect", cs canonicalUrl)
                        renderPlain ""
                    else redirectToPath canonicalUrl

    action currentAction@NewTimesheetEntryAction = runBepis currentAction BepisFormAction do
        windowStart <- windowStartFromParamOrCurrent
        filters <- canonicalTimesheetFilters windowStart timesheetFiltersFromRequest
        let selectedStaffFilterId = listToMaybe filters.filterStaffIds
        let maybeWorkedOn = paramOrNothing @Day "workedOn"
        case maybeWorkedOn of
            Nothing -> respondWithNewTimesheetForm windowStart selectedStaffFilterId (Left NoTimesheetDay)
            Just workedOn ->
                prepareTimesheetChooser selectedStaffFilterId workedOn >>= respondWithTimesheetChooser windowStart selectedStaffFilterId

    action currentAction@ChooseBlankTimesheetEntryAction = runBepis currentAction BepisFormAction do
        windowStart <- windowStartFromParamOrCurrent
        workedOn <- maybe (accessDeniedUnless False >> pure windowStart) pure (paramOrNothing @Day "workedOn")
        requestedStaffId <- maybe (accessDeniedUnless False >> pure UUID.nil) pure (paramOrNothing @UUID "staffFilterId")
        filters <- canonicalTimesheetFilters windowStart timesheetFiltersFromRequest
        let selectedStaffFilterId = listToMaybe filters.filterStaffIds
        classification <- requireBlankTimesheetClassification
        prepareChosenBlankTimesheetForm requestedStaffId workedOn classification >>= \case
            Nothing -> accessDeniedUnless False >> respondWithNewTimesheetForm windowStart selectedStaffFilterId (Left NoEnabledTimesheetStaff)
            Just outcome -> respondWithNewTimesheetForm windowStart selectedStaffFilterId outcome

    action currentAction@CreateTimesheetEntryAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        context <- requireTimesheetMutationContext
        createOrdinaryTimesheetEntry context >>= respondWithTimesheetCreateOutcome context

    action currentAction@NewTimesheetEntryFromRosterShiftAction { rosterSlotId } = runBepis currentAction BepisFormAction do
        windowStart <- windowStartFromParamOrCurrent
        filters <- canonicalTimesheetFilters windowStart timesheetFiltersFromRequest
        let selectedStaffFilterId = listToMaybe filters.filterStaffIds
        prepareRosterPrefillTimesheetForm rosterSlotId selectedStaffFilterId False
            >>= respondWithRosterPrefillTimesheetForm selectedStaffFilterId

    action currentAction@CreateTimesheetEntryFromRosterShiftAction { rosterSlotId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        state <- requireTimesheetSurfaceState parseCreateTimesheetEntryFromRosterShiftState
        context <- requireTimesheetSurfaceContext state
        createRosterPrefillTimesheetEntry context rosterSlotId >>= respondWithTimesheetRosterPrefillOutcome context

    action currentAction@EditTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisFormAction do
        timesheetEntry <- fetchEditableTimesheetEntry timesheetEntryId
        let workedOn = timesheetEntryOperationalDate timesheetEntry
        filters <- canonicalTimesheetFilters workedOn timesheetFiltersFromRequest
        let selectedStaffFilterId = listToMaybe filters.filterStaffIds
        prepareEditTimesheetForm selectedStaffFilterId timesheetEntry >>= respondWithEditTimesheetForm

    action currentAction@UpdateTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        existingEntry <- fetchEditableTimesheetEntry timesheetEntryId
        context <- requireTimesheetMutationContext
        editOrdinaryTimesheetEntry context existingEntry >>= respondWithTimesheetEditOutcome context

    action currentAction@ShowTimesheetEntryDeleteConfirmationAction { timesheetEntryId } = runBepis currentAction BepisFormAction do
        ensureVenueWritable
        case parseAppShellActionParams @OpenTimesheetDeleteConfirmationDialog of
            Left errors -> do
                reportTimesheetSurfaceRequestErrors errors
                redirectToPath (timesheetWindowUrlWithFilters (param @Day "anchorDate") timesheetFiltersFromRequest)
            Right _ -> do
                timesheetEntry <- fetchEditableTimesheetEntry timesheetEntryId
                context <- requireTimesheetMutationContext
                respondHtml $
                    renderTimesheetDeleteConfirmation
                        timesheetEntry
                        (param @Int "rosterCalendarRevision")
                        context.timesheetFilters

    action currentAction@DeleteTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        timesheetEntry <- fetchEditableTimesheetEntry timesheetEntryId
        context <- requireTimesheetMutationContext
        result <- deleteTimesheetEntryMutation context.timesheetScope timesheetEntry >>= requireTimesheetCalendarResult
        respondWithTimesheetCompletion context result "Timesheet entry removed" True

    action currentAction@ApproveTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisMutationAction do
        ensureManagerModeAccess
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        accessDeniedUnless (isNothing timesheetEntry.deletedAt)
        state <- requireTimesheetSurfaceState parseApproveTimesheetEntryState
        context <- requireTimesheetSurfaceContext state
        reviewTimesheetEntry context ApproveTimesheet timesheetEntry >>= respondWithTimesheetReviewOutcome context

    action currentAction@UnapproveTimesheetEntryAction { timesheetEntryId } = runBepis currentAction BepisPageAction do
        ensureManagerModeAccess
        ensureVenueWritable
        timesheetEntry <- fetch timesheetEntryId
        ensureRecordInCurrentVenue timesheetEntry.venueId
        accessDeniedUnless (isNothing timesheetEntry.deletedAt)
        state <- requireTimesheetSurfaceState parseUnapproveTimesheetEntryState
        context <- requireTimesheetSurfaceContext state
        reviewTimesheetEntry context UnapproveTimesheet timesheetEntry >>= respondWithTimesheetReviewOutcome context
