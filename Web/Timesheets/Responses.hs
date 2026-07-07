module Web.Timesheets.Responses
    ( renderTimesheetWeekPage
    , respondWithTimesheetDateMoveUpdate
    , respondWithTimesheetFragment
    , respondWithTimesheetFragments
    , respondWithTimesheetDaySectionUpdate
    , respondWithTimesheetWeekFragmentsUpdate
    , respondWithTimesheetWeekView
    ) where

import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceMountedFragment (..))
import Application.Helper.LiveUpdate (setActorLiveFragmentsRefresh)
import Application.Helper.Profiling
import Application.Helper.View (ToastOverlayPosition (..), dialogOverlayMountId,
                                renderToastOob, successToast)
import Application.Helper.View.Oob (outerHtmlOobSwap)
import Data.List (nub)
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day, addDays)
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.Timesheets.FrontendSurface (TimesheetWeekScopeValue (..),
                                       TimesheetsMountStateValue (..),
                                       timesheetsCandidateMountedFragments,
                                       timesheetsSurfaceScope,
                                       timesheetsSurfaceWireFragments)
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
        mconcat (mapMaybe (renderTimesheetProjectionFragmentFromProjection (TimesheetFragmentOob outerHtmlOobSwap) projection) (normalizeTimesheetFragments fragments)) <> extraHtml

respondWithTimesheetActorInvalidation :: (?context :: ControllerContext, ?request :: Request) => TimesheetProjectionRequest -> [TimesheetProjectionFragment] -> Blaze.Html -> IO ()
respondWithTimesheetActorInvalidation requestKey fragments extraHtml = do
    let scope = TimesheetWeekScopeValue (unpackId currentVenueId) requestKey.projectionWeekOffset
    let mountState = TimesheetsMountStateValue requestKey.projectionShowApproved requestKey.projectionShowAllStaff requestKey.projectionStaffFilterId
    let selectedMountedFragments = selectTimesheetMountedFragments requestKey (normalizeTimesheetFragments fragments) (timesheetsCandidateMountedFragments scope mountState)
    setActorLiveFragmentsRefresh (timesheetsSurfaceScope scope) (timesheetsSurfaceWireFragments selectedMountedFragments)
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
    respondWithTimesheetActorInvalidation
        requestKey
        [TimesheetProjectionDaySection dayOffset]
        ( when closeDialog [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            <> renderToastOob ToastBottomCenter (successToast successMessage)
        )
    where
        requestKey = TimesheetProjectionRequest weekOffset showApproved showAllStaff staffFilterId

respondWithTimesheetDateMoveUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Day -> Day -> Bool -> Bool -> Maybe UUID.UUID -> Text -> IO ()
respondWithTimesheetDateMoveUpdate weekOffset oldWorkedOn newWorkedOn showApproved showAllStaff staffFilterId successMessage = do
    venueConfig <- fetchVenueConfig
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    let weekEndDate = addDays 6 weekStartDate
    let daysInVisibleWeek = filter (\day -> day >= weekStartDate && day <= weekEndDate) (nub [oldWorkedOn, newWorkedOn])
    let fragments = map (TimesheetProjectionDaySection . timesheetDayOffset weekStartDate) daysInVisibleWeek
    respondWithTimesheetActorInvalidation
        requestKey
        fragments
        ( [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
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
