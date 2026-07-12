module Web.Timesheets.Responses
    ( renderTimesheetWeekPage
    , respondWithTimesheetMutationUpdate
    , respondWithTimesheetFragment
    , respondWithTimesheetFragments
    , respondWithTimesheetDaySectionUpdate
    , respondWithTimesheetWeekFragmentsUpdate
    , respondWithTimesheetWeekView
    ) where

import Application.Helper.FrontendContract.Surface.FragmentRender (FragmentRenderMode (..))
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceMountedFragment (..))
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

respondWithTimesheetFragments :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> [TimesheetProjectionFragment] -> Blaze.Html -> IO ()
respondWithTimesheetFragments requestKey fragments extraHtml = do
    projection <- fetchTimesheetWeekProjection requestKey
    respondHtmlProfiled $
        mconcat (mapMaybe (renderTimesheetProjectionFragmentFromProjection (FragmentOob outerHtmlOobSwap) projection) (normalizeTimesheetFragments fragments)) <> extraHtml

respondWithTimesheetActorFragments :: (?context :: ControllerContext, ?request :: Request) => TimesheetProjectionRequest -> [TimesheetProjectionFragment] -> Blaze.Html -> IO ()
respondWithTimesheetActorFragments requestKey fragments extraHtml = do
    let scope = TimesheetWeekScopeValue (unpackId currentVenueId) requestKey.projectionWeekOffset
    let mountState = TimesheetsMountStateValue requestKey.projectionShowApproved requestKey.projectionShowAllStaff requestKey.projectionStaffFilterId
    let selectedMountedFragments = selectTimesheetMountedFragments requestKey (normalizeTimesheetFragments fragments) (timesheetsCandidateMountedFragments scope mountState)
    setActorLocalFragmentsRefresh (timesheetsSurfaceScope scope) (timesheetsSurfaceFragmentKeys selectedMountedFragments)
    respondHtmlProfiled extraHtml

respondWithTimesheetResourceInvalidation :: (?context :: ControllerContext, ?request :: Request) => TimesheetProjectionRequest -> Set.Set SurfaceResourceValue -> Blaze.Html -> IO ()
respondWithTimesheetResourceInvalidation requestKey touchedResources extraHtml = do
    let scope = TimesheetWeekScopeValue (unpackId currentVenueId) requestKey.projectionWeekOffset
    let mountState = TimesheetsMountStateValue requestKey.projectionShowApproved requestKey.projectionShowAllStaff requestKey.projectionStaffFilterId
    setActorLiveResourcesRefresh (timesheetsSurfaceScope scope) touchedResources (timesheetsCandidateMountedFragments scope mountState)
    respondHtmlProfiled extraHtml

selectTimesheetMountedFragments :: TimesheetProjectionRequest -> [TimesheetProjectionFragment] -> [FrontendSurfaceMountedFragment] -> [FrontendSurfaceMountedFragment]
selectTimesheetMountedFragments _ fragments mountedFragments =
    filter (\mountedFragment -> mountedFragment.mountedFragmentTargetId `elem` targetIds) mountedFragments
    where
        targetIds = mapMaybe fragmentTargetId fragments
        fragmentTargetId = \case
            TimesheetProjectionToolbar -> Just timesheetWeekToolbarId
            TimesheetProjectionDayColumns -> Just timesheetDayColumnsId
            TimesheetProjectionDaySection dayOffset -> Just (timesheetDaySectionDomId dayOffset)

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

respondWithTimesheetWeekFragmentsUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Bool -> Bool -> Maybe UUID.UUID -> IO ()
respondWithTimesheetWeekFragmentsUpdate weekOffset showApproved showAllStaff staffFilterId =
    profileActionSpan "timesheets.page.fragments_update" do
        let requestKey = TimesheetProjectionRequest weekOffset showApproved showAllStaff staffFilterId
        setHtmxPushUrl (timesheetWeekUrl weekOffset showApproved showAllStaff staffFilterId)
        respondWithTimesheetFragments requestKey [TimesheetProjectionToolbar, TimesheetProjectionDayColumns] mempty

respondWithTimesheetDaySectionUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Day -> Bool -> Bool -> Maybe UUID.UUID -> Text -> Bool -> IO ()
respondWithTimesheetDaySectionUpdate weekOffset workedOn showApproved showAllStaff staffFilterId successMessage closeDialog = do
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
        requestKey = TimesheetProjectionRequest weekOffset showApproved showAllStaff staffFilterId

respondWithTimesheetMutationUpdate :: (?context :: ControllerContext, ?request :: Request) => Int -> Bool -> Bool -> Maybe UUID.UUID -> Set.Set SurfaceResourceValue -> Text -> Bool -> IO ()
respondWithTimesheetMutationUpdate weekOffset showApproved showAllStaff staffFilterId touchedResources successMessage closeDialog =
    respondWithTimesheetResourceInvalidation
        requestKey
        touchedResources
        ( when closeDialog [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            <> renderToastOob ToastBottomCenter (successToast successMessage)
        )
  where
    requestKey = TimesheetProjectionRequest weekOffset showApproved showAllStaff staffFilterId

renderTimesheetWeekPage :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Int -> Bool -> Bool -> Maybe UUID.UUID -> IO ()
renderTimesheetWeekPage weekOffset showApproved showAllStaff staffFilterId =
    profileActionSpan "timesheets.page.render" do
        projection <- profileActionSpan "timesheets.page.fetch_read_model" (fetchTimesheetWeekProjection requestKey)
        profileActionSpan "timesheets.page.respond" (respondWithTimesheetWeekView (timesheetIndexView projection))
    where
        requestKey = TimesheetProjectionRequest weekOffset showApproved showAllStaff staffFilterId

respondWithTimesheetWeekView :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IndexView -> IO ()
respondWithTimesheetWeekView indexView =
    if isHtmxRequest
        then respondWithTimesheetWeekFragmentsUpdate indexView.weekOffset indexView.showApproved indexView.showAllStaff indexView.selectedStaffFilterId
        else profileActionSpan "timesheets.page.render_response" (renderProfiled indexView)
