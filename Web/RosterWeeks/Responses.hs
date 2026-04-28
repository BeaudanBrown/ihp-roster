module Web.RosterWeeks.Responses
    ( respondWithRosterContent
    , respondWithRosterContentOob
    , respondWithRosterContentUpdate
    , respondWithRosterToast
    ) where

import Application.Helper.Profiling (respondHtmlProfiled)
import Application.Helper.RosterGroups (fetchCurrentVenueRosterGroupOrDefault,
                                        fetchCurrentVenueRosterGroups)
import Application.Helper.View (ToastOverlayPosition (ToastBottomCenter),
                                errorToast, renderToastOob, successToast)
import Web.Controller.Prelude
import Web.RosterWeeks.Capabilities (buildRosterViewCapabilities)
import Web.RosterWeeks.RenderData (fetchVisibleRosterRenderDataCached,
                                   renderVisibleRosterProjectionFragment)
import Web.RosterWeeks.Types (RosterProjectionFragment (RosterProjectionContent),
                              RosterRenderData (..))
import Web.View.RosterWeeks.Grid (renderRosterContentFragment,
                                  renderRosterContentFragmentOob)

respondWithRosterContent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ()
respondWithRosterContent rosterGroupId weekOffset =
    respondHtmlProfiled . fromMaybe mempty =<< renderVisibleRosterProjectionFragment rosterGroupId weekOffset RosterProjectionContent

respondWithRosterContentOob :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ()
respondWithRosterContentOob rosterGroupId weekOffset = do
    rosterGroups <- fetchCurrentVenueRosterGroups
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
    rosterData <- fetchVisibleRosterRenderDataCached rosterGroupId weekOffset
    case rosterData of
        Nothing -> respondHtmlProfiled [hsx|<div id="roster-content" hx-swap-oob="outerHTML"></div>|]
        Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, panelStaff, orderedSlotNames, allSlots, slotConflicts, renderIndexes } ->
            let viewCapabilities = buildRosterViewCapabilities (Just rosterWeek)
             in respondHtmlProfiled $
                    renderRosterContentFragmentOob
                        (Just rosterWeek)
                        rosterDays
                        weekOffset
                        rosterGroups
                        currentRosterGroup
                        assignmentFilters
                        staffMembers
                        staffOptionStates
                        panelStaff
                        orderedSlotNames
                        weekStartDate
                        allSlots
                        slotConflicts
                        renderIndexes
                        viewCapabilities

respondWithRosterContentUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> IO ()
respondWithRosterContentUpdate rosterGroupId weekOffset successMessage = do
    rosterGroups <- fetchCurrentVenueRosterGroups
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
    rosterData <- fetchVisibleRosterRenderDataCached rosterGroupId weekOffset
    respondHtmlProfiled $
        mconcat
            [ case rosterData of
                Nothing -> [hsx|<div id="roster-content"></div>|]
                Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, panelStaff, orderedSlotNames, allSlots, slotConflicts, renderIndexes } ->
                    let viewCapabilities = buildRosterViewCapabilities (Just rosterWeek)
                     in renderRosterContentFragment
                            (Just rosterWeek)
                            rosterDays
                            weekOffset
                            rosterGroups
                            currentRosterGroup
                            assignmentFilters
                            staffMembers
                            staffOptionStates
                            panelStaff
                            orderedSlotNames
                            weekStartDate
                            allSlots
                            slotConflicts
                            renderIndexes
                            viewCapabilities
            , renderToastOob ToastBottomCenter (successToast successMessage)
            ]

respondWithRosterToast :: (?context :: ControllerContext, ?request :: Request) => Text -> Text -> IO ()
respondWithRosterToast message toastClass =
    respondHtmlProfiled $
        renderToastOob ToastBottomCenter $
            if toastClass == "app-toast-error"
                then errorToast message
                else successToast message
