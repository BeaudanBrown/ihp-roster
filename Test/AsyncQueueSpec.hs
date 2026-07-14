module Test.AsyncQueueSpec where

import Application.Async.Queue
import Application.Async.Registry (dispatchAppJob)
import Config
import Control.Concurrent (forkIO, newEmptyMVar, putMVar, takeMVar)
import Control.Exception (SomeException, try)
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (withFrameworkConfig)
import IHP.Job.Types
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests = beforeAll testContext do
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
                results <- runConcurrentActions 30 (enqueueAppJob (testJobRequest (Just "queue-concurrent")))
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

runConcurrentActions :: Int -> IO a -> IO [Either SomeException a]
runConcurrentActions count action = do
    vars <- mapM (const newEmptyMVar) [1 .. count]
    _ <- mapM (\var -> forkIO (try action >>= putMVar var)) vars
    mapM takeMVar vars
