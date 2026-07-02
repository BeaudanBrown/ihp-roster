{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.RosterWeeks.RenderData
    ( RosterReadModelBackend (..)
    , currentRosterReadModelBackend
    , fetchVisibleRosterReadModelDirect
    , fetchVisibleRosterReadModel
    , renderVisibleRosterReadModelFragment
    , fetchVisibleRosterRenderDataCached
    , renderVisibleRosterProjectionFragment
    , renderRosterProjectionFragment
    , renderRosterProjectionFragmentWithMode
    , renderRosterContentFromProjection
    , renderRosterStaffPanelFromProjection
    , renderRequestedRowFragmentFromProjection
    , renderRequestedDaySectionFragmentFromProjection
    , fetchRosterRenderData
    , fetchVisibleRosterRenderData
    , fetchVisibleRosterWeek
    , buildRosterRenderIndexes
    , fetchVisibleRosterStaffPanelEntries
    , fetchVisibleRosterRowFragment
    , fetchVisibleRosterDaySectionFragment
    , keepCurrentRosterWeekProjectionHot
    , fetchHiddenRosterRenderData
    , fetchHiddenRosterWeekSkeleton
    , maskRosterSlots
    , renderRequestedRow
    , renderRequestedRowFragment
    , renderRequestedDaySection
    , renderRequestedDaySectionFragment
    )
where

import Application.Helper.Conflict
import Application.Helper.Controller
import Application.Helper.LiveSurface (FragmentRenderMode (..))
import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Application.Helper.RosterWagePrediction
import Application.Helper.UserPreferences
import Data.Coerce (coerce)
import Data.List (find, nubBy)
import qualified Data.Map.Strict as Map
import Data.Maybe (isNothing)
import qualified Data.Time.Calendar as Calendar
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.RosterWeeks.Capabilities
import Web.RosterWeeks.Conflicts
import Web.RosterWeeks.DirectReadModel
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Filters
import Web.RosterWeeks.Projection
import Web.RosterWeeks.Rows
import Web.RosterWeeks.Service
import Web.RosterWeeks.StaffOptions
import Web.RosterWeeks.Types
import Web.View.RosterWeeks.Grid
import Web.View.RosterWeeks.StaffPanel

-- One compile-time seam for the roster SQL/direct read-model trial. The
-- branch default is direct; projection rollback is this constructor selection.
data RosterReadModelBackend
    = ProjectionRosterReadModel
    | DirectRosterReadModel
    deriving (Eq, Show)

currentRosterReadModelBackend :: RosterReadModelBackend
currentRosterReadModelBackend = DirectRosterReadModel

shouldShowRosterWageEstimates :: (?context :: ControllerContext) => Bool -> Bool
shouldShowRosterWageEstimates userShowWageEstimates =
    hasRole VenueAdminRole && userShowWageEstimates

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

fetchVisibleRosterReadModel :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterRenderData)
fetchVisibleRosterReadModel rosterGroupId weekOffset =
    profileActionSpan "roster.read_model.fetch_visible" do
        case currentRosterReadModelBackend of
            ProjectionRosterReadModel -> fetchVisibleRosterRenderDataCached rosterGroupId weekOffset
            DirectRosterReadModel -> fetchVisibleRosterReadModelDirect rosterGroupId weekOffset

renderVisibleRosterReadModelFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> RosterProjectionFragment -> IO (Maybe Blaze.Html)
renderVisibleRosterReadModelFragment rosterGroupId weekOffset fragment =
    profileActionSpan "roster.read_model.render_fragment" do
        case currentRosterReadModelBackend of
            ProjectionRosterReadModel -> renderVisibleRosterProjectionFragment rosterGroupId weekOffset fragment
            DirectRosterReadModel ->
                case fragment of
                    RosterProjectionContent -> do
                        rosterGroups <- profileActionSpan "roster.fragment.fetch_roster_groups" fetchCurrentVenueRosterGroups
                        currentRosterGroup <- profileActionSpan "roster.fragment.resolve_current_group" (fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId))
                        rosterData <- fetchVisibleRosterReadModelDirect rosterGroupId weekOffset
                        Just <$> renderRosterContentFromProjection rosterGroups currentRosterGroup rosterData
                    RosterProjectionGridToolbar -> renderVisibleRosterReadModelFragmentDirect rosterGroupId weekOffset fragment
                    RosterProjectionGridFrame -> renderVisibleRosterReadModelFragmentDirect rosterGroupId weekOffset fragment
                    _ -> renderVisibleRosterReadModelFragmentDirect rosterGroupId weekOffset fragment

fetchVisibleRosterRenderDataCached :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterRenderData)
fetchVisibleRosterRenderDataCached rosterGroupId weekOffset =
    profileActionSpan "roster.direct_read_model.load_legacy_alias" do
        fetchVisibleRosterReadModelDirect rosterGroupId weekOffset

renderVisibleRosterProjectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> RosterProjectionFragment -> IO (Maybe Blaze.Html)
renderVisibleRosterProjectionFragment rosterGroupId weekOffset fragment =
    profileActionSpan "roster.direct_read_model.render_legacy_alias" do
        case fragment of
            RosterProjectionContent -> do
                rosterGroups <- fetchCurrentVenueRosterGroups
                currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
                rosterData <- fetchVisibleRosterRenderDataCached rosterGroupId weekOffset
                Just <$> renderRosterContentFromProjection rosterGroups currentRosterGroup rosterData
            _ -> renderVisibleRosterReadModelFragmentDirect rosterGroupId weekOffset fragment

renderRosterProjectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe RosterRenderData -> RosterProjectionFragment -> Maybe Blaze.Html
renderRosterProjectionFragment =
    renderRosterProjectionFragmentWithMode FragmentPlain

renderRosterProjectionFragmentWithMode :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => FragmentRenderMode -> Maybe RosterRenderData -> RosterProjectionFragment -> Maybe Blaze.Html
renderRosterProjectionFragmentWithMode renderMode rosterData fragment =
    case fragment of
        RosterProjectionContent ->
            Nothing
        RosterProjectionGridToolbar ->
            renderGridFragment renderRosterGridToolbarFragment renderRosterGridToolbarFragmentWithSwap rosterData
        RosterProjectionGridFrame ->
            renderGridFragment renderRosterGridFrameFragment renderRosterGridFrameFragmentWithSwap rosterData
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
            let gridModel = rosterGridRenderModelFromProjection viewCapabilities projection
            pure $ case renderMode of
                FragmentPlain        -> plainRenderer gridModel
                FragmentOob swapAttr -> swapRenderer swapAttr gridModel
        renderDayColumnsFragment maybeRosterData = do
            projection <- maybeRosterData
            let dayModel = rosterDayRenderModelFromProjection projection
            if isHiddenDraftForCurrentUser projection.rosterWeek
                then Nothing
                else pure $ case renderMode of
                    FragmentPlain -> renderRosterDayColumnsFragment dayModel projection.rosterDays
                    FragmentOob swapAttr -> renderRosterDayColumnsFragmentWithSwap swapAttr dayModel projection.rosterDays
        renderDayRailFragment maybeRosterData = do
            projection <- maybeRosterData
            let visibleRosterWeek = visibleRosterWeekForCurrentUser projection.rosterWeek
            let viewCapabilities = buildRosterViewCapabilities visibleRosterWeek
            let dayModel = rosterDayRenderModelFromProjection projection
            pure $ case renderMode of
                FragmentPlain ->
                    if isNothing visibleRosterWeek
                        then renderHiddenDraftDayRailFragmentWithSwap Nothing dayModel projection.rosterDays
                        else renderRosterDayRailFragment viewCapabilities.canManageRosterColumns dayModel projection.rosterDays
                FragmentOob swapAttr ->
                    if isNothing visibleRosterWeek
                        then renderHiddenDraftDayRailFragmentWithSwap swapAttr dayModel projection.rosterDays
                        else renderRosterDayRailFragmentWithSwap swapAttr viewCapabilities.canManageRosterColumns dayModel projection.rosterDays
        renderWageRailFragment maybeRosterData = do
            projection <- maybeRosterData
            let dayModel = rosterDayRenderModelFromProjection projection
            pure $ case renderMode of
                FragmentPlain -> renderRosterWageRailFragment dayModel projection.rosterDays
                FragmentOob swapAttr -> renderRosterWageRailFragmentWithSwap swapAttr dayModel projection.rosterDays
        renderSlotsGridFragment maybeRosterData = do
            projection <- maybeRosterData
            let visibleRosterWeek = visibleRosterWeekForCurrentUser projection.rosterWeek
            let viewCapabilities = buildRosterViewCapabilities visibleRosterWeek
            let dayModel = rosterDayRenderModelFromProjection projection
            pure $ case renderMode of
                FragmentPlain ->
                    if isNothing visibleRosterWeek
                        then renderHiddenDraftSlotsGridFragmentWithSwap Nothing projection.rosterDays
                        else renderRosterSlotsGridFragment projection.rosterEndTimesEnabled viewCapabilities.canManageRosterColumns visibleRosterWeek projection.orderedSlotNames dayModel projection.rosterDays
                FragmentOob swapAttr ->
                    if isNothing visibleRosterWeek
                        then renderHiddenDraftSlotsGridFragmentWithSwap swapAttr projection.rosterDays
                        else renderRosterSlotsGridFragmentWithSwap swapAttr projection.rosterEndTimesEnabled viewCapabilities.canManageRosterColumns visibleRosterWeek projection.orderedSlotNames dayModel projection.rosterDays

renderRosterContentFromProjection :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => [RosterGroup] -> RosterGroup -> Maybe RosterRenderData -> IO Blaze.Html
renderRosterContentFromProjection rosterGroups currentRosterGroup rosterData =
    case rosterData of
        Nothing -> pure [hsx|<div id="roster-content"></div>|]
        Just projection -> do
            let viewCapabilities = buildRosterViewCapabilities (visibleRosterWeekForCurrentUser projection.rosterWeek)
            pure $ renderRosterContentFragment (rosterGridRenderModelFromProjectionWithGroups rosterGroups currentRosterGroup viewCapabilities projection)

rosterGridRenderModelFromProjection :: (?context :: ControllerContext) => RosterViewCapabilities -> RosterRenderData -> RosterGridRenderModel
rosterGridRenderModelFromProjection viewCapabilities projection@RosterRenderData { rosterGroups, currentRosterGroup } =
    rosterGridRenderModelFromProjectionWithGroups rosterGroups currentRosterGroup viewCapabilities projection

rosterGridRenderModelFromProjectionWithGroups :: (?context :: ControllerContext) => [RosterGroup] -> RosterGroup -> RosterViewCapabilities -> RosterRenderData -> RosterGridRenderModel
rosterGridRenderModelFromProjectionWithGroups rosterGroups currentRosterGroup viewCapabilities RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, panelStaff, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays } =
    RosterGridRenderModel
        { gridRosterWeek = visibleRosterWeekForCurrentUser rosterWeek
        , gridRosterDays = rosterDays
        , gridWeekOffset = rosterWeek.weekOffset
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

visibleRosterWeekForCurrentUser :: (?context :: ControllerContext) => RosterWeek -> Maybe RosterWeek
visibleRosterWeekForCurrentUser rosterWeek
    | rosterWeek.isLive || hasRole ManagerRole' = Just rosterWeek
    | otherwise = Nothing

isHiddenDraftForCurrentUser :: (?context :: ControllerContext) => RosterWeek -> Bool
isHiddenDraftForCurrentUser rosterWeek = isNothing (visibleRosterWeekForCurrentUser rosterWeek)

rosterDayRenderModelFromProjection :: (?context :: ControllerContext) => RosterRenderData -> RosterDayRenderModel
rosterDayRenderModelFromProjection RosterRenderData { rosterWeek, weekStartDate, assignmentFilters, staffMembers, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays } =
    RosterDayRenderModel
        { dayIsEditable = hasRole ManagerRole' && not rosterWeek.isLive
        , daySlotNames = orderedSlotNames
        , dayAssignmentFilters = assignmentFilters
        , dayStaffMembers = staffMembers
        , dayShiftTypes = shiftTypes
        , dayWeekStartDate = weekStartDate
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

renderRosterStaffPanelFromProjection :: (?context :: ControllerContext, ?request :: Request) => Maybe RosterRenderData -> Blaze.Html
renderRosterStaffPanelFromProjection =
    renderRosterStaffPanelFromProjectionWithMode FragmentPlain

renderRosterStaffPanelFromProjectionWithMode :: (?context :: ControllerContext, ?request :: Request) => FragmentRenderMode -> Maybe RosterRenderData -> Blaze.Html
renderRosterStaffPanelFromProjectionWithMode renderMode rosterData =
    case rosterData of
        Nothing -> mempty
        Just RosterRenderData { rosterWeek, rosterGroups, panelStaff } ->
            let hasMultipleRosterGroups = length rosterGroups > 1
             in case renderMode of
                    FragmentPlain -> renderRosterStaffPanelFragment rosterWeek.weekOffset (coerce rosterWeek.rosterGroupId) hasMultipleRosterGroups RosterStaffPanelCurrentGroup panelStaff
                    FragmentOob swapAttr -> renderRosterStaffPanelFragmentWithSwap swapAttr rosterWeek.weekOffset (coerce rosterWeek.rosterGroupId) hasMultipleRosterGroups RosterStaffPanelCurrentGroup panelStaff

renderRequestedRowFragmentFromProjection :: (?context :: ControllerContext, ?request :: Request) => RosterRenderData -> UUID.UUID -> Int -> Maybe Blaze.Html
renderRequestedRowFragmentFromProjection =
    renderRequestedRowFragmentFromProjectionWithMode FragmentPlain

renderRequestedRowFragmentFromProjectionWithMode :: (?context :: ControllerContext, ?request :: Request) => FragmentRenderMode -> RosterRenderData -> UUID.UUID -> Int -> Maybe Blaze.Html
renderRequestedRowFragmentFromProjectionWithMode renderMode RosterRenderData { rosterWeek, weekStartDate, assignmentFilters, staffMembers, orderedSlotNames, shiftTypes, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled } rosterDayId rowIndex =
    case renderMode of
        FragmentPlain -> renderRequestedRowFragment (hasRole ManagerRole' && not rosterWeek.isLive) weekStartDate orderedSlotNames assignmentFilters staffMembers shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayId, rowIndex)
        FragmentOob _ -> renderRequestedRow weekStartDate orderedSlotNames assignmentFilters staffMembers shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayId, rowIndex)

renderRequestedDaySectionFragmentFromProjection :: (?context :: ControllerContext, ?request :: Request) => RosterRenderData -> UUID.UUID -> Maybe Blaze.Html
renderRequestedDaySectionFragmentFromProjection =
    renderRequestedDaySectionFragmentFromProjectionWithMode FragmentPlain

renderRequestedDaySectionFragmentFromProjectionWithMode :: (?context :: ControllerContext, ?request :: Request) => FragmentRenderMode -> RosterRenderData -> UUID.UUID -> Maybe Blaze.Html
renderRequestedDaySectionFragmentFromProjectionWithMode renderMode RosterRenderData { rosterWeek, weekStartDate, assignmentFilters, staffMembers, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays } rosterDayId =
    case renderMode of
        FragmentPlain -> renderRequestedDaySectionFragment (hasRole ManagerRole' && not rosterWeek.isLive) weekStartDate orderedSlotNames assignmentFilters staffMembers shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayId
        FragmentOob _ -> renderRequestedDaySection weekStartDate orderedSlotNames assignmentFilters staffMembers shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayId

fetchVisibleRosterReadModelDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterRenderData)
fetchVisibleRosterReadModelDirect rosterGroupId weekOffset = do
    visibleRosterWeek <- profileActionSpan "roster.direct.fetch_visible_week" (fetchVisibleRosterWeek rosterGroupId weekOffset)
    rosterGroups <- profileActionSpan "roster.direct.fetch_roster_groups" fetchCurrentVenueRosterGroups
    currentRosterGroup <- profileActionSpan "roster.direct.resolve_current_group" (fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId))
    case visibleRosterWeek of
        Nothing -> do
            (backingRosterWeek, rosterDays, weekStartDate, orderedSlotNames, shiftTypes, maskedSlots) <- fetchHiddenRosterRenderDataDirect rosterGroupId weekOffset
            rosterLayoutMode <- fetchCurrentRosterLayoutMode
            userShowWageEstimates <- fetchCurrentUserShowWageEstimates
            showRosterWarnings <- fetchCurrentUserShowRosterWarnings
            venueConfig <- fetchVenueConfig
            let showWageEstimates = shouldShowRosterWageEstimates userShowWageEstimates
            rosterPublicHolidays <- fetchRosterPublicHolidayMap venueConfig weekStartDate
            staffSelfServicePanel <- profileActionSpan "roster.build_staff_self_service_panel" (fetchRosterStaffSelfServicePanel venueConfig)
            let renderIndexes = buildRosterRenderIndexes rosterDays (filterVisibleRosterSlots rosterDays maskedSlots) [] []
            pure $
                Just
                    RosterRenderData
                        { rosterWeek = backingRosterWeek
                        , rosterGroups = rosterGroups
                        , currentRosterGroup = currentRosterGroup
                        , rosterDays
                        , weekStartDate
                        , assignmentFilters = defaultRosterAssignmentFilters
                        , staffMembers = []
                        , panelStaff = []
                        , staffSelfServicePanel
                        , orderedSlotNames
                        , shiftTypes
                        , allSlots = maskedSlots
                        , slotConflicts = []
                        , renderIndexes
                        , rosterLayoutMode
                        , rosterEndTimesEnabled = venueConfig.rosterEndTimesEnabled
                        , rosterWagePrediction = Nothing
                        , showWageEstimates
                        , showRosterWarnings
                        , rosterPublicHolidays
                        }
        Just _  -> fetchRosterRenderDataDirect rosterGroupId weekOffset

fetchRosterRenderDataDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterRenderData)
fetchRosterRenderDataDirect rosterGroupId weekOffset = do
    venueConfig <- profileActionSpan "roster.direct.fetch_venue_config" fetchVenueConfig
    rosterGroups <- profileActionSpan "roster.direct.fetch_roster_groups" fetchCurrentVenueRosterGroups
    currentRosterGroup <- profileActionSpan "roster.direct.resolve_current_group" (fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId))
    assignmentFilters <- profileActionSpan "roster.direct.fetch_assignment_filters" fetchRosterAssignmentFilters
    rosterLayoutMode <- profileActionSpan "roster.direct.fetch_layout_preference" fetchCurrentRosterLayoutMode
    userShowWageEstimates <- profileActionSpan "roster.direct.fetch_wage_preference" fetchCurrentUserShowWageEstimates
    showRosterWarnings <- profileActionSpan "roster.direct.fetch_warning_preference" fetchCurrentUserShowRosterWarnings
    let showWageEstimates = shouldShowRosterWageEstimates userShowWageEstimates
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    rosterPublicHolidays <- profileActionSpan "roster.direct.fetch_public_holidays" (fetchRosterPublicHolidayMap venueConfig weekStartDate)

    baseFactsOrNothing <- profileActionSpan "roster.direct.fetch_base_facts" (fetchRosterBaseFactsDirect rosterGroupId weekOffset)
    case baseFactsOrNothing of
        Nothing -> pure Nothing
        Just RosterBaseFacts { baseRosterWeek = rosterWeek, baseRosterDays = rosterDays, baseAllSlots = allSlots, baseVisibleSlots = visibleSlots, baseOrderedSlotDefinitions = orderedSlotNames, baseShiftTypes = shiftTypes, baseEligibleStaff = eligibleStaffMembers, baseStaffMembers = staffMembers } -> do
            panelStaff <- profileActionSpan "roster.build_staff_panel" (fetchRosterStaffPanelEntries eligibleStaffMembers visibleSlots)
            staffSelfServicePanel <- profileActionSpan "roster.build_staff_self_service_panel" (fetchRosterStaffSelfServicePanel venueConfig)
            slotConflicts <-
                if rosterWeek.isLive
                    then pure []
                    else profileActionSpan "roster.direct.build_slot_conflicts" (buildSlotConflictsDirect rosterGroupId venueConfig.lateToEarlyMinStartGapMinutes weekStartDate visibleSlots)
            let renderIndexes = buildRosterRenderIndexes rosterDays visibleSlots staffMembers slotConflicts
            rosterWagePrediction <-
                if showWageEstimates
                    then Just <$> profileActionSpan "roster.predict_wages" (fetchRosterWagePrediction venueConfig rosterWeek rosterDays visibleSlots)
                    else pure Nothing
            pure (Just RosterRenderData { rosterWeek, rosterGroups, currentRosterGroup, rosterDays, weekStartDate, assignmentFilters, staffMembers, panelStaff, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled = venueConfig.rosterEndTimesEnabled, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays })

fetchRosterRenderData :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterRenderData)
fetchRosterRenderData rosterGroupId weekOffset = do
    _ <- profileActionSpan "roster.ensure_week_exists" (ensureRosterWeekExists rosterGroupId weekOffset)
    venueConfig <- fetchVenueConfig
    rosterGroups <- fetchCurrentVenueRosterGroups
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
    assignmentFilters <- fetchRosterAssignmentFilters
    rosterLayoutMode <- fetchCurrentRosterLayoutMode
    userShowWageEstimates <- fetchCurrentUserShowWageEstimates
    showRosterWarnings <- fetchCurrentUserShowRosterWarnings
    let showWageEstimates = shouldShowRosterWageEstimates userShowWageEstimates
    let weekStartDate = venueWeekStartDate venueConfig weekOffset
    rosterPublicHolidays <- fetchRosterPublicHolidayMap venueConfig weekStartDate

    rosterWeekOrNothing <- query @RosterWeek
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
        |> filterWhere (#weekOffset, weekOffset)
        |> fetchOneOrNothing

    case rosterWeekOrNothing of
        Nothing -> pure Nothing
        Just rosterWeek -> do
            rosterDays <- query @RosterDay
                |> filterWhere (#rosterWeekId, coerce (get #id rosterWeek))
                |> orderBy #dayOffset
                |> fetch

            allSlots <- query @RosterSlot
                |> filterWhereIn (#rosterDayId, map (coerce . (.id)) rosterDays)
                |> filterWhere (#deletedAt, Nothing)
                |> fetch

            let visibleSlots = filterVisibleRosterSlots rosterDays allSlots
            eligibleStaffMembers <- profileActionSpan "roster.fetch_eligible_staff" (fetchEligibleRosterGroupStaff rosterGroupId)
            assignedStaffMembers <- profileActionSpan "roster.fetch_assigned_staff" (fetchAssignedRosterWeekStaff visibleSlots)
            let staffMembers = nubBy (\left right -> left.id == right.id) (eligibleStaffMembers <> assignedStaffMembers)
            shiftTypes <- profileActionSpan "roster.fetch_shift_types" fetchCurrentVenueRosterShiftTypes
            panelStaff <- profileActionSpan "roster.build_staff_panel" (fetchRosterStaffPanelEntries eligibleStaffMembers visibleSlots)
            staffSelfServicePanel <- profileActionSpan "roster.build_staff_self_service_panel" (fetchRosterStaffSelfServicePanel venueConfig)
            orderedSlotNames <- profileActionSpan "roster.fetch_ordered_slot_names" (fetchRosterWeekOrderedSlotNames rosterWeek)
            slotConflicts <-
                if rosterWeek.isLive
                    then pure []
                    else profileActionSpan "roster.build_slot_conflicts" (buildSlotConflicts rosterGroupId venueConfig.lateToEarlyMinStartGapMinutes weekStartDate rosterDays visibleSlots staffMembers)
            let renderIndexes = buildRosterRenderIndexes rosterDays visibleSlots staffMembers slotConflicts
            rosterWagePrediction <-
                if showWageEstimates
                    then Just <$> profileActionSpan "roster.predict_wages" (fetchRosterWagePrediction venueConfig rosterWeek rosterDays visibleSlots)
                    else pure Nothing
            pure (Just RosterRenderData { rosterWeek, rosterGroups, currentRosterGroup, rosterDays, weekStartDate, assignmentFilters, staffMembers, panelStaff, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled = venueConfig.rosterEndTimesEnabled, rosterWagePrediction, showWageEstimates, showRosterWarnings, rosterPublicHolidays })

fetchRosterStaffSelfServicePanel :: (?context :: ControllerContext, ?modelContext :: ModelContext) => VenueConfig -> IO (Maybe RosterStaffSelfServicePanel)
fetchRosterStaffSelfServicePanel venueConfig
    | hasRole ManagerRole' = pure Nothing
    | currentUserIsSuperAdmin = pure Nothing
    | otherwise = do
        maybeStaff <- fetchCurrentUserStaff
        case maybeStaff of
            Nothing -> pure Nothing
            Just staff -> do
                operationalDay <- currentOperationalDayForVenue venueConfig
                let timesheetWeekOffset = venueWeekOffsetForDay venueConfig operationalDay
                let timesheetWeekStartDate = venueWeekStartDate venueConfig timesheetWeekOffset
                quickToolsTimesheetEntries <-
                    query @TimesheetEntry
                        |> filterWhere (#venueId, unpackId currentVenueId)
                        |> filterWhere (#staffId, unpackId staff.id)
                        |> filterWhere (#workedOn, operationalDay)
                        |> filterWhere (#deletedAt, Nothing)
                        |> orderByAsc #startTime
                        |> fetch
                quickToolsShiftTypes <- fetchCurrentVenueRosterShiftTypes
                let quickToolsLeaveRequest =
                        newRecord @LeaveRequest
                            |> set #startDate operationalDay
                            |> set #endDate (Calendar.addDays 1 operationalDay)
                pure $
                    Just
                        RosterStaffSelfServicePanel
                            { quickToolsLeaveRequest
                            , quickToolsVenueId = currentVenueId
                            , quickToolsTimesheetEntries
                            , quickToolsStaffMembers = [staff]
                            , quickToolsShiftTypes
                            , quickToolsOperationalDay = operationalDay
                            , quickToolsTimesheetWeekOffset = timesheetWeekOffset
                            , quickToolsTimesheetWeekStartDate = timesheetWeekStartDate
                            , quickToolsTimesheetEditWindowDays = venueConfig.staffTimesheetEditWindowDays
                            }

fetchVisibleRosterRenderData :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterRenderData)
fetchVisibleRosterRenderData rosterGroupId weekOffset = do
    visibleRosterWeek <- fetchVisibleRosterWeek rosterGroupId weekOffset
    rosterGroups <- fetchCurrentVenueRosterGroups
    currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
    case visibleRosterWeek of
        Nothing -> do
            (backingRosterWeek, rosterDays, weekStartDate, orderedSlotNames, shiftTypes, maskedSlots) <- fetchHiddenRosterRenderData rosterGroupId weekOffset
            rosterLayoutMode <- fetchCurrentRosterLayoutMode
            userShowWageEstimates <- fetchCurrentUserShowWageEstimates
            showRosterWarnings <- fetchCurrentUserShowRosterWarnings
            venueConfig <- fetchVenueConfig
            let showWageEstimates = shouldShowRosterWageEstimates userShowWageEstimates
            rosterPublicHolidays <- fetchRosterPublicHolidayMap venueConfig weekStartDate
            staffSelfServicePanel <- profileActionSpan "roster.build_staff_self_service_panel" (fetchRosterStaffSelfServicePanel venueConfig)
            let renderIndexes = buildRosterRenderIndexes rosterDays (filterVisibleRosterSlots rosterDays maskedSlots) [] []
            pure $
                Just
                    RosterRenderData
                        { rosterWeek = backingRosterWeek
                        , rosterGroups = rosterGroups
                        , currentRosterGroup = currentRosterGroup
                        , rosterDays
                        , weekStartDate
                        , assignmentFilters = defaultRosterAssignmentFilters
                        , staffMembers = []
                        , panelStaff = []
                        , staffSelfServicePanel
                        , orderedSlotNames
                        , shiftTypes
                        , allSlots = maskedSlots
                        , slotConflicts = []
                        , renderIndexes
                        , rosterLayoutMode
                        , rosterEndTimesEnabled = venueConfig.rosterEndTimesEnabled
                        , rosterWagePrediction = Nothing
                        , showWageEstimates
                        , showRosterWarnings
                        , rosterPublicHolidays
                        }
        Just _  -> fetchRosterRenderData rosterGroupId weekOffset

fetchVisibleRosterWeek :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterWeek)
fetchVisibleRosterWeek rosterGroupId weekOffset = do
    _ <- profileActionSpan "roster.visible_week.ensure_exists" (ensureRosterWeekExists rosterGroupId weekOffset)
    rosterWeekOrNothing <-
        profileActionSpan "roster.visible_week.fetch" do
            query @RosterWeek
                |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
                |> filterWhere (#weekOffset, weekOffset)
                |> fetchOneOrNothing

    pure $
        case rosterWeekOrNothing of
            Just rosterWeek | get #isLive rosterWeek || hasRole ManagerRole' -> Just rosterWeek
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
                [ ((slot.rosterDayId, slot.rowIndex, slot.rosterWeekSlotDefinitionId), slot)
                | slot <- visibleSlots
                ]
        , rosterStaffById = Map.fromList [(coerce (get #id staff), staff) | staff <- staffMembers]
        , rosterConflictsBySlotId = Map.fromList [(coerce slotId, conflicts) | (slotId, conflicts) <- slotConflicts]
        }

renderVisibleRosterReadModelFragmentDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> RosterProjectionFragment -> IO (Maybe Blaze.Html)
renderVisibleRosterReadModelFragmentDirect rosterGroupId weekOffset fragment = do
    visibleRosterWeek <- fetchVisibleRosterWeek rosterGroupId weekOffset
    case visibleRosterWeek of
        Nothing -> do
            rosterData <- fetchVisibleRosterReadModelDirect rosterGroupId weekOffset
            pure (renderRosterProjectionFragment rosterData fragment)
        Just rosterWeek ->
            case fragment of
                RosterProjectionStaffPanel -> do
                    rosterGroups <- fetchCurrentVenueRosterGroups
                    panelStaff <- profileActionSpan "roster.build_staff_panel" (fetchRosterStaffPanelEntriesDirect RosterStaffPanelCurrentGroup rosterGroupId rosterWeek)
                    pure (Just (renderRosterStaffPanelFragment rosterWeek.weekOffset (coerce rosterWeek.rosterGroupId) (length rosterGroups > 1) RosterStaffPanelCurrentGroup panelStaff))
                RosterProjectionContent -> do
                    rosterData <- fetchVisibleRosterReadModelDirect rosterGroupId weekOffset
                    case rosterData of
                        Nothing -> pure Nothing
                        Just projection -> Just <$> renderRosterContentFromProjection projection.rosterGroups projection.currentRosterGroup rosterData
                RosterProjectionGridToolbar -> do
                    rosterData <- fetchVisibleRosterReadModelDirect rosterGroupId weekOffset
                    pure (renderRosterProjectionFragment rosterData fragment)
                RosterProjectionGridFrame -> do
                    rosterData <- fetchVisibleRosterReadModelDirect rosterGroupId weekOffset
                    pure (renderRosterProjectionFragment rosterData fragment)
                RosterProjectionDayColumns -> do
                    rosterData <- fetchVisibleRosterReadModelDirect rosterGroupId weekOffset
                    pure (renderRosterProjectionFragment rosterData fragment)
                RosterProjectionDayRail -> do
                    rosterData <- fetchVisibleRosterReadModelDirect rosterGroupId weekOffset
                    pure (renderRosterProjectionFragment rosterData fragment)
                RosterProjectionWageRail -> do
                    rosterData <- fetchVisibleRosterReadModelDirect rosterGroupId weekOffset
                    pure (renderRosterProjectionFragment rosterData fragment)
                RosterProjectionSlotsGrid -> do
                    rosterData <- fetchVisibleRosterReadModelDirect rosterGroupId weekOffset
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
                    pure (renderRequestedRowFragment (hasRole ManagerRole' && not rosterWeek.isLive) weekStartDate facts.baseOrderedSlotDefinitions assignmentFilters staffMembers facts.baseShiftTypes renderIndexes rosterLayoutMode venueConfig.rosterEndTimesEnabled (rosterDayUuid, rowIndex))
                RosterProjectionDaySection rosterDayUuid -> do
                    facts@RosterBaseFacts { baseRosterDays = rosterDays, baseVisibleSlots = visibleSlots, baseStaffMembers = staffMembers } <- fetchRosterBaseFactsForWeekDirect rosterGroupId rosterWeek
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
                    rosterWagePrediction <-
                        if showWageEstimates
                            then Just <$> profileActionSpan "roster.predict_wages" (fetchRosterWagePrediction venueConfig rosterWeek rosterDays visibleSlots)
                            else pure Nothing
                    pure (renderRequestedDaySectionFragment (hasRole ManagerRole' && not rosterWeek.isLive) weekStartDate facts.baseOrderedSlotDefinitions assignmentFilters staffMembers facts.baseShiftTypes facts.baseAllSlots slotConflicts renderIndexes rosterLayoutMode venueConfig.rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayUuid)

fetchVisibleRosterStaffPanelEntriesDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterStaffPanelScope -> Id RosterGroup -> Int -> IO (Maybe [RosterStaffPanelEntry])
fetchVisibleRosterStaffPanelEntriesDirect panelScope rosterGroupId weekOffset = do
    visibleRosterWeek <- fetchVisibleRosterWeek rosterGroupId weekOffset
    case visibleRosterWeek of
        Nothing -> pure (Just [])
        Just rosterWeek -> Just <$> profileActionSpan "roster.build_staff_panel" (fetchRosterStaffPanelEntriesDirect panelScope rosterGroupId rosterWeek)

buildDirectStaffPanel :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterBaseFacts -> IO [RosterStaffPanelEntry]
buildDirectStaffPanel RosterBaseFacts { baseEligibleStaff = eligibleStaffMembers, baseVisibleSlots = visibleSlots } =
    profileActionSpan "roster.build_staff_panel" (fetchRosterStaffPanelEntries eligibleStaffMembers visibleSlots)

fetchVisibleRosterStaffPanelEntries :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterStaffPanelScope -> Id RosterGroup -> Int -> IO (Maybe [RosterStaffPanelEntry])
fetchVisibleRosterStaffPanelEntries panelScope rosterGroupId weekOffset =
    fetchVisibleRosterStaffPanelEntriesDirect panelScope rosterGroupId weekOffset

fetchVisibleRosterRowFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Id RosterDay -> Int -> IO (Maybe Blaze.Html)
fetchVisibleRosterRowFragment rosterGroupId weekOffset rosterDayId rowIndex = do
    renderVisibleRosterReadModelFragment rosterGroupId weekOffset (RosterProjectionRow (unpackId rosterDayId) rowIndex)

fetchVisibleRosterDaySectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Id RosterDay -> IO (Maybe Blaze.Html)
fetchVisibleRosterDaySectionFragment rosterGroupId weekOffset rosterDayId = do
    renderVisibleRosterReadModelFragment rosterGroupId weekOffset (RosterProjectionDaySection (unpackId rosterDayId))

keepCurrentRosterWeekProjectionHot :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ()
keepCurrentRosterWeekProjectionHot _ _ =
    pure ()

fetchHiddenRosterRenderDataDirect :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (RosterWeek, [RosterDay], Calendar.Day, [RosterWeekSlotDefinition], [ShiftType], [RosterSlot])
fetchHiddenRosterRenderDataDirect =
    fetchHiddenRosterRenderDataWith fetchRosterRenderDataDirect

fetchHiddenRosterRenderData :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (RosterWeek, [RosterDay], Calendar.Day, [RosterWeekSlotDefinition], [ShiftType], [RosterSlot])
fetchHiddenRosterRenderData =
    fetchHiddenRosterRenderDataWith fetchRosterRenderData

fetchHiddenRosterRenderDataWith :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => (Id RosterGroup -> Int -> IO (Maybe RosterRenderData)) -> Id RosterGroup -> Int -> IO (RosterWeek, [RosterDay], Calendar.Day, [RosterWeekSlotDefinition], [ShiftType], [RosterSlot])
fetchHiddenRosterRenderDataWith fetchRenderData rosterGroupId weekOffset = do
    rosterDataOrNothing <- fetchRenderData rosterGroupId weekOffset
    case rosterDataOrNothing of
        Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, orderedSlotNames, shiftTypes, allSlots } ->
            pure (rosterWeek, rosterDays, weekStartDate, orderedSlotNames, shiftTypes, maskRosterSlots rosterWeek allSlots)
        Nothing -> error "Roster week should exist after ensureRosterWeekExists"

fetchHiddenRosterWeekSkeleton :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (RosterWeek, [RosterDay], [RosterWeekSlotDefinition], [RosterSlot])
fetchHiddenRosterWeekSkeleton rosterGroupId weekOffset = do
    (rosterWeek, rosterDays, _, orderedSlotNames, _, maskedSlots) <- fetchHiddenRosterRenderData rosterGroupId weekOffset
    pure (rosterWeek, rosterDays, orderedSlotNames, maskedSlots)

maskRosterSlots :: (?context :: ControllerContext) => RosterWeek -> [RosterSlot] -> [RosterSlot]
maskRosterSlots rosterWeek slots =
    if get #isLive rosterWeek || hasRole ManagerRole'
        then slots
        else map maskSlot slots
    where
        maskSlot slot =
            slot
                |> set #staffId Nothing
                |> set #startTime Nothing
                |> set #endTime Nothing
                |> set #shiftTypeId Nothing
                |> set #durationMinutes Nothing

renderRequestedRow :: (?context :: ControllerContext, ?request :: Request) => Calendar.Day -> [RosterWeekSlotDefinition] -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> (UUID.UUID, Int) -> Maybe Blaze.Html
renderRequestedRow weekStartDate orderedSlotNames assignmentFilters staffMembers shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayUuid, targetRowIndex) = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    dayRows <- Map.lookup rosterDayUuid renderIndexes.rosterDayRowsByDayId
    let rowCount = length dayRows
    let lastRowIndex = lastRowIndexForRows dayRows
    let indexedRows = zip [0 :: Int ..] dayRows
    (rowPosition, (_, rowSlots)) <- find (\(_, (rowIndex, _)) -> rowIndex == targetRowIndex) indexedRows
    let date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) weekStartDate
    pure (renderRowOob RosterRowRenderModel { rowIsEditable = True, rowSlotNames = orderedSlotNames, rowAssignmentFilters = assignmentFilters, rowStaffMembers = staffMembers, rowShiftTypes = shiftTypes, rowDate = date, rowRosterDay = rosterDay, rowCount, rowLastRowIndex = lastRowIndex, rowRenderIndexes = renderIndexes, rowRosterLayoutMode = rosterLayoutMode, rowRosterEndTimesEnabled = rosterEndTimesEnabled, rowPublishAttempted = False } (rowPosition, (targetRowIndex, rowSlots)))

renderRequestedRowFragment :: (?context :: ControllerContext, ?request :: Request) => Bool -> Calendar.Day -> [RosterWeekSlotDefinition] -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> (UUID.UUID, Int) -> Maybe Blaze.Html
renderRequestedRowFragment isEditable weekStartDate orderedSlotNames assignmentFilters staffMembers shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayUuid, targetRowIndex) = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    dayRows <- Map.lookup rosterDayUuid renderIndexes.rosterDayRowsByDayId
    let rowCount = length dayRows
    let lastRowIndex = lastRowIndexForRows dayRows
    let indexedRows = zip [0 :: Int ..] dayRows
    (rowPosition, (_, rowSlots)) <- find (\(_, (rowIndex, _)) -> rowIndex == targetRowIndex) indexedRows
    let date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) weekStartDate
    pure (renderRowFragment RosterRowRenderModel { rowIsEditable = isEditable, rowSlotNames = orderedSlotNames, rowAssignmentFilters = assignmentFilters, rowStaffMembers = staffMembers, rowShiftTypes = shiftTypes, rowDate = date, rowRosterDay = rosterDay, rowCount, rowLastRowIndex = lastRowIndex, rowRenderIndexes = renderIndexes, rowRosterLayoutMode = rosterLayoutMode, rowRosterEndTimesEnabled = rosterEndTimesEnabled, rowPublishAttempted = False } (rowPosition, (targetRowIndex, rowSlots)))

renderRequestedDaySection :: (?context :: ControllerContext, ?request :: Request) => Calendar.Day -> [RosterWeekSlotDefinition] -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> Maybe RosterWagePrediction -> Bool -> Bool -> Map.Map Calendar.Day Text -> UUID.UUID -> Maybe Blaze.Html
renderRequestedDaySection weekStartDate orderedSlotNames assignmentFilters staffMembers shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayUuid = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    pure (renderRosterDaySectionFragment RosterDayRenderModel { dayIsEditable = True, daySlotNames = orderedSlotNames, dayAssignmentFilters = assignmentFilters, dayStaffMembers = staffMembers, dayShiftTypes = shiftTypes, dayWeekStartDate = weekStartDate, dayAllSlots = allSlots, daySlotConflicts = slotConflicts, dayRenderIndexes = renderIndexes, dayRosterLayoutMode = rosterLayoutMode, dayRosterEndTimesEnabled = rosterEndTimesEnabled, dayRosterWagePrediction = rosterWagePrediction, dayShowWageEstimates = showWageEstimates, dayShowRosterWarnings = showRosterWarnings, dayPublicHolidays = rosterPublicHolidays, dayPublishAttempted = False } rosterDay)

renderRequestedDaySectionFragment :: (?context :: ControllerContext, ?request :: Request) => Bool -> Calendar.Day -> [RosterWeekSlotDefinition] -> RosterAssignmentFilters -> [Staff] -> [ShiftType] -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> Maybe RosterWagePrediction -> Bool -> Bool -> Map.Map Calendar.Day Text -> UUID.UUID -> Maybe Blaze.Html
renderRequestedDaySectionFragment isEditable weekStartDate orderedSlotNames assignmentFilters staffMembers shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterWagePrediction showWageEstimates showRosterWarnings rosterPublicHolidays rosterDayUuid = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    pure (renderRosterDaySectionFragment RosterDayRenderModel { dayIsEditable = isEditable, daySlotNames = orderedSlotNames, dayAssignmentFilters = assignmentFilters, dayStaffMembers = staffMembers, dayShiftTypes = shiftTypes, dayWeekStartDate = weekStartDate, dayAllSlots = allSlots, daySlotConflicts = slotConflicts, dayRenderIndexes = renderIndexes, dayRosterLayoutMode = rosterLayoutMode, dayRosterEndTimesEnabled = rosterEndTimesEnabled, dayRosterWagePrediction = rosterWagePrediction, dayShowWageEstimates = showWageEstimates, dayShowRosterWarnings = showRosterWarnings, dayPublicHolidays = rosterPublicHolidays, dayPublishAttempted = False } rosterDay)

fetchCurrentVenueRosterShiftTypes :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueRosterShiftTypes =
    query @ShiftType
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch
