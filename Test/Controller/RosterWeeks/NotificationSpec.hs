module Test.Controller.RosterWeeks.NotificationSpec where

import Application.Helper.RosterGroups (syncStaffRosterGroupAssignments)
import Data.Maybe (fromJust)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders)
import Test.Hspec
import Test.Support
import Web.Controller.RosterWeeks ()
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "RosterWeeksController.Notification" do
        it "shows a Published roster email confirmation with recipient and skipped counts" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Confirmation Venue"
                rosterGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> fetchOne
                manager <- createUserRecord "notification-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                managerStaff <- query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#userId, Just (unpackId manager.id))
                    |> fetchOne
                trialStaff <- createStaffRecord venue Nothing "Trial" "Recipient"
                syncStaffRosterGroupAssignments managerStaff [rosterGroup.id]
                syncStaffRosterGroupAssignments trialStaff [rosterGroup.id]
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowRosterNotificationConfirmationAction (rosterNotificationParams rosterWeek)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Email roster"
                response `responseBodyShouldContain` "Confirmation Venue"
                response `responseBodyShouldContain` rosterGroup.name
                response `responseBodyShouldContain` "1 recipient"
                response `responseBodyShouldContain` "1 skipped"

        it "queues an immutable notification run and returns queued and skipped toast counts" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Queue Venue"
                rosterGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> fetchOne
                manager <- createUserRecord "queue-notification-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                managerStaff <- query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#userId, Just (unpackId manager.id))
                    |> fetchOne
                trialStaff <- createStaffRecord venue Nothing "Skipped" "Trial"
                syncStaffRosterGroupAssignments managerStaff [rosterGroup.id]
                syncStaffRosterGroupAssignments trialStaff [rosterGroup.id]
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateRosterNotificationRunAction (rosterNotificationParams rosterWeek)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Roster email queued for 1 recipient. 1 skipped."
                responseHeaders response `shouldContain` [("HX-Reswap", "none")]
                lookup "HX-Trigger" (responseHeaders response) `shouldSatisfy` isJust
                runs <- query @RosterNotificationRun |> fetch
                length runs `shouldBe` 1
                (fromJust (head runs)).requestedByUserId `shouldBe` unpackId manager.id
                jobs <- query @AppJob
                    |> filterWhere (#relatedTable, Just "roster_notification_runs")
                    |> fetch
                length jobs `shouldBe` 1

        it "does not create another run while the latest delivery is active" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Active Run Venue"
                rosterGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> fetchOne
                manager <- createUserRecord "active-run-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                managerStaff <- query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#userId, Just (unpackId manager.id))
                    |> fetchOne
                syncStaffRosterGroupAssignments managerStaff [rosterGroup.id]
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True

                firstResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateRosterNotificationRunAction (rosterNotificationParams rosterWeek)
                secondResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateRosterNotificationRunAction (rosterNotificationParams rosterWeek)

                firstResponse `responseStatusShouldBe` status200
                secondResponse `responseStatusShouldBe` status200
                secondResponse `responseBodyShouldContain` "Roster email delivery is already in progress."
                pageResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))
                pageResponse `responseStatusShouldBe` status200
                pageResponse `responseBodyShouldContain` "Roster email delivery is in progress."
                runs <- query @RosterNotificationRun |> fetch
                length runs `shouldBe` 1

        it "keeps Email roster visible but disabled when a Published roster has no eligible recipients" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Zero Recipient Venue"
                rosterGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> fetchOne
                manager <- createUserRecord "zero-recipient-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                managerStaff <- query @Staff
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#userId, Just (unpackId manager.id))
                    |> fetchOne
                syncStaffRosterGroupAssignments managerStaff []
                _ <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True

                response <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "id=\"roster-email-button\""
                response `responseBodyShouldContain` "No eligible recipients"

        it "rejects a direct send when no eligible recipients remain" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "No Audience Send Venue"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "no-audience-send-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                managerStaff <- query @Staff |> filterWhere (#userId, Just (unpackId manager.id)) |> fetchOne
                syncStaffRosterGroupAssignments managerStaff []
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True

                response <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateRosterNotificationRunAction (rosterNotificationParams rosterWeek)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "No eligible recipients are available."
                runs <- query @RosterNotificationRun |> fetch
                length runs `shouldBe` 0

        it "summarizes the latest attempted run in confirmation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Latest Run Venue"
                rosterGroup <- query @RosterGroup
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> fetchOne
                manager <- createUserRecord "latest-run-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                worker <- createUserRecord "latest-run-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                managerStaff <- query @Staff |> filterWhere (#userId, Just (unpackId manager.id)) |> fetchOne
                workerStaff <- query @Staff |> filterWhere (#userId, Just (unpackId worker.id)) |> fetchOne
                trialStaff <- createStaffRecord venue Nothing "Latest" "Trial"
                syncStaffRosterGroupAssignments managerStaff [rosterGroup.id]
                syncStaffRosterGroupAssignments workerStaff [rosterGroup.id]
                syncStaffRosterGroupAssignments trialStaff [rosterGroup.id]
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True
                _ <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateRosterNotificationRunAction (rosterNotificationParams rosterWeek)
                jobs <- query @AppJob |> orderByAsc #createdAt |> fetch
                case jobs of
                    [firstJob, secondJob] -> do
                        _ <- firstJob |> set #status JobStatusSucceeded |> updateRecord
                        _ <- secondJob |> set #status JobStatusFailed |> updateRecord
                        pure ()
                    _ -> expectationFailure "expected two notification delivery jobs"

                response <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowRosterNotificationConfirmationAction (rosterNotificationParams rosterWeek)

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "latest-run-manager@example.com"
                response `responseBodyShouldContain` "Requested"
                response `responseBodyShouldContain` "Delivered"
                response `responseBodyShouldContain` ">1</dd>"
                response `responseBodyShouldContain` "In progress"
                response `responseBodyShouldContain` "Failed"
                response `responseBodyShouldContain` "2 recipients"
                response `responseBodyShouldContain` "1 skipped"

                repeatResponse <- withUserAndCurrentVenue manager venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateRosterNotificationRunAction (rosterNotificationParams rosterWeek)
                repeatResponse `responseStatusShouldBe` status200
                repeatResponse `responseBodyShouldContain` "Roster email queued for 2 recipients. 1 skipped."
                runs <- query @RosterNotificationRun |> fetch
                length runs `shouldBe` 2

        it "hides Email roster from workers and on draft weeks" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Visibility Venue"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "visibility-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                worker <- createUserRecord "visibility-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True

                workerResponse <- withUserAndCurrentVenue worker venue.id do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))
                rosterDays <- query @RosterDay
                    |> filterWhere (#rosterGroupId, rosterWeek.fixtureRosterGroupId)
                    |> fetch
                _ <- mapM (updateRecord . set #publicationState Draft) rosterDays
                managerResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction (ShowRosterWindowAction (tshow (testAnchorForOffset 0)))

                workerResponse `responseStatusShouldBe` status200
                workerResponse `responseBodyShouldNotContain` "id=\"roster-email-button\""
                managerResponse `responseStatusShouldBe` status200
                managerResponse `responseBodyShouldNotContain` "id=\"roster-email-button\""

        it "rejects worker and cross-venue notification submissions" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Authorized Venue"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "scope-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                worker <- createUserRecord "scope-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                localWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True
                foreignVenue <- createVenueWithConfig "Foreign Venue"
                foreignGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId foreignVenue.id) |> fetchOne
                foreignWeek <- createRosterWeekRecordForRosterGroup foreignVenue foreignGroup 0 True

                workerResponse <- withUserAndCurrentVenue worker venue.id do
                    callActionWithParams CreateRosterNotificationRunAction (rosterNotificationParams localWeek)
                crossVenueResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateRosterNotificationRunAction (rosterNotificationParams foreignWeek)

                workerResponse `responseStatusShouldBe` status302
                crossVenueResponse `responseStatusShouldBe` status403
                runs <- query @RosterNotificationRun |> fetch
                length runs `shouldBe` 0

        it "rejects malformed notification week ids without creating a run" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Malformed Notification Venue"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                manager <- createUserRecord "malformed-notification-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True

                confirmationResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams ShowRosterNotificationConfirmationAction [("rosterGroupId", "not-a-uuid")]
                sendResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateRosterNotificationRunAction [("rosterGroupId", "not-a-uuid")]
                missingConfirmationResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction ShowRosterNotificationConfirmationAction
                missingSendResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction CreateRosterNotificationRunAction

                confirmationResponse `responseStatusShouldBe` status400
                sendResponse `responseStatusShouldBe` status400
                missingConfirmationResponse `responseStatusShouldBe` status400
                missingSendResponse `responseStatusShouldBe` status400
                runs <- query @RosterNotificationRun |> fetch
                length runs `shouldBe` 0

        it "records the actual founder actor during support-mode delivery" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Support Notification Venue"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                founder <- createUserRecordWithPlatformRole "notification-founder@example.com" "staff" (Just SuperAdmin) True
                worker <- createUserRecord "support-notification-worker@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                workerStaff <- query @Staff |> filterWhere (#userId, Just (unpackId worker.id)) |> fetchOne
                syncStaffRosterGroupAssignments workerStaff [rosterGroup.id]
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True

                response <- withUserAndCurrentVenue founder venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateRosterNotificationRunAction (rosterNotificationParams rosterWeek)

                response `responseStatusShouldBe` status200
                run <- query @RosterNotificationRun |> fetchOne
                run.requestedByUserId `shouldBe` unpackId founder.id
