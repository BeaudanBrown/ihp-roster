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
import Application.RosterTemplates (RosterTemplateLibrary,
                                    currentRosterTemplateActor,
                                    fetchRosterTemplateLibrary,
                                    rosterTemplateActorUserId)
import Application.VenueTime.Model (requireMelbourneDateRangeUTC)
import Data.Coerce (coerce)
import Data.List (find)
import qualified Data.Map.Strict as Map
import Data.Maybe (isNothing)
import qualified Data.Time.Calendar as Calendar
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.RosterWeeks.Capabilities
import Web.RosterWeeks.DateRange (RosterWindowLane)
import Web.RosterWeeks.DirectReadModel
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Filters
import Web.RosterWeeks.Rows
import Web.RosterWeeks.Service
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

renderVisibleRosterReadModelFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> RosterProjectionFragment -> IO (Maybe Blaze.Html)
renderVisibleRosterReadModelFragment rosterGroupId weekOffset fragment =
    profileActionSpan "roster.read_model.render_fragment" do
        case fragment of
            RosterProjectionContent -> do
                rosterGroups <- profileActionSpan "roster.fragment.fetch_roster_groups" fetchViewableRosterGroups
                currentRosterGroupOrNothing <- profileActionSpan "roster.fragment.resolve_current_group" (fetchViewableRosterGroup rosterGroupId)
                accessDeniedUnless (isJust currentRosterGroupOrNothing)
                rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
                Just <$> renderRosterContentFromProjection rosterGroups (fromMaybe (error "authorized roster group missing") currentRosterGroupOrNothing) rosterData
            _ -> renderVisibleRosterFragment rosterGroupId weekOffset fragment

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
            let gridModel = (rosterGridRenderModelFromProjection viewCapabilities projection) { gridViewMode = currentRosterGridViewMode }
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
rosterGridRenderModelFromProjectionWithGroups rosterGroups currentRosterGroup viewCapabilities gridViewMode RosterRenderData { rosterWeek, weekOffset, rosterDays, weekStartDate, assignmentFilters, staffMembers, panelStaff, templateLibrary, templateLibraryUserId, rosterNotificationPanelData = notificationPanelData, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterTimePickerStartMinute, rosterTimePickerFinalSelectableMinute, rosterWagePrediction, showWageEstimates, showRosterWarnings, highlightOwnLiveShifts, currentViewerStaffKey, rosterPublicHolidays } =
    RosterGridRenderModel
        { gridRosterWeek = visibleRosterWeekForCurrentUser rosterWeek
        , gridRosterDays = rosterDays
        , gridWeekOffset = weekOffset
        , gridRosterGroups = rosterGroups
        , gridCurrentRosterGroup = currentRosterGroup
        , gridAssignmentFilters = assignmentFilters
        , gridStaffMembers = staffMembers
        , gridPanelStaff = panelStaff
        , gridTemplateLibrary = templateLibrary
        , gridTemplateLibraryUserId = templateLibraryUserId
        , gridNotificationPanelData = notificationPanelData
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
        , gridHighlightOwnLiveShifts = highlightOwnLiveShifts
        , gridCurrentViewerStaffKey = currentViewerStaffKey
        , gridPublicHolidays = rosterPublicHolidays
        , gridPublishAttempted = False
        , gridViewMode = gridViewMode
        , gridTimelineTodayUrl = Nothing
        }

currentRosterGridViewMode :: (?request :: Request) => RosterGridViewMode
currentRosterGridViewMode =
    case (paramOrNothing @Text "rosterView", paramOrNothing @Int "dayOffset") of
        (Just "timeline", Just dayOffset) -> RosterDayTimelineGridView (max 0 (min 6 dayOffset))
        _ -> RosterWeekGridView

visibleRosterWeekForCurrentUser :: (?context :: ControllerContext) => Maybe RosterWeek -> Maybe RosterWeek
visibleRosterWeekForCurrentUser (Just rosterWeek)
    | rosterWeek.isLive || hasRole Manager = Just rosterWeek
visibleRosterWeekForCurrentUser Nothing = Nothing
visibleRosterWeekForCurrentUser _ = Nothing

isHiddenDraftForCurrentUser :: (?context :: ControllerContext) => Maybe RosterWeek -> Bool
isHiddenDraftForCurrentUser maybeRosterWeek =
    not (hasRole Manager) && maybe True (not . (.isLive)) maybeRosterWeek

rosterDayRenderModelFromProjection :: (?context :: ControllerContext) => RosterRenderData -> RosterDayRenderModel
rosterDayRenderModelFromProjection RosterRenderData { rosterWeek, weekOffset, currentRosterGroup, weekStartDate, assignmentFilters, staffMembers, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays } =
    RosterDayRenderModel
        { dayIsEditable = hasRole Manager && maybe False (not . (.isLive)) rosterWeek
        , daySlotNames = orderedSlotNames
        , dayAssignmentFilters = assignmentFilters
        , dayStaffMembers = staffMembers
        , dayShiftTypes = shiftTypes
        , dayWeekStartDate = weekStartDate
        , dayTimelineContext = Just (weekOffset, currentRosterGroup.id)
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
rosterStaffPanelRenderModelFromProjection panelScope RosterRenderData { rosterWeek, weekOffset, rosterGroups, currentRosterGroup, weekStartDate, assignmentFilters, panelStaff, templateLibrary, templateLibraryUserId, rosterNotificationPanelData = notificationPanelData, rosterLayoutMode, showWageEstimates, showRosterWarnings, highlightOwnLiveShifts } =
    RosterStaffPanelRenderModel
        { staffPanelRosterWeek = visibleRosterWeekForCurrentUser rosterWeek
        , staffPanelWeekOffset = weekOffset
        , staffPanelWeekStartDate = weekStartDate
        , staffPanelRosterGroups = rosterGroups
        , staffPanelCurrentRosterGroup = currentRosterGroup
        , staffPanelAssignmentFilters = assignmentFilters
        , staffPanelViewCapabilities = buildRosterViewCapabilities (visibleRosterWeekForCurrentUser rosterWeek)
        , staffPanelRosterLayoutMode = rosterLayoutMode
        , staffPanelShowWageEstimates = showWageEstimates
        , staffPanelShowRosterWarnings = showRosterWarnings
        , staffPanelHighlightOwnLiveShifts = highlightOwnLiveShifts
        , staffPanelViewMode = currentRosterGridViewMode
        , staffPanelScope = panelScope
        , staffPanelEntries = panelStaff
        , staffPanelTemplateLibrary = templateLibrary
        , staffPanelTemplateUserId = templateLibraryUserId
        , staffPanelNotificationPanelData = notificationPanelData
        }

renderRequestedRowFragmentFromProjectionWithMode :: (?context :: ControllerContext, ?request :: Request) => FragmentRenderMode -> RosterRenderData -> UUID.UUID -> Int -> Maybe Blaze.Html
renderRequestedRowFragmentFromProjectionWithMode renderMode RosterRenderData { rosterWeek, weekStartDate, assignmentFilters, staffMembers, orderedSlotNames, shiftTypes, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled } rosterDayId rowIndex =
    case renderMode of
        FragmentPlain -> renderRequestedRowFragment (hasRole Manager && maybe False (not . (.isLive)) rosterWeek) weekStartDate orderedSlotNames assignmentFilters staffMembers shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayId, rowIndex)
        FragmentOob _ -> renderRequestedRow weekStartDate orderedSlotNames assignmentFilters staffMembers shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayId, rowIndex)

renderRequestedDaySectionFragmentFromProjectionWithMode :: (?context :: ControllerContext, ?request :: Request) => FragmentRenderMode -> RosterRenderData -> UUID.UUID -> Maybe Blaze.Html
renderRequestedDaySectionFragmentFromProjectionWithMode renderMode RosterRenderData { rosterWeek, weekStartDate, assignmentFilters, staffMembers, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays } rosterDayId =
    case renderMode of
        FragmentPlain -> renderRequestedDaySectionFragment (hasRole Manager && maybe False (not . (.isLive)) rosterWeek) weekStartDate orderedSlotNames assignmentFilters staffMembers shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayId
        FragmentOob _ -> renderRequestedDaySection weekStartDate orderedSlotNames assignmentFilters staffMembers shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayId

fetchVisibleRosterReadModel :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterRenderData)
fetchVisibleRosterReadModel rosterGroupId weekOffset = profileActionSpan "roster.read_model.fetch_visible" do
    rosterGroupIsViewable <- isJust <$> fetchViewableRosterGroup rosterGroupId
    accessDeniedUnless rosterGroupIsViewable
    visibleRosterWeek <- profileActionSpan "roster.direct.fetch_visible_week" (fetchVisibleRosterWeek rosterGroupId weekOffset)
    rosterDataOrNothing <- fetchRosterRenderData rosterGroupId weekOffset
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

fetchRosterRenderData :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterRenderData)
fetchRosterRenderData rosterGroupId weekOffset = do
    venueConfig <- profileActionSpan "roster.direct.fetch_venue_config" fetchVenueConfig
    rosterGroups <- profileActionSpan "roster.direct.fetch_roster_groups" fetchViewableRosterGroups
    currentRosterGroupOrNothing <- profileActionSpan "roster.direct.resolve_current_group" (fetchViewableRosterGroup rosterGroupId)
    accessDeniedUnless (isJust currentRosterGroupOrNothing)
    let currentRosterGroup = fromMaybe (error "authorized roster group missing") currentRosterGroupOrNothing
    assignmentFilters <- profileActionSpan "roster.direct.fetch_assignment_filters" fetchRosterAssignmentFilters
    rosterLayoutMode <- profileActionSpan "roster.direct.fetch_layout_preference" fetchCurrentRosterLayoutMode
    userShowWageEstimates <- profileActionSpan "roster.direct.fetch_wage_preference" fetchCurrentUserShowWageEstimates
    showRosterWarnings <- profileActionSpan "roster.direct.fetch_warning_preference" fetchCurrentUserShowRosterWarnings
    highlightOwnLiveShifts <- profileActionSpan "roster.direct.fetch_own_highlight_preference" fetchCurrentUserHighlightOwnLiveShifts
    maybeCurrentViewerStaff <- profileActionSpan "roster.direct.fetch_current_staff" fetchCurrentUserStaff
    let showWageEstimates = shouldShowRosterWageEstimates userShowWageEstimates
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    (templateLibraryUserId, templateLibrary) <- fetchRosterPanelTemplateLibrary currentRosterGroup
    rosterPublicHolidays <- profileActionSpan "roster.direct.fetch_public_holidays" (fetchRosterPublicHolidayMap venueConfig weekStartDate)

    baseFactsOrNothing <- profileActionSpan "roster.direct.fetch_base_facts" (fetchRosterBaseFactsDirect rosterGroupId weekOffset)
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
            notificationPanelData <- fetchRosterPanelNotificationData currentRosterGroup rosterWeek
            staffSelfServicePanel <- profileActionSpan "roster.build_staff_self_service_panel" (fetchRosterStaffSelfServicePanel venueConfig rosterGroups rosterGroupId weekOffset highlightOwnLiveShifts)
            slotConflicts <-
                if maybe False (.isLive) rosterWeek
                    then pure []
                    else profileActionSpan "roster.direct.build_slot_conflicts" (buildSlotConflictsDirect rosterGroupId venueConfig.lateToEarlyMinStartGapMinutes weekStartDate visibleSlots)
            let renderIndexes = buildRosterRenderIndexes rosterDays visibleSlots staffMembers slotConflicts
            let wageSlots = filterRosterWageSlots (pinnedRosterWageStaffId showWageEstimates panelStaffMembers) visibleSlots
            rosterWagePrediction <-
                case (showWageEstimates, rosterWeek) of
                    (True, Just legacyRosterWeek) -> Just <$> profileActionSpan "roster.predict_wages" (fetchRosterWagePrediction venueConfig legacyRosterWeek rosterDays wageSlots)
                    _ -> pure Nothing
            pure (Just RosterRenderData { rosterWeek, weekOffset, rosterGroups, currentRosterGroup, rosterDays, weekStartDate, assignmentFilters, staffMembers, panelStaff, templateLibrary, templateLibraryUserId, rosterNotificationPanelData = notificationPanelData, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled = venueConfig.rosterEndTimesEnabled, rosterTimePickerStartMinute = venueConfig.timePickerStartMinuteOfDay, rosterTimePickerFinalSelectableMinute = venueConfig.timePickerFinalSelectableMinuteOfDay, rosterWagePrediction, showWageEstimates, showRosterWarnings, highlightOwnLiveShifts, currentViewerStaffKey, rosterPublicHolidays })

fetchRosterPanelNotificationData :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterGroup -> Maybe RosterWeek -> IO (Maybe Notification.RosterNotificationPanelData)
fetchRosterPanelNotificationData rosterGroup (Just rosterWeek)
    | hasRole Manager && rosterWeek.isLive = do
        panelNotificationAudience <- Notification.fetchRosterNotificationAudience currentVenue rosterGroup
        panelLatestNotificationRun <- Notification.fetchLatestRosterNotificationRunSummary rosterWeek
        pure (Just Notification.RosterNotificationPanelData { .. })
fetchRosterPanelNotificationData _ _ = pure Nothing

-- Templates are intentionally hidden from the Roster side panel for the next release.
-- Keep the implementation and routes intact so the feature can be re-enabled later.
rosterTemplatesVisibleInPanel :: Bool
rosterTemplatesVisibleInPanel = False

fetchRosterPanelTemplateLibrary :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterGroup -> IO (Maybe (Id User), Maybe RosterTemplateLibrary)
fetchRosterPanelTemplateLibrary rosterGroup
    | not rosterTemplatesVisibleInPanel = pure (Nothing, Nothing)
    | not (hasRole Manager) = pure (Nothing, Nothing)
    | otherwise = do
        actor <- currentRosterTemplateActor
        library <- fetchRosterTemplateLibrary actor rosterGroup
        pure (rosterTemplateActorUserId actor <$ library, library)

fetchRosterStaffSelfServicePanel :: (?context :: ControllerContext, ?modelContext :: ModelContext) => VenueConfig -> [RosterGroup] -> Id RosterGroup -> Int -> Bool -> IO (Maybe RosterStaffSelfServicePanel)
fetchRosterStaffSelfServicePanel venueConfig rosterGroups rosterGroupId weekOffset highlightOwnLiveShifts
    | hasRole Manager = pure Nothing
    | currentUserIsUnimpersonatedSuperAdmin = pure Nothing
    | otherwise = do
        maybeStaff <- fetchCurrentUserStaff
        case maybeStaff of
            Nothing -> pure Nothing
            Just staff -> do
                operationalDay <- currentOperationalDayForVenue venueConfig
                let timesheetWeekOffset = venueWeekOffsetForDay venueConfig operationalDay
                let timesheetWeekStartDate = venueWeekStartDate venueConfig timesheetWeekOffset
                let (dayStartsAt, dayEndsAt) = requireMelbourneDateRangeUTC operationalDay operationalDay
                quickToolsTimesheetEntries <-
                    query @TimesheetEntry
                        |> filterWhere (#venueId, unpackId currentVenueId)
                        |> filterWhere (#staffId, unpackId staff.id)
                        |> filterWhereGreaterThanOrEqualTo (#startsAt, dayStartsAt)
                        |> filterWhereLessThan (#startsAt, dayEndsAt)
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
                            , quickToolsRosterGroupId = rosterGroupId
                            , quickToolsRosterGroups = rosterGroups
                            , quickToolsRosterWeekOffset = weekOffset
                            , quickToolsTimesheetEntries
                            , quickToolsStaffMembers = [staff]
                            , quickToolsShiftTypes
                            , quickToolsOperationalDay = operationalDay
                            , quickToolsTimesheetWeekOffset = timesheetWeekOffset
                            , quickToolsTimesheetWeekStartDate = timesheetWeekStartDate
                            , quickToolsTimesheetEditWindowDays = venueConfig.staffTimesheetEditWindowDays
                            , quickToolsHighlightOwnLiveShifts = highlightOwnLiveShifts
                            }

fetchVisibleRosterWeek :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterWeek)
fetchVisibleRosterWeek rosterGroupId weekOffset = do
    rosterGroupIsViewable <- isJust <$> fetchViewableRosterGroup rosterGroupId
    accessDeniedUnless rosterGroupIsViewable
    rosterWeekOrNothing <-
        profileActionSpan "roster.visible_week.fetch" do
            query @RosterWeek
                |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
                |> filterWhere (#weekOffset, weekOffset)
                |> fetchOneOrNothing

    pure $
        case rosterWeekOrNothing of
            Just rosterWeek | get #isLive rosterWeek || hasRole Manager -> Just rosterWeek
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
        }

renderVisibleRosterFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> RosterProjectionFragment -> IO (Maybe Blaze.Html)
renderVisibleRosterFragment rosterGroupId weekOffset fragment = do
    visibleRosterWeek <- fetchVisibleRosterWeek rosterGroupId weekOffset
    case visibleRosterWeek of
        Nothing -> do
            rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
            pure (renderRosterProjectionFragment rosterData fragment)
        Just rosterWeek ->
            case fragment of
                RosterProjectionStaffPanel -> do
                    panelModel <- fetchVisibleRosterStaffPanelRenderModel RosterStaffPanelCurrentGroup rosterGroupId weekOffset
                    pure (Just (renderrosterStaffPanelLiveFragment panelModel))
                RosterProjectionContent -> do
                    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
                    case rosterData of
                        Nothing -> pure Nothing
                        Just projection -> Just <$> renderRosterContentFromProjection projection.rosterGroups projection.currentRosterGroup rosterData
                RosterProjectionGridToolbar -> do
                    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
                    pure (renderRosterProjectionFragment rosterData fragment)
                RosterProjectionGridFrame -> do
                    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
                    pure (renderRosterProjectionFragment rosterData fragment)
                RosterProjectionDayColumns -> do
                    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
                    pure (renderRosterProjectionFragment rosterData fragment)
                RosterProjectionDayRail -> do
                    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
                    pure (renderRosterProjectionFragment rosterData fragment)
                RosterProjectionWageRail -> do
                    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
                    pure (renderRosterProjectionFragment rosterData fragment)
                RosterProjectionSlotsGrid -> do
                    rosterData <- fetchVisibleRosterReadModel rosterGroupId weekOffset
                    pure (renderRosterProjectionFragment rosterData fragment)
                RosterProjectionRow rosterDayUuid rowIndex -> do
                    facts@RosterBaseFacts { baseRosterDays = rosterDays, baseVisibleSlots = visibleSlots, baseStaffMembers = staffMembers } <- fetchRosterBaseFactsForWeekDirect rosterGroupId rosterWeek
                    venueConfig <- fetchVenueConfig
                    assignmentFilters <- fetchRosterAssignmentFilters
                    rosterLayoutMode <- fetchCurrentRosterLayoutMode
                    let weekStartDate = venueWeekStartDate venueConfig weekOffset
                    let targetSlots = filter (\slot -> slot.rosterDayId == rosterDayUuid && slot.rowIndex == rowIndex) visibleSlots
                    slotConflicts <-
                        if rosterWeek.isLive
                            then pure []
                            else profileActionSpan "roster.direct.build_slot_conflicts" (buildSlotConflictsForSlotsDirect rosterGroupId venueConfig.lateToEarlyMinStartGapMinutes weekStartDate visibleSlots targetSlots)
                    let renderIndexes = buildRosterRenderIndexes rosterDays visibleSlots staffMembers slotConflicts
                    pure (renderRequestedRowFragment (hasRole Manager && not rosterWeek.isLive) weekStartDate facts.baseOrderedSlotDefinitions assignmentFilters staffMembers facts.baseShiftTypes renderIndexes rosterLayoutMode venueConfig.rosterEndTimesEnabled (rosterDayUuid, rowIndex))
                RosterProjectionDaySection rosterDayUuid -> do
                    facts@RosterBaseFacts { baseRosterDays = rosterDays, baseVisibleSlots = visibleSlots, baseStaffMembers = staffMembers, basePanelStaff = panelStaffMembers } <- fetchRosterBaseFactsForWeekDirect rosterGroupId rosterWeek
                    venueConfig <- fetchVenueConfig
                    assignmentFilters <- fetchRosterAssignmentFilters
                    rosterLayoutMode <- fetchCurrentRosterLayoutMode
                    userShowWageEstimates <- fetchCurrentUserShowWageEstimates
                    showRosterWarnings <- fetchCurrentUserShowRosterWarnings
                    let showWageEstimates = shouldShowRosterWageEstimates userShowWageEstimates
                    let weekStartDate = venueWeekStartDate venueConfig weekOffset
                    rosterPublicHolidays <- fetchRosterPublicHolidayMap venueConfig weekStartDate
                    let targetSlots = filter (\slot -> slot.rosterDayId == rosterDayUuid) visibleSlots
                    slotConflicts <-
                        if rosterWeek.isLive
                            then pure []
                            else profileActionSpan "roster.direct.build_slot_conflicts" (buildSlotConflictsForSlotsDirect rosterGroupId venueConfig.lateToEarlyMinStartGapMinutes weekStartDate visibleSlots targetSlots)
                    let renderIndexes = buildRosterRenderIndexes rosterDays visibleSlots staffMembers slotConflicts
                    let wageSlots = filterRosterWageSlots (pinnedRosterWageStaffId showWageEstimates panelStaffMembers) visibleSlots
                    rosterWagePrediction <-
                        if showWageEstimates
                            then Just <$> profileActionSpan "roster.predict_wages" (fetchRosterWagePrediction venueConfig rosterWeek rosterDays wageSlots)
                            else pure Nothing
                    pure (renderRequestedDaySectionFragment (hasRole Manager && not rosterWeek.isLive) weekStartDate facts.baseOrderedSlotDefinitions assignmentFilters staffMembers facts.baseShiftTypes facts.baseAllSlots slotConflicts renderIndexes rosterLayoutMode venueConfig.rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayUuid)


fetchVisibleRosterStaffPanelRenderModel :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterStaffPanelScope -> Id RosterGroup -> Int -> IO RosterStaffPanelRenderModel
fetchVisibleRosterStaffPanelRenderModel panelScope rosterGroupId weekOffset = do
    visibleRosterWeek <- fetchVisibleRosterWeek rosterGroupId weekOffset
    rosterGroups <- profileActionSpan "roster.fragment.fetch_roster_groups" fetchViewableRosterGroups
    currentRosterGroupOrNothing <- profileActionSpan "roster.fragment.resolve_current_group" (fetchViewableRosterGroup rosterGroupId)
    accessDeniedUnless (isJust currentRosterGroupOrNothing)
    let currentRosterGroup = fromMaybe (error "authorized roster group missing") currentRosterGroupOrNothing
    assignmentFilters <- profileActionSpan "roster.fragment.fetch_assignment_filters" fetchRosterAssignmentFilters
    rosterLayoutMode <- profileActionSpan "roster.fragment.fetch_layout_preference" fetchCurrentRosterLayoutMode
    userShowWageEstimates <- profileActionSpan "roster.fragment.fetch_wage_preference" fetchCurrentUserShowWageEstimates
    showRosterWarnings <- profileActionSpan "roster.fragment.fetch_warning_preference" fetchCurrentUserShowRosterWarnings
    highlightOwnLiveShifts <- profileActionSpan "roster.fragment.fetch_own_highlight_preference" fetchCurrentUserHighlightOwnLiveShifts
    venueConfig <- profileActionSpan "roster.fragment.fetch_venue_config" fetchVenueConfig
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    (templateLibraryUserId, templateLibrary) <- fetchRosterPanelTemplateLibrary currentRosterGroup
    baseFacts <- fetchRosterBaseFactsDirect rosterGroupId weekOffset
    panelStaff <- case baseFacts of
        Nothing -> pure []
        Just facts -> do
            panelStaffMembers <- case panelScope of
                RosterStaffPanelCurrentGroup -> pure facts.basePanelStaff
                RosterStaffPanelAllVenue     -> fetchCurrentVenueActiveStaff
            profileActionSpan "roster.build_staff_panel" (fetchRosterStaffPanelEntriesForScope panelScope panelStaffMembers facts.baseVisibleSlots)
    notificationPanelData <- fetchRosterPanelNotificationData currentRosterGroup visibleRosterWeek
    pure RosterStaffPanelRenderModel
        { staffPanelRosterWeek = visibleRosterWeek
        , staffPanelWeekOffset = weekOffset
        , staffPanelWeekStartDate = weekStartDate
        , staffPanelRosterGroups = rosterGroups
        , staffPanelCurrentRosterGroup = currentRosterGroup
        , staffPanelAssignmentFilters = assignmentFilters
        , staffPanelViewCapabilities = buildRosterViewCapabilities visibleRosterWeek
        , staffPanelRosterLayoutMode = rosterLayoutMode
        , staffPanelShowWageEstimates = shouldShowRosterWageEstimates userShowWageEstimates
        , staffPanelShowRosterWarnings = showRosterWarnings
        , staffPanelHighlightOwnLiveShifts = highlightOwnLiveShifts
        , staffPanelViewMode = currentRosterGridViewMode
        , staffPanelScope = panelScope
        , staffPanelEntries = panelStaff
        , staffPanelTemplateLibrary = templateLibrary
        , staffPanelTemplateUserId = templateLibraryUserId
        , staffPanelNotificationPanelData = notificationPanelData
        }

renderRequestedRow :: (?context :: ControllerContext, ?request :: Request) => Calendar.Day -> [RosterWindowLane] -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> (UUID.UUID, Int) -> Maybe Blaze.Html
renderRequestedRow weekStartDate orderedSlotNames assignmentFilters staffMembers shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayUuid, targetRowIndex) = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    dayRows <- Map.lookup rosterDayUuid renderIndexes.rosterDayRowsByDayId
    let rowCount = length dayRows
    let lastRowIndex = lastRowIndexForRows dayRows
    let indexedRows = zip [0 :: Int ..] dayRows
    (rowPosition, (_, rowSlots)) <- find (\(_, (rowIndex, _)) -> rowIndex == targetRowIndex) indexedRows
    let date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) weekStartDate
    pure (renderRowOob RosterRowRenderModel { rowIsEditable = True, rowSlotNames = orderedSlotNames, rowAssignmentFilters = assignmentFilters, rowStaffMembers = staffMembers, rowShiftTypes = shiftTypes, rowDate = date, rowRosterDay = rosterDay, rowCount, rowLastRowIndex = lastRowIndex, rowRenderIndexes = renderIndexes, rowRosterLayoutMode = rosterLayoutMode, rowRosterEndTimesEnabled = rosterEndTimesEnabled, rowPublishAttempted = False } (rowPosition, (targetRowIndex, rowSlots)))

renderRequestedRowFragment :: (?context :: ControllerContext, ?request :: Request) => Bool -> Calendar.Day -> [RosterWindowLane] -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> (UUID.UUID, Int) -> Maybe Blaze.Html
renderRequestedRowFragment isEditable weekStartDate orderedSlotNames assignmentFilters staffMembers shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayUuid, targetRowIndex) = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    dayRows <- Map.lookup rosterDayUuid renderIndexes.rosterDayRowsByDayId
    let rowCount = length dayRows
    let lastRowIndex = lastRowIndexForRows dayRows
    let indexedRows = zip [0 :: Int ..] dayRows
    (rowPosition, (_, rowSlots)) <- find (\(_, (rowIndex, _)) -> rowIndex == targetRowIndex) indexedRows
    let date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) weekStartDate
    pure (renderRowFragment RosterRowRenderModel { rowIsEditable = isEditable, rowSlotNames = orderedSlotNames, rowAssignmentFilters = assignmentFilters, rowStaffMembers = staffMembers, rowShiftTypes = shiftTypes, rowDate = date, rowRosterDay = rosterDay, rowCount, rowLastRowIndex = lastRowIndex, rowRenderIndexes = renderIndexes, rowRosterLayoutMode = rosterLayoutMode, rowRosterEndTimesEnabled = rosterEndTimesEnabled, rowPublishAttempted = False } (rowPosition, (targetRowIndex, rowSlots)))

renderRequestedDaySection :: (?context :: ControllerContext, ?request :: Request) => Calendar.Day -> [RosterWindowLane] -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> Maybe RosterWagePrediction -> Bool -> Bool -> Map.Map Calendar.Day Text -> UUID.UUID -> Maybe Blaze.Html
renderRequestedDaySection weekStartDate orderedSlotNames assignmentFilters staffMembers shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayUuid = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    pure (renderRosterDaySectionFragment RosterDayRenderModel { dayIsEditable = True, daySlotNames = orderedSlotNames, dayAssignmentFilters = assignmentFilters, dayStaffMembers = staffMembers, dayShiftTypes = shiftTypes, dayWeekStartDate = weekStartDate, dayTimelineContext = Nothing, dayAllSlots = allSlots, daySlotConflicts = slotConflicts, dayRenderIndexes = renderIndexes, dayRosterLayoutMode = rosterLayoutMode, dayRosterEndTimesEnabled = rosterEndTimesEnabled, dayRosterWagePrediction = rosterWagePrediction, dayShowWageEstimates = showWageEstimates, dayShowRosterWarnings = showRosterWarnings, dayPublicHolidays = rosterPublicHolidays, dayPublishAttempted = False } rosterDay)

renderRequestedDaySectionFragment :: (?context :: ControllerContext, ?request :: Request) => Bool -> Calendar.Day -> [RosterWindowLane] -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> Maybe RosterWagePrediction -> Bool -> Bool -> Map.Map Calendar.Day Text -> UUID.UUID -> Maybe Blaze.Html
renderRequestedDaySectionFragment isEditable weekStartDate orderedSlotNames assignmentFilters staffMembers shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayUuid = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    pure (renderRosterDaySectionFragment RosterDayRenderModel { dayIsEditable = isEditable, daySlotNames = orderedSlotNames, dayAssignmentFilters = assignmentFilters, dayStaffMembers = staffMembers, dayShiftTypes = shiftTypes, dayWeekStartDate = weekStartDate, dayTimelineContext = Nothing, dayAllSlots = allSlots, daySlotConflicts = slotConflicts, dayRenderIndexes = renderIndexes, dayRosterLayoutMode = rosterLayoutMode, dayRosterEndTimesEnabled = rosterEndTimesEnabled, dayRosterWagePrediction = rosterWagePrediction, dayShowWageEstimates = showWageEstimates, dayShowRosterWarnings = showRosterWarnings, dayPublicHolidays = rosterPublicHolidays, dayPublishAttempted = False } rosterDay)

fetchCurrentVenueRosterShiftTypes :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueRosterShiftTypes =
    fetchVenueShiftTypes currentVenueId
