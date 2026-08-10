module Web.Timesheets.Responses
    ( renderTimesheetWeekPage
    , respondWithTimesheetMutationUpdate
    , respondWithTimesheetPreferenceUpdate
    , respondWithTimesheetFragment
    , respondWithTimesheetDaySectionUpdate
    , respondWithTimesheetWeekView
    ) where

import Application.Helper.FrontendContract.Surface.FragmentRender (FragmentRenderMode (..))
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceMountedFragment,
                                                            mountedFragmentKey)
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Live as SurfaceLive
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh,
                                      setActorLocalFragmentsRefresh)
import Application.Helper.Profiling
import Application.Helper.SurfaceResource (SurfaceResourceValue)
import Application.Helper.View (ToastOverlayPosition (..), dialogOverlayMountId,
                                renderToastOob, successToast)
import Data.List (nub)
import qualified Data.Set as Set
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day)
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue (..),
                                       timesheetsCandidateMountedFragments,
                                       timesheetsSurfaceFragmentKeys,
                                       timesheetsSurfaceScope)
import Web.Timesheets.Paths (timesheetWeekUrl)
import Web.Timesheets.Projection
import Web.View.Timesheets.Index

respondWithTimesheetFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> TimesheetProjectionFragment -> IO ()
respondWithTimesheetFragment requestKey fragment =
    profileActionSpan "timesheets.fragment.respond" do
        maybeHtml <- profileActionSpan "timesheets.fragment.render" (renderTimesheetProjectionFragment requestKey fragment)
        when (isNothing maybeHtml) do
            TextIO.putStrLn ("timesheet_projection_miss: request=" <> tshow requestKey <> " fragment=" <> tshow fragment)
        respondHtmlProfiled (fromMaybe mempty maybeHtml)

respondWithTimesheetActorFragments :: (?context :: ControllerContext, ?request :: Request) => TimesheetProjectionRequest -> [TimesheetProjectionFragment] -> Blaze.Html -> IO ()
respondWithTimesheetActorFragments requestKey fragments extraHtml = do
    let scope = TimesheetWeekScopeValue (unpackId currentVenueId) requestKey.projectionWeekOffset
    let mountState = TimesheetsMountStateValue requestKey.projectionStaffFilterId
    let selectedMountedFragments = selectTimesheetMountedFragments requestKey (normalizeTimesheetFragments fragments) (timesheetsCandidateMountedFragments scope mountState)
    setActorLocalFragmentsRefresh (timesheetsSurfaceScope scope) (timesheetsSurfaceFragmentKeys selectedMountedFragments)
    respondHtmlProfiled extraHtml

respondWithTimesheetResourceInvalidation :: (?context :: ControllerContext, ?request :: Request) => TimesheetProjectionRequest -> Set.Set SurfaceResourceValue -> Blaze.Html -> IO ()
respondWithTimesheetResourceInvalidation requestKey touchedResources extraHtml = do
    let scope = TimesheetWeekScopeValue (unpackId currentVenueId) requestKey.projectionWeekOffset
    let mountState = TimesheetsMountStateValue requestKey.projectionStaffFilterId
    setActorLiveResourcesRefresh (timesheetsSurfaceScope scope) touchedResources (timesheetsCandidateMountedFragments scope mountState)
    respondHtmlProfiled extraHtml

selectTimesheetMountedFragments :: TimesheetProjectionRequest -> [TimesheetProjectionFragment] -> [FrontendSurfaceMountedFragment] -> [FrontendSurfaceMountedFragment]
selectTimesheetMountedFragments _ fragments mountedFragments =
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
                == Just (dayOffset, ())

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

respondWithTimesheetPreferenceUpdate :: (?context :: ControllerContext, ?request :: Request) => Int -> Maybe UUID.UUID -> IO ()
respondWithTimesheetPreferenceUpdate weekOffset staffFilterId =
    respondWithTimesheetActorFragments
        (TimesheetProjectionRequest weekOffset staffFilterId)
        [TimesheetProjectionToolbar, TimesheetProjectionDayColumns, TimesheetProjectionSidePanel]
        mempty

respondWithTimesheetDaySectionUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Day -> Maybe UUID.UUID -> Text -> Bool -> IO ()
respondWithTimesheetDaySectionUpdate weekOffset workedOn staffFilterId successMessage closeDialog = do
    venueConfig <- fetchVenueConfig
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    let dayOffset = timesheetDayOffset weekStartDate workedOn
    respondWithTimesheetActorFragments
        requestKey
        [TimesheetProjectionDaySection dayOffset]
        ( when closeDialog [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            <> renderToastOob ToastBottomCenter (successToast successMessage)
        )
    where
        requestKey = TimesheetProjectionRequest weekOffset staffFilterId

respondWithTimesheetMutationUpdate :: (?context :: ControllerContext, ?request :: Request) => Int -> Maybe UUID.UUID -> Set.Set SurfaceResourceValue -> Text -> Bool -> IO ()
respondWithTimesheetMutationUpdate weekOffset staffFilterId touchedResources successMessage closeDialog =
    respondWithTimesheetResourceInvalidation
        requestKey
        touchedResources
        ( when closeDialog [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            <> renderToastOob ToastBottomCenter (successToast successMessage)
        )
  where
    requestKey = TimesheetProjectionRequest weekOffset staffFilterId

renderTimesheetWeekPage :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Int -> Maybe UUID.UUID -> IO ()
renderTimesheetWeekPage weekOffset staffFilterId =
    profileActionSpan "timesheets.page.render" do
        projection <- profileActionSpan "timesheets.page.fetch_read_model" (fetchTimesheetWeekProjection requestKey)
        profileActionSpan "timesheets.page.respond" (respondWithTimesheetWeekView (timesheetIndexView projection))
    where
        requestKey = TimesheetProjectionRequest weekOffset staffFilterId

respondWithTimesheetWeekView :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IndexView -> IO ()
respondWithTimesheetWeekView indexView =
    if isHtmxRequest
        then profileActionSpan "timesheets.page.render_shell_response" do
            setHtmxPushUrl (timesheetWeekUrl indexView.weekOffset indexView.selectedStaffFilterId)
            respondHtmlProfiled (renderTimesheetWeekShell indexView)
        else profileActionSpan "timesheets.page.render_response" (renderProfiled indexView)
