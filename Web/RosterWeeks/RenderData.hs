{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.RosterWeeks.RenderData
    ( rosterProjectionDefinition
    , fetchVisibleRosterRenderDataCached
    , renderVisibleRosterProjectionFragment
    , renderRosterProjectionFragment
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
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate
import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Application.Helper.SurfaceProjection
import Data.Coerce (coerce)
import Data.List (find, nubBy)
import qualified Data.Map.Strict as Map
import qualified Data.Time.Calendar as Calendar
import qualified Data.UUID as UUID
import qualified Text.Blaze.Html as Blaze
import Web.Controller.Prelude
import Web.RosterWeeks.Capabilities
import Web.RosterWeeks.Conflicts
import Web.RosterWeeks.Filters
import Web.RosterWeeks.Projection
import Web.RosterWeeks.Rows
import Web.RosterWeeks.Service
import Web.RosterWeeks.StaffOptions
import Web.RosterWeeks.Types
import Web.View.RosterWeeks.Grid
import Web.View.RosterWeeks.StaffPanel

rosterLiveSurfaceDefinition :: (?context :: ControllerContext) => LiveSurfaceDefinition RosterProjectionScope RosterProjectionFragment
rosterLiveSurfaceDefinition =
    LiveSurfaceDefinition
        { surfaceFeature = "roster"
        , surfaceScope = \scope -> buildRosterWeekScope scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset
        , surfaceDefaultFragments = const [RosterProjectionContent, RosterProjectionStaffPanel]
        , surfaceFragmentRef = \scope fragment ->
            case fragment of
                RosterProjectionContent ->
                    buildRosterContentFragmentRef scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset
                RosterProjectionStaffPanel ->
                    buildRosterStaffPanelFragmentRef scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset
                RosterProjectionDaySection rosterDayId ->
                    buildRosterDaySectionFragmentRef scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset rosterDayId
                RosterProjectionRow rosterDayId rowIndex ->
                    buildRosterRowFragmentRef scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset rosterDayId rowIndex
        , surfaceDecorateRequestsWithin = const ["#roster-week-shell"]
        }

rosterProjectionDefinition :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ProjectionLiveSurfaceDefinition RosterProjectionScope (Maybe RosterRenderData) RosterProjectionFragment
rosterProjectionDefinition =
    mkSurfaceProjectionDefinition
        rosterLiveSurfaceDefinition
        "roster-week"
        defaultSurfaceProjectionCachePolicy
        (\scope -> tshow scope.rosterProjectionGroupId <> ":" <> tshow scope.rosterProjectionWeekOffset)
        do
            filters <- fetchRosterAssignmentFilters
            pure (tshow currentUser.id <> ":" <> encodeRosterAssignmentFilters filters)
        (\scope -> currentLiveUpdateVersion (buildRosterWeekScope scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset))
        (\scope -> fetchVisibleRosterRenderData scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset)
        renderRosterProjectionFragment

fetchVisibleRosterRenderDataCached :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterRenderData)
fetchVisibleRosterRenderDataCached rosterGroupId weekOffset =
    profileActionSpanWithDetail "roster.projection.load" do
        let scope = buildRosterProjectionScope rosterGroupId weekOffset
        before <- readSurfaceProjectionCacheStats
        projection <- loadLiveSurfaceProjection rosterProjectionDefinition scope
        after <- readSurfaceProjectionCacheStats
        pure (projection, surfaceProjectionCacheDeltaDetail before after)

renderVisibleRosterProjectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> RosterProjectionFragment -> IO (Maybe Blaze.Html)
renderVisibleRosterProjectionFragment rosterGroupId weekOffset fragment =
    case fragment of
        RosterProjectionContent -> do
            rosterGroups <- fetchCurrentVenueRosterGroups
            currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
            rosterData <- fetchVisibleRosterRenderDataCached rosterGroupId weekOffset
            pure (Just (renderRosterContentFromProjection rosterGroups currentRosterGroup rosterData))
        _ ->
            profileActionSpanWithDetail "roster.projection.render_fragment" do
                let scope = buildRosterProjectionScope rosterGroupId weekOffset
                before <- readSurfaceProjectionCacheStats
                html <- renderLiveSurfaceProjectionFragment rosterProjectionDefinition scope fragment
                after <- readSurfaceProjectionCacheStats
                pure (html, surfaceProjectionCacheDeltaDetail before after)

renderRosterProjectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Maybe RosterRenderData -> RosterProjectionFragment -> Maybe Blaze.Html
renderRosterProjectionFragment rosterData fragment =
    case fragment of
        RosterProjectionContent ->
            Nothing
        RosterProjectionStaffPanel ->
            Just (renderRosterStaffPanelFromProjection rosterData)
        RosterProjectionDaySection rosterDayId ->
            rosterData >>= \projection -> renderRequestedDaySectionFragmentFromProjection projection rosterDayId
        RosterProjectionRow rosterDayId rowIndex ->
            rosterData >>= \projection -> renderRequestedRowFragmentFromProjection projection rosterDayId rowIndex

renderRosterContentFromProjection :: (?context :: ControllerContext, ?request :: Request) => [RosterGroup] -> RosterGroup -> Maybe RosterRenderData -> Blaze.Html
renderRosterContentFromProjection rosterGroups currentRosterGroup rosterData =
    case rosterData of
        Nothing -> [hsx|<div id="roster-content"></div>|]
        Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, panelStaff, orderedSlotNames, allSlots, slotConflicts, renderIndexes } ->
            let viewCapabilities = buildRosterViewCapabilities (Just rosterWeek)
             in renderRosterContentFragment
                    RosterGridRenderModel
                        { gridRosterWeek = Just rosterWeek
                        , gridRosterDays = rosterDays
                        , gridWeekOffset = rosterWeek.weekOffset
                        , gridRosterGroups = rosterGroups
                        , gridCurrentRosterGroup = currentRosterGroup
                        , gridAssignmentFilters = assignmentFilters
                        , gridStaffMembers = staffMembers
                        , gridStaffOptionStates = staffOptionStates
                        , gridPanelStaff = panelStaff
                        , gridSlotNames = orderedSlotNames
                        , gridWeekStartDate = weekStartDate
                        , gridAllSlots = allSlots
                        , gridSlotConflicts = slotConflicts
                        , gridRenderIndexes = renderIndexes
                        , gridViewCapabilities = viewCapabilities
                        }

renderRosterStaffPanelFromProjection :: (?context :: ControllerContext, ?request :: Request) => Maybe RosterRenderData -> Blaze.Html
renderRosterStaffPanelFromProjection rosterData =
    case rosterData of
        Nothing -> mempty
        Just RosterRenderData { rosterWeek, panelStaff } ->
            renderRosterStaffPanelFragment rosterWeek.weekOffset (coerce rosterWeek.rosterGroupId) panelStaff

renderRequestedRowFragmentFromProjection :: (?context :: ControllerContext, ?request :: Request) => RosterRenderData -> UUID.UUID -> Int -> Maybe Blaze.Html
renderRequestedRowFragmentFromProjection RosterRenderData { rosterWeek, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, orderedSlotNames, renderIndexes } rosterDayId rowIndex =
    renderRequestedRowFragment (hasRole ManagerRole' && not rosterWeek.isLive) weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates renderIndexes (rosterDayId, rowIndex)

renderRequestedDaySectionFragmentFromProjection :: (?context :: ControllerContext, ?request :: Request) => RosterRenderData -> UUID.UUID -> Maybe Blaze.Html
renderRequestedDaySectionFragmentFromProjection RosterRenderData { rosterWeek, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, orderedSlotNames, allSlots, slotConflicts, renderIndexes } =
    renderRequestedDaySectionFragment (hasRole ManagerRole' && not rosterWeek.isLive) weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates allSlots slotConflicts renderIndexes

fetchRosterRenderData :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterRenderData)
fetchRosterRenderData rosterGroupId weekOffset = do
    _ <- profileActionSpan "roster.ensure_week_exists" (ensureRosterWeekExists rosterGroupId weekOffset)
    venueConfig <- fetchVenueConfig
    assignmentFilters <- fetchRosterAssignmentFilters
    let weekStartDate = venueWeekStartDate venueConfig weekOffset

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
            panelStaff <- profileActionSpan "roster.build_staff_panel" (fetchRosterStaffPanelEntries eligibleStaffMembers visibleSlots)
            staffOptionStates <- profileActionSpan "roster.build_staff_option_states" (buildRosterStaffOptionStates rosterGroupId assignmentFilters weekStartDate rosterDays visibleSlots staffMembers)
            orderedSlotNames <- profileActionSpan "roster.fetch_ordered_slot_names" (fetchRosterWeekOrderedSlotNamesFromSlots allSlots)
            slotConflicts <-
                if rosterWeek.isLive
                    then pure []
                    else profileActionSpan "roster.build_slot_conflicts" (buildSlotConflicts rosterGroupId venueConfig.lateToEarlyMinStartGapMinutes weekStartDate rosterDays visibleSlots staffMembers)
            let renderIndexes = buildRosterRenderIndexes rosterDays visibleSlots staffMembers slotConflicts
            pure (Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, panelStaff, orderedSlotNames, allSlots, slotConflicts, renderIndexes })

fetchVisibleRosterRenderData :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterRenderData)
fetchVisibleRosterRenderData rosterGroupId weekOffset = do
    visibleRosterWeek <- fetchVisibleRosterWeek rosterGroupId weekOffset
    case visibleRosterWeek of
        Nothing -> do
            (backingRosterWeek, rosterDays, weekStartDate, orderedSlotNames, maskedSlots) <- fetchHiddenRosterRenderData rosterGroupId weekOffset
            let renderIndexes = buildRosterRenderIndexes rosterDays (filterVisibleRosterSlots rosterDays maskedSlots) [] []
            pure $
                Just
                    RosterRenderData
                        { rosterWeek = backingRosterWeek
                        , rosterDays
                        , weekStartDate
                        , assignmentFilters = defaultRosterAssignmentFilters
                        , staffMembers = []
                        , staffOptionStates = Map.empty
                        , panelStaff = []
                        , orderedSlotNames
                        , allSlots = maskedSlots
                        , slotConflicts = []
                        , renderIndexes
                        }
        Just _  -> fetchRosterRenderData rosterGroupId weekOffset

fetchVisibleRosterWeek :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterWeek)
fetchVisibleRosterWeek rosterGroupId weekOffset = do
    _ <- ensureRosterWeekExists rosterGroupId weekOffset
    rosterWeekOrNothing <-
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

fetchVisibleRosterStaffPanelEntries :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe [RosterStaffPanelEntry])
fetchVisibleRosterStaffPanelEntries rosterGroupId weekOffset = do
    rosterData <- fetchVisibleRosterRenderDataCached rosterGroupId weekOffset
    pure ((\RosterRenderData { panelStaff } -> panelStaff) <$> rosterData)

fetchVisibleRosterRowFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Id RosterDay -> Int -> IO (Maybe Blaze.Html)
fetchVisibleRosterRowFragment rosterGroupId weekOffset rosterDayId rowIndex = do
    renderVisibleRosterProjectionFragment rosterGroupId weekOffset (RosterProjectionRow (unpackId rosterDayId) rowIndex)

fetchVisibleRosterDaySectionFragment :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> Id RosterDay -> IO (Maybe Blaze.Html)
fetchVisibleRosterDaySectionFragment rosterGroupId weekOffset rosterDayId = do
    renderVisibleRosterProjectionFragment rosterGroupId weekOffset (RosterProjectionDaySection (unpackId rosterDayId))

keepCurrentRosterWeekProjectionHot :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO ()
keepCurrentRosterWeekProjectionHot rosterGroupId weekOffset = do
    currentWeekOffset <- fetchCurrentRosterWeekOffset
    when (weekOffset == currentWeekOffset) $
        warmLiveSurfaceProjection rosterProjectionDefinition (buildRosterProjectionScope rosterGroupId weekOffset)

fetchHiddenRosterRenderData :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (RosterWeek, [RosterDay], Calendar.Day, [RosterWeekSlotDefinition], [RosterSlot])
fetchHiddenRosterRenderData rosterGroupId weekOffset = do
    rosterDataOrNothing <- fetchRosterRenderData rosterGroupId weekOffset
    case rosterDataOrNothing of
        Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, orderedSlotNames, allSlots } ->
            pure (rosterWeek, rosterDays, weekStartDate, orderedSlotNames, maskRosterSlots rosterWeek allSlots)
        Nothing -> error "Roster week should exist after ensureRosterWeekExists"

fetchHiddenRosterWeekSkeleton :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (RosterWeek, [RosterDay], [RosterWeekSlotDefinition], [RosterSlot])
fetchHiddenRosterWeekSkeleton rosterGroupId weekOffset = do
    (rosterWeek, rosterDays, _, orderedSlotNames, maskedSlots) <- fetchHiddenRosterRenderData rosterGroupId weekOffset
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
                |> set #durationMinutes Nothing
                |> set #note Nothing

renderRequestedRow :: (?context :: ControllerContext, ?request :: Request) => Calendar.Day -> [RosterWeekSlotDefinition] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID.UUID, UUID.UUID) RosterAssignmentOptionState -> RosterRenderIndexes -> (UUID.UUID, Int) -> Maybe Blaze.Html
renderRequestedRow weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates renderIndexes (rosterDayUuid, targetRowIndex) = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    dayRows <- Map.lookup rosterDayUuid renderIndexes.rosterDayRowsByDayId
    let rowCount = length dayRows
    let lastRowIndex = lastRowIndexForRows dayRows
    let indexedRows = zip [0 :: Int ..] dayRows
    (rowPosition, (_, rowSlots)) <- find (\(_, (rowIndex, _)) -> rowIndex == targetRowIndex) indexedRows
    let date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) weekStartDate
    pure (renderRowOob RosterRowRenderModel { rowIsEditable = True, rowSlotNames = orderedSlotNames, rowAssignmentFilters = assignmentFilters, rowStaffMembers = staffMembers, rowStaffOptionStates = staffOptionStates, rowDate = date, rowRosterDay = rosterDay, rowCount, rowLastRowIndex = lastRowIndex, rowRenderIndexes = renderIndexes } (rowPosition, (targetRowIndex, rowSlots)))

renderRequestedRowFragment :: (?context :: ControllerContext, ?request :: Request) => Bool -> Calendar.Day -> [RosterWeekSlotDefinition] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID.UUID, UUID.UUID) RosterAssignmentOptionState -> RosterRenderIndexes -> (UUID.UUID, Int) -> Maybe Blaze.Html
renderRequestedRowFragment isEditable weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates renderIndexes (rosterDayUuid, targetRowIndex) = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    dayRows <- Map.lookup rosterDayUuid renderIndexes.rosterDayRowsByDayId
    let rowCount = length dayRows
    let lastRowIndex = lastRowIndexForRows dayRows
    let indexedRows = zip [0 :: Int ..] dayRows
    (rowPosition, (_, rowSlots)) <- find (\(_, (rowIndex, _)) -> rowIndex == targetRowIndex) indexedRows
    let date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) weekStartDate
    pure (renderRowFragment RosterRowRenderModel { rowIsEditable = isEditable, rowSlotNames = orderedSlotNames, rowAssignmentFilters = assignmentFilters, rowStaffMembers = staffMembers, rowStaffOptionStates = staffOptionStates, rowDate = date, rowRosterDay = rosterDay, rowCount, rowLastRowIndex = lastRowIndex, rowRenderIndexes = renderIndexes } (rowPosition, (targetRowIndex, rowSlots)))

renderRequestedDaySection :: (?context :: ControllerContext, ?request :: Request) => Calendar.Day -> [RosterWeekSlotDefinition] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID.UUID, UUID.UUID) RosterAssignmentOptionState -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> UUID.UUID -> Maybe Blaze.Html
renderRequestedDaySection weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates allSlots slotConflicts renderIndexes rosterDayUuid = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    pure (renderRosterDaySectionFragment RosterDayRenderModel { dayIsEditable = True, daySlotNames = orderedSlotNames, dayAssignmentFilters = assignmentFilters, dayStaffMembers = staffMembers, dayStaffOptionStates = staffOptionStates, dayWeekStartDate = weekStartDate, dayAllSlots = allSlots, daySlotConflicts = slotConflicts, dayRenderIndexes = renderIndexes } rosterDay)

renderRequestedDaySectionFragment :: (?context :: ControllerContext, ?request :: Request) => Bool -> Calendar.Day -> [RosterWeekSlotDefinition] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID.UUID, UUID.UUID) RosterAssignmentOptionState -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> UUID.UUID -> Maybe Blaze.Html
renderRequestedDaySectionFragment isEditable weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates allSlots slotConflicts renderIndexes rosterDayUuid = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    pure (renderRosterDaySectionFragment RosterDayRenderModel { dayIsEditable = isEditable, daySlotNames = orderedSlotNames, dayAssignmentFilters = assignmentFilters, dayStaffMembers = staffMembers, dayStaffOptionStates = staffOptionStates, dayWeekStartDate = weekStartDate, dayAllSlots = allSlots, daySlotConflicts = slotConflicts, dayRenderIndexes = renderIndexes } rosterDay)
