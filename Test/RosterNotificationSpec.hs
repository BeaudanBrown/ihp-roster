module Test.RosterNotificationSpec where

import Application.RosterNotification
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Set as Set
import Generated.Types hiding (createRosterNotificationRun)
import IHP.ControllerPrelude
import IHP.Test.Mocking (withContext)
import Test.Hspec
import Test.Support


tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Roster notification runs" do
        it "snapshots every eligible linked group staff member and queues one durable delivery each" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Notification Venue"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                actor <- createUserRecord "manager-notify@example.com" "staff" True
                _ <- createVenueMembershipRecord venue actor Manager
                worker <- createUserRecord "worker-notify@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                _trial <- createStaffRecord venue Nothing "Trial" "Person"
                inactiveUser <- createUserRecord "inactive-notify@example.com" "staff" True
                _ <- createVenueMembershipRecord venue inactiveUser Worker
                inactiveStaff <- query @Staff |> filterWhere (#userId, Just (unpackId inactiveUser.id)) |> fetchOne
                _ <- inactiveStaff |> set #isActive False |> updateRecord
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 2 True

                run <- createRosterNotificationRun actor rosterWeek

                recipients <- decodeRosterNotificationRecipients run
                skipped <- decodeRosterNotificationSkippedRecipients run
                Set.fromList (map (.recipientEmail) recipients)
                    `shouldBe` Set.fromList ["manager-notify@example.com", "worker-notify@example.com"]
                Set.fromList (map (.skippedReason) skipped)
                    `shouldBe` Set.fromList [RosterNotificationSkippedUnlinked, RosterNotificationSkippedInactive]
                run.requestedByUserId `shouldBe` unpackId actor.id
                run.rosterWeekId `shouldBe` unpackId rosterWeek.id
                jobs <- query @AppJob
                    |> filterWhere (#relatedTable, Just "roster_notification_runs")
                    |> filterWhere (#relatedId, Just (unpackId run.id))
                    |> fetch
                length jobs `shouldBe` 2
                Set.fromList (map payloadRecipientEmail jobs)
                    `shouldBe` Set.fromList [Just "manager-notify@example.com", Just "worker-notify@example.com"]
                map (.dedupeKey) jobs `shouldSatisfy` all isJust
  where
    payloadRecipientEmail :: AppJob -> Maybe Text
    payloadRecipientEmail appJob =
        AesonTypes.parseMaybe (Aeson.withObject "payload" (Aeson..: "recipientEmail")) appJob.payload
