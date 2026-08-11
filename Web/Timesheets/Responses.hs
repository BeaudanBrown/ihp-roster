module Web.Timesheets.Responses
    ( renderTimesheetWeekPage
    , respondWithTimesheetMutationUpdate
    , respondWithTimesheetPreferenceUpdate
    , respondWithTimesheetFragment
    , respondWithTimesheetFragments
    , respondWithTimesheetDaySectionUpdate
    , respondWithTimesheetWindowFragmentsUpdate
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
import Application.Helper.View.Oob (outerHtmlOobSwap)
import Data.List (nub)
import qualified Data.Set as Set
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day, addDays)
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue (..),
                                       timesheetsCandidateMountedFragments,
                                       timesheetsSurfaceFragmentKeys,
                                       timesheetsSurfaceScope)
import Web.Timesheets.Paths (timesheetWindowUrl)
import Web.Timesheets.Projection
import Web.View.Timesheets.Index

respondWithTimesheetFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> TimesheetProjectionFragment -> IO ()
respondWithTimesheetFragment requestKey fragment =
    profileActionSpan "timesheets.fragment.respond" do
        maybeHtml <- profileActionSpan "timesheets.fragment.render" (renderTimesheetProjectionFragment requestKey fragment)
        when (isNothing maybeHtml) do
            TextIO.putStrLn ("timesheet_projection_miss: request=" <> tshow requestKey <> " fragment=" <> tshow fragment)
        respondHtmlProfiled (fromMaybe mempty maybeHtml)

respondWithTimesheetFragments :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> [TimesheetProjectionFragment] -> Blaze.Html -> IO ()
respondWithTimesheetFragments requestKey fragments extraHtml = do
    projection <- fetchTimesheetWeekProjection requestKey
    respondHtmlProfiled $
        mconcat (mapMaybe (renderTimesheetProjectionFragmentFromProjection (FragmentOob outerHtmlOobSwap) projection) (normalizeTimesheetFragments fragments)) <> extraHtml

respondWithTimesheetActorFragments :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> [TimesheetProjectionFragment] -> Blaze.Html -> IO ()
respondWithTimesheetActorFragments requestKey fragments extraHtml = do
    projection <- fetchTimesheetWeekProjection requestKey
    let scope = timesheetScopeFromProjection projection
    let mountState = TimesheetsMountStateValue requestKey.projectionStaffFilterId
    let selectedMountedFragments = selectTimesheetMountedFragments projection (normalizeTimesheetFragments fragments) (timesheetsCandidateMountedFragments scope mountState)
    setActorLocalFragmentsRefresh (timesheetsSurfaceScope scope) (timesheetsSurfaceFragmentKeys selectedMountedFragments)
    respondHtmlProfiled extraHtml

respondWithTimesheetResourceInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> Set.Set SurfaceResourceValue -> Blaze.Html -> IO ()
respondWithTimesheetResourceInvalidation requestKey touchedResources extraHtml = do
    projection <- fetchTimesheetWeekProjection requestKey
    let scope = timesheetScopeFromProjection projection
    let mountState = TimesheetsMountStateValue requestKey.projectionStaffFilterId
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

respondWithTimesheetWindowFragmentsUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Day -> Maybe UUID.UUID -> IO ()
respondWithTimesheetWindowFragmentsUpdate windowStart staffFilterId =
    profileActionSpan "timesheets.page.fragments_update" do
        let requestKey = timesheetProjectionRequestForWindow windowStart staffFilterId
        setHtmxPushUrl (timesheetWindowUrl windowStart staffFilterId)
        respondWithTimesheetFragments requestKey [TimesheetProjectionToolbar, TimesheetProjectionDayColumns, TimesheetProjectionSidePanel] mempty

respondWithTimesheetPreferenceUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Maybe UUID.UUID -> IO ()
respondWithTimesheetPreferenceUpdate weekOffset staffFilterId = do
    venueConfig <- fetchVenueConfig
    respondWithTimesheetActorFragments
        (timesheetProjectionRequestForOffset venueConfig weekOffset staffFilterId)
        [TimesheetProjectionToolbar, TimesheetProjectionDayColumns, TimesheetProjectionSidePanel]
        mempty

respondWithTimesheetDaySectionUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Day -> Maybe UUID.UUID -> Text -> Bool -> IO ()
respondWithTimesheetDaySectionUpdate weekOffset workedOn staffFilterId successMessage closeDialog = do
    venueConfig <- fetchVenueConfig
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    let dayOffset = timesheetDayOffset weekStartDate workedOn
    let requestKey = timesheetProjectionRequestForOffset venueConfig weekOffset staffFilterId
    respondWithTimesheetActorFragments
        requestKey
        [TimesheetProjectionDaySection dayOffset]
        ( when closeDialog [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            <> renderToastOob ToastBottomCenter (successToast successMessage)
        )

respondWithTimesheetMutationUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Maybe UUID.UUID -> Set.Set SurfaceResourceValue -> Text -> Bool -> IO ()
respondWithTimesheetMutationUpdate weekOffset staffFilterId touchedResources successMessage closeDialog = do
    venueConfig <- fetchVenueConfig
    respondWithTimesheetResourceInvalidation
        (timesheetProjectionRequestForOffset venueConfig weekOffset staffFilterId)
        touchedResources
        ( when closeDialog [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            <> renderToastOob ToastBottomCenter (successToast successMessage)
        )

renderTimesheetWeekPage :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Int -> Maybe UUID.UUID -> IO ()
renderTimesheetWeekPage weekOffset staffFilterId =
    profileActionSpan "timesheets.page.render" do
        venueConfig <- fetchVenueConfig
        let requestKey = timesheetProjectionRequestForOffset venueConfig weekOffset staffFilterId
        projection <- profileActionSpan "timesheets.page.fetch_read_model" (fetchTimesheetWeekProjection requestKey)
        profileActionSpan "timesheets.page.respond" (respondWithTimesheetWeekView (timesheetIndexView projection))

timesheetProjectionRequestForOffset :: VenueConfig -> Int -> Maybe UUID.UUID -> TimesheetProjectionRequest
timesheetProjectionRequestForOffset venueConfig weekOffset =
    timesheetProjectionRequestForWindow (venueWeekStartDate venueConfig weekOffset)

timesheetProjectionRequestForWindow :: Day -> Maybe UUID.UUID -> TimesheetProjectionRequest
timesheetProjectionRequestForWindow windowStart staffFilterId =
    TimesheetProjectionRequest
        { projectionWindowStart = windowStart
        , projectionWindowEnd = addDays 7 windowStart
        , projectionStaffFilterId = staffFilterId
        }

respondWithTimesheetWeekView :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IndexView -> IO ()
respondWithTimesheetWeekView indexView =
    if isHtmxRequest
        then respondWithTimesheetWindowFragmentsUpdate indexView.weekStartDate indexView.selectedStaffFilterId
        else profileActionSpan "timesheets.page.render_response" (renderProfiled indexView)
