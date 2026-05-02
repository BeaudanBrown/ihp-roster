module Web.Timesheets.Responses
    ( renderTimesheetDaySectionFromProjection
    , renderTimesheetWeekPage
    , respondWithTimesheetDateMoveUpdate
    , respondWithTimesheetDaySectionFragment
    , respondWithTimesheetDaySectionUpdate
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
import Web.Timesheets.Projection
import Web.View.Timesheets.Index

respondWithTimesheetDaySectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Int -> Bool -> Bool -> Maybe UUID.UUID -> IO ()
respondWithTimesheetDaySectionFragment weekOffset dayOffset showApproved showAllStaff staffFilterId = do
    maybeHtml <- renderTimesheetProjectionFragment (TimesheetProjectionRequest weekOffset showApproved showAllStaff staffFilterId) (TimesheetProjectionDaySection dayOffset)
    when (isNothing maybeHtml) do
        TextIO.putStrLn ("timesheet_projection_miss: weekOffset=" <> tshow weekOffset <> " dayOffset=" <> tshow dayOffset)
    respondHtmlProfiled (fromMaybe mempty maybeHtml)

respondWithTimesheetDaySectionUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Day -> Bool -> Bool -> Maybe UUID.UUID -> Text -> Bool -> Bool -> IO ()
respondWithTimesheetDaySectionUpdate weekOffset workedOn showApproved showAllStaff staffFilterId successMessage closeDialog renderMainFragmentOob = do
    projection <- fetchTimesheetWeekProjectionCached (TimesheetProjectionRequest weekOffset showApproved showAllStaff staffFilterId)
    let weekStartDate = projection.timesheetWeekStartDate
    let dayOffset = timesheetDayOffset weekStartDate workedOn
    let mainFragment =
            if renderMainFragmentOob
                then renderDaySectionOob dayModel
                else renderDaySection dayModel
        dayModel = timesheetDayRenderModelFromProjection projection dayOffset
    respondHtmlProfiled $
        mconcat
            [ mainFragment
            , when closeDialog [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            , renderToastOob ToastBottomCenter (successToast successMessage)
            ]

respondWithTimesheetDateMoveUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Int -> Day -> Day -> Bool -> Bool -> Maybe UUID.UUID -> Text -> IO ()
respondWithTimesheetDateMoveUpdate weekOffset oldWorkedOn newWorkedOn showApproved showAllStaff staffFilterId successMessage = do
    projection <- fetchTimesheetWeekProjectionCached (TimesheetProjectionRequest weekOffset showApproved showAllStaff staffFilterId)
    let weekStartDate = projection.timesheetWeekStartDate
    let weekEndDate = projection.timesheetWeekEndDate
    let daysInVisibleWeek = filter (\day -> day >= weekStartDate && day <= weekEndDate) (nub [oldWorkedOn, newWorkedOn])
    let dayFragments =
            map
                (renderTimesheetDaySectionFromProjection True projection . timesheetDayOffset weekStartDate)
                daysInVisibleWeek
    respondHtmlProfiled $
        mconcat
            [ mconcat dayFragments
            , [hsx|<div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>|]
            , renderToastOob ToastBottomCenter (successToast successMessage)
            ]

renderTimesheetDaySectionFromProjection :: (?context :: ControllerContext, ?request :: Request) => Bool -> TimesheetWeekProjection -> Int -> Blaze.Html
renderTimesheetDaySectionFromProjection renderOob projection dayOffset =
    let renderer = if renderOob then renderDaySectionOob else renderDaySection
     in renderer (timesheetDayRenderModelFromProjection projection dayOffset)

renderTimesheetWeekPage :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Int -> Bool -> Bool -> Maybe UUID.UUID -> IO ()
renderTimesheetWeekPage weekOffset showApproved showAllStaff staffFilterId =
    respondWithTimesheetWeekView . timesheetIndexView =<< fetchTimesheetWeekProjectionCached (TimesheetProjectionRequest weekOffset showApproved showAllStaff staffFilterId)

respondWithTimesheetWeekView :: (?context :: ControllerContext, ?request :: Request, ?respond :: Respond) => IndexView -> IO ()
respondWithTimesheetWeekView indexView =
    if isHtmxRequest
        then respondHtmlProfiled (renderTimesheetWeekShell indexView)
        else renderProfiled indexView
