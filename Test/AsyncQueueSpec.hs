module Test.AsyncQueueSpec where

import Application.Async.Boundary (runAppJobBoundary)
import Application.Async.Queue
import Application.Async.Registry (dispatchAppJob)
import Application.EmailDelivery (emailDeliveryJobKind)
import Application.Job.App ()
import Application.WageSourceAlert.Job (wageSourceHealthCheckJobKind)
import Application.Xero.Keepalive (xeroConnectionKeepaliveJobKind)
import Application.Xero.ReferenceSyncJob (xeroReferenceSyncJobKind)
import Config
import Control.Exception (AsyncException (ThreadKilled), SomeException)
import qualified Control.Exception as BaseException
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (withFrameworkConfig)
import qualified IHP.Job.Queue as JobQueue
import IHP.Job.Types
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Test.Support.Concurrency (runConcurrentActionsImmediately)

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Async queue" do
        it "deduplicates sequential active jobs" $ withContext do
            withCleanDb do
                EnqueuedAppJob firstJob <- enqueueAppJob (testJobRequest (Just "queue-sequential"))
                ExistingActiveAppJob secondJob <- enqueueAppJob (testJobRequest (Just "queue-sequential"))

                secondJob.id `shouldBe` firstJob.id
                jobCount <- query @AppJob |> filterWhere (#dedupeKey, Just "queue-sequential") |> fetchCount
                jobCount `shouldBe` 1

        it "deduplicates concurrent active jobs without surfacing unique violations" $ withContext do
            withCleanDb do
                results <- runConcurrentActionsImmediately 30 (enqueueAppJob (testJobRequest (Just "queue-concurrent")))
                let successes = rights results
                let failures = lefts results
                failures `shouldSatisfy` null
                length [ () | EnqueuedAppJob _ <- successes ] `shouldBe` 1
                length [ () | ExistingActiveAppJob _ <- successes ] `shouldBe` 29

                activeJobs <- query @AppJob
                    |> filterWhere (#dedupeKey, Just "queue-concurrent")
                    |> filterWhereIn (#status, activeAppJobStatuses)
                    |> fetch
                length activeJobs `shouldBe` 1

        it "retires a claimed legacy roster-timesheet job without creating an entry" $ withContext do
            withCleanDb do
                legacyJob <-
                    newRecord @AppJob
                        |> set #jobKind "roster_timesheet_creation"
                        |> set #status JobStatusRunning
                        |> createRecord

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    dispatchAppJob legacyJob

                retiredJob <- fetch legacyJob.id
                retiredJob.status `shouldBe` JobStatusSucceeded
                retiredJob.result `shouldBe` Aeson.object
                    [ "status" Aeson..= ("retired" :: Text)
                    , "reason" Aeson..= ("replaced_by_roster_timesheet_suggestions" :: Text)
                    ]
                query @TimesheetEntry |> fetchCount >>= (`shouldBe` 0)

        it "projects an unknown job kind to the one safe IHP boundary exception" $ withContext do
            withCleanDb do
                let unsupportedKind = "secret-provider-job-kind"
                appJob <-
                    newRecord @AppJob
                        |> set #jobKind unsupportedKind
                        |> set #status JobStatusRunning
                        |> set #attemptsCount 1
                        |> createRecord

                result <- withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    attempted <- BaseException.try (dispatchAppJob appJob) :: IO (Either SomeException ())
                    forM_ (lefts [attempted]) (JobQueue.jobDidFail ?modelContext.hasqlPool appJob)
                    pure attempted

                case result of
                    Right () -> expectationFailure "Expected unknown job dispatch to fail"
                    Left exception -> do
                        let persistedMessage = tshow exception
                        persistedMessage `shouldBe` "application.async.error.app-job/job-unknown-kind: The stored job kind is unsupported."
                        persistedMessage `shouldSatisfy` (not . Text.isInfixOf unsupportedKind)
                persistedJob <- fetch appJob.id
                persistedJob.status `shouldBe` JobStatusRetry
                persistedJob.lastError `shouldBe` Just "application.async.error.app-job/job-unknown-kind: The stored job kind is unsupported."
                persistedJob.runAt `shouldSatisfy` (> appJob.runAt)

        it "classifies malformed, unsupported, and invalid-provenance jobs before IHP persistence" $ withContext do
            withCleanDb do
                let cases =
                        [ ( newRecord @AppJob
                                |> set #jobKind emailDeliveryJobKind
                                |> set #payloadSchemaVersion 99
                          , "application.async.error.app-job/job-unsupported-payload-schema-version: The stored job payload version is unsupported."
                          )
                        , ( newRecord @AppJob
                                |> set #jobKind wageSourceHealthCheckJobKind
                                |> set #payloadSchemaVersion 1
                                |> set #payload (Aeson.object ["source" Aeson..= ("secret-unknown-source" :: Text)])
                          , "application.async.error.app-job/job-malformed-persisted-payload: The stored job payload is invalid."
                          )
                        , ( newRecord @AppJob
                                |> set #jobKind xeroConnectionKeepaliveJobKind
                                |> set #payloadSchemaVersion 1
                          , "application.async.error.app-job/job-invalid-provenance: The stored job provenance is invalid."
                          )
                        ]
                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    forM_ cases \(appJob, expectedMessage) -> do
                        result <- BaseException.try (dispatchAppJob appJob) :: IO (Either SomeException ())
                        case result of
                            Right () -> expectationFailure "Expected invalid persisted job to fail"
                            Left exception -> tshow exception `shouldBe` expectedMessage

        it "sanitizes unexpected synchronous exceptions and leaves asynchronous cancellation native" $ withContext do
            syncResult <- BaseException.try (runAppJobBoundary (BaseException.throwIO (userError "secret raw exception"))) :: IO (Either SomeException ())
            case syncResult of
                Right () -> expectationFailure "Expected synchronous failure"
                Left exception -> do
                    let persistedMessage = tshow exception
                    persistedMessage `shouldBe` "application.async.error.app-job/job-unexpected-synchronous-failure: The job could not be completed."
                    persistedMessage `shouldSatisfy` (not . Text.isInfixOf "secret raw exception")

            asyncResult <- BaseException.try (runAppJobBoundary (BaseException.throwIO ThreadKilled)) :: IO (Either AsyncException ())
            asyncResult `shouldBe` Left ThreadKilled

        it "keeps IHP retry counts and default backoff authoritative per job kind" $ withContext do
            let ordinaryJob = newRecord @AppJob |> set #jobKind emailDeliveryJobKind
            let xeroReferenceJob = newRecord @AppJob |> set #jobKind xeroReferenceSyncJobKind
            appJobMaxAttemptsFor ordinaryJob `shouldBe` 10
            appJobMaxAttemptsFor xeroReferenceJob `shouldBe` 1
            JobQueue.backoffDelay (backoffStrategy @AppJob) 3 `shouldBe` 30

        it "does not deduplicate jobs without a dedupe key" $ withContext do
            withCleanDb do
                results <- mapM (const (enqueueAppJob (testJobRequest Nothing))) [1 .. 3 :: Int]
                length [ () | EnqueuedAppJob _ <- results ] `shouldBe` 3
                jobCount <- query @AppJob |> filterWhere (#jobKind, "test_queue_job") |> fetchCount
                jobCount `shouldBe` 3

        it "allows a new job after the prior deduped job is no longer active" $ withContext do
            withCleanDb do
                EnqueuedAppJob firstJob <- enqueueAppJob (testJobRequest (Just "queue-completed"))
                _ <- firstJob |> set #status JobStatusSucceeded |> updateRecord

                EnqueuedAppJob secondJob <- enqueueAppJob (testJobRequest (Just "queue-completed"))

                secondJob.id `shouldNotBe` firstJob.id
                jobCount <- query @AppJob |> filterWhere (#dedupeKey, Just "queue-completed") |> fetchCount
                jobCount `shouldBe` 2

appJobMaxAttemptsFor :: AppJob -> Int
appJobMaxAttemptsFor appJob =
    let ?job = appJob
     in maxAttempts @AppJob

testJobRequest :: Maybe Text -> AppJobRequest
testJobRequest dedupeKey =
    AppJobRequest
        { jobKind = "test_queue_job"
        , payload = Aeson.object []
        , payloadSchemaVersion = 1
        , requestedByUserId = Nothing
        , venueId = Nothing
        , relatedTable = Nothing
        , relatedId = Nothing
        , dedupeKey
        , runAt = Nothing
        }
