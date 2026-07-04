module Web.RosterWeeks.Responses
    ( respondWithRosterContent
    , respondWithRosterContentError
    , respondWithRosterContentOob
    , respondWithRosterContentUpdate
    , respondWithRosterFragments
    , respondWithRosterFragmentsUpdate
    , respondWithRosterToast
    ) where

import Application.Helper.FrontendSurface.FragmentRender (FragmentRenderMode (..))
import Application.Helper.Profiling (respondHtmlProfiled)
import Application.Helper.RosterGroups (fetchCurrentVenueRosterGroupOrDefault,
                                        fetchCurrentVenueRosterGroups)
import Application.Helper.View (ToastOverlayConfig,
                                ToastOverlayPosition (ToastBottomCenter),
                                errorToast, renderToastOob, successToast)
import Application.Helper.View.Oob (outerHtmlOobSwap)
import qualified Data.Text.IO as TextIO
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.RosterWeeks.Capabilities (buildRosterViewCapabilities)
import Web.RosterWeeks.RenderData (fetchVisibleRosterReadModel,
                                   renderRosterProjectionFragmentWithMode,
                                   renderVisibleRosterReadModelFragment)
import Web.RosterWeeks.Types (RosterGridRenderModel (..),
                              RosterProjectionFragment (..),
                              RosterRenderData (..))
import Web.View.RosterWeeks.Grid (renderrosterContentLiveFragment,
                                  renderrosterContentLiveFragmentOob)

respondWithRosterContent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ()
respondWithRosterContent rosterGroupId weekOffset = do
    maybeHtml <- renderVisibleRosterReadModelFragment rosterGroupId weekOffset RosterProjectionContent
    when (isNothing maybeHtml) do
        TextIO.putStrLn ("roster_read_model_miss: rosterGroupId=" <> tshow rosterGroupId <> " weekOffset=" <> tshow weekOffset)
    respondHtmlProfiled (fromMaybe mempty maybeHtml)

respondWithRosterFragmentsUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [RosterProjectionFragment] -> ToastOverlayConfig -> IO ()
respondWithRosterFragmentsUpdate rosterGroupId weekOffset fragments toast =
    respondWithRosterFragments rosterGroupId weekOffset fragments (renderToastOob ToastBottomCenter toast)

respondWithRosterFragments :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [RosterProjectionFragment] -> Blaze.Html -> IO ()
respondWithRosterFragments rosterGroupId weekOffset fragments extraHtml = do
    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
    respondHtmlProfiled $
        mconcat (mapMaybe (renderRosterProjectionFragmentWithMode (FragmentOob outerHtmlOobSwap) rosterData) (nub fragments)) <> extraHtml

respondWithRosterContentOob :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ()
respondWithRosterContentOob rosterGroupId weekOffset = do
    rosterGroups <- fetchCurrentVenueRosterGroups
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
    case rosterData of
        Nothing -> do
            TextIO.putStrLn ("roster_read_model_miss_oob: rosterGroupId=" <> tshow rosterGroupId <> " weekOffset=" <> tshow weekOffset)
            respondHtmlProfiled [hsx|<div id="roster-content" hx-swap-oob="outerHTML"></div>|]
        Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, panelStaff, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays } -> do
            let viewCapabilities = buildRosterViewCapabilities (Just rosterWeek)
            respondHtmlProfiled $
                    renderrosterContentLiveFragmentOob
                        RosterGridRenderModel
                            { gridRosterWeek = Just rosterWeek
                            , gridRosterDays = rosterDays
                            , gridWeekOffset = weekOffset
                            , gridRosterGroups = rosterGroups
                            , gridCurrentRosterGroup = currentRosterGroup
                            , gridAssignmentFilters = assignmentFilters
                            , gridStaffMembers = staffMembers
                            , gridPanelStaff = panelStaff
                            , gridStaffSelfServicePanel = staffSelfServicePanel
                            , gridSlotNames = orderedSlotNames
                            , gridShiftTypes = shiftTypes
                            , gridWeekStartDate = weekStartDate
                            , gridAllSlots = allSlots
                            , gridSlotConflicts = slotConflicts
                            , gridRenderIndexes = renderIndexes
                            , gridViewCapabilities = viewCapabilities
                            , gridRosterLayoutMode = rosterLayoutMode
                            , gridRosterEndTimesEnabled = rosterEndTimesEnabled
                            , gridRosterWagePrediction = rosterWagePrediction
                            , gridShowWageEstimates = showWageEstimates
                            , gridShowRosterWarnings = showRosterWarnings
                            , gridPublicHolidays = rosterPublicHolidays
                            , gridPublishAttempted = False
                            }

respondWithRosterContentUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> IO ()
respondWithRosterContentUpdate rosterGroupId weekOffset successMessage = do
    respondWithRosterContentToast rosterGroupId weekOffset False (successToast successMessage)

respondWithRosterContentError :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> IO ()
respondWithRosterContentError rosterGroupId weekOffset errorMessage = do
    respondWithRosterContentToast rosterGroupId weekOffset True (errorToast errorMessage)

respondWithRosterContentToast :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Bool -> ToastOverlayConfig -> IO ()
respondWithRosterContentToast rosterGroupId weekOffset publishAttempted toast = do
    rosterGroups <- fetchCurrentVenueRosterGroups
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
    respondHtmlProfiled $
        mconcat
            [ case rosterData of
                Nothing -> [hsx|<div id="roster-content"></div>|]
                Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, panelStaff, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays } ->
                    let viewCapabilities = buildRosterViewCapabilities (Just rosterWeek)
                     in renderrosterContentLiveFragment
                            RosterGridRenderModel
                                { gridRosterWeek = Just rosterWeek
                                , gridRosterDays = rosterDays
                                , gridWeekOffset = weekOffset
                                , gridRosterGroups = rosterGroups
                                , gridCurrentRosterGroup = currentRosterGroup
                                , gridAssignmentFilters = assignmentFilters
                                , gridStaffMembers = staffMembers
                                , gridPanelStaff = panelStaff
                                , gridStaffSelfServicePanel = staffSelfServicePanel
                                , gridSlotNames = orderedSlotNames
                                , gridShiftTypes = shiftTypes
                                , gridWeekStartDate = weekStartDate
                                , gridAllSlots = allSlots
                                , gridSlotConflicts = slotConflicts
                                , gridRenderIndexes = renderIndexes
                                , gridViewCapabilities = viewCapabilities
                                , gridRosterLayoutMode = rosterLayoutMode
                                , gridRosterEndTimesEnabled = rosterEndTimesEnabled
                                , gridRosterWagePrediction = rosterWagePrediction
                                , gridShowWageEstimates = showWageEstimates
                                , gridShowRosterWarnings = showRosterWarnings
                                , gridPublicHolidays = rosterPublicHolidays
                                , gridPublishAttempted = publishAttempted
                                }
            , renderToastOob ToastBottomCenter toast
            ]

respondWithRosterToast :: (?context :: ControllerContext, ?request :: Request) => Text -> Text -> IO ()
respondWithRosterToast message toastClass =
    respondHtmlProfiled $
        renderToastOob ToastBottomCenter $
            if toastClass == "app-toast-error"
                then errorToast message
                else successToast message
