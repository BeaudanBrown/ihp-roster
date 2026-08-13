module Web.RosterWeeks.Responses
    ( respondWithRosterContent
    , respondWithRosterContentError
    , respondWithRosterContentOob
    , respondWithRosterContentUpdate
    , respondWithRosterDialogOverlay
    , respondWithRosterFragments
    , respondWithRosterFragmentsUpdate
    , respondWithRosterOwnHighlightPreferenceUpdate
    , respondWithRosterResourceInvalidation
    , respondWithRosterToast
    , respondWithRosterTemplateApplicationUpdate
    ) where

import Application.Helper.FrontendContract.Surface.FragmentRender (FragmentRenderMode (..))
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh,
                                      setActorLocalFragmentsRefresh)
import Application.Helper.Profiling (respondHtmlProfiled)
import Application.Helper.RosterGroups (fetchViewableRosterGroup,
                                        fetchViewableRosterGroups)
import Application.Helper.SurfaceResource (SurfaceResourceValue)
import Application.Helper.View (ToastOverlayConfig,
                                ToastOverlayPosition (ToastBottomCenter),
                                dialogOverlayMountId, errorToast,
                                renderToastOob, successToast)
import Application.Helper.WeekBoundaries (venueWeekStartDate)
import qualified Data.Set as Set
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day, addDays, diffDays)
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.RosterWeeks.Capabilities (buildRosterViewCapabilities)
import Web.RosterWeeks.FrontendSurface (RosterWeekScopeValue (..),
                                        rosterCandidateMountedFragments,
                                        rosterMountedFragmentForProjection,
                                        rosterMountedFragmentPlanFromRenderData,
                                        rosterSurfaceFragmentKeys,
                                        rosterSurfaceScope)
import Web.RosterWeeks.Projection (rosterGridInnerAndStaffPanelFragments)
import Web.RosterWeeks.RenderData (fetchVisibleRosterReadModel,
                                   renderRosterProjectionFragmentWithMode,
                                   renderVisibleRosterReadModelFragment)
import Web.RosterWeeks.Types (RosterGridRenderModel (..),
                              RosterGridViewMode (..),
                              RosterProjectionFragment (..),
                              RosterRenderData (..))
import Web.View.RosterWeeks.Grid (renderrosterContentLiveFragment,
                                  renderrosterContentLiveFragmentOob)
import Web.View.RosterWeeks.StaffSelfServicePanel (renderRosterStaffSelfServicePanelFragmentOob)

respondWithRosterContent :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ()
respondWithRosterContent rosterGroupId weekOffset = do
    maybeHtml <- renderVisibleRosterReadModelFragment rosterGroupId weekOffset RosterProjectionContent
    when (isNothing maybeHtml) do
        TextIO.putStrLn ("roster_read_model_miss: rosterGroupId=" <> tshow rosterGroupId <> " weekOffset=" <> tshow weekOffset)
    respondHtmlProfiled (fromMaybe mempty maybeHtml)

respondWithRosterFragmentsUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [RosterProjectionFragment] -> ToastOverlayConfig -> IO ()
respondWithRosterFragmentsUpdate rosterGroupId weekOffset fragments toast =
    respondWithRosterFragments rosterGroupId weekOffset fragments (renderToastOob ToastBottomCenter toast)

respondWithRosterOwnHighlightPreferenceUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> ToastOverlayConfig -> IO ()
respondWithRosterOwnHighlightPreferenceUpdate rosterGroupId weekOffset toast = do
    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
    let selfServicePanel = rosterData >>= (.staffSelfServicePanel)
    respondWithRosterFragments
        rosterGroupId
        weekOffset
        rosterGridInnerAndStaffPanelFragments
        (renderRosterStaffSelfServicePanelFragmentOob selfServicePanel <> renderToastOob ToastBottomCenter toast)

respondWithRosterFragments :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [RosterProjectionFragment] -> Blaze.Html -> IO ()
respondWithRosterFragments rosterGroupId weekOffset fragments extraHtml =
    respondWithRosterActorInvalidation rosterGroupId weekOffset fragments extraHtml

respondWithRosterActorInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> [RosterProjectionFragment] -> Blaze.Html -> IO ()
respondWithRosterActorInvalidation rosterGroupId weekOffset fragments extraHtml = do
    scope <- fetchRosterWindowScopeValue rosterGroupId weekOffset
    setHeader ("HX-Reswap", "none")
    setActorLocalFragmentsRefresh (rosterSurfaceScope scope) (rosterSurfaceFragmentKeys (map (rosterMountedFragmentForProjection scope) (nub fragments)))
    respondHtmlProfiled extraHtml

respondWithRosterResourceInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Set.Set SurfaceResourceValue -> [RosterProjectionFragment] -> Blaze.Html -> IO ()
respondWithRosterResourceInvalidation rosterGroupId weekOffset touchedResources fragments extraHtml = do
    scope <- fetchRosterWindowScopeValue rosterGroupId weekOffset
    let mountedFragments = map (rosterMountedFragmentForProjection scope) (nub fragments)
    setHeader ("HX-Reswap", "none")
    setActorLiveResourcesRefresh (rosterSurfaceScope scope) touchedResources mountedFragments
    respondHtmlProfiled extraHtml

respondWithRosterDialogOverlay :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Blaze.Html -> IO ()
respondWithRosterDialogOverlay rosterGroupId weekOffset dialog =
    respondWithRosterResourceInvalidation rosterGroupId weekOffset Set.empty [] [hsx|
        <div id={dialogOverlayMountId} hx-swap-oob="innerHTML">{dialog}</div>
    |]

respondWithRosterCompleteResourceInvalidation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Set.Set SurfaceResourceValue -> Blaze.Html -> IO ()
respondWithRosterCompleteResourceInvalidation rosterGroupId weekOffset touchedResources extraHtml = do
    maybeRosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
    case maybeRosterData of
        Nothing -> respondWithRosterResourceInvalidation rosterGroupId weekOffset touchedResources [RosterProjectionContent] extraHtml
        Just rosterData -> do
            let windowStart = rosterData.weekStartDate
            let scope = RosterWeekScopeValue
                    { rosterWeekVenueId = unpackId currentVenueId
                    , rosterWeekGroupId = rosterGroupId
                    , rosterWeekWeekOffset = weekOffset
                    , rosterWeekWindowStart = windowStart
                    , rosterWeekWindowEnd = addDays 7 windowStart
                    , rosterWeekCalendarRevision = rosterData.rosterCalendarRevision
                    , rosterWeekTimelineDayOffset = currentRosterTimelineDayOffset windowStart
                    }
            let plan = rosterMountedFragmentPlanFromRenderData rosterData.templateLibraryUserId rosterData.rosterDays rosterData.renderIndexes
            setHeader ("HX-Reswap", "none")
            setActorLiveResourcesRefresh (rosterSurfaceScope scope) touchedResources (rosterCandidateMountedFragments scope plan)
            respondHtmlProfiled extraHtml

respondWithRosterTemplateApplicationUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Set.Set SurfaceResourceValue -> IO ()
respondWithRosterTemplateApplicationUpdate rosterGroupId weekOffset touchedResources =
    respondWithRosterCompleteResourceInvalidation rosterGroupId weekOffset touchedResources [hsx|
        <div id={dialogOverlayMountId} hx-swap-oob="innerHTML"></div>
        {renderToastOob ToastBottomCenter (successToast "Template applied.")}
    |]

respondWithRosterContentOob :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ()
respondWithRosterContentOob rosterGroupId weekOffset = do
    rosterGroups <- fetchViewableRosterGroups
    currentRosterGroupOrNothing <- fetchViewableRosterGroup rosterGroupId
    accessDeniedUnless (isJust currentRosterGroupOrNothing)
    let currentRosterGroup = fromMaybe (error "authorized roster group missing") currentRosterGroupOrNothing
    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
    case rosterData of
        Nothing -> do
            TextIO.putStrLn ("roster_read_model_miss_oob: rosterGroupId=" <> tshow rosterGroupId <> " weekOffset=" <> tshow weekOffset)
            respondHtmlProfiled [hsx|<div id="roster-content" hx-swap-oob="outerHTML"></div>|]
        Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, rosterCalendarRevision, assignmentFilters, staffMembers, panelStaff, templateLibrary, templateLibraryUserId, rosterNotificationPanelData, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterTimePickerStartMinute, rosterTimePickerFinalSelectableMinute, rosterWagePrediction, showWageEstimates, showRosterWarnings, highlightOwnLiveShifts, currentViewerStaffKey, rosterPublicHolidays } -> do
            let viewCapabilities = buildRosterViewCapabilities rosterWeek
            respondHtmlProfiled $
                    renderrosterContentLiveFragmentOob
                        RosterGridRenderModel
                            { gridRosterWeek = rosterWeek
                            , gridRosterDays = rosterDays
                            , gridWeekOffset = weekOffset
                            , gridRosterGroups = rosterGroups
                            , gridCurrentRosterGroup = currentRosterGroup
                            , gridAssignmentFilters = assignmentFilters
                            , gridStaffMembers = staffMembers
                            , gridPanelStaff = panelStaff
                            , gridTemplateLibrary = templateLibrary
                            , gridTemplateLibraryUserId = templateLibraryUserId
                            , gridNotificationPanelData = rosterNotificationPanelData
                            , gridStaffSelfServicePanel = staffSelfServicePanel
                            , gridSlotNames = orderedSlotNames
                            , gridShiftTypes = shiftTypes
                            , gridWeekStartDate = weekStartDate
                            , gridRosterCalendarRevision = rosterCalendarRevision
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
                            , gridHighlightOwnLiveShifts = highlightOwnLiveShifts
                            , gridCurrentViewerStaffKey = currentViewerStaffKey
                            , gridPublicHolidays = rosterPublicHolidays
                            , gridPublishAttempted = False
                            , gridViewMode = currentRosterGridViewMode weekStartDate
                            , gridTimelineTodayUrl = Nothing
                            }

respondWithRosterContentUpdate :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Set.Set SurfaceResourceValue -> Text -> IO ()
respondWithRosterContentUpdate rosterGroupId weekOffset touchedResources successMessage =
    respondWithRosterCompleteResourceInvalidation
        rosterGroupId
        weekOffset
        touchedResources
        (renderToastOob ToastBottomCenter (successToast successMessage))

respondWithRosterContentError :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Text -> IO ()
respondWithRosterContentError rosterGroupId weekOffset errorMessage = do
    respondWithRosterContentToast rosterGroupId weekOffset True (errorToast errorMessage)

respondWithRosterContentToast :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Bool -> ToastOverlayConfig -> IO ()
respondWithRosterContentToast rosterGroupId weekOffset publishAttempted toast = do
    rosterGroups <- fetchViewableRosterGroups
    currentRosterGroupOrNothing <- fetchViewableRosterGroup rosterGroupId
    accessDeniedUnless (isJust currentRosterGroupOrNothing)
    let currentRosterGroup = fromMaybe (error "authorized roster group missing") currentRosterGroupOrNothing
    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
    respondHtmlProfiled $
        mconcat
            [ case rosterData of
                Nothing -> [hsx|<div id="roster-content"></div>|]
                Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, rosterCalendarRevision, assignmentFilters, staffMembers, panelStaff, templateLibrary, templateLibraryUserId, rosterNotificationPanelData, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterTimePickerStartMinute, rosterTimePickerFinalSelectableMinute, rosterWagePrediction, showWageEstimates, showRosterWarnings, highlightOwnLiveShifts, currentViewerStaffKey, rosterPublicHolidays } ->
                    let viewCapabilities = buildRosterViewCapabilities rosterWeek
                     in renderrosterContentLiveFragment
                            RosterGridRenderModel
                                { gridRosterWeek = rosterWeek
                                , gridRosterDays = rosterDays
                                , gridWeekOffset = weekOffset
                                , gridRosterGroups = rosterGroups
                                , gridCurrentRosterGroup = currentRosterGroup
                                , gridAssignmentFilters = assignmentFilters
                                , gridStaffMembers = staffMembers
                                , gridPanelStaff = panelStaff
                                , gridTemplateLibrary = templateLibrary
                                , gridTemplateLibraryUserId = templateLibraryUserId
                                , gridNotificationPanelData = rosterNotificationPanelData
                                , gridStaffSelfServicePanel = staffSelfServicePanel
                                , gridSlotNames = orderedSlotNames
                                , gridShiftTypes = shiftTypes
                                , gridWeekStartDate = weekStartDate
                                , gridRosterCalendarRevision = rosterCalendarRevision
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
                                , gridHighlightOwnLiveShifts = highlightOwnLiveShifts
                                , gridCurrentViewerStaffKey = currentViewerStaffKey
                                , gridPublicHolidays = rosterPublicHolidays
                                , gridPublishAttempted = publishAttempted
                                , gridViewMode = currentRosterGridViewMode weekStartDate
                                , gridTimelineTodayUrl = Nothing
                                }
            , renderToastOob ToastBottomCenter toast
            ]

fetchRosterWindowScopeValue :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO RosterWeekScopeValue
fetchRosterWindowScopeValue rosterGroupId weekOffset = do
    venueConfig <- fetchVenueConfig
    let windowStart = venueWeekStartDate venueConfig weekOffset
    pure RosterWeekScopeValue
        { rosterWeekVenueId = unpackId currentVenueId
        , rosterWeekGroupId = rosterGroupId
        , rosterWeekWeekOffset = weekOffset
        , rosterWeekWindowStart = windowStart
        , rosterWeekWindowEnd = addDays 7 windowStart
        , rosterWeekCalendarRevision = venueConfig.rosterCalendarRevision
        , rosterWeekTimelineDayOffset = currentRosterTimelineDayOffset windowStart
        }

currentRosterGridViewMode :: (?request :: Request) => Day -> RosterGridViewMode
currentRosterGridViewMode windowStart =
    case (paramOrNothing @Text "rosterView", paramOrNothing @Day "dayDate", paramOrNothing @Int "dayOffset") of
        (Just "timeline", Just dayDate, _) -> RosterDayTimelineGridView (clampDayOffset (fromInteger (diffDays dayDate windowStart)))
        (Just "timeline", Nothing, Just dayOffset) -> RosterDayTimelineGridView (clampDayOffset dayOffset)
        _ -> RosterWeekGridView
  where
    clampDayOffset = max 0 . min 6

currentRosterTimelineDayOffset :: (?request :: Request) => Day -> Maybe Int
currentRosterTimelineDayOffset windowStart = case currentRosterGridViewMode windowStart of
    RosterDayTimelineGridView dayOffset -> Just dayOffset
    RosterWeekGridView                  -> Nothing

respondWithRosterToast :: (?context :: ControllerContext, ?request :: Request) => Text -> Text -> IO ()
respondWithRosterToast message toastClass =
    respondHtmlProfiled $
        renderToastOob ToastBottomCenter $
            if toastClass == "app-toast-error"
                then errorToast message
                else successToast message
