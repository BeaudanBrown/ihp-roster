module Test.RosterNotificationSpec where

import Application.Async.Queue (appJobMaxAttempts)
import Application.Async.Registry (dispatchAppJob)
import Application.Helper.Mail (AppMailSettings (..))
import Application.RosterNotification
import Application.RosterNotification.Delivery
import Config (config)
import Control.Concurrent (newEmptyMVar, putMVar, readMVar)
import Control.Concurrent.Async (async, wait)
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
import IHP.FrameworkConfig (FrameworkConfig, withFrameworkConfig)
import IHP.Job.Types (JobStatus (JobStatusSucceeded))
import IHP.Mail
import qualified IHP.Mail as Mail
import IHP.Test.Mocking (callActionWithParams, idToParam,
                         responseStatusShouldBe, withContext)
import Network.HTTP.Types.Status (status200)
import Network.Mail.Mime (Address (..))
import Test.Hspec
import Test.Support
import qualified Text.Blaze.Html.Renderer.Text as Blaze
import Web.Controller.RosterWeeks ()
import Web.FrontController ()
import Web.Mail.RosterNotification
import Web.Types


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

        it "delivers every recipient from one immutable snapshot while an Open shift is concurrently assigned" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Concurrent Snapshot Venue"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                actor <- createUserRecord "concurrent-snapshot-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue actor Manager
                actorStaff <- query @Staff |> filterWhere (#userId, Just (unpackId actor.id)) |> fetchOne
                otherUser <- createUserRecord "concurrent-snapshot-other@example.com" "staff" True
                _ <- createVenueMembershipRecord venue otherUser Worker
                otherStaff <- query @Staff |> filterWhere (#userId, Just (unpackId otherUser.id)) |> fetchOne
                noShiftUser <- createUserRecord "concurrent-snapshot-empty@example.com" "staff" True
                _ <- createVenueMembershipRecord venue noShiftUser Worker
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True
                rosterDay <- createRosterDayRecord rosterWeek 0
                actorLane <- createSlotNameRecordForRosterGroup venue rosterGroup "Manager only lane"
                otherLane <- createSlotNameRecordForRosterGroup venue rosterGroup "Other staff private lane"
                openLane <- createSlotNameRecordForRosterGroup venue rosterGroup "Snapshot open lane"
                actorShift <- createCompleteRosterSlotRecord rosterDay actorLane actorStaff 0
                _ <- createCompleteRosterSlotRecord rosterDay otherLane otherStaff 1
                openShift <- createRosterSlotRecord rosterDay openLane Nothing 2
                    >>= updateRecord
                        . set #shiftTypeId actorShift.shiftTypeId
                        . setTestRosterSlotBoundaries defaultWeekEpoch (TimeOfDay 12 0 0) (TimeOfDay 16 0 0)
                run <- withDatabaseTestContext \notificationContext -> do
                    startGate <- newEmptyMVar
                    createRunTask <- async $
                        withContext
                            ( do
                                readMVar startGate
                                createRosterNotificationRunUnlessActive actor rosterWeek
                            )
                            notificationContext
                    assignOpenShiftTask <- async do
                        readMVar startGate
                        withUserAndCurrentVenue actor venue.id do
                            callActionWithParams
                                (UpdateRosterSlotAction openShift.id)
                                [("staffId", idToParam otherStaff.id)]
                    putMVar startGate ()
                    creationResult <- wait createRunTask
                    fillResponse <- wait assignOpenShiftTask
                    fillResponse `responseStatusShouldBe` status200
                    case creationResult of
                        RosterNotificationRunCreated createdRun -> pure createdRun
                        _ -> fail "expected concurrent production run creation to succeed"
                immutableSnapshot <- decodeRosterNotificationSnapshot run
                appJobs <- query @AppJob
                    |> filterWhere (#relatedTable, Just "roster_notification_runs")
                    |> filterWhere (#relatedId, Just (unpackId run.id))
                    |> fetch
                delivered <- newIORef []
                let runtime = RosterNotificationDeliveryRuntime
                        { deliveryBaseUrl = "https://app.example"
                        , deliveryMailSettings = AppMailSettings "rosters@example.com" "support@example.com" "support@example.com"
                        , deliverRosterNotificationMail = \mail -> modifyIORef' delivered (mail :)
                        , invalidateRosterNotificationStatus = publishRosterNotificationStatusResource
                        }

                forM_ appJobs (performRosterNotificationDeliveryJobWith runtime)
                durableEvents <- query @LiveInvalidationEvent |> filterWhere (#source, "roster.notification.delivery.complete" :: Text) |> fetch
                length durableEvents `shouldBe` length appJobs
                forM_ durableEvents \durableEvent ->
                    query @LiveInvalidationEventResource |> filterWhere (#eventId, unpackId durableEvent.id) |> fetchCount `shouldReturn` 1

                deliveredMails <- readIORef delivered
                length deliveredMails `shouldBe` 3
                map (.notificationSnapshot) deliveredMails `shouldSatisfy` all (== immutableSnapshot)
                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    actorMail <- mailFor "concurrent-snapshot-manager@example.com" deliveredMails
                    otherMail <- mailFor "concurrent-snapshot-other@example.com" deliveredMails
                    noShiftMail <- mailFor "concurrent-snapshot-empty@example.com" deliveredMails
                    let concurrentShiftStayedOpen =
                            immutableSnapshot.snapshotShifts
                                |> find ((== "Snapshot open lane") . (.shiftLaneName))
                                |> maybe False (isNothing . (.shiftStaffId))
                    mailText actorMail `shouldSatisfy` isInfixOf "Manager only lane"
                    mailText actorMail `shouldSatisfy` (not . isInfixOf "Other staff private lane")
                    mailText otherMail `shouldSatisfy` isInfixOf "Other staff private lane"
                    mailText otherMail `shouldSatisfy` isInfixOf "Snapshot open lane"
                    mailText otherMail `shouldSatisfy` (not . isInfixOf "Manager only lane")
                    mailText noShiftMail `shouldSatisfy` isInfixOf "You have no assigned shifts in this roster."
                    mailText noShiftMail `shouldSatisfy` (not . isInfixOf "Manager only lane")
                    mailText noShiftMail `shouldSatisfy` (not . isInfixOf "Other staff private lane")
                    if concurrentShiftStayedOpen
                        then do
                            mailText actorMail `shouldSatisfy` isInfixOf "Snapshot open lane"
                            mailText noShiftMail `shouldSatisfy` isInfixOf "Snapshot open lane"
                        else do
                            mailText actorMail `shouldSatisfy` (not . isInfixOf "Snapshot open lane")
                            mailText noShiftMail `shouldSatisfy` (not . isInfixOf "Snapshot open lane")

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
                        , invalidateRosterNotificationStatus = \_ _ -> pure ()
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
                        , invalidateRosterNotificationStatus = \_ _ -> pure ()
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
                invalidations <- newIORef []
                let failingRuntime = RosterNotificationDeliveryRuntime
                        { deliveryBaseUrl = "https://app.example"
                        , deliveryMailSettings = AppMailSettings "rosters@example.com" "support@example.com" "support@example.com"
                        , deliverRosterNotificationMail = \_ -> modifyIORef' attempts (+ 1) >> fail "temporary SMTP failure"
                        , invalidateRosterNotificationStatus = \label _ -> modifyIORef' invalidations (label :)
                        }
                firstAttempt <- Exception.try (performRosterNotificationDeliveryJobWith failingRuntime appJob) :: IO (Either Exception.SomeException ())
                let succeedingRuntime = failingRuntime
                        { deliverRosterNotificationMail = \_ -> modifyIORef' attempts (+ 1)
                        }

                firstAttempt `shouldSatisfy` isLeft
                retryingJob <- fetch appJob.id
                retryingJob.status `shouldBe` JobStatusRetry
                readIORef invalidations >>= (`shouldBe` ["roster.notification.delivery.failed"])
                performRosterNotificationDeliveryJobWith succeedingRuntime appJob

                readIORef attempts >>= (`shouldBe` 2)
                readIORef invalidations >>= (`shouldBe` ["roster.notification.delivery.complete", "roster.notification.delivery.failed"])
                updatedJob <- fetch appJob.id
                updatedJob.status `shouldBe` JobStatusSucceeded

        it "marks the final provider failure terminal, invalidates status, and allows another deliberate run" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Terminal Delivery Venue"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                actor <- createUserRecord "terminal-delivery@example.com" "staff" True
                _ <- createVenueMembershipRecord venue actor Manager
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True
                run <- createRosterNotificationRun actor rosterWeek
                appJob <- query @AppJob |> filterWhere (#relatedId, Just (unpackId run.id)) |> fetchOne
                finalAttemptJob <- appJob |> set #attemptsCount appJobMaxAttempts |> updateRecord
                invalidations <- newIORef []
                let failingRuntime = RosterNotificationDeliveryRuntime
                        { deliveryBaseUrl = "https://app.example"
                        , deliveryMailSettings = AppMailSettings "rosters@example.com" "support@example.com" "support@example.com"
                        , deliverRosterNotificationMail = \_ -> fail "terminal SMTP failure"
                        , invalidateRosterNotificationStatus = \label _ -> modifyIORef' invalidations (label :)
                        }

                deliveryResult <- Exception.try (performRosterNotificationDeliveryJobWith failingRuntime finalAttemptJob) :: IO (Either Exception.SomeException ())

                deliveryResult `shouldSatisfy` isLeft
                failedJob <- fetch appJob.id
                failedJob.status `shouldBe` JobStatusFailed
                failedJob.lastError `shouldSatisfy` maybe False (isInfixOf "terminal SMTP failure")
                readIORef invalidations >>= (`shouldBe` ["roster.notification.delivery.failed"])
                repeatResult <- createRosterNotificationRunUnlessActive actor rosterWeek
                case repeatResult of
                    RosterNotificationRunCreated repeatedRun -> repeatedRun.id `shouldNotBe` run.id
                    _ -> expectationFailure "expected terminal delivery to permit another notification run"

  where
    mailFor :: Text -> [RosterNotificationMail] -> IO RosterNotificationMail
    mailFor emailAddress mails =
        maybe (fail ("expected delivered mail for " <> cs emailAddress)) pure $
            find ((== emailAddress) . (.recipientEmail) . (.notificationRecipient)) mails

    mailText :: (?context :: FrameworkConfig) => RosterNotificationMail -> Text
    mailText mail =
        let ?mail = mail
         in text mail

    payloadRecipientEmail :: AppJob -> Maybe Text
    payloadRecipientEmail appJob =
        AesonTypes.parseMaybe (Aeson.withObject "payload" (Aeson..: "recipientEmail")) appJob.payload
