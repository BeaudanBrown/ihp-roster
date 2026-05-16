{-# LANGUAGE BlockArguments      #-}
{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Web.RosterWeeks.RenderData
    ( rosterLiveSurfaceDefinition
    , rosterProjectionDefinition
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
import Application.Helper.LiveUpdate (LiveFragmentKey (..), LiveUpdateScope (..), currentLiveUpdateVersion)
import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Application.Helper.RosterWagePrediction
import Application.Helper.SurfaceProjection
import Application.Helper.UserPreferences
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
import Web.RosterWeeks.Dom
import Web.RosterWeeks.Paths (rosterWeekContentFragmentUrl,
                              rosterWeekDaySectionFragmentUrl,
                              rosterWeekRowFragmentUrl,
                              rosterWeekStaffPanelFragmentUrl)
import Web.RosterWeeks.Rows
import Web.RosterWeeks.Service
import Web.RosterWeeks.StaffOptions
import Web.RosterWeeks.Types
import Web.View.RosterWeeks.Grid
import Web.View.RosterWeeks.StaffPanel

data RosterLiveSurface

rosterLiveSurfaceDefinition :: (?context :: ControllerContext) => TypedLiveSurfaceDefinition RosterLiveSurface RosterProjectionScope RosterProjectionFragment
rosterLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "roster"
        , typedSurfaceScope = rosterSurfaceScope
        , typedSurfaceScopeFromWire = rosterSurfaceScopeFromWire
        , typedSurfaceDefaultFragments = const [RosterProjectionContent, RosterProjectionStaffPanel]
        , typedSurfaceFragmentRef = \scope fragment ->
            case fragment of
                RosterProjectionContent ->
                    mkSurfaceFragmentRef
                        RosterContentFragment
                        rosterContentFragmentId
                        (rosterWeekContentFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
                RosterProjectionStaffPanel ->
                    mkSurfaceFragmentRef
                        RosterStaffPanelFragment
                        rosterStaffPanelFragmentId
                        (rosterWeekStaffPanelFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId)
                RosterProjectionDaySection rosterDayId ->
                    mkSurfaceFragmentRef
                        RosterDaySectionFragment { rosterDayId }
                        (rosterDaySectionDomId (coerce rosterDayId))
                        (rosterWeekDaySectionFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId (coerce rosterDayId))
                RosterProjectionRow rosterDayId rowIndex ->
                    mkSurfaceFragmentRef
                        RosterRowFragment { rosterDayId, rowIndex }
                        (rosterRowDomIdText (coerce rosterDayId) rowIndex)
                        (rosterWeekRowFragmentUrl scope.rosterProjectionWeekOffset scope.rosterProjectionGroupId (coerce rosterDayId) rowIndex)
        , typedSurfaceDecorateRequestsWithin = const ["#roster-week-shell"]
        , typedSurfaceAuthorize = liveSurfaceAuthorizationByRequirement (\scope -> RequireCurrentVenueRosterGroup (unpackId currentVenueId) (unpackId scope.rosterProjectionGroupId))
        }
    where
        rosterSurfaceScope scope =
            SurfaceScope (buildRosterWeekScope scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset)

        rosterSurfaceScopeFromWire scope =
            case (currentVenueOrNothing, scope) of
                (Just _, RosterWeekScope { rosterGroupId, weekOffset }) ->
                    Just RosterProjectionScope
                        { rosterProjectionGroupId = coerce rosterGroupId
                        , rosterProjectionWeekOffset = weekOffset
                        }
                _ ->
                    Nothing

rosterProjectionDefinition :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ProjectionLiveSurfaceDefinition RosterLiveSurface RosterProjectionScope (Maybe RosterRenderData) RosterProjectionFragment
rosterProjectionDefinition =
    mkTypedSurfaceProjectionDefinition
        rosterLiveSurfaceDefinition
        "roster-week"
        defaultSurfaceProjectionCachePolicy
        (\scope -> tshow scope.rosterProjectionGroupId <> ":" <> tshow scope.rosterProjectionWeekOffset)
        do
            filters <- fetchRosterAssignmentFilters
            layoutMode <- fetchCurrentRosterLayoutMode
            pure (tshow currentUser.id <> ":" <> encodeRosterAssignmentFilters filters <> ":" <> rosterLayoutModeValue layoutMode)
        rosterProjectionVersion
        (\scope -> fetchVisibleRosterRenderData scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset)
        renderRosterProjectionFragment

rosterProjectionVersion :: (?context :: ControllerContext, ?modelContext :: ModelContext) => RosterProjectionScope -> IO Int
rosterProjectionVersion scope = do
    rosterVersion <- currentLiveUpdateVersion (buildRosterWeekScope scope.rosterProjectionGroupId scope.rosterProjectionWeekOffset)
    if hasRole ManagerRole' || currentUserIsSuperAdmin
        then pure rosterVersion
        else do
            venueConfig <- fetchVenueConfig
            operationalDay <- currentOperationalDayForVenue venueConfig
            let timesheetWeekOffset = venueWeekOffsetForDay venueConfig operationalDay
            timesheetVersion <- currentLiveUpdateVersion TimesheetWeekScope { venueId = unpackId currentVenueId, weekOffset = timesheetWeekOffset }
            leaveVersion <- currentLiveUpdateVersion LeaveRequestsScope { venueId = unpackId currentVenueId }
            pure (rosterVersion + timesheetVersion + leaveVersion + fromInteger (Calendar.toModifiedJulianDay operationalDay))

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
        Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, panelStaff, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction } ->
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

renderRosterStaffPanelFromProjection :: (?context :: ControllerContext, ?request :: Request) => Maybe RosterRenderData -> Blaze.Html
renderRosterStaffPanelFromProjection rosterData =
    case rosterData of
        Nothing -> mempty
        Just RosterRenderData { rosterWeek, panelStaff } ->
            renderRosterStaffPanelFragment rosterWeek.weekOffset (coerce rosterWeek.rosterGroupId) panelStaff

renderRequestedRowFragmentFromProjection :: (?context :: ControllerContext, ?request :: Request) => RosterRenderData -> UUID.UUID -> Int -> Maybe Blaze.Html
renderRequestedRowFragmentFromProjection RosterRenderData { rosterWeek, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, orderedSlotNames, shiftTypes, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled } rosterDayId rowIndex =
    renderRequestedRowFragment (hasRole ManagerRole' && not rosterWeek.isLive) weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayId, rowIndex)

renderRequestedDaySectionFragmentFromProjection :: (?context :: ControllerContext, ?request :: Request) => RosterRenderData -> UUID.UUID -> Maybe Blaze.Html
renderRequestedDaySectionFragmentFromProjection RosterRenderData { rosterWeek, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled } =
    renderRequestedDaySectionFragment (hasRole ManagerRole' && not rosterWeek.isLive) weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled

fetchRosterRenderData :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (Maybe RosterRenderData)
fetchRosterRenderData rosterGroupId weekOffset = do
    _ <- profileActionSpan "roster.ensure_week_exists" (ensureRosterWeekExists rosterGroupId weekOffset)
    venueConfig <- fetchVenueConfig
    assignmentFilters <- fetchRosterAssignmentFilters
    rosterLayoutMode <- fetchCurrentRosterLayoutMode
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
            shiftTypes <- profileActionSpan "roster.fetch_shift_types" fetchCurrentVenueRosterShiftTypes
            panelStaff <- profileActionSpan "roster.build_staff_panel" (fetchRosterStaffPanelEntries eligibleStaffMembers visibleSlots)
            staffSelfServicePanel <- profileActionSpan "roster.build_staff_self_service_panel" (fetchRosterStaffSelfServicePanel venueConfig)
            staffOptionStates <- profileActionSpan "roster.build_staff_option_states" (buildRosterStaffOptionStates rosterGroupId assignmentFilters weekStartDate rosterDays visibleSlots staffMembers)
            orderedSlotNames <- profileActionSpan "roster.fetch_ordered_slot_names" (fetchRosterWeekOrderedSlotNames rosterWeek)
            slotConflicts <-
                if rosterWeek.isLive
                    then pure []
                    else profileActionSpan "roster.build_slot_conflicts" (buildSlotConflicts rosterGroupId venueConfig.lateToEarlyMinStartGapMinutes weekStartDate rosterDays visibleSlots staffMembers)
            let renderIndexes = buildRosterRenderIndexes rosterDays visibleSlots staffMembers slotConflicts
            rosterWagePrediction <-
                if hasRole VenueAdminRole
                    then Just <$> profileActionSpan "roster.predict_wages" (fetchRosterWagePrediction venueConfig rosterWeek rosterDays visibleSlots)
                    else pure Nothing
            pure (Just RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, panelStaff, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled = venueConfig.rosterEndTimesEnabled, rosterWagePrediction })

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
    case visibleRosterWeek of
        Nothing -> do
            (backingRosterWeek, rosterDays, weekStartDate, orderedSlotNames, shiftTypes, maskedSlots) <- fetchHiddenRosterRenderData rosterGroupId weekOffset
            rosterLayoutMode <- fetchCurrentRosterLayoutMode
            venueConfig <- fetchVenueConfig
            staffSelfServicePanel <- profileActionSpan "roster.build_staff_self_service_panel" (fetchRosterStaffSelfServicePanel venueConfig)
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
                        , staffSelfServicePanel
                        , orderedSlotNames
                        , shiftTypes
                        , allSlots = maskedSlots
                        , slotConflicts = []
                        , renderIndexes
                        , rosterLayoutMode
                        , rosterEndTimesEnabled = venueConfig.rosterEndTimesEnabled
                        , rosterWagePrediction = Nothing
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

fetchHiddenRosterRenderData :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> IO (RosterWeek, [RosterDay], Calendar.Day, [RosterWeekSlotDefinition], [ShiftType], [RosterSlot])
fetchHiddenRosterRenderData rosterGroupId weekOffset = do
    rosterDataOrNothing <- fetchRosterRenderData rosterGroupId weekOffset
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

renderRequestedRow :: (?context :: ControllerContext, ?request :: Request) => Calendar.Day -> [RosterWeekSlotDefinition] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID.UUID, UUID.UUID) RosterAssignmentOptionState -> [ShiftType] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> (UUID.UUID, Int) -> Maybe Blaze.Html
renderRequestedRow weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayUuid, targetRowIndex) = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    dayRows <- Map.lookup rosterDayUuid renderIndexes.rosterDayRowsByDayId
    let rowCount = length dayRows
    let lastRowIndex = lastRowIndexForRows dayRows
    let indexedRows = zip [0 :: Int ..] dayRows
    (rowPosition, (_, rowSlots)) <- find (\(_, (rowIndex, _)) -> rowIndex == targetRowIndex) indexedRows
    let date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) weekStartDate
    pure (renderRowOob RosterRowRenderModel { rowIsEditable = True, rowSlotNames = orderedSlotNames, rowAssignmentFilters = assignmentFilters, rowStaffMembers = staffMembers, rowStaffOptionStates = staffOptionStates, rowShiftTypes = shiftTypes, rowDate = date, rowRosterDay = rosterDay, rowCount, rowLastRowIndex = lastRowIndex, rowRenderIndexes = renderIndexes, rowRosterLayoutMode = rosterLayoutMode, rowRosterEndTimesEnabled = rosterEndTimesEnabled } (rowPosition, (targetRowIndex, rowSlots)))

renderRequestedRowFragment :: (?context :: ControllerContext, ?request :: Request) => Bool -> Calendar.Day -> [RosterWeekSlotDefinition] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID.UUID, UUID.UUID) RosterAssignmentOptionState -> [ShiftType] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> (UUID.UUID, Int) -> Maybe Blaze.Html
renderRequestedRowFragment isEditable weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates shiftTypes renderIndexes rosterLayoutMode rosterEndTimesEnabled (rosterDayUuid, targetRowIndex) = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    dayRows <- Map.lookup rosterDayUuid renderIndexes.rosterDayRowsByDayId
    let rowCount = length dayRows
    let lastRowIndex = lastRowIndexForRows dayRows
    let indexedRows = zip [0 :: Int ..] dayRows
    (rowPosition, (_, rowSlots)) <- find (\(_, (rowIndex, _)) -> rowIndex == targetRowIndex) indexedRows
    let date = Calendar.addDays (toInteger (get #dayOffset rosterDay)) weekStartDate
    pure (renderRowFragment RosterRowRenderModel { rowIsEditable = isEditable, rowSlotNames = orderedSlotNames, rowAssignmentFilters = assignmentFilters, rowStaffMembers = staffMembers, rowStaffOptionStates = staffOptionStates, rowShiftTypes = shiftTypes, rowDate = date, rowRosterDay = rosterDay, rowCount, rowLastRowIndex = lastRowIndex, rowRenderIndexes = renderIndexes, rowRosterLayoutMode = rosterLayoutMode, rowRosterEndTimesEnabled = rosterEndTimesEnabled } (rowPosition, (targetRowIndex, rowSlots)))

renderRequestedDaySection :: (?context :: ControllerContext, ?request :: Request) => Calendar.Day -> [RosterWeekSlotDefinition] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID.UUID, UUID.UUID) RosterAssignmentOptionState -> [ShiftType] -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> UUID.UUID -> Maybe Blaze.Html
renderRequestedDaySection weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterDayUuid = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    pure (renderRosterDaySectionFragment RosterDayRenderModel { dayIsEditable = True, daySlotNames = orderedSlotNames, dayAssignmentFilters = assignmentFilters, dayStaffMembers = staffMembers, dayStaffOptionStates = staffOptionStates, dayShiftTypes = shiftTypes, dayWeekStartDate = weekStartDate, dayAllSlots = allSlots, daySlotConflicts = slotConflicts, dayRenderIndexes = renderIndexes, dayRosterLayoutMode = rosterLayoutMode, dayRosterEndTimesEnabled = rosterEndTimesEnabled } rosterDay)

renderRequestedDaySectionFragment :: (?context :: ControllerContext, ?request :: Request) => Bool -> Calendar.Day -> [RosterWeekSlotDefinition] -> RosterAssignmentFilters -> [Staff] -> Map.Map (UUID.UUID, UUID.UUID) RosterAssignmentOptionState -> [ShiftType] -> [RosterSlot] -> [(Id RosterSlot, [RosterConflict])] -> RosterRenderIndexes -> RosterLayoutModeEnum -> Bool -> UUID.UUID -> Maybe Blaze.Html
renderRequestedDaySectionFragment isEditable weekStartDate orderedSlotNames assignmentFilters staffMembers staffOptionStates shiftTypes allSlots slotConflicts renderIndexes rosterLayoutMode rosterEndTimesEnabled rosterDayUuid = do
    rosterDay <- Map.lookup rosterDayUuid renderIndexes.rosterDayById
    pure (renderRosterDaySectionFragment RosterDayRenderModel { dayIsEditable = isEditable, daySlotNames = orderedSlotNames, dayAssignmentFilters = assignmentFilters, dayStaffMembers = staffMembers, dayStaffOptionStates = staffOptionStates, dayShiftTypes = shiftTypes, dayWeekStartDate = weekStartDate, dayAllSlots = allSlots, daySlotConflicts = slotConflicts, dayRenderIndexes = renderIndexes, dayRosterLayoutMode = rosterLayoutMode, dayRosterEndTimesEnabled = rosterEndTimesEnabled } rosterDay)

fetchCurrentVenueRosterShiftTypes :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [ShiftType]
fetchCurrentVenueRosterShiftTypes =
    query @ShiftType
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch
