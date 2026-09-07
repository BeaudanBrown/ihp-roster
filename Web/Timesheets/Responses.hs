module Web.Timesheets.Responses
    ( requireTimesheetSurfaceContext
    , respondWithSuggestedTimesheetForm
    , respondWithTimesheetSuggestionOutcome
    , respondWithTimesheetReviewOutcome
    , requireTimesheetCalendarResult
    , requireCurrentTimesheetCalendar
    , requireCurrentTimesheetMutationCalendar
    , requireCurrentTimesheetCalendarValues
    , requireTimesheetMutationContext
    , markStaleTimesheetCalendarResponseForRefresh
    , respondWithNewTimesheetForm
    , respondWithEditTimesheetForm
    , respondWithTimesheetCreateOutcome
    , respondWithTimesheetEditOutcome
    , respondWithTimesheetCompletion
    , respondWithTimesheetMutationUpdate
    , respondWithTimesheetPreferenceUpdate
    , respondWithTimesheetFragment
    , respondWithTimesheetWeekView
    , renderTimesheetWindowPage
    ) where

import Application.Error.Types (appErrorSafeMessage)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceMountedFragment,
                                                            mountedFragmentKey)
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Live as SurfaceLive
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh,
                                      setActorLocalFragmentsRefresh)
import Application.Helper.Profiling
import Application.Helper.SurfaceResource (LiveMutationResult (..),
                                           SurfaceResourceValue)
import Application.Helper.View (ToastOverlayPosition (..),
                                renderDialogOverlayClearOob, renderToastOob,
                                successToast)
import Application.Helper.View.Timesheets (TimesheetFormInputs)
import Data.List (nub)
import qualified Data.Set as Set
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day, addDays)
import Network.HTTP.Types.Status (status409)
import qualified Network.Wai as Wai
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.Timesheets.EntryWorkflow
import Web.Timesheets.Filters (TimesheetViewFilters (..))
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue,
                                       timesheetWeekScopeForAnchor,
                                       timesheetsCandidateMountedFragments,
                                       timesheetsMountStateForFilters,
                                       timesheetsSurfaceFragmentKeys,
                                       timesheetsSurfaceScope)
import Web.Timesheets.Paths (timesheetWindowUrl, timesheetWindowUrlWithFilters)
import Web.Timesheets.Projection
import Web.Timesheets.Validation (TimesheetCalendarConflict (..))
import Web.View.Timesheets.Edit
import Web.View.Timesheets.Index
import Web.View.Timesheets.New
import Web.View.Timesheets.SuggestedNew

requireTimesheetCalendarResult :: (?context :: ControllerContext, ?request :: Request) => Either TimesheetCalendarConflict value -> IO value
requireTimesheetCalendarResult = \case
    Right value -> pure value
    Left TimesheetCalendarChanged ->
        if isHtmxRequest
            then respondTimesheetCalendarRefresh
            else buildAccessDeniedResponse >>= respondAndStop

respondTimesheetCalendarRefresh :: IO value
respondTimesheetCalendarRefresh =
    respondAndStop (Wai.responseLBS status409 [("Content-Type", "text/plain"), ("HX-Refresh", "true")]
        "The roster calendar changed. Review the refreshed window and try again.")

markStaleTimesheetCalendarResponseForRefresh :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO ()
markStaleTimesheetCalendarResponseForRefresh =
    when isHtmxRequest $
        forM_ (paramOrNothing @Int "rosterCalendarRevision") \expectedRevision -> do
            venueConfig <- fetchVenueConfig
            when (expectedRevision /= venueConfig.rosterCalendarRevision) respondTimesheetCalendarRefresh

requireCurrentTimesheetCalendar :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetSurfaceRequestState -> IO TimesheetWeekScopeValue
requireCurrentTimesheetCalendar state =
    requireCurrentTimesheetCalendarValues state.surfaceRequestAnchorDate state.surfaceRequestCalendarRevision

requireCurrentTimesheetMutationCalendar :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO TimesheetWeekScopeValue
requireCurrentTimesheetMutationCalendar =
    requireCurrentTimesheetCalendarValues (param @Day "anchorDate") (param @Int "rosterCalendarRevision")

requireCurrentTimesheetCalendarValues :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Day -> Int -> IO TimesheetWeekScopeValue
requireCurrentTimesheetCalendarValues anchorDate expectedRevision = do
    venueConfig <- fetchVenueConfig
    when (venueConfig.rosterCalendarRevision /= expectedRevision) do
        setErrorMessage "The roster calendar changed. Review the refreshed window and try again."
        redirectToPath (timesheetWindowUrl anchorDate timesheetFiltersFromRequest.filterStaffId)
    pure (timesheetWeekScopeForAnchor venueConfig anchorDate)

requireTimesheetMutationContext :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO TimesheetRequestContext
requireTimesheetMutationContext = do
    timesheetScope <- requireCurrentTimesheetMutationCalendar
    timesheetFilters <- canonicalTimesheetFilters timesheetFiltersFromRequest
    pure TimesheetRequestContext { .. }

requireTimesheetSurfaceContext :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetSurfaceRequestState -> IO TimesheetRequestContext
requireTimesheetSurfaceContext state = do
    timesheetScope <- requireCurrentTimesheetCalendar state
    timesheetFilters <- canonicalTimesheetFilters (TimesheetViewFilters state.surfaceRequestStaffFilterId state.surfaceRequestRosterGroupFilterId)
    pure TimesheetRequestContext { .. }

respondWithSuggestedTimesheetForm :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Maybe UUID -> TimesheetSuggestionFormOutcome -> IO ()
respondWithSuggestedTimesheetForm selectedStaffFilterId = \case
    SuggestedTimesheetMissing -> do
        windowStart <- windowStartFromParamOrCurrent
        setErrorMessage "That rostered shift is no longer available as a timesheet suggestion."
        redirectToPath (timesheetWindowUrl windowStart selectedStaffFilterId)
    SuggestedTimesheetCanonicalRedirect path -> redirectToPath path
    SuggestedTimesheetTimingUnavailable workedOn -> respondWithNewTimesheetForm workedOn selectedStaffFilterId (Left TimesheetTimingUnavailable)
    SuggestedTimesheetForm model -> respondSuggestedTimesheetDialog model

respondSuggestedTimesheetDialog :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => SuggestedTimesheetRenderModel -> IO ()
respondSuggestedTimesheetDialog suggestedTimesheetRenderModel =
    if isHtmxRequest
        then respondHtml (renderSuggestedTimesheetDialog suggestedTimesheetRenderModel)
        else render SuggestedNewView { .. }

respondWithTimesheetSuggestionOutcome :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => TimesheetRequestContext -> TimesheetSuggestionOutcome -> IO ()
respondWithTimesheetSuggestionOutcome context = \case
    SuggestionUnavailable -> reject "That rostered shift is no longer available as a timesheet suggestion."
    SuggestionTimingUnavailable -> respondWithNewTimesheetForm context.timesheetScope.timesheetWindowStart context.timesheetFilters.filterStaffId (Left TimesheetTimingUnavailable)
    SuggestionInvalid model -> respondSuggestedTimesheetDialog model
    SuggestionAccessDenied -> buildAccessDeniedResponse >>= respondAndStop
    SuggestionCalendarConflict conflict -> requireTimesheetCalendarResult (Left conflict)
    SuggestionChanged intent -> reject case intent of
        CreateSuggestedTimesheet -> "That rostered shift changed before the timesheet entry was created. Review the current suggestion and try again."
        ApproveSuggestedTimesheet -> "That rostered shift changed before the timesheet entry was approved. Review the current suggestion and try again."
    SuggestionApprovalFailed failure -> reject (appErrorSafeMessage failure)
    SuggestionCompleted intent _ result ->
        respondWithTimesheetCompletion context result (case intent of
            CreateSuggestedTimesheet  -> "Rostered timesheet entry created"
            ApproveSuggestedTimesheet -> "Rostered timesheet entry approved") True
  where
    reject message = do
        setErrorMessage message
        redirectToPath (timesheetWindowUrl context.timesheetScope.timesheetWindowStart context.timesheetFilters.filterStaffId)

respondWithTimesheetReviewOutcome :: (?context :: ControllerContext, ?request :: Request) => TimesheetRequestContext -> TimesheetReviewOutcome -> IO ()
respondWithTimesheetReviewOutcome context = \case
    TimesheetReviewTimingInvalid -> respondAndStop (Wai.responseLBS status409 [("Content-Type", "text/plain")] "Repair the Timesheet timing before approval.")
    TimesheetReviewFailed failure -> do
        setErrorMessage (appErrorSafeMessage failure)
        redirectToPath (timesheetWindowUrl context.timesheetScope.timesheetWindowStart context.timesheetFilters.filterStaffId)
    TimesheetReviewCalendarConflict conflict -> requireTimesheetCalendarResult (Left conflict)
    TimesheetReviewCompleted intent result ->
        respondWithTimesheetCompletion context result (case intent of
            ApproveTimesheet   -> "Timesheet entry approved"
            UnapproveTimesheet -> "Timesheet entry unapproved") False

respondWithNewTimesheetForm :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Day -> Maybe UUID -> Either TimesheetCreationBlocker NewTimesheetRenderModel -> IO ()
respondWithNewTimesheetForm windowStart selectedStaffFilterId = \case
    Left blocker -> do
        setErrorMessage case blocker of
            NoTimesheetStaff -> "No staff record found. Contact an administrator."
            NoTimesheetShiftTypes -> "Add at least one shift type before creating a timesheet entry."
            NoTimesheetDay -> "Please choose a day before creating a timesheet entry."
            TimesheetTimingUnavailable -> "Timesheet creation is unavailable until the venue timezone configuration is repaired."
        redirectToPath (timesheetWindowUrl windowStart selectedStaffFilterId)
    Right newTimesheetRenderModel ->
        if isHtmxRequest
            then respondHtml (renderNewTimesheetDialog newTimesheetRenderModel)
            else render NewView { .. }

respondWithEditTimesheetForm :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => TimesheetFormInputs -> IO ()
respondWithEditTimesheetForm timesheetFormInputs =
    if isHtmxRequest
        then respondHtml (renderEditTimesheetDialog timesheetFormInputs)
        else render EditView { .. }

respondWithTimesheetCompletion :: (?context :: ControllerContext, ?request :: Request) => TimesheetRequestContext -> LiveMutationResult TimesheetEntry -> Text -> Bool -> IO ()
respondWithTimesheetCompletion context result message closeDialog =
    if isHtmxRequest
        then respondWithTimesheetMutationUpdate context.timesheetScope (timesheetsMountStateForFilters context.timesheetFilters) result.liveMutationTouchedResources message closeDialog
        else do
            setSuccessMessage message
            redirectToPath (timesheetWindowUrl context.timesheetScope.timesheetWindowStart context.timesheetFilters.filterStaffId)

respondWithTimesheetCreateOutcome :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => TimesheetRequestContext -> TimesheetCreateOutcome -> IO ()
respondWithTimesheetCreateOutcome context = \case
    TimesheetCreateBlocked blocker -> renderForm (Left blocker)
    TimesheetCreateInvalid form -> renderForm (Right form)
    TimesheetCreateCompleted outcome -> do
        result <- requireTimesheetCalendarResult outcome
        respondWithTimesheetCompletion context result "Timesheet entry created" True
  where
    renderForm = respondWithNewTimesheetForm context.timesheetScope.timesheetWindowStart context.timesheetFilters.filterStaffId

respondWithTimesheetEditOutcome :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => TimesheetRequestContext -> TimesheetEditOutcome -> IO ()
respondWithTimesheetEditOutcome context = \case
    TimesheetEditInvalid form -> respondWithEditTimesheetForm form
    TimesheetEditCompleted outcome -> do
        (approvalReset, result) <- requireTimesheetCalendarResult outcome
        let message = if approvalReset then "Timesheet entry updated (approval reset)" else "Timesheet entry updated"
        respondWithTimesheetCompletion context result message True

respondWithTimesheetFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> TimesheetProjectionFragment -> IO ()
respondWithTimesheetFragment requestKey fragment =
    profileActionSpan "timesheets.fragment.respond" do
        maybeHtml <- profileActionSpan "timesheets.fragment.render" (renderTimesheetProjectionFragment requestKey fragment)
        when (isNothing maybeHtml) do
            TextIO.putStrLn ("timesheet_projection_miss: request=" <> tshow requestKey <> " fragment=" <> tshow fragment)
        respondHtmlProfiled (fromMaybe mempty maybeHtml)

respondWithTimesheetActorFragments :: (?context :: ControllerContext, ?request :: Request) => TimesheetWeekScopeValue -> TimesheetsMountStateValue -> [TimesheetProjectionFragment] -> Blaze.Html -> IO ()
respondWithTimesheetActorFragments scope mountState fragments extraHtml = do
    let selectedMountedFragments = selectTimesheetMountedFragments scope (normalizeTimesheetFragments fragments) (timesheetsCandidateMountedFragments scope mountState)
    setActorLocalFragmentsRefresh (timesheetsSurfaceScope scope) (timesheetsSurfaceFragmentKeys selectedMountedFragments)
    respondHtmlProfiled extraHtml

respondWithTimesheetResourceInvalidation :: (?context :: ControllerContext, ?request :: Request) => TimesheetWeekScopeValue -> TimesheetsMountStateValue -> Set.Set SurfaceResourceValue -> Blaze.Html -> IO ()
respondWithTimesheetResourceInvalidation scope mountState touchedResources extraHtml = do
    setActorLiveResourcesRefresh (timesheetsSurfaceScope scope) touchedResources (timesheetsCandidateMountedFragments scope mountState)
    respondHtmlProfiled extraHtml

selectTimesheetMountedFragments :: TimesheetWeekScopeValue -> [TimesheetProjectionFragment] -> [FrontendSurfaceMountedFragment] -> [FrontendSurfaceMountedFragment]
selectTimesheetMountedFragments scope fragments mountedFragments =
    filter (\mountedFragment -> any (matchesFragment mountedFragment) fragments) mountedFragments
  where
    matchesFragment mountedFragment = \case
        TimesheetProjectionToolbar ->
            isJust (SurfaceLive.matchTimesheetToolbarLiveFragment mountedFragment.mountedFragmentKey)
        TimesheetProjectionDayColumns ->
            isJust (SurfaceLive.matchTimesheetDayColumnsLiveFragment mountedFragment.mountedFragmentKey)
        TimesheetProjectionSidePanel ->
            isJust (SurfaceLive.matchTimesheetSidePanelContentLiveFragment mountedFragment.mountedFragmentKey)
        TimesheetProjectionDaySection dayOffset ->
            SurfaceLive.matchTimesheetDaySectionLiveFragment mountedFragment.mountedFragmentKey
                == Just (addDays (toInteger dayOffset) scope.timesheetWindowStart, ())

normalizeTimesheetFragments :: [TimesheetProjectionFragment] -> [TimesheetProjectionFragment]
normalizeTimesheetFragments fragments =
    if TimesheetProjectionDayColumns `elem` uniqueFragments
        then filter (not . isDaySectionFragment) uniqueFragments
        else uniqueFragments
    where
        uniqueFragments = nub fragments
        isDaySectionFragment = \case
            TimesheetProjectionDaySection _ -> True
            _                               -> False

respondWithTimesheetPreferenceUpdate :: (?context :: ControllerContext, ?request :: Request) => TimesheetWeekScopeValue -> TimesheetsMountStateValue -> IO ()
respondWithTimesheetPreferenceUpdate scope mountState =
    respondWithTimesheetActorFragments
        scope
        mountState
        [TimesheetProjectionToolbar, TimesheetProjectionDayColumns, TimesheetProjectionSidePanel]
        mempty

respondWithTimesheetMutationUpdate :: (?context :: ControllerContext, ?request :: Request) => TimesheetWeekScopeValue -> TimesheetsMountStateValue -> Set.Set SurfaceResourceValue -> Text -> Bool -> IO ()
respondWithTimesheetMutationUpdate scope mountState touchedResources successMessage closeDialog = do
    respondWithTimesheetResourceInvalidation
        scope
        mountState
        touchedResources
        ( when closeDialog renderDialogOverlayClearOob
            <> renderToastOob ToastBottomCenter (successToast successMessage)
        )

renderTimesheetWindowPage :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Day -> TimesheetViewFilters -> IO ()
renderTimesheetWindowPage windowStart filters =
    profileActionSpan "timesheets.page.render" do
        let requestKey = TimesheetProjectionRequest windowStart (addDays 7 windowStart) filters.filterStaffId filters.filterRosterGroupId
        projection <- profileActionSpan "timesheets.page.fetch_read_model" (fetchTimesheetWeekProjection requestKey)
        profileActionSpan "timesheets.page.respond" (respondWithTimesheetWeekView (timesheetIndexView projection))

respondWithTimesheetWeekView :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IndexView -> IO ()
respondWithTimesheetWeekView indexView =
    if isHtmxRequest
        then do
            setHtmxPushUrl (timesheetWindowUrlWithFilters indexView.weekStartDate indexView.viewFilters)
            profileActionSpan "timesheets.page.render_response" (respondHtmlProfiled (renderTimesheetWeekShell indexView))
        else profileActionSpan "timesheets.page.render_response" (renderProfiled indexView)
