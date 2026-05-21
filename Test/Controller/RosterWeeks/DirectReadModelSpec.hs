{-# LANGUAGE OverloadedLabels    #-}
{-# LANGUAGE OverloadedRecordDot #-}

module Test.Controller.RosterWeeks.DirectReadModelSpec where

import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        ensureVenueDefaultRosterGroup)
import Data.List (sortOn)
import Data.Maybe (fromJust)
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

data DirectReadModelFixture = DirectReadModelFixture
    { venue                 :: Venue
    , manager               :: User
    , rosterGroup           :: RosterGroup
    , rosterWeek            :: RosterWeek
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

    pure DirectReadModelFixture { venue, manager, rosterGroup, rosterWeek, eligibleStaff, assignedInactiveStaff = assignedInactiveStaff', visibleSparseSlot, closedDaySlot, otherGroupSlot }

sortSlotDefinitions :: [RosterWeekSlotDefinition] -> [RosterWeekSlotDefinition]
sortSlotDefinitions = sortOn (\slotDefinition -> (slotDefinition.sortOrder, slotDefinition.createdAt))
