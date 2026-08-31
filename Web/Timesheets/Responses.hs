module Web.Timesheets.Responses
    ( respondWithTimesheetMutationUpdate
    , respondWithTimesheetPreferenceUpdate
    , respondWithTimesheetFragment
    , respondWithTimesheetWeekView
    , renderTimesheetWindowPage
    ) where

import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceMountedFragment,
                                                            mountedFragmentKey)
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Live as SurfaceLive
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh,
                                      setActorLocalFragmentsRefresh)
import Application.Helper.Profiling
import Application.Helper.SurfaceResource (SurfaceResourceValue)
import Application.Helper.View (ToastOverlayPosition (..),
                                renderDialogOverlayClearOob, renderToastOob,
                                successToast)
import Data.List (nub)
import qualified Data.Set as Set
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day, addDays)
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.Timesheets.Filters (TimesheetViewFilters (..))
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue (..),
                                       timesheetsCandidateMountedFragments,
                                       timesheetsSurfaceFragmentKeys,
                                       timesheetsSurfaceScope)
import Web.Timesheets.Paths (timesheetWindowUrlWithFilters)
import Web.Timesheets.Projection
import Web.View.Timesheets.Index

respondWithTimesheetFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> TimesheetProjectionFragment -> IO ()
respondWithTimesheetFragment requestKey fragment =
    profileActionSpan "timesheets.fragment.respond" do
        maybeHtml <- profileActionSpan "timesheets.fragment.render" (renderTimesheetProjectionFragment requestKey fragment)
        when (isNothing maybeHtml) do
            TextIO.putStrLn ("timesheet_projection_miss: request=" <> tshow requestKey <> " fragment=" <> tshow fragment)
        respondHtmlProfiled (fromMaybe mempty maybeHtml)

respondWithTimesheetActorFragments :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> [TimesheetProjectionFragment] -> Blaze.Html -> IO ()
respondWithTimesheetActorFragments requestKey fragments extraHtml = do
    projection <- fetchTimesheetWeekProjection requestKey
    let scope = timesheetScopeFromProjection projection
    let mountState = TimesheetsMountStateValue requestKey.projectionStaffFilterId requestKey.projectionRosterGroupFilterId
    let selectedMountedFragments = selectTimesheetMountedFragments projection (normalizeTimesheetFragments fragments) (timesheetsCandidateMountedFragments scope mountState)
    setActorLocalFragmentsRefresh (timesheetsSurfaceScope scope) (timesheetsSurfaceFragmentKeys selectedMountedFragments)
    respondHtmlProfiled extraHtml

respondWithTimesheetResourceInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> Set.Set SurfaceResourceValue -> Blaze.Html -> IO ()
respondWithTimesheetResourceInvalidation requestKey touchedResources extraHtml = do
    projection <- fetchTimesheetWeekProjection requestKey
    let scope = timesheetScopeFromProjection projection
    let mountState = TimesheetsMountStateValue requestKey.projectionStaffFilterId requestKey.projectionRosterGroupFilterId
    setActorLiveResourcesRefresh (timesheetsSurfaceScope scope) touchedResources (timesheetsCandidateMountedFragments scope mountState)
    respondHtmlProfiled extraHtml

selectTimesheetMountedFragments :: TimesheetWeekProjection -> [TimesheetProjectionFragment] -> [FrontendSurfaceMountedFragment] -> [FrontendSurfaceMountedFragment]
selectTimesheetMountedFragments projection fragments mountedFragments =
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
                == Just (addDays (toInteger dayOffset) projection.timesheetWeekStartDate, ())

timesheetScopeFromProjection :: (?context :: ControllerContext) => TimesheetWeekProjection -> TimesheetWeekScopeValue
timesheetScopeFromProjection projection =
    TimesheetWeekScopeValue
        { timesheetWeekVenueId = unpackId currentVenueId
        , timesheetWindowStart = projection.timesheetWeekStartDate
        , timesheetWindowEnd = addDays 1 projection.timesheetWeekEndDate
        , timesheetCalendarRevision = projection.timesheetCalendarRevision
        }

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

respondWithTimesheetPreferenceUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetWeekScopeValue -> Maybe UUID.UUID -> IO ()
respondWithTimesheetPreferenceUpdate scope staffFilterId = do
    filters <- canonicalTimesheetFilters timesheetFiltersFromRequest
    respondWithTimesheetActorFragments
        (timesheetProjectionRequestForScope scope staffFilterId)
            { projectionRosterGroupFilterId = filters.filterRosterGroupId }
        [TimesheetProjectionToolbar, TimesheetProjectionDayColumns, TimesheetProjectionSidePanel]
        mempty

respondWithTimesheetMutationUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetWeekScopeValue -> Maybe UUID.UUID -> Set.Set SurfaceResourceValue -> Text -> Bool -> IO ()
respondWithTimesheetMutationUpdate scope staffFilterId touchedResources successMessage closeDialog = do
    respondWithTimesheetResourceInvalidation
        (timesheetProjectionRequestForScope scope staffFilterId)
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

timesheetProjectionRequestForScope :: TimesheetWeekScopeValue -> Maybe UUID.UUID -> TimesheetProjectionRequest
timesheetProjectionRequestForScope scope staffFilterId =
    TimesheetProjectionRequest
        { projectionWindowStart = scope.timesheetWindowStart
        , projectionWindowEnd = scope.timesheetWindowEnd
        , projectionStaffFilterId = staffFilterId
        , projectionRosterGroupFilterId = Nothing
        }

respondWithTimesheetWeekView :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IndexView -> IO ()
respondWithTimesheetWeekView indexView =
    if isHtmxRequest
        then do
            setHtmxPushUrl (timesheetWindowUrlWithFilters indexView.weekStartDate indexView.viewFilters)
            profileActionSpan "timesheets.page.render_response" (respondHtmlProfiled (renderTimesheetWeekShell indexView))
        else profileActionSpan "timesheets.page.render_response" (renderProfiled indexView)
