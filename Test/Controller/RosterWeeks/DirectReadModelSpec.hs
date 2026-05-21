{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}

module Test.Controller.RosterWeeks.DirectReadModelSpec where

import Application.Helper.Conflict
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        ensureVenueDefaultRosterGroup,
                                        fetchCurrentVenueRosterGroupOrDefault,
                                        fetchCurrentVenueRosterGroups)
import Application.Helper.SurfaceProjection (SurfaceProjectionCacheStats (..),
                                             readSurfaceProjectionCacheStats)
import Application.Helper.UserPreferences (upsertCurrentUserRosterLayoutMode)
import Application.Helper.WeekBoundaries (weekdayIndexForDay)
import Data.Coerce (coerce)
import Data.List (sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromJust)
import qualified Data.Text.Lazy as LText
import qualified Data.Time.Calendar as Calendar
import Data.Time.Clock (getCurrentTime)
import Data.Time.LocalTime (TimeOfDay (..))
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import qualified Text.Blaze.Html as Blaze
import qualified Text.Blaze.Html.Renderer.Text as HtmlRenderer
import Web.RosterWeeks.DirectReadModel
import Web.RosterWeeks.Filters
import Web.RosterWeeks.RenderData
import Web.RosterWeeks.Types


tests :: Spec
tests = beforeAll testContext do
    describe "Roster direct read model" do
        it "reads manager-visible base facts without projection cache state" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                facts <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        fetchRosterBaseFactsDirect fixture.rosterGroup.id 0

                let RosterBaseFacts { baseRosterWeek, baseRosterDays, baseAllSlots, baseVisibleSlots, baseOrderedSlotDefinitions, baseShiftTypes, baseEligibleStaff, baseAssignedStaff, baseStaffMembers } = fromJust facts
                baseRosterWeek.id `shouldBe` fixture.rosterWeek.id
                map (.dayOffset) baseRosterDays `shouldBe` [0 .. 6]
                map (.rowIndex) baseVisibleSlots `shouldBe` [3]
                map (.id) baseAllSlots `shouldContain` [fixture.closedDaySlot.id]
                map (.id) baseVisibleSlots `shouldNotContain` [fixture.closedDaySlot.id, fixture.otherGroupSlot.id]
                map (.sortOrder) baseOrderedSlotDefinitions `shouldBe` sort (map (.sortOrder) baseOrderedSlotDefinitions)
                map (.name) baseShiftTypes `shouldBe` ["Breakfast", "Dinner"]
                map (.id) baseEligibleStaff `shouldContain` [fixture.eligibleStaff.id]
                map (.id) baseEligibleStaff `shouldNotContain` [fixture.assignedInactiveStaff.id]
                map (.id) baseAssignedStaff `shouldBe` [fixture.assignedInactiveStaff.id]
                map (.id) baseStaffMembers `shouldContain` [fixture.eligibleStaff.id, fixture.assignedInactiveStaff.id]

        it "builds direct render data with the same base facts used by the roster seam" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                renderData <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        fetchVisibleRosterReadModelDirect fixture.rosterGroup.id 0

                let rosterData = fromJust renderData
                rosterData.rosterWeek.id `shouldBe` fixture.rosterWeek.id
                map (.id) rosterData.staffMembers `shouldContain` [fixture.eligibleStaff.id, fixture.assignedInactiveStaff.id]
                map (.id) rosterData.allSlots `shouldContain` [fixture.visibleSparseSlot.id, fixture.closedDaySlot.id]
                map (.id) rosterData.orderedSlotNames `shouldBe` map (.id) (sortSlotDefinitions rosterData.orderedSlotNames)

        it "derives direct assignment option hidden reasons from SQL facts" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        initialData <- fromJust <$> fetchVisibleRosterReadModelDirect fixture.rosterGroup.id 0
                        openDay <- fetch (Id fixture.visibleSparseSlot.rosterDayId) :: IO RosterDay
                        _ <- fixture.eligibleStaff |> set #idealShiftsPerWeek 1 |> updateRecord
                        _ <- createRosterSlotRecord openDay fixture.earlySlotName (Just fixture.eligibleStaff) 4
                        _ <- createLeaveRequestRecord fixture.venue fixture.eligibleStaff initialData.weekStartDate (Calendar.addDays 1 initialData.weekStartDate) "approved"

                        facts <- fromJust <$> fetchRosterBaseFactsDirect fixture.rosterGroup.id 0
                        states <- buildRosterStaffOptionStatesDirect allAssignmentFilters initialData.weekStartDate facts.baseVisibleSlots facts.baseStaffMembers

                        let targetState = fromJust (Map.lookup (coerce fixture.visibleSparseSlot.id, coerce fixture.eligibleStaff.id) states)
                        targetState.optionHidden `shouldBe` True
                        targetState.optionHiddenByIdeal `shouldBe` True
                        targetState.optionHiddenByUnavailable `shouldBe` True
                        targetState.optionHiddenByLeave `shouldBe` True
                        targetState.optionHiddenByAssignedToday `shouldBe` True

        it "derives each direct roster conflict type from SQL facts" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        (duplicateSlot, lateSlot, preferenceSlot) <- addDirectReadModelConflictFacts fixture
                        initialData <- fromJust <$> fetchVisibleRosterReadModelDirect fixture.rosterGroup.id 0
                        facts <- fromJust <$> fetchRosterBaseFactsDirect fixture.rosterGroup.id 0
                        conflicts <- buildSlotConflictsDirect fixture.rosterGroup.id 480 initialData.weekStartDate facts.baseVisibleSlots

                        let allTypes = sort (concatMap (map (.conflictType) . snd) conflicts)
                        forM_ [DuplicateAssignment, LeaveConflict, LateToEarlyConflict, ShiftPreferenceDayUnavailable, ShiftPreferenceSlotMismatch, IdealShiftThresholdExceeded] $ \conflictType ->
                            allTypes `shouldContain` [conflictType]
                        lookup fixture.visibleSparseSlot.id conflicts `shouldSatisfy` hasConflictType LateToEarlyConflict
                        lookup duplicateSlot.id conflicts `shouldSatisfy` hasConflictType DuplicateAssignment
                        lookup lateSlot.id conflicts `shouldSatisfy` hasConflictType LateToEarlyConflict
                        lookup preferenceSlot.id conflicts `shouldSatisfy` hasConflictType ShiftPreferenceSlotMismatch

        it "matches projection-cached and direct render data for a manager draft with sparse rows and conflicts" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        _ <- addDirectReadModelConflictFacts fixture
                        assertProjectionDirectParity fixture.rosterGroup.id 0 allAssignmentFilters DayRows

        it "matches projection-cached and direct render data for staff hidden draft and published roster states" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                withUserAndCurrentVenue fixture.eligibleUser fixture.venue.id do
                    withCurrentControllerContext do
                        assertProjectionDirectParity fixture.rosterGroup.id 0 defaultRosterAssignmentFilters DayRows

                _ <- fixture.rosterWeek |> set #isLive True |> updateRecord

                withUserAndCurrentVenue fixture.eligibleUser fixture.venue.id do
                    withCurrentControllerContext do
                        assertProjectionDirectParity fixture.rosterGroup.id 0 defaultRosterAssignmentFilters DayColumns

        it "does not warm or populate projection cache through the direct seam" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        before <- readSurfaceProjectionCacheStats
                        _ <- fetchVisibleRosterReadModel fixture.rosterGroup.id 0
                        _ <- renderVisibleRosterReadModelFragment fixture.rosterGroup.id 0 RosterProjectionStaffPanel
                        keepCurrentRosterWeekProjectionHot fixture.rosterGroup.id 0
                        after <- readSurfaceProjectionCacheStats

                        projectionCacheDelta after before `shouldBe` zeroProjectionCacheDelta

addDirectReadModelConflictFacts :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => DirectReadModelFixture -> IO (RosterSlot, RosterSlot, RosterSlot)
addDirectReadModelConflictFacts fixture = do
    initialData <- fromJust <$> fetchVisibleRosterReadModelDirect fixture.rosterGroup.id 0
    openDay <- fetch (Id fixture.visibleSparseSlot.rosterDayId) :: IO RosterDay
    nextDay <- query @RosterDay
        |> filterWhere (#rosterWeekId, unpackId fixture.rosterWeek.id)
        |> filterWhere (#dayOffset, 1)
        |> fetchOne
    _ <- nextDay |> set #isClosed False |> updateRecord
    _ <- fixture.assignedInactiveStaff |> set #idealShiftsPerWeek 1 |> updateRecord
    duplicateSlot <- createRosterSlotRecord openDay fixture.earlySlotName (Just fixture.assignedInactiveStaff) 5 >>= \slot ->
        slot |> set #startTime (Just (TimeOfDay 12 0 0)) |> updateRecord
    lateSlot <- createRosterSlotRecord nextDay fixture.earlySlotName (Just fixture.assignedInactiveStaff) 7 >>= \slot ->
        slot |> set #startTime (Just (TimeOfDay 6 0 0)) |> updateRecord
    _ <- fixture.visibleSparseSlot |> set #startTime (Just (TimeOfDay 23 0 0)) |> updateRecord
    _ <- createLeaveRequestRecord fixture.venue fixture.assignedInactiveStaff initialData.weekStartDate (Calendar.addDays 1 initialData.weekStartDate) "approved"
    preferenceStaff <- createStaffRecord fixture.venue Nothing "Pref" "Mismatch"
    preferenceSlot <- createRosterSlotRecord openDay fixture.earlySlotName (Just preferenceStaff) 6 >>= \slot ->
        slot |> set #startTime (Just (TimeOfDay 12 0 0)) |> updateRecord
    _ <- createStaffShiftPreferenceRecord fixture.venue preferenceStaff (weekdayIndexForDay initialData.weekStartDate) 9 10
    pure (duplicateSlot, lateSlot, preferenceSlot)

assertProjectionDirectParity :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Id RosterGroup -> Int -> RosterAssignmentFilters -> RosterLayoutModeEnum -> IO ()
assertProjectionDirectParity rosterGroupId weekOffset assignmentFilters layoutMode = do
    setRosterAssignmentFiltersSession assignmentFilters
    _ <- upsertCurrentUserRosterLayoutMode layoutMode

    projectionData <- fetchVisibleRosterRenderDataCached rosterGroupId weekOffset
    directData <- fetchVisibleRosterReadModelDirect rosterGroupId weekOffset
    snapshotRosterRenderData <$> projectionData `shouldBe` snapshotRosterRenderData <$> directData

    projectionStaffPanel <- renderVisibleRosterProjectionFragment rosterGroupId weekOffset RosterProjectionStaffPanel
    let directStaffPanel = renderRosterProjectionFragment directData RosterProjectionStaffPanel
    renderMaybeHtml projectionStaffPanel `shouldBe` renderMaybeHtml directStaffPanel

    forM_ directData \rosterData -> do
        let rosterDay = fromJust (head rosterData.rosterDays)
            dayId = coerce rosterDay.id
            rowIndex = maybe 0 (fst . fromJust . head) (Map.lookup dayId rosterData.renderIndexes.rosterDayRowsByDayId)
        projectionDay <- renderVisibleRosterProjectionFragment rosterGroupId weekOffset (RosterProjectionDaySection dayId)
        let directDay = renderRosterProjectionFragment directData (RosterProjectionDaySection dayId)
        renderMaybeHtml projectionDay `shouldBe` renderMaybeHtml directDay

        projectionRow <- renderVisibleRosterProjectionFragment rosterGroupId weekOffset (RosterProjectionRow dayId rowIndex)
        let directRow = renderRosterProjectionFragment directData (RosterProjectionRow dayId rowIndex)
        renderMaybeHtml projectionRow `shouldBe` renderMaybeHtml directRow

        rosterGroups <- fetchCurrentVenueRosterGroups
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (Just rosterGroupId)
        projectionContent <- renderVisibleRosterProjectionFragment rosterGroupId weekOffset RosterProjectionContent
        directContent <- Just <$> renderRosterContentFromProjection rosterGroups currentRosterGroup directData
        renderMaybeHtml projectionContent `shouldBe` renderMaybeHtml directContent

renderMaybeHtml :: Maybe Blaze.Html -> Text
renderMaybeHtml = maybe "" (LText.toStrict . HtmlRenderer.renderHtml)

zeroProjectionCacheDelta :: SurfaceProjectionCacheStats
zeroProjectionCacheDelta = SurfaceProjectionCacheStats { hits = 0, misses = 0, loads = 0, warms = 0, evictions = 0 }

projectionCacheDelta :: SurfaceProjectionCacheStats -> SurfaceProjectionCacheStats -> SurfaceProjectionCacheStats
projectionCacheDelta after before =
    SurfaceProjectionCacheStats
        { hits = after.hits - before.hits
        , misses = after.misses - before.misses
        , loads = after.loads - before.loads
        , warms = after.warms - before.warms
        , evictions = after.evictions - before.evictions
        }

data RosterRenderDataSnapshot = RosterRenderDataSnapshot
    { snapshotRosterWeekId            :: UUID.UUID
    , snapshotRosterWeekIsLive        :: Bool
    , snapshotRosterDays              :: [(UUID.UUID, Int, Bool)]
    , snapshotWeekStartDate           :: Calendar.Day
    , snapshotAssignmentFilters       :: (Bool, Bool, Bool, Bool)
    , snapshotStaffIds                :: [UUID.UUID]
    , snapshotStaffOptionStates       :: [((UUID.UUID, UUID.UUID), (Bool, Int, Bool, Bool, Bool, Bool))]
    , snapshotPanelStaff              :: [(UUID.UUID, Int, Text)]
    , snapshotSelfServiceStaffIds     :: Maybe [UUID.UUID]
    , snapshotOrderedSlotNames        :: [(UUID.UUID, Text, Int)]
    , snapshotShiftTypes              :: [(UUID.UUID, Text, Int)]
    , snapshotAllSlots                :: [(UUID.UUID, UUID.UUID, Int, UUID.UUID, Maybe UUID.UUID, Maybe TimeOfDay, Maybe TimeOfDay, Maybe UUID.UUID, Maybe Int)]
    , snapshotSlotConflicts           :: [(UUID.UUID, [(ConflictType, ConflictSeverity, Text)])]
    , snapshotRenderRows              :: [(UUID.UUID, [(Int, [UUID.UUID])])]
    , snapshotRenderSlotKeys          :: [((UUID.UUID, Int, UUID.UUID), UUID.UUID)]
    , snapshotRenderStaffIds          :: [UUID.UUID]
    , snapshotRenderConflictKeys      :: [(UUID.UUID, [ConflictType])]
    , snapshotRosterLayoutMode        :: RosterLayoutModeEnum
    , snapshotRosterEndTimesEnabled   :: Bool
    , snapshotRosterWagePredictionSet :: Bool
    } deriving (Eq, Show)

snapshotRosterRenderData :: RosterRenderData -> RosterRenderDataSnapshot
snapshotRosterRenderData RosterRenderData { rosterWeek, rosterDays, weekStartDate, assignmentFilters, staffMembers, staffOptionStates, panelStaff, staffSelfServicePanel, orderedSlotNames, shiftTypes, allSlots, slotConflicts, renderIndexes, rosterLayoutMode, rosterEndTimesEnabled, rosterWagePrediction } =
    RosterRenderDataSnapshot
        { snapshotRosterWeekId = coerce rosterWeek.id
        , snapshotRosterWeekIsLive = rosterWeek.isLive
        , snapshotRosterDays = map snapshotRosterDay rosterDays
        , snapshotWeekStartDate = weekStartDate
        , snapshotAssignmentFilters = (assignmentFilters.hideStaffAtIdealShifts, assignmentFilters.hideStaffUnavailable, assignmentFilters.hideStaffOnApprovedLeave, assignmentFilters.hideStaffAlreadyAssignedToday)
        , snapshotStaffIds = map (coerce . (.id)) staffMembers
        , snapshotStaffOptionStates = Map.toAscList (Map.map snapshotOptionState staffOptionStates)
        , snapshotPanelStaff = map snapshotPanelEntry panelStaff
        , snapshotSelfServiceStaffIds = fmap (map (coerce . (.id)) . (.quickToolsStaffMembers)) staffSelfServicePanel
        , snapshotOrderedSlotNames = map (\slotName -> (coerce slotName.id, slotName.name, slotName.sortOrder)) orderedSlotNames
        , snapshotShiftTypes = map (\shiftType -> (coerce shiftType.id, shiftType.name, shiftType.sortOrder)) shiftTypes
        , snapshotAllSlots = sortOn (\(slotId, _, _, _, _, _, _, _, _) -> slotId) (map snapshotRosterSlot allSlots)
        , snapshotSlotConflicts = sortOn fst (map snapshotSlotConflict slotConflicts)
        , snapshotRenderRows = Map.toAscList (Map.map (map (\(rowIndex, slots) -> (rowIndex, map (coerce . (.id)) slots))) renderIndexes.rosterDayRowsByDayId)
        , snapshotRenderSlotKeys = Map.toAscList (Map.map (coerce . (.id)) renderIndexes.rosterSlotByDayRowSlotName)
        , snapshotRenderStaffIds = Map.keys renderIndexes.rosterStaffById
        , snapshotRenderConflictKeys = Map.toAscList (Map.map (map (.conflictType)) renderIndexes.rosterConflictsBySlotId)
        , snapshotRosterLayoutMode = rosterLayoutMode
        , snapshotRosterEndTimesEnabled = rosterEndTimesEnabled
        , snapshotRosterWagePredictionSet = isJust rosterWagePrediction
        }

snapshotRosterDay :: RosterDay -> (UUID.UUID, Int, Bool)
snapshotRosterDay rosterDay = (coerce rosterDay.id, rosterDay.dayOffset, rosterDay.isClosed)

snapshotOptionState :: RosterAssignmentOptionState -> (Bool, Int, Bool, Bool, Bool, Bool)
snapshotOptionState optionState =
    ( optionState.optionHidden
    , optionState.optionAssignedShiftCount
    , optionState.optionHiddenByIdeal
    , optionState.optionHiddenByUnavailable
    , optionState.optionHiddenByLeave
    , optionState.optionHiddenByAssignedToday
    )

snapshotPanelEntry :: RosterStaffPanelEntry -> (UUID.UUID, Int, Text)
snapshotPanelEntry entry = (coerce entry.staff.id, entry.assignedShiftCount, entry.userRole)

snapshotRosterSlot :: RosterSlot -> (UUID.UUID, UUID.UUID, Int, UUID.UUID, Maybe UUID.UUID, Maybe TimeOfDay, Maybe TimeOfDay, Maybe UUID.UUID, Maybe Int)
snapshotRosterSlot slot =
    ( coerce slot.id
    , slot.rosterDayId
    , slot.rowIndex
    , slot.rosterWeekSlotDefinitionId
    , slot.staffId
    , slot.startTime
    , slot.endTime
    , slot.shiftTypeId
    , slot.durationMinutes
    )

snapshotSlotConflict :: (Id RosterSlot, [RosterConflict]) -> (UUID.UUID, [(ConflictType, ConflictSeverity, Text)])
snapshotSlotConflict (slotId, conflicts) =
    (coerce slotId, map (\conflict -> (conflict.conflictType, conflict.severity, conflict.message)) conflicts)

data DirectReadModelFixture = DirectReadModelFixture
    { venue                 :: Venue
    , manager               :: User
    , rosterGroup           :: RosterGroup
    , rosterWeek            :: RosterWeek
    , earlySlotName         :: SlotName
    , eligibleUser          :: User
    , eligibleStaff         :: Staff
    , assignedInactiveStaff :: Staff
    , visibleSparseSlot     :: RosterSlot
    , closedDaySlot         :: RosterSlot
    , otherGroupSlot        :: RosterSlot
    }

createDirectReadModelFixture :: (?modelContext :: ModelContext) => IO DirectReadModelFixture
createDirectReadModelFixture = do
    venue <- createVenueWithConfig "Direct Read Venue"
    manager <- createUserRecord "direct-read-manager@example.com" "staff" True
    _ <- createVenueMembershipRecord venue manager "manager"
    rosterGroup <- ensureVenueDefaultRosterGroup venue
    otherRosterGroup <- createVenueRosterGroupWithDefaults venue "Other" 1 True
    earlySlotName <- fetchSlotNameRecordForRosterGroup rosterGroup "Early"
    otherSlotName <- fetchSlotNameRecordForRosterGroup otherRosterGroup "Early"

    awardLevel <- createPayLevelRecord venue "Direct Read Level"
    breakfast <- createShiftTypeRecord venue awardLevel "Breakfast"
    _ <- breakfast |> set #sortOrder 1 |> updateRecord
    dinner <- createShiftTypeRecord venue awardLevel "Dinner"
    _ <- dinner |> set #sortOrder 2 |> updateRecord

    eligibleUser <- createUserRecord "direct-eligible@example.com" "staff" True
    _ <- createVenueMembershipRecord venue eligibleUser "worker"
    eligibleStaff <- createStaffRecord venue (Just eligibleUser) "Able" "Eligible"

    inactiveUser <- createUserRecord "direct-inactive@example.com" "staff" True
    _ <- createVenueMembershipRecord venue inactiveUser "worker"
    assignedInactiveStaff <- createStaffRecord venue (Just inactiveUser) "Bert" "Inactive"
    assignedInactiveStaff' <- assignedInactiveStaff |> set #isActive False |> updateRecord

    rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 False
    rosterDays <- forM [0 :: Int .. 6] (createRosterDayRecord rosterWeek)
    let openDay = fromJust (head rosterDays)
    closedDay <- (rosterDays !! 1) |> set #isClosed True |> updateRecord

    visibleSparseSlot <- createRosterSlotRecord openDay earlySlotName (Just assignedInactiveStaff') 3 >>= \slot ->
        slot
            |> set #startTime (Just (TimeOfDay 9 0 0))
            |> set #shiftTypeId (Just (unpackId breakfast.id))
            |> updateRecord
    closedDaySlot <- createRosterSlotRecord closedDay earlySlotName (Just eligibleStaff) 0 >>= \slot ->
        slot
            |> set #startTime (Just (TimeOfDay 10 0 0))
            |> set #shiftTypeId (Just (unpackId dinner.id))
            |> updateRecord

    deletedSlot <- createRosterSlotRecord openDay earlySlotName (Just eligibleStaff) 1
    now <- getCurrentTime
    _ <- deletedSlot |> set #deletedAt (Just now) |> set #deleteReason (Just "direct_read_fixture") |> updateRecord

    otherWeek <- createRosterWeekRecordForRosterGroup venue otherRosterGroup 0 False
    otherDay <- createRosterDayRecord otherWeek 0
    otherGroupSlot <- createRosterSlotRecord otherDay otherSlotName (Just eligibleStaff) 0

    pure DirectReadModelFixture { venue, manager, rosterGroup, earlySlotName, rosterWeek, eligibleUser, eligibleStaff, assignedInactiveStaff = assignedInactiveStaff', visibleSparseSlot, closedDaySlot, otherGroupSlot }

sortSlotDefinitions :: [RosterWeekSlotDefinition] -> [RosterWeekSlotDefinition]
sortSlotDefinitions = sortOn (\slotDefinition -> (slotDefinition.sortOrder, slotDefinition.createdAt))

allAssignmentFilters :: RosterAssignmentFilters
allAssignmentFilters =
    RosterAssignmentFilters
        { hideStaffAtIdealShifts = True
        , hideStaffUnavailable = True
        , hideStaffOnApprovedLeave = True
        , hideStaffAlreadyAssignedToday = True
        }

hasConflictType :: ConflictType -> Maybe [RosterConflict] -> Bool
hasConflictType expected = maybe False (any ((== expected) . (.conflictType)))

createStaffShiftPreferenceRecord :: (?modelContext :: ModelContext) => Venue -> Staff -> Int -> Int -> Int -> IO StaffShiftPreference
createStaffShiftPreferenceRecord venue staff weekdayIndex startHour endHour =
    newRecord @StaffShiftPreference
        |> set #venueId (unpackId venue.id)
        |> set #staffId (unpackId staff.id)
        |> set #weekdayIndex weekdayIndex
        |> set #preferredStartHour startHour
        |> set #preferredEndHour endHour
        |> createRecord
