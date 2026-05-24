module Web.RosterWeeks.Responses
    ( respondWithRosterContent
    , respondWithRosterContentError
    , respondWithRosterContentOob
    , respondWithRosterContentUpdate
    , respondWithRosterToast
    ) where

import Application.Helper.Profiling (respondHtmlProfiled)
import Application.Helper.RosterGroups (fetchCurrentVenueRosterGroupOrDefault,
                                        fetchCurrentVenueRosterGroups)
import Application.Helper.View (ToastOverlayConfig,
                                ToastOverlayPosition (ToastBottomCenter),
                                errorToast, renderToastOob, successToast)
import qualified Data.Text.IO as TextIO
import Web.Controller.Prelude
import Web.RosterWeeks.Capabilities (buildRosterViewCapabilities)
import Web.RosterWeeks.RenderData (fetchVisibleRosterReadModel,
                                   renderVisibleRosterReadModelFragment)
import Web.RosterWeeks.Types (RosterGridRenderModel (..),
                              RosterProjectionFragment (RosterProjectionContent),
                              RosterRenderData (..))
import Web.View.RosterWeeks.Grid (renderRosterContentFragment,
                                  renderRosterContentFragmentOob)

respondWithRosterContent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ()
respondWithRosterContent rosterGroupId weekOffset = do
    maybeHtml <- renderVisibleRosterReadModelFragment rosterGroupId weekOffset RosterProjectionContent
    when (isNothing maybeHtml) do
        TextIO.putStrLn ("roster_projection_miss: rosterGroupId=" <> tshow rosterGroupId <> " weekOffset=" <> tshow weekOffset)
    respondHtmlProfiled (fromMaybe mempty maybeHtml)

respondWithRosterContentOob :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ()
respondWithRosterContentOob rosterGroupId weekOffset = do
    rosterGroups <- fetchCurrentVenueRosterGroups
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
    case rosterData of
        Nothing -> do
            TextIO.putStrLn ("roster_projection_miss_oob: rosterGroupId=" <> tshow rosterGroupId <> " weekOffset=" <> tshow weekOffset)
            respondHtmlProfiled [hsx|<div id="roster-content" hx-swap-oob="outerHTML"></div>|]
        Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, panelStaff, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction } -> do
            let viewCapabilities = buildRosterViewCapabilities (Just rosterWeek)
            respondHtmlProfiled $
                    renderRosterContentFragmentOob
                        RosterGridRenderModel
                            { gridRosterWeek = Just rosterWeek
                            , gridRosterDays = rosterDays
                            , gridWeekOffset = weekOffset
                            , gridRosterGroups = rosterGroups
                            , gridCurrentRosterGroup = currentRosterGroup
                            , gridAssignmentFilters = assignmentFilters
                            , gridStaffMembers = staffMembers
                            , gridStaffOptionStates = staffOptionStates
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
                            }

respondWithRosterContentUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> IO ()
respondWithRosterContentUpdate rosterGroupId weekOffset successMessage = do
    respondWithRosterContentToast rosterGroupId weekOffset (successToast successMessage)

respondWithRosterContentError :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> IO ()
respondWithRosterContentError rosterGroupId weekOffset errorMessage = do
    respondWithRosterContentToast rosterGroupId weekOffset (errorToast errorMessage)

respondWithRosterContentToast :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> ToastOverlayConfig -> IO ()
respondWithRosterContentToast rosterGroupId weekOffset toast = do
    rosterGroups <- fetchCurrentVenueRosterGroups
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
    respondHtmlProfiled $
        mconcat
            [ case rosterData of
                Nothing -> [hsx|<div id="roster-content"></div>|]
                Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, panelStaff, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction } ->
                    let viewCapabilities = buildRosterViewCapabilities (Just rosterWeek)
                     in renderRosterContentFragment
                            RosterGridRenderModel
                                { gridRosterWeek = Just rosterWeek
                                , gridRosterDays = rosterDays
                                , gridWeekOffset = weekOffset
                                , gridRosterGroups = rosterGroups
                                , gridCurrentRosterGroup = currentRosterGroup
                                , gridAssignmentFilters = assignmentFilters
                                , gridStaffMembers = staffMembers
                                , gridStaffOptionStates = staffOptionStates
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
