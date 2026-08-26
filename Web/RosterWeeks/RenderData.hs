{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.RosterWeeks.RenderData
    ( fetchVisibleRosterReadModel
    , fetchVisibleRosterStaffPanelRenderModel
    , renderRosterProjectionFragmentWithMode
    , renderVisibleRosterReadModelFragment
    )
where

import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Application.Helper.Conflict
import Application.Helper.Controller
import Application.Helper.FrontendContract.Surface.FragmentRender (FragmentRenderMode (..))
import Application.Helper.ProfileLeave (defaultLeaveRequestForOperationalDay)
import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Application.Helper.RosterWagePrediction
import Application.Helper.UserPreferences
import Application.Helper.VenueScopedQueries (fetchVenueShiftTypes)
import qualified Application.RosterNotification as Notification
import Application.RosterPublication (rosterDaysArePublished)
import Application.RosterTemplates (RosterTemplateLibrary,
                                    currentRosterTemplateActor,
                                    fetchRosterTemplateLibrary)
import Application.VenueTime.Model (decodeRosterShiftTiming,
                                    decodeTimesheetTiming)
import Data.Coerce (coerce)
import Data.List (find)
import qualified Data.Map.Strict as Map
import Data.Maybe (isNothing)
import qualified Data.Time.Calendar as Calendar
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.RosterWeeks.Capabilities
import Web.RosterWeeks.DateRange (RosterWindowLane, RosterWindowScope (..),
                                  rosterWindowScopeMatchesConfig)
import Web.RosterWeeks.DirectReadModel
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Filters
import Web.RosterWeeks.Rows
import Web.RosterWeeks.StaffOptions
import Web.RosterWeeks.Types
import Web.RosterWeeks.WageFilter (filterRosterWageSlots,
                                   pinnedRosterWageStaffId)
import Web.View.RosterWeeks.Grid
import Web.View.RosterWeeks.StaffPanel

shouldShowRosterWageEstimates :: (?context :: ControllerContext) => Bool -> Bool
shouldShowRosterWageEstimates userShowWageEstimates =
    hasRole VenueAdmin && userShowWageEstimates

fetchRosterPublicHolidayMap :: (?modelContext :: ModelContext) => VenueConfig -> Calendar.Day -> IO (Map.Map Calendar.Day Text)
fetchRosterPublicHolidayMap venueConfig weekStartDate = do
    holidays <-
        query @PublicHoliday
            |> filterWhere (#jurisdiction, venueConfig.publicHolidayJurisdiction)
            |> filterWhere (#isRegional, False)
            |> filterWhereGreaterThanOrEqualTo (#holidayDate, weekStartDate)
            |> filterWhereLessThanOrEqualTo (#holidayDate, Calendar.addDays 6 weekStartDate)
            |> orderByAsc #holidayDate
            |> orderByAsc #name
            |> fetch
    pure $
        Map.fromListWith
            (\newName existingName -> existingName <> ", " <> newName)
            [ (holiday.holidayDate, holiday.name)
            | holiday <- holidays
            ]

renderVisibleRosterReadModelFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterProjectionFragment -> IO (Maybe Blaze.Html)
renderVisibleRosterReadModelFragment scope fragment =
    profileActionSpan "roster.read_model.render_fragment" do
        case fragment of
            RosterProjectionContent -> do
                rosterGroups <- profileActionSpan "roster.fragment.fetch_roster_groups" fetchViewableRosterGroups
                currentRosterGroupOrNothing <- profileActionSpan "roster.fragment.resolve_current_group" (fetchViewableRosterGroup scope.rosterWindowRosterGroupId)
                accessDeniedUnless (isJust currentRosterGroupOrNothing)
                rosterData <- fetchVisibleRosterReadModel scope
                Just <$> renderRosterContentFromProjection rosterGroups (fromMaybe (externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "authorized roster group missing") currentRosterGroupOrNothing) rosterData
            _ -> renderVisibleRosterFragment scope fragment

renderRosterProjectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe RosterRenderData -> RosterProjectionFragment -> Maybe Blaze.Html
renderRosterProjectionFragment =
    renderRosterProjectionFragmentWithMode FragmentPlain

renderRosterProjectionFragmentWithMode :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => FragmentRenderMode -> Maybe RosterRenderData -> RosterProjectionFragment -> Maybe Blaze.Html
renderRosterProjectionFragmentWithMode renderMode rosterData fragment =
    case fragment of
        RosterProjectionContent ->
            Nothing
        RosterProjectionGridToolbar ->
            renderGridFragment renderrosterGridToolbarLiveFragment renderrosterGridToolbarLiveFragmentWithSwap rosterData
        RosterProjectionGridFrame ->
            renderGridFragment renderrosterGridFrameLiveFragment renderrosterGridFrameLiveFragmentWithSwap rosterData
        RosterProjectionDayColumns ->
            renderDayColumnsFragment rosterData
        RosterProjectionDayRail ->
            renderDayRailFragment rosterData
        RosterProjectionWageRail ->
            renderWageRailFragment rosterData
        RosterProjectionSlotsGrid ->
            renderSlotsGridFragment rosterData
        RosterProjectionStaffPanel ->
            Just (renderRosterStaffPanelFromProjectionWithMode renderMode rosterData)
        RosterProjectionDaySection rosterDayId ->
            rosterData >>= \projection ->
                if isHiddenDraftForCurrentUser projection.rosterWeek
                    then Nothing
                    else renderRequestedDaySectionFragmentFromProjectionWithMode renderMode projection rosterDayId
        RosterProjectionRow rosterDayId rowIndex ->
            rosterData >>= \projection ->
                if isHiddenDraftForCurrentUser projection.rosterWeek
                    then Nothing
                    else renderRequestedRowFragmentFromProjectionWithMode renderMode projection rosterDayId rowIndex
    where
        renderGridFragment plainRenderer swapRenderer maybeRosterData = do
            projection <- maybeRosterData
            let visibleRosterWeek = visibleRosterWeekForCurrentUser projection.rosterWeek
            let viewCapabilities = buildRosterViewCapabilities visibleRosterWeek
            let gridModel = (rosterGridRenderModelFromProjection viewCapabilities projection) { gridViewMode = currentRosterGridViewMode projection.weekStartDate }
            pure $ case renderMode of
                FragmentPlain        -> plainRenderer gridModel
                FragmentOob swapAttr -> swapRenderer swapAttr gridModel
        renderDayColumnsFragment maybeRosterData = do
            projection <- maybeRosterData
            let dayModel = rosterDayRenderModelFromProjection projection
            if isHiddenDraftForCurrentUser projection.rosterWeek
                then Nothing
                else pure $ case renderMode of
                    FragmentPlain -> renderrosterDayColumnsLiveFragment dayModel projection.rosterDays
                    FragmentOob swapAttr -> renderrosterDayColumnsLiveFragmentWithSwap swapAttr dayModel projection.rosterDays
        renderDayRailFragment maybeRosterData = do
            projection <- maybeRosterData
            let visibleRosterWeek = visibleRosterWeekForCurrentUser projection.rosterWeek
            let viewCapabilities = buildRosterViewCapabilities visibleRosterWeek
            let dayModel = rosterDayRenderModelFromProjection projection
            pure $ case renderMode of
                FragmentPlain ->
                    if isNothing visibleRosterWeek
                        then renderHiddenDraftDayRailFragmentWithSwap Nothing dayModel projection.rosterDays
                        else renderrosterDayRailLiveFragment viewCapabilities.canManageRosterColumns dayModel projection.rosterDays
                FragmentOob swapAttr ->
                    if isNothing visibleRosterWeek
                        then renderHiddenDraftDayRailFragmentWithSwap swapAttr dayModel projection.rosterDays
                        else renderrosterDayRailLiveFragmentWithSwap swapAttr viewCapabilities.canManageRosterColumns dayModel projection.rosterDays
        renderWageRailFragment maybeRosterData = do
            projection <- maybeRosterData
            let dayModel = rosterDayRenderModelFromProjection projection
            pure $ case renderMode of
                FragmentPlain -> renderrosterWageRailLiveFragment dayModel projection.rosterDays
                FragmentOob swapAttr -> renderrosterWageRailLiveFragmentWithSwap swapAttr dayModel projection.rosterDays
        renderSlotsGridFragment maybeRosterData = do
            projection <- maybeRosterData
            let visibleRosterWeek = visibleRosterWeekForCurrentUser projection.rosterWeek
            let viewCapabilities = buildRosterViewCapabilities visibleRosterWeek
            let dayModel = rosterDayRenderModelFromProjection projection
            pure $ case renderMode of
                FragmentPlain ->
                    if isNothing visibleRosterWeek
                        then renderHiddenDraftSlotsGridFragmentWithSwap Nothing projection.rosterDays
                        else renderrosterSlotsGridLiveFragment projection.rosterEndTimesEnabled viewCapabilities.canManageRosterColumns visibleRosterWeek projection.orderedSlotNames dayModel projection.rosterDays
                FragmentOob swapAttr ->
                    if isNothing visibleRosterWeek
                        then renderHiddenDraftSlotsGridFragmentWithSwap swapAttr projection.rosterDays
                        else renderrosterSlotsGridLiveFragmentWithSwap swapAttr projection.rosterEndTimesEnabled viewCapabilities.canManageRosterColumns visibleRosterWeek projection.orderedSlotNames dayModel projection.rosterDays

renderRosterContentFromProjection :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => [RosterGroup] -> RosterGroup -> Maybe RosterRenderData -> IO Blaze.Html
renderRosterContentFromProjection rosterGroups currentRosterGroup rosterData =
    case rosterData of
        Nothing -> pure [hsx|<div id="roster-content"></div>|]
        Just projection -> do
            let viewCapabilities = buildRosterViewCapabilities (visibleRosterWeekForCurrentUser projection.rosterWeek)
            pure $ renderrosterContentLiveFragment (rosterGridRenderModelFromProjectionWithGroups rosterGroups currentRosterGroup viewCapabilities RosterWeekGridView projection)

rosterGridRenderModelFromProjection :: (?context :: ControllerContext) => RosterViewCapabilities -> RosterRenderData -> RosterGridRenderModel
rosterGridRenderModelFromProjection viewCapabilities projection@RosterRenderData { rosterGroups, currentRosterGroup } =
    rosterGridRenderModelFromProjectionWithGroups rosterGroups currentRosterGroup viewCapabilities RosterWeekGridView projection

rosterGridRenderModelFromProjectionWithGroups :: (?context :: ControllerContext) => [RosterGroup] -> RosterGroup -> RosterViewCapabilities -> RosterGridViewMode -> RosterRenderData -> RosterGridRenderModel
rosterGridRenderModelFromProjectionWithGroups rosterGroups currentRosterGroup viewCapabilities gridViewMode RosterRenderData { rosterWeek, rosterWindowScope, rosterDays, weekStartDate, rosterCalendarRevision, assignmentFilters, staffMembers, panelStaff, templateLibrary, rosterNotificationPanelData = notificationPanelData, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterTimePickerStartMinute, rosterTimePickerFinalSelectableMinute, rosterWagePrediction, showWageEstimates, showRosterWarnings, highlightOwnLiveShifts, currentViewerStaffKey, rosterPublicHolidays } =
    RosterGridRenderModel
        { gridRosterWeek = visibleRosterWeekForCurrentUser rosterWeek
        , gridRosterDays = rosterDays
        , gridWindowScope = rosterWindowScope
        , gridRosterGroups = rosterGroups
        , gridCurrentRosterGroup = currentRosterGroup
        , gridAssignmentFilters = assignmentFilters
        , gridStaffMembers = staffMembers
        , gridPanelStaff = panelStaff
        , gridTemplateLibrary = templateLibrary
        , gridNotificationPanelData = notificationPanelData
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
        , gridViewMode = gridViewMode
        , gridTimelineTodayUrl = Nothing
        }

currentRosterGridViewMode :: (?request :: Request) => Calendar.Day -> RosterGridViewMode
currentRosterGridViewMode windowStart =
    case (paramOrNothing @Text "rosterView", paramOrNothing @Calendar.Day "dayDate", paramOrNothing @Int "dayOffset") of
        (Just "timeline", Just dayDate, _) -> RosterDayTimelineGridView (clampDayOffset (fromInteger (Calendar.diffDays dayDate windowStart)))
        (Just "timeline", Nothing, Just dayOffset) -> RosterDayTimelineGridView (clampDayOffset dayOffset)
        _ -> RosterWeekGridView
  where
    clampDayOffset = max 0 . min 6

visibleRosterWeekForCurrentUser :: (?context :: ControllerContext) => Maybe RosterWindowState -> Maybe RosterWindowState
visibleRosterWeekForCurrentUser (Just rosterWeek)
    | rosterWeek.windowIsPublished || hasRole Manager = Just rosterWeek
visibleRosterWeekForCurrentUser Nothing = Nothing
visibleRosterWeekForCurrentUser _ = Nothing

isHiddenDraftForCurrentUser :: (?context :: ControllerContext) => Maybe RosterWindowState -> Bool
isHiddenDraftForCurrentUser maybeRosterWeek =
    not (hasRole Manager) && maybe True (not . (.windowIsPublished)) maybeRosterWeek

rosterDayRenderModelFromProjection :: (?context :: ControllerContext) => RosterRenderData -> RosterDayRenderModel
rosterDayRenderModelFromProjection RosterRenderData { rosterWeek, weekStartDate, rosterCalendarRevision, assignmentFilters, staffMembers, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays } =
    RosterDayRenderModel
        { dayIsEditable = hasRole Manager && maybe False (not . (.windowIsPublished)) rosterWeek
        , daySlotNames = orderedSlotNames
        , dayAssignmentFilters = assignmentFilters
        , dayStaffMembers = staffMembers
        , dayShiftTypes = shiftTypes
        , dayWeekStartDate = weekStartDate
        , dayCalendarRevision = rosterCalendarRevision
        , dayAllSlots = allSlots
        , daySlotConflicts = slotConflicts
        , dayRenderIndexes = renderIndexes
        , dayRosterLayoutMode = rosterLayoutMode
        , dayRosterEndTimesEnabled = rosterEndTimesEnabled
        , dayRosterWagePrediction = rosterWagePrediction
        , dayShowWageEstimates = showWageEstimates
        , dayShowRosterWarnings = showRosterWarnings
        , dayPublicHolidays = rosterPublicHolidays
        , dayPublishAttempted = False
        }

renderRosterStaffPanelFromProjectionWithMode :: (?context :: ControllerContext, ?request :: Request) => FragmentRenderMode -> Maybe RosterRenderData -> Blaze.Html
renderRosterStaffPanelFromProjectionWithMode renderMode rosterData =
    case rosterData of
        Nothing -> mempty
        Just projection ->
            let panelModel = rosterStaffPanelRenderModelFromProjection RosterStaffPanelCurrentGroup projection
             in case renderMode of
                    FragmentPlain -> renderrosterStaffPanelLiveFragment panelModel
                    FragmentOob swapAttr -> renderrosterStaffPanelLiveFragmentWithSwap swapAttr panelModel

rosterStaffPanelRenderModelFromProjection :: (?context :: ControllerContext, ?request :: Request) => RosterStaffPanelScope -> RosterRenderData -> RosterStaffPanelRenderModel
rosterStaffPanelRenderModelFromProjection panelScope RosterRenderData { rosterWeek, rosterGroups, currentRosterGroup, weekStartDate, rosterCalendarRevision, assignmentFilters, panelStaff, templateLibrary, rosterNotificationPanelData = notificationPanelData, rosterLayoutMode, showWageEstimates, showRosterWarnings, highlightOwnLiveShifts } =
    RosterStaffPanelRenderModel
        { staffPanelRosterWeek = visibleRosterWeekForCurrentUser rosterWeek
        , staffPanelWeekStartDate = weekStartDate
        , staffPanelCalendarRevision = rosterCalendarRevision
        , staffPanelRosterGroups = rosterGroups
        , staffPanelCurrentRosterGroup = currentRosterGroup
        , staffPanelAssignmentFilters = assignmentFilters
        , staffPanelViewCapabilities = buildRosterViewCapabilities (visibleRosterWeekForCurrentUser rosterWeek)
        , staffPanelRosterLayoutMode = rosterLayoutMode
        , staffPanelShowWageEstimates = showWageEstimates
        , staffPanelShowRosterWarnings = showRosterWarnings
        , staffPanelHighlightOwnLiveShifts = highlightOwnLiveShifts
        , staffPanelViewMode = currentRosterGridViewMode weekStartDate
        , staffPanelScope = panelScope
        , staffPanelEntries = panelStaff
        , staffPanelTemplateLibrary = templateLibrary
        , staffPanelNotificationPanelData = notificationPanelData
        }

renderRequestedRowFragmentFromProjectionWithMode :: (?context :: ControllerContext, ?request :: Request) => FragmentRenderMode -> RosterRenderData -> UUID.UUID -> Int -> Maybe Blaze.Html
renderRequestedRowFragmentFromProjectionWithMode renderMode RosterRenderData { rosterWeek, weekStartDate, rosterCalendarRevision, assignmentFilters, staffMembers, orderedSlotNames, shiftTypes, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled } rosterDayId rowIndex =
    case renderMode of
        FragmentPlain -> renderRequestedRowFragment (hasRole Manager && maybe False (not . (.windowIsPublished)) rosterWeek) weekStartDate rosterCalendarRevision orderedSlotNames assignmentFilters staffMembers shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayId, rowIndex)
        FragmentOob _ -> renderRequestedRow weekStartDate rosterCalendarRevision orderedSlotNames assignmentFilters staffMembers shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayId, rowIndex)

renderRequestedDaySectionFragmentFromProjectionWithMode :: (?context :: ControllerContext, ?request :: Request) => FragmentRenderMode -> RosterRenderData -> UUID.UUID -> Maybe Blaze.Html
renderRequestedDaySectionFragmentFromProjectionWithMode renderMode RosterRenderData { rosterWeek, weekStartDate, rosterCalendarRevision, assignmentFilters, staffMembers, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays } rosterDayId =
    case renderMode of
        FragmentPlain -> renderRequestedDaySectionFragment (hasRole Manager && maybe False (not . (.windowIsPublished)) rosterWeek) weekStartDate rosterCalendarRevision orderedSlotNames assignmentFilters staffMembers shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayId
        FragmentOob _ -> renderRequestedDaySection weekStartDate rosterCalendarRevision orderedSlotNames assignmentFilters staffMembers shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayId

fetchVisibleRosterReadModel :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO (Maybe RosterRenderData)
fetchVisibleRosterReadModel scope = profileActionSpan "roster.read_model.fetch_visible" do
    rosterGroupIsViewable <- isJust <$> fetchViewableRosterGroup scope.rosterWindowRosterGroupId
    accessDeniedUnless rosterGroupIsViewable
    visibleRosterWeek <- profileActionSpan "roster.direct.fetch_visible_week" (fetchVisibleRosterWeek scope)
    rosterDataOrNothing <- fetchRosterRenderData scope
    pure $ case (visibleRosterWeek, rosterDataOrNothing) of
        (Nothing, Just rosterData) ->
            let hiddenRenderIndexes = buildRosterRenderIndexes rosterData.rosterDays [] [] []
             in Just
                    rosterData
                        { assignmentFilters = defaultRosterAssignmentFilters
                        , staffMembers = []
                        , panelStaff = []
                        , rosterNotificationPanelData = Nothing
                        , allSlots = []
                        , slotConflicts = []
                        , renderIndexes = hiddenRenderIndexes
                        , rosterWagePrediction = Nothing
                        , currentViewerStaffKey = Nothing
                        }
        _ -> rosterDataOrNothing

fetchRosterRenderData :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO (Maybe RosterRenderData)
fetchRosterRenderData scope = do
    venueConfig <- profileActionSpan "roster.direct.fetch_venue_config" fetchVenueConfig
    accessDeniedUnless (rosterWindowScopeMatchesConfig venueConfig scope)
    let rosterGroupId = scope.rosterWindowRosterGroupId
    rosterGroups <- profileActionSpan "roster.direct.fetch_roster_groups" fetchViewableRosterGroups
    currentRosterGroupOrNothing <- profileActionSpan "roster.direct.resolve_current_group" (fetchViewableRosterGroup rosterGroupId)
    accessDeniedUnless (isJust currentRosterGroupOrNothing)
    let currentRosterGroup = fromMaybe (externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "authorized roster group missing") currentRosterGroupOrNothing
    assignmentFilters <- profileActionSpan "roster.direct.fetch_assignment_filters" fetchRosterAssignmentFilters
    rosterLayoutMode <- profileActionSpan "roster.direct.fetch_layout_preference" fetchCurrentRosterLayoutMode
    userShowWageEstimates <- profileActionSpan "roster.direct.fetch_wage_preference" fetchCurrentUserShowWageEstimates
    showRosterWarnings <- profileActionSpan "roster.direct.fetch_warning_preference" fetchCurrentUserShowRosterWarnings
    highlightOwnLiveShifts <- profileActionSpan "roster.direct.fetch_own_highlight_preference" fetchCurrentUserHighlightOwnLiveShifts
    maybeCurrentViewerStaff <- profileActionSpan "roster.direct.fetch_current_staff" fetchCurrentUserStaff
    let showWageEstimates = shouldShowRosterWageEstimates userShowWageEstimates
    let weekStartDate = scope.rosterWindowStart
    templateLibrary <- fetchRosterPanelTemplateLibrary currentRosterGroup
    rosterPublicHolidays <- profileActionSpan "roster.direct.fetch_public_holidays" (fetchRosterPublicHolidayMap venueConfig weekStartDate)

    baseFactsOrNothing <- profileActionSpan "roster.direct.fetch_base_facts" (fetchRosterBaseFactsDirect scope)
    case baseFactsOrNothing of
        Nothing -> pure Nothing
        Just RosterBaseFacts { baseRosterWeek = rosterWeek, baseRosterDays = rosterDays, baseAllSlots = allSlots, baseVisibleSlots = visibleSlots, baseOrderedSlotDefinitions = orderedSlotNames, baseShiftTypes = shiftTypes, basePanelStaff = panelStaffMembers, baseStaffMembers = staffMembers } -> do
            let currentViewerStaffKey =
                    case maybeCurrentViewerStaff of
                        Just staff
                            | staff.isActive
                            , isNothing staff.archivedAt
                            , any (\slot -> slot.staffId == Just (unpackId staff.id)) visibleSlots ->
                                Just ("staff:" <> tshow staff.id)
                        _ -> Nothing
            panelStaff <- profileActionSpan "roster.build_staff_panel" (fetchRosterStaffPanelEntries panelStaffMembers visibleSlots)
            notificationPanelData <- fetchRosterPanelNotificationData currentRosterGroup weekStartDate rosterDays
            staffSelfServicePanel <- profileActionSpan "roster.build_staff_self_service_panel" (fetchRosterStaffSelfServicePanel venueConfig rosterGroups scope highlightOwnLiveShifts)
            slotConflicts <-
                if maybe False (.windowIsPublished) rosterWeek
                    then pure []
                    else profileActionSpan "roster.direct.build_slot_conflicts" (buildSlotConflictsDirect rosterGroupId venueConfig.lateToEarlyMinStartGapMinutes weekStartDate visibleSlots)
            let renderIndexes = buildRosterRenderIndexes rosterDays visibleSlots staffMembers slotConflicts
            let wageSlots = filterRosterWageSlots (pinnedRosterWageStaffId showWageEstimates panelStaffMembers) visibleSlots
            rosterWagePrediction <-
                if showWageEstimates
                    then Just <$> profileActionSpan "roster.predict_wages" (fetchRosterWagePredictionForWindow venueConfig rosterDays wageSlots)
                    else pure Nothing
            let rosterCalendarRevision = venueConfig.rosterCalendarRevision
            pure (Just RosterRenderData { rosterWeek, rosterWindowScope = scope, rosterGroups, currentRosterGroup, rosterDays, weekStartDate, rosterCalendarRevision, assignmentFilters, staffMembers, panelStaff, templateLibrary, rosterNotificationPanelData = notificationPanelData, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled = venueConfig.rosterEndTimesEnabled, rosterTimePickerStartMinute = venueConfig.timePickerStartMinuteOfDay, rosterTimePickerFinalSelectableMinute = venueConfig.timePickerFinalSelectableMinuteOfDay, rosterWagePrediction, showWageEstimates, showRosterWarnings, highlightOwnLiveShifts, currentViewerStaffKey, rosterPublicHolidays })

fetchRosterPanelNotificationData :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterGroup -> Day -> [RosterDay] -> IO (Maybe Notification.RosterNotificationPanelData)
fetchRosterPanelNotificationData rosterGroup windowStart rosterDays
    | hasRole Manager
    , map (.operationalDate) rosterDays == map (`Calendar.addDays` windowStart) [0 .. 6]
    , rosterDaysArePublished rosterDays = do
        panelNotificationAudience <- Notification.fetchRosterNotificationAudience currentVenue rosterGroup
        panelLatestNotificationRun <- Notification.fetchLatestRosterNotificationRunSummaryForWindow currentVenueId rosterGroup.id windowStart (Calendar.addDays 7 windowStart)
        pure (Just Notification.RosterNotificationPanelData { .. })
fetchRosterPanelNotificationData _ _ _ = pure Nothing

fetchRosterPanelTemplateLibrary :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterGroup -> IO (Maybe RosterTemplateLibrary)
fetchRosterPanelTemplateLibrary rosterGroup
    | not (hasRole Manager) = pure Nothing
    | otherwise = currentRosterTemplateActor >>= (`fetchRosterTemplateLibrary` rosterGroup)

fetchRosterStaffSelfServicePanel :: (?context :: ControllerContext, ?modelContext :: ModelContext) => VenueConfig -> [RosterGroup] -> RosterWindowScope -> Bool -> IO (Maybe RosterStaffSelfServicePanel)
fetchRosterStaffSelfServicePanel venueConfig rosterGroups scope highlightOwnLiveShifts
    | hasRole Manager = pure Nothing
    | currentUserIsUnimpersonatedSuperAdmin = pure Nothing
    | otherwise = do
        maybeStaff <- fetchCurrentUserStaff
        case maybeStaff of
            Nothing -> pure Nothing
            Just staff -> do
                operationalDay <- currentOperationalDayForVenue venueConfig
                let timesheetWeekStartDate = startOfWeekFor venueConfig.rosterWeekStartsOn operationalDay
                quickToolsTimesheetEntries <-
                    query @TimesheetEntry
                        |> filterWhere (#venueId, unpackId currentVenueId)
                        |> filterWhere (#staffId, unpackId staff.id)
                        |> filterWhere (#operationalDate, operationalDay)
                        |> filterWhere (#deletedAt, Nothing)
                        |> orderByAsc #startsAt
                        |> fetch
                quickToolsShiftTypes <- fetchCurrentVenueRosterShiftTypes
                let quickToolsLeaveRequest = defaultLeaveRequestForOperationalDay operationalDay
                pure $
                    Just
                        RosterStaffSelfServicePanel
                            { quickToolsLeaveRequest
                            , quickToolsVenueId = currentVenueId
                            , quickToolsRosterGroupId = scope.rosterWindowRosterGroupId
                            , quickToolsRosterGroups = rosterGroups
                            , quickToolsRosterWeekStartDate = scope.rosterWindowStart
                            , quickToolsTimesheetEntries
                            , quickToolsTimesheetTimingByEntryId = Map.fromList [(unpackId entry.id, decodeTimesheetTiming entry) | entry <- quickToolsTimesheetEntries]
                            , quickToolsStaffMembers = [staff]
                            , quickToolsShiftTypes
                            , quickToolsOperationalDay = operationalDay
                            , quickToolsTimesheetWeekStartDate = timesheetWeekStartDate
                            , quickToolsCalendarRevision = venueConfig.rosterCalendarRevision
                            , quickToolsTimesheetEditWindowDays = venueConfig.staffTimesheetEditWindowDays
                            , quickToolsHighlightOwnLiveShifts = highlightOwnLiveShifts
                            }

fetchVisibleRosterWeek :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> IO (Maybe RosterWindowState)
fetchVisibleRosterWeek scope = do
    rosterGroupIsViewable <- isJust <$> fetchViewableRosterGroup scope.rosterWindowRosterGroupId
    accessDeniedUnless rosterGroupIsViewable
    baseFacts <- profileActionSpan "roster.visible_window.fetch" (fetchRosterBaseFactsDirect scope)
    pure $
        case baseFacts >>= (.baseRosterWeek) of
            Just rosterWeek | rosterWeek.windowIsPublished || hasRole Manager -> Just rosterWeek
            _ -> Nothing

buildRosterRenderIndexes :: [RosterDay] -> [RosterSlot] -> [Staff] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes
buildRosterRenderIndexes rosterDays visibleSlots staffMembers slotConflicts =
    let slotsByRosterDayId =
            Map.fromListWith
                (<>)
                [ (slot.rosterDayId, [slot])
                | slot <- visibleSlots
                ]
     in RosterRenderIndexes
        { rosterDayById = Map.fromList [(coerce (get #id rosterDay), rosterDay) | rosterDay <- rosterDays]
        , rosterDayRowsByDayId =
            Map.fromList
                [ (coerce (get #id rosterDay), rowsForDay rosterDay (Map.findWithDefault [] (coerce (get #id rosterDay)) slotsByRosterDayId))
                | rosterDay <- rosterDays
                ]
        , rosterSlotByDayRowSlotName =
            Map.fromList
                [ ((slot.rosterDayId, slot.rowIndex, slot.rosterLaneId), slot)
                | slot <- visibleSlots
                ]
        , rosterStaffById = Map.fromList [(coerce (get #id staff), staff) | staff <- staffMembers]
        , rosterConflictsBySlotId = Map.fromList [(coerce slotId, conflicts) | (slotId, conflicts) <- slotConflicts]
        , rosterTimingBySlotId = Map.fromList [(unpackId slot.id, decodeRosterShiftTiming slot) | slot <- visibleSlots]
        }

renderVisibleRosterFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterWindowScope -> RosterProjectionFragment -> IO (Maybe Blaze.Html)
renderVisibleRosterFragment scope fragment = do
    visibleRosterWeek <- fetchVisibleRosterWeek scope
    case visibleRosterWeek of
        Nothing -> do
            rosterData <- fetchVisibleRosterReadModel scope
            pure (renderRosterProjectionFragment rosterData fragment)
        Just rosterWeek ->
            case fragment of
                RosterProjectionStaffPanel -> do
                    panelModel <- fetchVisibleRosterStaffPanelRenderModel RosterStaffPanelCurrentGroup scope
                    pure (Just (renderrosterStaffPanelLiveFragment panelModel))
                RosterProjectionContent -> do
                    rosterData <- fetchVisibleRosterReadModel scope
                    case rosterData of
                        Nothing -> pure Nothing
                        Just projection -> Just <$> renderRosterContentFromProjection projection.rosterGroups projection.currentRosterGroup rosterData
                RosterProjectionGridToolbar -> do
                    rosterData <- fetchVisibleRosterReadModel scope
                    pure (renderRosterProjectionFragment rosterData fragment)
                RosterProjectionGridFrame -> do
                    rosterData <- fetchVisibleRosterReadModel scope
                    pure (renderRosterProjectionFragment rosterData fragment)
                RosterProjectionDayColumns -> do
                    rosterData <- fetchVisibleRosterReadModel scope
                    pure (renderRosterProjectionFragment rosterData fragment)
                RosterProjectionDayRail -> do
                    rosterData <- fetchVisibleRosterReadModel scope
                    pure (renderRosterProjectionFragment rosterData fragment)
                RosterProjectionWageRail -> do
                    rosterData <- fetchVisibleRosterReadModel scope
                    pure (renderRosterProjectionFragment rosterData fragment)
                RosterProjectionSlotsGrid -> do
                    rosterData <- fetchVisibleRosterReadModel scope
                    pure (renderRosterProjectionFragment rosterData fragment)
                RosterProjectionRow rosterDayUuid rowIndex -> do
                    facts@RosterBaseFacts { baseRosterDays = rosterDays, baseVisibleSlots = visibleSlots, baseStaffMembers = staffMembers } <- fromMaybe (externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "authorized roster window missing") <$> fetchRosterBaseFactsDirect scope
                    venueConfig <- fetchVenueConfig
                    assignmentFilters <- fetchRosterAssignmentFilters
                    rosterLayoutMode <- fetchCurrentRosterLayoutMode
                    let weekStartDate = scope.rosterWindowStart
                    let targetSlots = filter (\slot -> slot.rosterDayId == rosterDayUuid && slot.rowIndex == rowIndex) visibleSlots
                    slotConflicts <-
                        if rosterWeek.windowIsPublished
                            then pure []
                            else profileActionSpan "roster.direct.build_slot_conflicts" (buildSlotConflictsForSlotsDirect scope.rosterWindowRosterGroupId venueConfig.lateToEarlyMinStartGapMinutes weekStartDate visibleSlots targetSlots)
                    let renderIndexes = buildRosterRenderIndexes rosterDays visibleSlots staffMembers slotConflicts
                    pure (renderRequestedRowFragment (hasRole Manager && not rosterWeek.windowIsPublished) weekStartDate scope.rosterWindowCalendarRevision facts.baseOrderedSlotDefinitions assignmentFilters staffMembers facts.baseShiftTypes renderIndexes rosterLayoutMode venueConfig.rosterEndTimesEnabled (rosterDayUuid, rowIndex))
                RosterProjectionDaySection rosterDayUuid -> do
                    facts@RosterBaseFacts { baseRosterDays = rosterDays, baseVisibleSlots = visibleSlots, baseStaffMembers = staffMembers, basePanelStaff = panelStaffMembers } <- fromMaybe (externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "authorized roster window missing") <$> fetchRosterBaseFactsDirect scope
                    venueConfig <- fetchVenueConfig
                    assignmentFilters <- fetchRosterAssignmentFilters
                    rosterLayoutMode <- fetchCurrentRosterLayoutMode
                    userShowWageEstimates <- fetchCurrentUserShowWageEstimates
                    showRosterWarnings <- fetchCurrentUserShowRosterWarnings
                    let showWageEstimates = shouldShowRosterWageEstimates userShowWageEstimates
                    let weekStartDate = scope.rosterWindowStart
                    rosterPublicHolidays <- fetchRosterPublicHolidayMap venueConfig weekStartDate
                    let targetSlots = filter (\slot -> slot.rosterDayId == rosterDayUuid) visibleSlots
                    slotConflicts <-
                        if rosterWeek.windowIsPublished
                            then pure []
                            else profileActionSpan "roster.direct.build_slot_conflicts" (buildSlotConflictsForSlotsDirect scope.rosterWindowRosterGroupId venueConfig.lateToEarlyMinStartGapMinutes weekStartDate visibleSlots targetSlots)
                    let renderIndexes = buildRosterRenderIndexes rosterDays visibleSlots staffMembers slotConflicts
                    let wageSlots = filterRosterWageSlots (pinnedRosterWageStaffId showWageEstimates panelStaffMembers) visibleSlots
                    rosterWagePrediction <-
                        if showWageEstimates
                            then Just <$> profileActionSpan "roster.predict_wages" (fetchRosterWagePredictionForWindow venueConfig rosterDays wageSlots)
                            else pure Nothing
                    pure (renderRequestedDaySectionFragment (hasRole Manager && not rosterWeek.windowIsPublished) weekStartDate venueConfig.rosterCalendarRevision facts.baseOrderedSlotDefinitions assignmentFilters staffMembers facts.baseShiftTypes facts.baseAllSlots slotConflicts renderIndexes rosterLayoutMode venueConfig.rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayUuid)


fetchVisibleRosterStaffPanelRenderModel :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterStaffPanelScope -> RosterWindowScope -> IO RosterStaffPanelRenderModel
fetchVisibleRosterStaffPanelRenderModel panelScope scope = do
    let rosterGroupId = scope.rosterWindowRosterGroupId
    visibleRosterWeek <- fetchVisibleRosterWeek scope
    rosterGroups <- profileActionSpan "roster.fragment.fetch_roster_groups" fetchViewableRosterGroups
    currentRosterGroupOrNothing <- profileActionSpan "roster.fragment.resolve_current_group" (fetchViewableRosterGroup rosterGroupId)
    accessDeniedUnless (isJust currentRosterGroupOrNothing)
    let currentRosterGroup = fromMaybe (externalRuntimeInvariantFailure AuthorizedFrameworkInvariant "authorized roster group missing") currentRosterGroupOrNothing
    assignmentFilters <- profileActionSpan "roster.fragment.fetch_assignment_filters" fetchRosterAssignmentFilters
    rosterLayoutMode <- profileActionSpan "roster.fragment.fetch_layout_preference" fetchCurrentRosterLayoutMode
    userShowWageEstimates <- profileActionSpan "roster.fragment.fetch_wage_preference" fetchCurrentUserShowWageEstimates
    showRosterWarnings <- profileActionSpan "roster.fragment.fetch_warning_preference" fetchCurrentUserShowRosterWarnings
    highlightOwnLiveShifts <- profileActionSpan "roster.fragment.fetch_own_highlight_preference" fetchCurrentUserHighlightOwnLiveShifts
    venueConfig <- profileActionSpan "roster.fragment.fetch_venue_config" fetchVenueConfig
    let weekStartDate = scope.rosterWindowStart
    templateLibrary <- fetchRosterPanelTemplateLibrary currentRosterGroup
    baseFacts <- fetchRosterBaseFactsDirect scope
    panelStaff <- case baseFacts of
        Nothing -> pure []
        Just facts -> do
            panelStaffMembers <- case panelScope of
                RosterStaffPanelCurrentGroup -> pure facts.basePanelStaff
                RosterStaffPanelAllVenue     -> fetchCurrentVenueActiveStaff
            profileActionSpan "roster.build_staff_panel" (fetchRosterStaffPanelEntriesForScope panelScope panelStaffMembers facts.baseVisibleSlots)
    notificationPanelData <- fetchRosterPanelNotificationData currentRosterGroup weekStartDate (maybe [] (.baseRosterDays) baseFacts)
    pure RosterStaffPanelRenderModel
        { staffPanelRosterWeek = visibleRosterWeek
        , staffPanelWeekStartDate = weekStartDate
        , staffPanelCalendarRevision = venueConfig.rosterCalendarRevision
        , staffPanelRosterGroups = rosterGroups
        , staffPanelCurrentRosterGroup = currentRosterGroup
        , staffPanelAssignmentFilters = assignmentFilters
        , staffPanelViewCapabilities = buildRosterViewCapabilities visibleRosterWeek
        , staffPanelRosterLayoutMode = rosterLayoutMode
        , staffPanelShowWageEstimates = shouldShowRosterWageEstimates userShowWageEstimates
        , staffPanelShowRosterWarnings = showRosterWarnings
        , staffPanelHighlightOwnLiveShifts = highlightOwnLiveShifts
        , staffPanelViewMode = currentRosterGridViewMode weekStartDate
        , staffPanelScope = panelScope
        , staffPanelEntries = panelStaff
        , staffPanelTemplateLibrary = templateLibrary
        , staffPanelNotificationPanelData = notificationPanelData
        }

renderRequestedRow :: (?context :: ControllerContext, ?request :: Request) => Calendar.Day -> Int -> [RosterWindowLane] -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> (UUID.UUID, Int) -> Maybe Blaze.Html
renderRequestedRow weekStartDate calendarRevision orderedSlotNames assignmentFilters staffMembers shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayUuid, targetRowIndex) = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    dayRows <- Map.lookup rosterDayUuid renderIndexes.rosterDayRowsByDayId
    let rowCount = length dayRows
    let lastRowIndex = lastRowIndexForRows dayRows
    let indexedRows = zip [0 :: Int ..] dayRows
    (rowPosition, (_, rowSlots)) <- find (\(_, (rowIndex, _)) -> rowIndex == targetRowIndex) indexedRows
    let date = rosterDay.operationalDate
    pure (renderRowOob RosterRowRenderModel { rowIsEditable = True, rowSlotNames = orderedSlotNames, rowAssignmentFilters = assignmentFilters, rowStaffMembers = staffMembers, rowShiftTypes = shiftTypes, rowDate = date, rowDayIndex = fromInteger (Calendar.diffDays date weekStartDate), rowRosterDay = rosterDay, rowCalendarRevision = calendarRevision, rowCount, rowLastRowIndex = lastRowIndex, rowRenderIndexes = renderIndexes, rowRosterLayoutMode = rosterLayoutMode, rowRosterEndTimesEnabled = rosterEndTimesEnabled, rowPublishAttempted = False } (rowPosition, (targetRowIndex, rowSlots)))

renderRequestedRowFragment :: (?context :: ControllerContext, ?request :: Request) => Bool -> Calendar.Day -> Int -> [RosterWindowLane] -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> (UUID.UUID, Int) -> Maybe Blaze.Html
renderRequestedRowFragment isEditable weekStartDate calendarRevision orderedSlotNames assignmentFilters staffMembers shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayUuid, targetRowIndex) = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    dayRows <- Map.lookup rosterDayUuid renderIndexes.rosterDayRowsByDayId
    let rowCount = length dayRows
    let lastRowIndex = lastRowIndexForRows dayRows
    let indexedRows = zip [0 :: Int ..] dayRows
    (rowPosition, (_, rowSlots)) <- find (\(_, (rowIndex, _)) -> rowIndex == targetRowIndex) indexedRows
    let date = rosterDay.operationalDate
    pure (renderRowFragment RosterRowRenderModel { rowIsEditable = isEditable, rowSlotNames = orderedSlotNames, rowAssignmentFilters = assignmentFilters, rowStaffMembers = staffMembers, rowShiftTypes = shiftTypes, rowDate = date, rowDayIndex = fromInteger (Calendar.diffDays date weekStartDate), rowRosterDay = rosterDay, rowCalendarRevision = calendarRevision, rowCount, rowLastRowIndex = lastRowIndex, rowRenderIndexes = renderIndexes, rowRosterLayoutMode = rosterLayoutMode, rowRosterEndTimesEnabled = rosterEndTimesEnabled, rowPublishAttempted = False } (rowPosition, (targetRowIndex, rowSlots)))

renderRequestedDaySection :: (?context :: ControllerContext, ?request :: Request) => Calendar.Day -> Int -> [RosterWindowLane] -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> Maybe RosterWagePrediction -> Bool -> Bool -> Map.Map Calendar.Day Text -> UUID.UUID -> Maybe Blaze.Html
renderRequestedDaySection weekStartDate calendarRevision orderedSlotNames assignmentFilters staffMembers shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayUuid = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    pure (renderRosterDaySectionFragment RosterDayRenderModel { dayIsEditable = True, daySlotNames = orderedSlotNames, dayAssignmentFilters = assignmentFilters, dayStaffMembers = staffMembers, dayShiftTypes = shiftTypes, dayWeekStartDate = weekStartDate, dayCalendarRevision = calendarRevision, dayAllSlots = allSlots, daySlotConflicts = slotConflicts, dayRenderIndexes = renderIndexes, dayRosterLayoutMode = rosterLayoutMode, dayRosterEndTimesEnabled = rosterEndTimesEnabled, dayRosterWagePrediction = rosterWagePrediction, dayShowWageEstimates = showWageEstimates, dayShowRosterWarnings = showRosterWarnings, dayPublicHolidays = rosterPublicHolidays, dayPublishAttempted = False } rosterDay)

renderRequestedDaySectionFragment :: (?context :: ControllerContext, ?request :: Request) => Bool -> Calendar.Day -> Int -> [RosterWindowLane] -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> Maybe RosterWagePrediction -> Bool -> Bool -> Map.Map Calendar.Day Text -> UUID.UUID -> Maybe Blaze.Html
renderRequestedDaySectionFragment isEditable weekStartDate calendarRevision orderedSlotNames assignmentFilters staffMembers shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayUuid = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    pure (renderRosterDaySectionFragment RosterDayRenderModel { dayIsEditable = isEditable, daySlotNames = orderedSlotNames, dayAssignmentFilters = assignmentFilters, dayStaffMembers = staffMembers, dayShiftTypes = shiftTypes, dayWeekStartDate = weekStartDate, dayCalendarRevision = calendarRevision, dayAllSlots = allSlots, daySlotConflicts = slotConflicts, dayRenderIndexes = renderIndexes, dayRosterLayoutMode = rosterLayoutMode, dayRosterEndTimesEnabled = rosterEndTimesEnabled, dayRosterWagePrediction = rosterWagePrediction, dayShowWageEstimates = showWageEstimates, dayShowRosterWarnings = showRosterWarnings, dayPublicHolidays = rosterPublicHolidays, dayPublishAttempted = False } rosterDay)

fetchCurrentVenueRosterShiftTypes :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueRosterShiftTypes =
    fetchVenueShiftTypes currentVenueId
