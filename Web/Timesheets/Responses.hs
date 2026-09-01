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
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.Timesheets.Filters (TimesheetViewFilters (..))
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue,
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
