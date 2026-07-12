module Web.RosterWeeks.Responses
    ( respondWithRosterContent
    , respondWithRosterContentError
    , respondWithRosterContentOob
    , respondWithRosterContentUpdate
    , respondWithRosterFragments
    , respondWithRosterFragmentsUpdate
    , respondWithRosterResourceInvalidation
    , respondWithRosterToast
    ) where

import Application.Helper.FrontendContract.Surface.FragmentRender (FragmentRenderMode (..))
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh,
                                      setActorLocalFragmentsRefresh)
import Application.Helper.Profiling (respondHtmlProfiled)
import Application.Helper.RosterGroups (fetchCurrentVenueRosterGroupOrDefault,
                                        fetchCurrentVenueRosterGroups)
import Application.Helper.SurfaceResource (SurfaceResourceValue)
import Application.Helper.View (ToastOverlayConfig,
                                ToastOverlayPosition (ToastBottomCenter),
                                errorToast, renderToastOob, successToast)
import Application.Helper.View.Oob (outerHtmlOobSwap)
import qualified Data.Set as Set
import qualified Data.Text.IO as TextIO
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.RosterWeeks.Capabilities (buildRosterViewCapabilities)
import Web.RosterWeeks.FrontendSurface (RosterWeekScopeValue (..),
                                        rosterMountedFragmentForProjection,
                                        rosterSurfaceFragmentKeys,
                                        rosterSurfaceScope)
import Web.RosterWeeks.RenderData (fetchVisibleRosterReadModel,
                                   renderRosterProjectionFragmentWithMode,
                                   renderVisibleRosterReadModelFragment)
import Web.RosterWeeks.Types (RosterGridRenderModel (..),
                              RosterGridViewMode (..),
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
respondWithRosterFragments rosterGroupId weekOffset fragments extraHtml =
    respondWithRosterActorInvalidation rosterGroupId weekOffset fragments extraHtml

respondWithRosterActorInvalidation :: (?context :: ControllerContext, ?request :: Request) => Id RosterGroup -> Int -> [RosterProjectionFragment] -> Blaze.Html -> IO ()
respondWithRosterActorInvalidation rosterGroupId weekOffset fragments extraHtml = do
    let scope = RosterWeekScopeValue
            { rosterWeekVenueId = unpackId currentVenueId
            , rosterWeekGroupId = rosterGroupId
            , rosterWeekWeekOffset = weekOffset
            , rosterWeekTimelineDayOffset = currentRosterTimelineDayOffset
            }
    setHeader ("HX-Reswap", "none")
    setActorLocalFragmentsRefresh (rosterSurfaceScope scope) (rosterSurfaceFragmentKeys (map (rosterMountedFragmentForProjection scope) (nub fragments)))
    respondHtmlProfiled extraHtml

respondWithRosterResourceInvalidation :: (?context :: ControllerContext, ?request :: Request) => Id RosterGroup -> Int -> Set.Set SurfaceResourceValue -> [RosterProjectionFragment] -> Blaze.Html -> IO ()
respondWithRosterResourceInvalidation rosterGroupId weekOffset touchedResources fragments extraHtml = do
    let scope = RosterWeekScopeValue
            { rosterWeekVenueId = unpackId currentVenueId
            , rosterWeekGroupId = rosterGroupId
            , rosterWeekWeekOffset = weekOffset
            , rosterWeekTimelineDayOffset = currentRosterTimelineDayOffset
            }
    let mountedFragments = map (rosterMountedFragmentForProjection scope) (nub fragments)
    setHeader ("HX-Reswap", "none")
    setActorLiveResourcesRefresh (rosterSurfaceScope scope) touchedResources mountedFragments
    respondHtmlProfiled extraHtml

respondWithRosterContentOob :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ()
respondWithRosterContentOob rosterGroupId weekOffset = do
    rosterGroups <- fetchCurrentVenueRosterGroups
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
    case rosterData of
        Nothing -> do
            TextIO.putStrLn ("roster_read_model_miss_oob: rosterGroupId=" <> tshow rosterGroupId <> " weekOffset=" <> tshow weekOffset)
            respondHtmlProfiled [hsx|<div id="roster-content" hx-swap-oob="outerHTML"></div>|]
        Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, panelStaff, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterTimePickerStartMinute, rosterTimePickerFinalSelectableMinute, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays } -> do
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
                            , gridRosterTimePickerStartMinute = rosterTimePickerStartMinute
                            , gridRosterTimePickerFinalSelectableMinute = rosterTimePickerFinalSelectableMinute
                            , gridRosterWagePrediction = rosterWagePrediction
                            , gridShowWageEstimates = showWageEstimates
                            , gridShowRosterWarnings = showRosterWarnings
                            , gridPublicHolidays = rosterPublicHolidays
                            , gridPublishAttempted = False
                            , gridViewMode = currentRosterGridViewMode
                            , gridTimelineTodayUrl = Nothing
                            }

respondWithRosterContentUpdate :: (?context :: ControllerContext, ?request :: Request) => Id RosterGroup -> Int -> Set.Set SurfaceResourceValue -> Text -> IO ()
respondWithRosterContentUpdate rosterGroupId weekOffset touchedResources successMessage =
    respondWithRosterResourceInvalidation
        rosterGroupId
        weekOffset
        touchedResources
        [RosterProjectionContent]
        (renderToastOob ToastBottomCenter (successToast successMessage))

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
                Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, panelStaff, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterTimePickerStartMinute, rosterTimePickerFinalSelectableMinute, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays } ->
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
                                , gridRosterTimePickerStartMinute = rosterTimePickerStartMinute
                                , gridRosterTimePickerFinalSelectableMinute = rosterTimePickerFinalSelectableMinute
                                , gridRosterWagePrediction = rosterWagePrediction
                                , gridShowWageEstimates = showWageEstimates
                                , gridShowRosterWarnings = showRosterWarnings
                                , gridPublicHolidays = rosterPublicHolidays
                                , gridPublishAttempted = publishAttempted
                                , gridViewMode = currentRosterGridViewMode
                                , gridTimelineTodayUrl = Nothing
                                }
            , renderToastOob ToastBottomCenter toast
            ]

currentRosterGridViewMode :: (?request :: Request) => RosterGridViewMode
currentRosterGridViewMode =
    case (paramOrNothing @Text "rosterView", paramOrNothing @Int "dayOffset") of
        (Just "timeline", Just dayOffset) -> RosterDayTimelineGridView (max 0 (min 6 dayOffset))
        _ -> RosterWeekGridView

currentRosterTimelineDayOffset :: (?request :: Request) => Maybe Int
currentRosterTimelineDayOffset = case currentRosterGridViewMode of
    RosterDayTimelineGridView dayOffset -> Just dayOffset
    RosterWeekGridView                  -> Nothing

respondWithRosterToast :: (?context :: ControllerContext, ?request :: Request) => Text -> Text -> IO ()
respondWithRosterToast message toastClass =
    respondHtmlProfiled $
        renderToastOob ToastBottomCenter $
            if toastClass == "app-toast-error"
                then errorToast message
                else successToast message
