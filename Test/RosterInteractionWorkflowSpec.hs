module Test.RosterInteractionWorkflowSpec where

import Data.UUID (UUID)
import qualified Data.UUID as UUID
import IHP.ModelSupport (unpackId)
import IHP.Prelude
import Test.Hspec
import Web.RosterWeeks.DropWorkflow

tests :: Spec
tests =
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

workflowUuid :: String -> UUID
workflowUuid value = fromMaybe (error "invalid roster workflow test UUID") (UUID.fromString value)
