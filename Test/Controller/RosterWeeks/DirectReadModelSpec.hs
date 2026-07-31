{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}

module Test.Controller.RosterWeeks.DirectReadModelSpec where

import Application.Helper.Conflict
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        ensureVenueDefaultRosterGroup)
import Application.Helper.WeekBoundaries (weekdayIndexForDay)
import Data.Coerce (coerce)
import Data.List (find, sortOn)
import qualified Data.Map.Strict as Map
import Data.Maybe (fromJust)
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import qualified Data.Time.Calendar as Calendar
import Data.Time.Clock (getCurrentTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Web.RosterWeeks.DirectReadModel
import Web.RosterWeeks.Filters
import Web.RosterWeeks.RenderData
import Web.RosterWeeks.Types


tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "RosterWeeksController direct read model" do
        it "reads manager-visible base facts directly" $ withContext do
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

        it "keeps deployed record decoding independent of physical table order" $ withContext do
            directReadSource <- TextIO.readFile "Web/RosterWeeks/DirectReadModel.hs"
            mutationSource <- TextIO.readFile "Web/Timesheets/Mutations.hs"
            directReadSource `shouldSatisfy` (not . Text.isInfixOf "SELECT roster_slots.*")
            directReadSource `shouldSatisfy` (not . Text.isInfixOf "SELECT staff.*")
            mutationSource `shouldSatisfy` (not . Text.isInfixOf "SELECT timesheet_entries.*")
            mutationSource `shouldSatisfy` (not . Text.isInfixOf "SELECT roster_slots.*")

        it "builds direct render data with the same base facts used by the roster seam" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                renderData <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        fetchVisibleRosterReadModel fixture.rosterGroup.id 0

                let rosterData = fromJust renderData
                rosterData.rosterWeek.id `shouldBe` fixture.rosterWeek.id
                map (.id) rosterData.staffMembers `shouldContain` [fixture.eligibleStaff.id, fixture.assignedInactiveStaff.id]
                map (.id) rosterData.allSlots `shouldContain` [fixture.visibleSparseSlot.id, fixture.closedDaySlot.id]
                map (.id) rosterData.orderedSlotNames `shouldBe` map (.id) (sortSlotDefinitions rosterData.orderedSlotNames)

        it "reads venue role values for direct staff panel entries" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture
                membership <- query @VenueMembership
                    |> filterWhere (#venueId, unpackId fixture.venue.id)
                    |> filterWhere (#userId, unpackId fixture.eligibleUser.id)
                    |> fetchOne
                _ <- membership
                    |> set #venueRole Manager
                    |> updateRecord

                entries <- withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        fetchRosterStaffPanelEntriesDirect RosterStaffPanelCurrentGroup fixture.rosterGroup.id fixture.rosterWeek

                let entry = fromJust (find ((== fixture.eligibleStaff.id) . (.staff.id)) entries)
                entry.userRole `shouldBe` "manager"

        it "derives direct assignment option hidden reasons from SQL facts" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        initialData <- fromJust <$> fetchVisibleRosterReadModel fixture.rosterGroup.id 0
                        openDay <- fetch (Id fixture.visibleSparseSlot.rosterDayId) :: IO RosterDay
                        _ <- fixture.eligibleStaff |> set #idealShiftsPerWeek 1 |> updateRecord
                        _ <- createRosterSlotRecord openDay fixture.earlySlotName (Just fixture.eligibleStaff) 4
                        _ <- createLeaveRequestRecord fixture.venue fixture.eligibleStaff initialData.weekStartDate (Calendar.addDays 1 initialData.weekStartDate) LeaveRequestStatusEnumApproved

                        facts <- fromJust <$> fetchRosterBaseFactsDirect fixture.rosterGroup.id 0
                        states <- buildRosterStaffOptionStatesDirect allAssignmentFilters initialData.weekStartDate facts.baseVisibleSlots facts.baseStaffMembers

                        let targetState = fromJust (Map.lookup (coerce fixture.visibleSparseSlot.id, coerce fixture.eligibleStaff.id) states)
                        targetState.optionHidden `shouldBe` True
                        targetState.optionHiddenByIdeal `shouldBe` True
                        targetState.optionHiddenByUnavailable `shouldBe` True
                        targetState.optionHiddenByLeave `shouldBe` True
                        targetState.optionHiddenByAssignedToday `shouldBe` True

        it "uses the authoritative local start date for after-midnight preferences" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        initialData <- fromJust <$> fetchVisibleRosterReadModel fixture.rosterGroup.id 0
                        openDay <- fetch (Id fixture.visibleSparseSlot.rosterDayId) :: IO RosterDay
                        staff <- createStaffRecord fixture.venue Nothing "After Midnight" "Preference"
                        slot <- createRosterSlotRecord openDay fixture.earlySlotName (Just staff) 8
                            >>= updateRecord
                                . setTestRosterSlotBoundaries initialData.weekStartDate (TimeOfDay 1 0 0) (TimeOfDay 2 0 0)
                        _ <- createStaffShiftPreferenceRecord fixture.venue staff (weekdayIndexForDay (Calendar.addDays 1 initialData.weekStartDate)) 5 6

                        states <- buildRosterStaffOptionStatesForSlotsDirect allAssignmentFilters initialData.weekStartDate [slot] [slot] [staff]
                        let targetState = fromJust (Map.lookup (coerce slot.id, coerce staff.id) states)
                        targetState.optionHiddenByUnavailable `shouldBe` False

                        conflicts <- buildSlotConflictsForSlotsDirect fixture.rosterGroup.id 0 initialData.weekStartDate [slot] [slot]
                        lookup slot.id conflicts `shouldNotSatisfy` hasConflictType ShiftPreferenceDayUnavailable
                        lookup slot.id conflicts `shouldSatisfy` hasConflictType ShiftPreferenceSlotMismatch

        it "derives each direct roster conflict type from SQL facts" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        (duplicateSlot, lateSlot, preferenceSlot) <- addDirectReadModelConflictFacts fixture
                        initialData <- fromJust <$> fetchVisibleRosterReadModel fixture.rosterGroup.id 0
                        facts <- fromJust <$> fetchRosterBaseFactsDirect fixture.rosterGroup.id 0
                        conflicts <- buildSlotConflictsDirect fixture.rosterGroup.id 480 initialData.weekStartDate facts.baseVisibleSlots

                        let allTypes = sort (concatMap (map (.conflictType) . snd) conflicts)
                        forM_ [DuplicateAssignment, LeaveConflict, LateToEarlyConflict, ShiftPreferenceDayUnavailable, ShiftPreferenceSlotMismatch, IdealShiftThresholdExceeded] $ \conflictType ->
                            allTypes `shouldContain` [conflictType]
                        lookup fixture.visibleSparseSlot.id conflicts `shouldSatisfy` hasConflictType LateToEarlyConflict
                        lookup duplicateSlot.id conflicts `shouldSatisfy` hasConflictType DuplicateAssignment
                        lookup lateSlot.id conflicts `shouldSatisfy` hasConflictType LateToEarlyConflict
                        lookup preferenceSlot.id conflicts `shouldSatisfy` hasConflictType ShiftPreferenceSlotMismatch

        it "evaluates late-to-early gaps from exact start instants" $ withContext do
            withCleanDb do
                fixture <- createDirectReadModelFixture

                withUserAndCurrentVenue fixture.manager fixture.venue.id do
                    withCurrentControllerContext do
                        initialData <- fromJust <$> fetchVisibleRosterReadModel fixture.rosterGroup.id 0
                        rosterDay <- fetch (Id fixture.visibleSparseSlot.rosterDayId) :: IO RosterDay
                        firstSlot <- createRosterSlotRecord rosterDay fixture.earlySlotName (Just fixture.eligibleStaff) 9
                            >>= updateRecord
                                . setTestRosterSlotBoundaries initialData.weekStartDate (TimeOfDay 9 0 30) (TimeOfDay 9 30 30)
                        secondSlot <- createRosterSlotRecord rosterDay fixture.earlySlotName (Just fixture.eligibleStaff) 10
                            >>= updateRecord
                                . setTestRosterSlotBoundaries initialData.weekStartDate (TimeOfDay 10 0 0) (TimeOfDay 10 30 0)

                        conflicts <- buildSlotConflictsForSlotsDirect fixture.rosterGroup.id 60 initialData.weekStartDate [firstSlot, secondSlot] [firstSlot, secondSlot]

                        lookup firstSlot.id conflicts `shouldSatisfy` hasConflictType LateToEarlyConflict
                        lookup secondSlot.id conflicts `shouldSatisfy` hasConflictType LateToEarlyConflict

addDirectReadModelConflictFacts :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => DirectReadModelFixture -> IO (RosterSlot, RosterSlot, RosterSlot)
addDirectReadModelConflictFacts fixture = do
    initialData <- fromJust <$> fetchVisibleRosterReadModel fixture.rosterGroup.id 0
    openDay <- fetch (Id fixture.visibleSparseSlot.rosterDayId) :: IO RosterDay
    nextDay <- query @RosterDay
        |> filterWhere (#rosterWeekId, unpackId fixture.rosterWeek.id)
        |> filterWhere (#dayOffset, 1)
        |> fetchOne
    _ <- nextDay |> set #isClosed False |> updateRecord
    _ <- fixture.assignedInactiveStaff |> set #idealShiftsPerWeek 1 |> updateRecord
    duplicateSlot <- createRosterSlotRecord openDay fixture.earlySlotName (Just fixture.assignedInactiveStaff) 5 >>= \slot ->
        slot |> setTestStartTime (Just (TimeOfDay 12 0 0)) |> updateRecord
    lateSlot <- createRosterSlotRecord nextDay fixture.earlySlotName (Just fixture.assignedInactiveStaff) 7 >>= \slot ->
        slot
            |> setTestRosterSlotBoundaries (Calendar.addDays 1 initialData.weekStartDate) (TimeOfDay 6 0 0) (TimeOfDay 7 0 0)
            |> updateRecord
    _ <- fixture.visibleSparseSlot |> setTestStartTime (Just (TimeOfDay 23 0 0)) |> updateRecord
    _ <- createLeaveRequestRecord fixture.venue fixture.assignedInactiveStaff initialData.weekStartDate (Calendar.addDays 1 initialData.weekStartDate) LeaveRequestStatusEnumApproved
    preferenceStaff <- createStaffRecord fixture.venue Nothing "Pref" "Mismatch"
    preferenceSlot <- createRosterSlotRecord openDay fixture.earlySlotName (Just preferenceStaff) 6 >>= \slot ->
        slot |> setTestStartTime (Just (TimeOfDay 12 0 0)) |> updateRecord
    _ <- createStaffShiftPreferenceRecord fixture.venue preferenceStaff (weekdayIndexForDay initialData.weekStartDate) 9 10
    pure (duplicateSlot, lateSlot, preferenceSlot)

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
    _ <- createVenueMembershipRecord venue manager Manager
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
    _ <- createVenueMembershipRecord venue eligibleUser Worker
    eligibleStaff <- createStaffRecord venue (Just eligibleUser) "Able" "Eligible"

    inactiveUser <- createUserRecord "direct-inactive@example.com" "staff" True
    _ <- createVenueMembershipRecord venue inactiveUser Worker
    assignedInactiveStaff <- createStaffRecord venue (Just inactiveUser) "Bert" "Inactive"
    assignedInactiveStaff' <- assignedInactiveStaff |> set #isActive False |> updateRecord

    rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 False
    rosterDays <- forM [0 :: Int .. 6] (createRosterDayRecord rosterWeek)
    let openDay = fromJust (head rosterDays)
    closedDay <- (rosterDays !! 1) |> set #isClosed True |> updateRecord

    visibleSparseSlot <- createRosterSlotRecord openDay earlySlotName (Just assignedInactiveStaff') 3 >>= \slot ->
        slot
            |> setTestStartTime (Just (TimeOfDay 9 0 0))
            |> set #shiftTypeId (Just (unpackId breakfast.id))
            |> updateRecord
    closedDaySlot <- createRosterSlotRecord closedDay earlySlotName (Just eligibleStaff) 0 >>= \slot ->
        slot
            |> setTestStartTime (Just (TimeOfDay 10 0 0))
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
