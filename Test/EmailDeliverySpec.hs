module Test.EmailDeliverySpec where

import Application.Async.Queue (appJobMaxAttempts)
import Application.EmailDelivery
import Application.Feedback.Notification (enqueueFeedbackNotificationJobs)
import Config
import Control.Exception (SomeException, try)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.Types as AesonTypes
import Data.Either (isLeft)
import Data.IORef
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (withFrameworkConfig)
import IHP.Job.Types (JobStatus (JobStatusSucceeded))
import IHP.Test.Mocking
import Test.Hspec
import Test.Support


tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Email delivery pipeline" do
        it "delivers snapshotted feedback mail after the recipient is deactivated" $ withContext do
            withCleanDb do
                (_, _, recipient, appJob) <- createQueuedFeedback "delivery-snapshot@example.com"
                now <- getCurrentTime
                _ <- recipient |> set #deactivatedAt (Just now) |> set #platformRole Nothing |> updateRecord
                deliveryCalls <- newIORef (0 :: Int)

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith
                        (enabledRuntime (modifyIORef' deliveryCalls (+ 1)))
                        appJob

                readIORef deliveryCalls `shouldReturn` 1
                completed <- fetch appJob.id
                completed.status `shouldBe` JobStatusSucceeded
                payloadResultText "deliveryStatus" completed `shouldBe` Just "sent"
                tshow completed.result `shouldSatisfy` (not . Text.isInfixOf "delivery-snapshot@example.com")

        it "completes disabled delivery without invoking transport or replaying the event" $ withContext do
            withCleanDb do
                (feedbackItem, _, _, appJob) <- createQueuedFeedback "delivery-disabled@example.com"
                calls <- newIORef (0 :: Int)

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith
                        EmailDeliveryRuntime
                            { deliveryIsDisabled = pure True
                            , deliverMail = \_ -> modifyIORef' calls (+ 1)
                            }
                        appJob

                readIORef calls `shouldReturn` 0
                completed <- fetch appJob.id
                payloadResultText "deliveryStatus" completed `shouldBe` Just "delivery_disabled"
                jobs <- enqueueFeedbackNotificationJobs feedbackItem
                map (.id) jobs `shouldBe` [appJob.id]
                query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetchCount >>= (`shouldBe` 1)

        it "skips a missing domain reference without sending" $ withContext do
            withCleanDb do
                (feedbackItem, _, _, appJob) <- createQueuedFeedback "delivery-skip@example.com"
                deleteRecord feedbackItem

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith
                        (enabledRuntime (expectationFailure "missing feedback must not send"))
                        appJob

                completed <- fetch appJob.id
                payloadResultText "deliveryStatus" completed `shouldBe` Just "delivery_skipped"
                payloadResultText "reason" completed `shouldBe` Just "domain_reference_missing"

        it "rethrows transport failure for the ten-attempt AppJob retry lifecycle" $ withContext do
            withCleanDb do
                (_, _, _, appJob) <- createQueuedFeedback "delivery-retry@example.com"

                result <- withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    try
                        ( performEmailDeliveryJobWith
                            (enabledRuntime (ioError (userError "simulated smtp outage")))
                            appJob
                        ) :: IO (Either SomeException ())

                result `shouldSatisfy` isLeft
                appJobMaxAttempts `shouldBe` 10
                unchanged <- fetch appJob.id
                unchanged.status `shouldNotBe` JobStatusSucceeded
                unchanged.result `shouldBe` Aeson.object []

        it "documents at-least-once behavior when failure follows provider acceptance" $ withContext do
            withCleanDb do
                (_, _, _, appJob) <- createQueuedFeedback "delivery-at-least-once@example.com"
                sends <- newIORef (0 :: Int)
                let sendThenFailOnce = do
                        attempt <- atomicModifyIORef' sends \count -> let next = count + 1 in (next, next)
                        when (attempt == 1) (ioError (userError "worker stopped after provider acceptance"))

                firstResult <- withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    try (performEmailDeliveryJobWith (enabledRuntime sendThenFailOnce) appJob) :: IO (Either SomeException ())
                firstResult `shouldSatisfy` isLeft

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith (enabledRuntime sendThenFailOnce) appJob

                readIORef sends `shouldReturn` 2
                completed <- fetch appJob.id
                payloadResultText "deliveryStatus" completed `shouldBe` Just "sent"

        it "hard-retires only active legacy award and billing transport jobs in the cutover migration" $ withContext do
            migrationSql <- TextIO.readFile "Application/Migration/1788001200.sql"

            migrationSql `shouldSatisfy` Text.isInfixOf "notification_snapshot JSONB"
            migrationSql `shouldSatisfy` Text.isInfixOf "'billing_notification'"
            migrationSql `shouldSatisfy` Text.isInfixOf "'wage_source_award_drift_notification'"
            migrationSql `shouldSatisfy` Text.isInfixOf "'retired_during_email_pipeline_migration'"
            migrationSql `shouldSatisfy` Text.isInfixOf "'job_status_not_started'"
            migrationSql `shouldSatisfy` Text.isInfixOf "'job_status_running'"
            migrationSql `shouldSatisfy` Text.isInfixOf "'job_status_retry'"
            migrationSql `shouldSatisfy` Text.isInfixOf "SET status = 'job_status_succeeded'"
            migrationSql `shouldSatisfy` not . Text.isInfixOf "'job_status_failed'"
            migrationSql `shouldSatisfy` not . Text.isInfixOf "'job_status_timed_out'"
            migrationSql `shouldSatisfy` not . Text.isInfixOf "DELETE FROM app_jobs"

        it "permanently deduplicates feedback events after terminal completion" $ withContext do
            withCleanDb do
                (feedbackItem, _, _, appJob) <- createQueuedFeedback "delivery-permanent@example.com"
                _ <- appJob |> set #status JobStatusSucceeded |> updateRecord

                repeated <- enqueueFeedbackNotificationJobs feedbackItem

                map (.id) repeated `shouldBe` [appJob.id]
                query @AppJob |> filterWhere (#jobKind, emailDeliveryJobKind) |> fetchCount >>= (`shouldBe` 1)

createQueuedFeedback ::
    (?modelContext :: ModelContext) =>
    Text ->
    IO (UserFeedbackItem, User, User, AppJob)
createQueuedFeedback recipientEmail = do
    venue <- createVenueWithConfig "Email Delivery Venue"
    submitter <- createUserRecord "email-delivery-submitter@example.com" "staff" True
    recipient <- createUserRecordWithPlatformRole recipientEmail "staff" (Just SuperAdmin) True
    feedbackItem <-
        newRecord @UserFeedbackItem
            |> set #venueId (unpackId venue.id)
            |> set #submittedByUserId (unpackId submitter.id)
            |> set #feedbackType Bug
            |> set #status "new"
            |> set #priority "normal"
            |> set #content "The feedback delivery test content"
            |> set #submittedRole (Just "worker")
            |> createRecord
    [appJob] <- enqueueFeedbackNotificationJobs feedbackItem
    pure (feedbackItem, submitter, recipient, appJob)

enabledRuntime :: IO () -> EmailDeliveryRuntime
enabledRuntime delivery =
    EmailDeliveryRuntime
        { deliveryIsDisabled = pure False
        , deliverMail = \_ -> delivery
        }

payloadResultText :: Text -> AppJob -> Maybe Text
payloadResultText key appJob =
    AesonTypes.parseMaybe (Aeson.withObject "email delivery result" (Aeson..: AesonKey.fromText key)) appJob.result
