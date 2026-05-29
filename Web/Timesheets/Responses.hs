module Web.Timesheets.Responses
    ( renderTimesheetWeekPage
    , respondWithTimesheetDateMoveUpdate
    , respondWithTimesheetFragment
    , respondWithTimesheetFragments
    , respondWithTimesheetDaySectionUpdate
    , respondWithTimesheetWeekFragmentsUpdate
    , respondWithTimesheetWeekView
    ) where

import Application.Helper.Profiling
import Application.Helper.View (ToastOverlayPosition (..), dialogOverlayMountId,
                                renderToastOob, successToast)
import Data.List (nub)
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day)
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.Timesheets.Paths (timesheetWeekUrl)
import Web.Timesheets.Projection
import Web.View.Timesheets.Index

respondWithTimesheetFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> TimesheetProjectionFragment -> IO ()
respondWithTimesheetFragment requestKey fragment = do
    maybeHtml <- renderTimesheetProjectionFragment requestKey fragment
    when (isNothing maybeHtml) do
        TextIO.putStrLn ("timesheet_projection_miss: request=" <> tshow requestKey <> " fragment=" <> tshow fragment)
    respondHtmlProfiled (fromMaybe mempty maybeHtml)

respondWithTimesheetFragments :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => TimesheetProjectionRequest -> [TimesheetProjectionFragment] -> Blaze.Html -> IO ()
respondWithTimesheetFragments requestKey fragments extraHtml = do
    projection <- fetchTimesheetWeekProjectionCached requestKey
    let renderFragment fragment =
            case renderTimesheetProjectionFragmentFromProjection True projection fragment of
                Nothing -> mempty
                Just html -> html
    respondHtmlProfiled $ mconcat (map renderFragment (nub fragments)) <> extraHtml

respondWithTimesheetWeekFragmentsUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Bool -> Bool -> Maybe UUID.UUID -> IO ()
respondWithTimesheetWeekFragmentsUpdate weekOffset showApproved showAllStaff staffFilterId = do
    let requestKey = TimesheetProjectionRequest weekOffset showApproved showAllStaff staffFilterId
    setHtmxPushUrl (timesheetWeekUrl weekOffset showApproved showAllStaff staffFilterId)
    respondWithTimesheetFragments requestKey [TimesheetProjectionToolbar, TimesheetProjectionDayColumns] mempty

respondWithTimesheetDaySectionUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Day -> Bool -> Bool -> Maybe UUID.UUID -> Text -> Bool -> IO ()
respondWithTimesheetDaySectionUpdate weekOffset workedOn showApproved showAllStaff staffFilterId successMessage closeDialog = do
    projection <- fetchTimesheetWeekProjectionCached requestKey
    let weekStartDate = projection.timesheetWeekStartDate
    let dayOffset = timesheetDayOffset weekStartDate workedOn
    respondHtmlProfiled $
        fragmentHtml projection (TimesheetProjectionDaySection dayOffset)
            <> when closeDialog [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            <> renderToastOob ToastBottomCenter (successToast successMessage)
    where
        requestKey = TimesheetProjectionRequest weekOffset showApproved showAllStaff staffFilterId

respondWithTimesheetDateMoveUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Day -> Day -> Bool -> Bool -> Maybe UUID.UUID -> Text -> IO ()
respondWithTimesheetDateMoveUpdate weekOffset oldWorkedOn newWorkedOn showApproved showAllStaff staffFilterId successMessage = do
    projection <- fetchTimesheetWeekProjectionCached requestKey
    let weekStartDate = projection.timesheetWeekStartDate
    let weekEndDate = projection.timesheetWeekEndDate
    let daysInVisibleWeek = filter (\day -> day >= weekStartDate && day <= weekEndDate) (nub [oldWorkedOn, newWorkedOn])
    let fragments = map (TimesheetProjectionDaySection . timesheetDayOffset weekStartDate) daysInVisibleWeek
    respondHtmlProfiled $
        mconcat (map (fragmentHtml projection) fragments)
            <> [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            <> renderToastOob ToastBottomCenter (successToast successMessage)
    where
        requestKey = TimesheetProjectionRequest weekOffset showApproved showAllStaff staffFilterId

fragmentHtml :: (?context :: ControllerContext, ?request :: Request) => TimesheetWeekProjection -> TimesheetProjectionFragment -> Blaze.Html
fragmentHtml projection fragment =
    fromMaybe mempty (renderTimesheetProjectionFragmentFromProjection True projection fragment)

renderTimesheetWeekPage :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Int -> Bool -> Bool -> Maybe UUID.UUID -> IO ()
renderTimesheetWeekPage weekOffset showApproved showAllStaff staffFilterId =
    respondWithTimesheetWeekView . timesheetIndexView =<< fetchTimesheetWeekProjectionCached (TimesheetProjectionRequest weekOffset showApproved showAllStaff staffFilterId)

respondWithTimesheetWeekView :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IndexView -> IO ()
respondWithTimesheetWeekView indexView =
    if isHtmxRequest
        then respondWithTimesheetWeekFragmentsUpdate indexView.weekOffset indexView.showApproved indexView.showAllStaff indexView.selectedStaffFilterId
        else renderProfiled indexView
