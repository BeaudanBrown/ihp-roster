module Test.RosterNotificationSpec where

import Application.Async.Registry (dispatchAppJob)
import Application.Helper.Mail (AppMailSettings (..))
import Application.RosterNotification
import Application.RosterNotification.Delivery
import Config (config)
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import Data.Either (isLeft)
import Data.IORef (modifyIORef', newIORef, readIORef)
import qualified Data.Set as Set
import Data.Text (isInfixOf)
import qualified Data.Text.Lazy as LazyText
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types hiding (createRosterNotificationRun)
import IHP.ControllerPrelude
import IHP.FrameworkConfig (withFrameworkConfig)
import IHP.Job.Types (JobStatus (JobStatusSucceeded))
import IHP.Mail
import qualified IHP.Mail as Mail
import IHP.Test.Mocking (withContext)
import Network.Mail.Mime (Address (..))
import Test.Hspec
import Test.Support
import qualified Text.Blaze.Html.Renderer.Text as Blaze
import Web.Mail.RosterNotification


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
                Set.size (Set.fromList (map (.dedupeKey) jobs)) `shouldBe` length jobs

        it "renders only the recipient's shifts and Open shifts from the snapshot" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Snapshot Mail Venue"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                recipientUser <- createUserRecord "snapshot-recipient@example.com" "staff" True
                _ <- createVenueMembershipRecord venue recipientUser Manager
                recipientStaff <- query @Staff |> filterWhere (#userId, Just (unpackId recipientUser.id)) |> fetchOne
                otherUser <- createUserRecord "other-schedule@example.com" "staff" True
                _ <- createVenueMembershipRecord venue otherUser Worker
                otherStaff <- query @Staff |> filterWhere (#userId, Just (unpackId otherUser.id)) |> fetchOne
                noShiftUser <- createUserRecord "no-shifts@example.com" "staff" True
                _ <- createVenueMembershipRecord venue noShiftUser Worker
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                ownLane <- createSlotNameRecordForRosterGroup venue rosterGroup "Front counter"
                otherLane <- createSlotNameRecordForRosterGroup venue rosterGroup "Private schedule"
                openLane <- createSlotNameRecordForRosterGroup venue rosterGroup "Open coverage"
                ownShift <- createCompleteRosterSlotRecord rosterDay ownLane recipientStaff 0
                _ <- createCompleteRosterSlotRecord rosterDay otherLane otherStaff 1
                _ <- createRosterSlotRecord rosterDay openLane Nothing 2
                    >>= updateRecord
                        . set #shiftTypeId ownShift.shiftTypeId
                        . setTestRosterSlotBoundaries defaultWeekEpoch (TimeOfDay 12 0 0) (TimeOfDay 16 0 0)
                run <- createRosterNotificationRun recipientUser rosterWeek
                snapshot <- decodeRosterNotificationSnapshot run
                recipients <- decodeRosterNotificationRecipients run
                recipient <- maybe (fail "expected notification recipient") pure (find (\entry -> entry.recipientUserId == unpackId recipientUser.id) recipients)
                noShiftRecipient <- maybe (fail "expected no-shift notification recipient") pure (find (\entry -> entry.recipientUserId == unpackId noShiftUser.id) recipients)
                let mail = RosterNotificationMail
                        { notificationSnapshot = snapshot
                        , notificationRecipient = recipient
                        , rosterUrl = "https://app.example/ShowRosterWeek?weekOffset=0&rosterGroupId=test"
                        , fromAddress = "rosters@example.com"
                        , replyToAddress = "support@example.com"
                        , supportEmail = "support@example.com"
                        }
                let ?mail = mail
                subject `shouldBe` "Your Main roster for week of 6 January"
                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    addressEmail (to mail) `shouldBe` "snapshot-recipient@example.com"
                    text mail `shouldSatisfy` isInfixOf "Venue: Snapshot Mail Venue"
                    text mail `shouldSatisfy` isInfixOf "Roster group: Main"
                    text mail `shouldSatisfy` isInfixOf "Front counter"
                    text mail `shouldSatisfy` isInfixOf "Open shifts"
                    text mail `shouldSatisfy` isInfixOf "Open coverage"
                    text mail `shouldSatisfy` (not . isInfixOf "Private schedule")
                    text mail `shouldSatisfy` isInfixOf "https://app.example/ShowRosterWeek?weekOffset=0&rosterGroupId=test"
                    let renderedHtml = LazyText.toStrict (Blaze.renderHtml (Mail.html mail))
                    renderedHtml `shouldSatisfy` isInfixOf "Front counter"
                    renderedHtml `shouldSatisfy` isInfixOf "Open coverage"
                    renderedHtml `shouldSatisfy` (not . isInfixOf "Private schedule")
                    renderedHtml `shouldSatisfy` isInfixOf "https://app.example/ShowRosterWeek?weekOffset=0&amp;rosterGroupId=test"
                    let noShiftMail = mail { notificationRecipient = noShiftRecipient }
                    text noShiftMail `shouldSatisfy` isInfixOf "You have no assigned shifts in this roster."
                    text noShiftMail `shouldSatisfy` (not . isInfixOf "Front counter")
                    text noShiftMail `shouldSatisfy` isInfixOf "Open coverage"

        it "delivers from the immutable run after the roster returns to draft" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Draft Delivery Venue"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                actor <- createUserRecord "draft-delivery@example.com" "staff" True
                _ <- createVenueMembershipRecord venue actor Manager
                actorStaff <- query @Staff |> filterWhere (#userId, Just (unpackId actor.id)) |> fetchOne
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True
                run <- createRosterNotificationRun actor rosterWeek
                appJob <- query @AppJob
                    |> filterWhere (#relatedId, Just (unpackId run.id))
                    |> fetchOne
                _ <- rosterWeek |> set #isLive False |> updateRecord
                delivered <- newIORef []
                let runtime = RosterNotificationDeliveryRuntime
                        { deliveryBaseUrl = "https://app.example"
                        , deliveryMailSettings = AppMailSettings
                            { mailFromAddress = "rosters@example.com"
                            , mailReplyToAddress = "support@example.com"
                            , mailSupportEmail = "support@example.com"
                            }
                        , deliverRosterNotificationMail = \mail -> modifyIORef' delivered (mail :)
                        }

                performRosterNotificationDeliveryJobWith runtime appJob

                deliveredMails <- readIORef delivered
                length deliveredMails `shouldBe` 1
                let deliveredMail = head deliveredMails
                fmap (.notificationSnapshot.snapshotRosterWeekId) deliveredMail `shouldBe` Just (unpackId rosterWeek.id)
                updatedJob <- fetch appJob.id
                updatedJob.status `shouldBe` JobStatusSucceeded
                updatedJob.result `shouldBe` Aeson.object
                    [ "runId" Aeson..= unpackId run.id
                    , "recipientStaffId" Aeson..= unpackId actorStaff.id
                    , "recipientUserId" Aeson..= unpackId actor.id
                    , "deliveryStatus" Aeson..= ("sent" :: Text)
                    ]

        it "rejects cross-venue delivery jobs without sending" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Scoped Delivery Venue"
                otherVenue <- createVenueWithConfig "Other Delivery Venue"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                actor <- createUserRecord "scoped-delivery@example.com" "staff" True
                _ <- createVenueMembershipRecord venue actor Manager
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True
                run <- createRosterNotificationRun actor rosterWeek
                appJob <- query @AppJob |> filterWhere (#relatedId, Just (unpackId run.id)) |> fetchOne
                let tamperedJob = appJob |> set #venueId (Just (unpackId otherVenue.id))

                result <- withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    Exception.try (dispatchAppJob tamperedJob) :: IO (Either Exception.SomeException ())

                result `shouldSatisfy` isLeft
                unchangedJob <- fetch appJob.id
                unchangedJob.status `shouldNotBe` JobStatusSucceeded

        it "rejects malformed and unsupported delivery payloads before sending" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Payload Validation Venue"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                actor <- createUserRecord "payload-validation@example.com" "staff" True
                _ <- createVenueMembershipRecord venue actor Manager
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True
                run <- createRosterNotificationRun actor rosterWeek
                appJob <- query @AppJob |> filterWhere (#relatedId, Just (unpackId run.id)) |> fetchOne
                delivered <- newIORef (0 :: Int)
                let runtime = RosterNotificationDeliveryRuntime
                        { deliveryBaseUrl = "https://app.example"
                        , deliveryMailSettings = AppMailSettings "rosters@example.com" "support@example.com" "support@example.com"
                        , deliverRosterNotificationMail = \_ -> modifyIORef' delivered (+ 1)
                        }
                let invalidJobs =
                        [ appJob |> set #payloadSchemaVersion 999
                        , appJob |> set #payload (Aeson.object [])
                        ]

                results <- forM invalidJobs (Exception.try . performRosterNotificationDeliveryJobWith runtime) :: IO [Either Exception.SomeException ()]

                results `shouldSatisfy` all isLeft
                readIORef delivered >>= (`shouldBe` 0)

        it "propagates delivery failures so the durable job can retry the same snapshot" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Retry Delivery Venue"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                actor <- createUserRecord "retry-delivery@example.com" "staff" True
                _ <- createVenueMembershipRecord venue actor Manager
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True
                run <- createRosterNotificationRun actor rosterWeek
                appJob <- query @AppJob |> filterWhere (#relatedId, Just (unpackId run.id)) |> fetchOne
                attempts <- newIORef (0 :: Int)
                let failingRuntime = RosterNotificationDeliveryRuntime
                        { deliveryBaseUrl = "https://app.example"
                        , deliveryMailSettings = AppMailSettings "rosters@example.com" "support@example.com" "support@example.com"
                        , deliverRosterNotificationMail = \_ -> modifyIORef' attempts (+ 1) >> fail "temporary SMTP failure"
                        }
                firstAttempt <- Exception.try (performRosterNotificationDeliveryJobWith failingRuntime appJob) :: IO (Either Exception.SomeException ())
                let succeedingRuntime = failingRuntime
                        { deliverRosterNotificationMail = \_ -> modifyIORef' attempts (+ 1)
                        }

                firstAttempt `shouldSatisfy` isLeft
                performRosterNotificationDeliveryJobWith succeedingRuntime appJob

                readIORef attempts >>= (`shouldBe` 2)
                updatedJob <- fetch appJob.id
                updatedJob.status `shouldBe` JobStatusSucceeded

  where
    payloadRecipientEmail :: AppJob -> Maybe Text
    payloadRecipientEmail appJob =
        AesonTypes.parseMaybe (Aeson.withObject "payload" (Aeson..: "recipientEmail")) appJob.payload
