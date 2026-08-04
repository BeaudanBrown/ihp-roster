module Test.RosterInteractionWorkflowSpec where

import Application.RosterShiftAssignment
import Application.VenueTime.Model
import Data.Either (isLeft)
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ModelSupport (newRecord, unpackId)
import IHP.ModelSupport.Types (Id' (Id))
import IHP.Prelude
import Test.Hspec
import Web.RosterWeeks.DropWorkflow
import Web.RosterWeeks.Service (rosterSlotBlocksPublish)
import Web.RosterWeeks.ShiftWorkflow

tests :: Spec
tests = do
    describe "roster interaction workflow tokens" do
        it "rejects malformed and wrong-kind opaque source tokens" do
            parseRosterDropSourceToken "" `shouldBe` Nothing
            parseRosterDropSourceToken "existing:not-a-uuid" `shouldBe` Nothing
            parseRosterDropSourceToken "staff:11111111-1111-1111-1111-111111111111:extra" `shouldBe` Nothing
            parseRosterDropSourceToken "day:11111111-1111-1111-1111-111111111111" `shouldBe` Nothing

        it "distinguishes existing shifts, staff, placement targets and delete without interpreting browser state" do
            let firstId = workflowUuid "11111111-1111-1111-1111-111111111111"
                secondId = workflowUuid "22222222-2222-2222-2222-222222222222"
            parseRosterDropSourceToken "existing:11111111-1111-1111-1111-111111111111"
                `shouldSatisfy` \case
                    Just (ExistingRosterShiftSource rosterSlotId) -> unpackId rosterSlotId == firstId
                    _ -> False
            parseRosterDropSourceToken "staff:11111111-1111-1111-1111-111111111111"
                `shouldSatisfy` \case
                    Just (RosterStaffSource staffId) -> unpackId staffId == firstId
                    _ -> False
            parseRosterShiftDropDestinationToken "delete"
                `shouldBe` Just DeleteRosterShiftDestination
            parseRosterShiftDropDestinationToken "day:11111111-1111-1111-1111-111111111111"
                `shouldSatisfy` \case
                    Just (PlaceRosterShiftDestination (DayRosterShiftDropTarget rosterDayId)) -> unpackId rosterDayId == firstId
                    _ -> False
            parseRosterShiftDropDestinationToken "new:11111111-1111-1111-1111-111111111111:22222222-2222-2222-2222-222222222222:3"
                `shouldSatisfy` \case
                    Just (PlaceRosterShiftDestination (PreciseRosterShiftDropTarget rosterDayId slotDefinitionId rowIndex)) ->
                        unpackId rosterDayId == firstId && unpackId slotDefinitionId == secondId && rowIndex == 3
                    _ -> False

        it "parses timeline placement as a typed target and rejects malformed minutes" do
            let firstId = workflowUuid "11111111-1111-1111-1111-111111111111"
                secondId = workflowUuid "22222222-2222-2222-2222-222222222222"
            parseTimelineShiftDropTargetToken "time:11111111-1111-1111-1111-111111111111:22222222-2222-2222-2222-222222222222:375"
                `shouldSatisfy` \case
                    Just TimelineShiftDropTarget { timelineTargetRosterDayId, timelineTargetSlotDefinitionId, timelineTargetOperationalMinute } ->
                        unpackId timelineTargetRosterDayId == firstId
                            && unpackId timelineTargetSlotDefinitionId == secondId
                            && timelineTargetOperationalMinute == 375
                    _ -> False
            parseTimelineShiftDropTargetToken "time:11111111-1111-1111-1111-111111111111:22222222-2222-2222-2222-222222222222:not-a-minute"
                `shouldBe` Nothing

    describe "explicit roster shift assignment" do
        it "applies Staff and Open as closed assignment variants" do
            let staffId = Id (workflowUuid "33333333-3333-3333-3333-333333333333") :: Id Staff
                assigned = applyRosterShiftAssignment (StaffAssignment staffId) (newRecord @RosterSlot)
                open = applyRosterShiftAssignment OpenAssignment assigned
                copied = copyRosterShiftAssignment open (newRecord @RosterSlot)

            assigned.assignmentState `shouldBe` "staff"
            assigned.staffId `shouldBe` Just (unpackId staffId)
            rosterShiftAssignment assigned `shouldBe` Right (StaffAssignment staffId)
            open.assignmentState `shouldBe` "open"
            open.staffId `shouldBe` Nothing
            rosterShiftAssignment open `shouldBe` Right OpenAssignment
            fmap (\slot -> (slot.assignmentState, slot.staffId)) copied
                `shouldBe` Right ("open", Nothing)

        it "rejects inconsistent or unknown persisted assignment shapes" do
            let invalidStaff = newRecord @RosterSlot |> set #assignmentState "staff" |> set #staffId Nothing
                invalidOpen = newRecord @RosterSlot |> set #assignmentState "open" |> set #staffId (Just (workflowUuid "33333333-3333-3333-3333-333333333333"))
                unknown = newRecord @RosterSlot |> set #assignmentState "unknown" |> set #staffId Nothing

            map (isLeft . rosterShiftAssignment) [invalidStaff, invalidOpen, unknown]
                `shouldBe` replicate 3 True

    describe "roster shift publication" do
        it "blocks structurally incomplete Open shifts" do
            let incompleteOpen = applyRosterShiftAssignment OpenAssignment (newRecord @RosterSlot)
            rosterSlotBlocksPublish incompleteOpen `shouldBe` True

    describe "roster shift workflow application" do
        it "applies one validated typed submission as exact authoritative slot fields" do
            let staffId = workflowUuid "33333333-3333-3333-3333-333333333333"
                shiftTypeId = workflowUuid "44444444-4444-4444-4444-444444444444"
                boundaryInput = ShiftBoundaryInput
                    { shiftBoundaryDate = fromGregorian 2025 1 6
                    , shiftBoundaryStartTime = TimeOfDay 9 0 0
                    , shiftBoundaryStartOccurrence = Nothing
                    , shiftBoundaryEndTime = TimeOfDay 17 0 0
                    , shiftBoundaryEndOccurrence = Nothing
                    , shiftBoundaryBreak = Nothing
                    }
                boundaries = either (error . show) (\value -> value) (resolveShiftBoundaries "Australia/Melbourne" boundaryInput)
                valid = ValidatedRosterShift
                    { validRosterShiftAssignment = StaffAssignment (Id staffId)
                    , validRosterShiftBoundaries = boundaries
                    , validRosterShiftTypeId = shiftTypeId
                    }
                slot = applyValidatedRosterShift valid (newRecord @RosterSlot)

            slot.assignmentState `shouldBe` "staff"
            slot.staffId `shouldBe` Just staffId
            slot.shiftTypeId `shouldBe` Just shiftTypeId
            slot.startsAt `shouldBe` Just (UTCTime (fromGregorian 2025 1 5) (secondsToDiffTime (22 * 60 * 60)))
            slot.endsAt `shouldBe` Just (UTCTime (fromGregorian 2025 1 6) (secondsToDiffTime (6 * 60 * 60)))
            slot.timezone `shouldBe` "Australia/Melbourne"

workflowUuid :: String -> UUID
workflowUuid value = fromMaybe (error "invalid roster workflow test UUID") (UUID.fromString value)
