module Test.RosterNotificationSpec where

import Application.Async.Queue (appJobMaxAttempts)
import Application.Async.Registry (dispatchAppJob)
import Application.EmailDelivery
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterNotificationStatusResource)
import Application.Helper.LiveUpdate.DurableCodec (DurableResource (..),
                                                   encodeDurableResource)
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults)
import Application.RosterNotification
import Config (config)
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.Types as AesonTypes
import Data.Either (isLeft)
import Data.IORef (modifyIORef', newIORef, readIORef)
import qualified Data.Set as Set
import Data.Text (isInfixOf)
import qualified Data.Text.Lazy as LazyText
import Data.Time.Calendar (addDays, fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types hiding (createRosterNotificationRun)
import IHP.ControllerPrelude
import IHP.FrameworkConfig (withFrameworkConfig)
import IHP.Job.Types (JobStatus (JobStatusFailed, JobStatusSucceeded))
import qualified IHP.MailPrelude as Mail
import IHP.Test.Mocking (withContext)
import Network.Mail.Mime (Address (..))
import Test.Hspec
import Test.Support
import Test.Support.EmailDelivery
import qualified IHP.HSX.Markup as Markup
import Web.Mail.RosterNotification


tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Roster notification runs" do
        it "creates immutable runs for native Published date windows without a roster week" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Native notification window"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                actor <- createUserRecord "native-notify@example.com" "staff" True
                _ <- createVenueMembershipRecord venue actor Manager
                let windowStart = fromGregorian 2027 2 1
                let windowEnd = addDays 7 windowStart
                forM_ [0 .. 6] \dayOffset ->
                    newRecord @RosterDay
                        |> set #venueId (unpackId venue.id)
                        |> set #rosterGroupId (unpackId rosterGroup.id)
                        |> set #operationalDate (addDays dayOffset windowStart)
                        |> set #publicationState Published
                        |> createRecord

                run <- createRosterNotificationRunForWindow actor venue rosterGroup windowStart windowEnd
                snapshot <- decodeRosterNotificationSnapshot run

                run.weekStart `shouldBe` windowStart
                run.windowEnd `shouldBe` windowEnd
                snapshot.snapshotWeekStart `shouldBe` windowStart
                snapshot.snapshotWeekEnd `shouldBe` addDays (-1) windowEnd

        it "uses explicit Operational dates for notification identity" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Notification Venue"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                actor <- createUserRecord "manager-notify@example.com" "staff" True
                _ <- createVenueMembershipRecord venue actor Manager
                worker <- createUserRecord "worker-notify@example.com" "staff" True
                _ <- createVenueMembershipRecord venue worker Worker
                _ <- createStaffRecord venue Nothing "Trial" "Person"
                inactiveUser <- createUserRecord "inactive-notify@example.com" "staff" True
                _ <- createVenueMembershipRecord venue inactiveUser Worker
                inactiveStaff <- query @Staff |> filterWhere (#userId, Just (unpackId inactiveUser.id)) |> fetchOne
                _ <- inactiveStaff |> set #isActive False |> updateRecord
                rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 2 True

                run <- createRosterNotificationRunForWindow actor venue rosterGroup rosterWeek.fixtureWindowStart (addDays 7 rosterWeek.fixtureWindowStart)

                recipients <- decodeRosterNotificationRecipients run
                skipped <- decodeRosterNotificationSkippedRecipients run
                Set.fromList (map (.recipientEmail) recipients)
                    `shouldBe` Set.fromList ["manager-notify@example.com", "worker-notify@example.com"]
                Set.fromList (map (.skippedReason) skipped)
                    `shouldBe` Set.fromList [RosterNotificationSkippedUnlinked, RosterNotificationSkippedInactive]
                run.requestedByUserId `shouldBe` unpackId actor.id
                run.weekStart `shouldBe` testAnchorForOffset 2
                jobs <- query @AppJob
                    |> filterWhere (#relatedTable, Just "roster_notification_runs")
                    |> filterWhere (#relatedId, Just (unpackId run.id))
                    |> fetch
                length jobs `shouldBe` 2
                map (.jobKind) jobs `shouldSatisfy` all (== emailDeliveryJobKind)
                Set.fromList (map payloadRecipientAddress jobs)
                    `shouldBe` Set.fromList [Just "manager-notify@example.com", Just "worker-notify@example.com"]
                map payloadMailKind jobs `shouldSatisfy` all (== Just rosterNotificationMailKind)
                tshow (map (.payload) jobs) `shouldSatisfy` not . isInfixOf "Notification Venue"

        it "rejects a window whose Published days belong to another group" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Mismatched notification provenance"
                rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                otherGroup <- createVenueRosterGroupWithDefaults venue "Other group" 2 False
                actor <- createUserRecord "mismatched-notify@example.com" "staff" True
                _ <- createVenueMembershipRecord venue actor Manager
                _otherWindow <- createRosterWindowRecordForRosterGroupAt venue otherGroup (testAnchorForOffset 0) True

                result <- Exception.try (createRosterNotificationRunForWindow actor venue rosterGroup (testAnchorForOffset 0) (addDays 7 (testAnchorForOffset 0))) :: IO (Either Exception.SomeException RosterNotificationRun)
                result `shouldSatisfy` isLeft

        it "excludes migration-retired legacy jobs from delivered run summaries" $ withContext do
            withCleanDb do
                (run, _, _, _, _) <- createRosterMailFixture
                [retiredJob, sentJob] <- query @AppJob
                    |> filterWhere (#relatedId, Just (unpackId run.id))
                    |> orderByAsc #createdAt
                    |> fetch
                _ <- retiredJob
                    |> set #jobKind "roster_notification_delivery"
                    |> set #status JobStatusSucceeded
                    |> set #result
                        ( Aeson.object
                            [ "deliveryStatus" Aeson..= ("retired_during_email_pipeline_migration" :: Text)
                            ]
                        )
                    |> updateRecord
                _ <- sentJob
                    |> set #status JobStatusSucceeded
                    |> set #result (Aeson.object ["deliveryStatus" Aeson..= ("sent" :: Text)])
                    |> updateRecord

                Just summary <-
                    fetchLatestRosterNotificationRunSummaryForWindow
                        (Id run.venueId)
                        (Id run.rosterGroupId)
                        run.weekStart
                        run.windowEnd
                summary.summaryRecipientCount `shouldBe` 2
                summary.summaryDeliveredCount `shouldBe` 1
                summary.summaryInProgressCount `shouldBe` 0

        it "renders only the recipient's shifts and Open shifts from the snapshot" $ withContext do
            withCleanDb do
                (run, recipientUser, _, _, _) <- createRosterMailFixture
                snapshot <- decodeRosterNotificationSnapshot run
                recipients <- decodeRosterNotificationRecipients run
                recipient <- maybe (fail "expected recipient") pure (find ((== unpackId recipientUser.id) . (.recipientUserId)) recipients)
                let mail = RosterNotificationMail
                        { notificationSnapshot = snapshot
                        , notificationRecipient = recipient
                        , rosterUrl = "https://app.example/ShowRosterWindow?anchorDate=2025-01-06&rosterGroupId=test"
                        , fromAddress = "rosters@example.com"
                        , replyToAddress = "support@example.com"
                        , supportEmail = "support@example.com"
                        }
                let ?mail = mail
                Mail.subject `shouldBe` "Your Main roster for week of 6 January"
                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    addressEmail (Mail.to mail) `shouldBe` "snapshot-recipient@example.com"
                    Mail.text mail `shouldSatisfy` isInfixOf "Front counter"
                    Mail.text mail `shouldSatisfy` isInfixOf "Open coverage"
                    Mail.text mail `shouldSatisfy` not . isInfixOf "Private schedule"
                    let renderedHtml = LazyText.toStrict (Markup.renderMarkupLazyText (Mail.html mail))
                    renderedHtml `shouldSatisfy` isInfixOf "Open coverage"
                    renderedHtml `shouldSatisfy` isInfixOf "rosterGroupId=test"

        it "delivers immutable recipient content through the shared worker after roster changes" $ withContext do
            withCleanDb do
                (run, recipientUser, otherUser, rosterWeek, openShift) <- createRosterMailFixture
                recipientStaff <- query @Staff |> filterWhere (#userId, Just (unpackId recipientUser.id)) |> fetchOne
                _ <- openShift
                    |> set #assignmentState "staff"
                    |> set #staffId (Just (unpackId recipientStaff.id))
                    |> updateRecord
                rosterDays <- query @RosterDay
                    |> filterWhere (#rosterGroupId, rosterWeek.fixtureRosterGroupId)
                    |> fetch
                _ <- mapM (updateRecord . set #publicationState Draft) rosterDays
                jobs <- query @AppJob |> filterWhere (#relatedId, Just (unpackId run.id)) |> fetch
                delivered <- newIORef []

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    forM_ jobs $ performEmailDeliveryJobWith $ capturingEmailDeliveryRuntime \mail -> do
                        let ?mail = mail
                        modifyIORef' delivered ((addressEmail (Mail.to mail), Mail.text mail) :)

                deliveredMails <- readIORef delivered
                length deliveredMails `shouldBe` 2
                recipientText <- mailTextFor recipientUser.email deliveredMails
                otherText <- mailTextFor otherUser.email deliveredMails
                recipientText `shouldSatisfy` isInfixOf "Front counter"
                recipientText `shouldSatisfy` isInfixOf "Open coverage"
                recipientText `shouldSatisfy` not . isInfixOf "Private schedule"
                otherText `shouldSatisfy` isInfixOf "Private schedule"
                otherText `shouldSatisfy` isInfixOf "Open coverage"
                completed <- query @AppJob |> filterWhere (#relatedId, Just (unpackId run.id)) |> fetch
                map (.status) completed `shouldSatisfy` all (== JobStatusSucceeded)
                map (resultText "deliveryStatus") completed `shouldSatisfy` all (== Just "sent")
                events <- query @LiveInvalidationEvent |> filterWhere (#source, "roster.notification.delivery.complete" :: Text) |> fetch
                length events `shouldBe` length jobs

        it "rejects tampered venue and relationship provenance without sending" $ withContext do
            withCleanDb do
                (run, _, _, _, _) <- createRosterMailFixture
                otherVenue <- createVenueWithConfig "Other Delivery Venue"
                appJob <- query @AppJob |> filterWhere (#relatedId, Just (unpackId run.id)) |> fetchOne
                calls <- newIORef (0 :: Int)
                let runtime = capturingEmailDeliveryRuntime (\_ -> modifyIORef' calls (+ 1))
                results <- withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    forM
                        [ appJob |> set #venueId (Just (unpackId otherVenue.id))
                        , appJob |> set #relatedTable (Just "staff_documents")
                        ]
                        (Exception.try . performEmailDeliveryJobWith runtime) :: IO [Either Exception.SomeException ()]

                results `shouldSatisfy` all isLeft
                readIORef calls `shouldReturn` 0

        it "uses shared retry and disabled-delivery outcomes without legacy callbacks" $ withContext do
            withCleanDb do
                (run, _, _, _, _) <- createRosterMailFixture
                [firstJob, secondJob] <- query @AppJob
                    |> filterWhere (#relatedId, Just (unpackId run.id))
                    |> orderByAsc #createdAt
                    |> fetch
                failure <- withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    Exception.try
                        ( performEmailDeliveryJobWith
                            (failingEmailDeliveryRuntime "temporary SMTP failure")
                            firstJob
                        ) :: IO (Either Exception.SomeException ())
                failure `shouldSatisfy` isLeft
                unchanged <- fetch firstJob.id
                unchanged.status `shouldNotBe` JobStatusSucceeded

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith
                        disabledEmailDeliveryRuntime
                        secondJob
                disabled <- fetch secondJob.id
                resultText "deliveryStatus" disabled `shouldBe` Just "delivery_disabled"

        it "invalidates aggregate status after the shared final delivery failure" $ withContext do
            withCleanDb do
                (run, _, _, _, _) <- createRosterMailFixture
                appJob <- query @AppJob |> filterWhere (#relatedId, Just (unpackId run.id)) |> fetchOne
                finalFailureJob <-
                    appJob
                        |> set #attemptsCount appJobMaxAttempts
                        |> set #status JobStatusFailed
                        |> updateRecord

                handleEmailDeliveryFailureAfterFinalAttempt finalFailureJob

                [event] <- query @LiveInvalidationEvent
                    |> filterWhere (#source, "roster.notification.delivery.failed" :: Text)
                    |> fetch
                [eventResource] <- query @LiveInvalidationEventResource
                    |> filterWhere (#eventId, unpackId event.id)
                    |> fetch
                let Right expectedResource =
                        encodeDurableResource
                            (rosterNotificationStatusResource run.rosterGroupId run.weekStart run.windowEnd)
                eventResource.resourceKey `shouldBe` expectedResource.durableResourceKey
                eventResource.resourcePayload `shouldBe` expectedResource.durableResourcePayload

        it "routes production dispatch only through the shared job kind" $ withContext do
            withCleanDb do
                (run, _, _, _, _) <- createRosterMailFixture
                appJob <- query @AppJob |> filterWhere (#relatedId, Just (unpackId run.id)) |> fetchOne
                let malformed = appJob |> set #payloadSchemaVersion 999
                result <- withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    Exception.try (dispatchAppJob malformed) :: IO (Either Exception.SomeException ())
                result `shouldSatisfy` isLeft

createRosterMailFixture ::
    (?modelContext :: ModelContext) =>
    IO (RosterNotificationRun, User, User, TestRosterWindow, RosterSlot)
createRosterMailFixture = do
    venue <- createVenueWithConfig "Snapshot Mail Venue"
    rosterGroup <- query @RosterGroup |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
    recipientUser <- createUserRecord "snapshot-recipient@example.com" "staff" True
    _ <- createVenueMembershipRecord venue recipientUser Manager
    recipientStaff <- query @Staff |> filterWhere (#userId, Just (unpackId recipientUser.id)) |> fetchOne
    otherUser <- createUserRecord "other-schedule@example.com" "staff" True
    _ <- createVenueMembershipRecord venue otherUser Worker
    otherStaff <- query @Staff |> filterWhere (#userId, Just (unpackId otherUser.id)) |> fetchOne
    rosterWeek <- createRosterWeekRecordForRosterGroup venue rosterGroup 0 True
    rosterDay <- createRosterDayRecord rosterWeek 0
    ownLane <- createSlotNameRecordForRosterGroup venue rosterGroup "Front counter"
    otherLane <- createSlotNameRecordForRosterGroup venue rosterGroup "Private schedule"
    openLane <- createSlotNameRecordForRosterGroup venue rosterGroup "Open coverage"
    ownShift <- createCompleteRosterSlotRecord rosterDay ownLane recipientStaff 0
    _ <- createCompleteRosterSlotRecord rosterDay otherLane otherStaff 1
    openShift <- createRosterSlotRecord rosterDay openLane Nothing 2
        >>= updateRecord
            . set #shiftTypeId ownShift.shiftTypeId
            . setTestRosterSlotBoundaries defaultWeekEpoch (TimeOfDay 12 0 0) (TimeOfDay 16 0 0)
    run <- createRosterNotificationRunForWindow recipientUser venue rosterGroup rosterWeek.fixtureWindowStart (addDays 7 rosterWeek.fixtureWindowStart)
    pure (run, recipientUser, otherUser, rosterWeek, openShift)

mailTextFor :: Text -> [(Text, Text)] -> IO Text
mailTextFor address mails =
    maybe (fail ("expected mail for " <> cs address)) pure (lookup address mails)

payloadRecipientAddress :: AppJob -> Maybe Text
payloadRecipientAddress appJob =
    AesonTypes.parseMaybe (Aeson.withObject "payload" (Aeson..: "recipientAddress")) appJob.payload

payloadMailKind :: AppJob -> Maybe Text
payloadMailKind appJob =
    AesonTypes.parseMaybe (Aeson.withObject "payload" (Aeson..: "mailKind")) appJob.payload

resultText :: Text -> AppJob -> Maybe Text
resultText key appJob =
    AesonTypes.parseMaybe (Aeson.withObject "result" (Aeson..: AesonKey.fromText key)) appJob.result
