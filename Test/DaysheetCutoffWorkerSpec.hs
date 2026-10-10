module Test.DaysheetCutoffWorkerSpec where

import Application.Daysheet.Authority (memberAccess)
import qualified Application.Daysheet.Cutoff as Cutoff
import Application.Async.Heartbeat (performWorkerHeartbeatJob)
import Application.Daysheet.CutoffCapture (CutoffClock (..))
import Application.Daysheet.DefinitionCodec (decodeDefinition)
import Application.Daysheet.Storage (saveDraft, publishDraft)
import Application.Job.App ()
import Application.Job.DaysheetCapture ()
import qualified IHP.Job.Types as Job
import Control.Concurrent (newEmptyMVar, newMVar, modifyMVar_, putMVar, readMVar)
import Control.Concurrent.Async (mapConcurrently_, withAsync, wait)
import Control.Concurrent.QSem (newQSem, waitQSem, signalQSem)
import qualified Control.Exception as Exception
import Data.IORef
import System.Timeout (timeout)
import Application.Daysheet.CutoffJob
import Application.Daysheet.CutoffWorker
import qualified Application.Daysheet.Daily as Daily
import Application.Daysheet.DailyStorage
import Application.Daysheet.Recipients
import Control.Exception (SomeException, try)
import qualified Data.Aeson as Aeson
import Data.Either (isLeft)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.DaysheetCutoffCaptureSpec (makeClock)
import Test.DaysheetReportStorageSpec (setup, day, reportKey, nonce)
import Test.Hspec
import Test.Support
import qualified Test.Support.Daysheet as Fixture

fetchCaptureJob :: (?modelContext :: ModelContext) => IO DaysheetCaptureJob
fetchCaptureJob = query @DaysheetCaptureJob |> fetchOne

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Daysheet cutoff queue" do
        it "reserves eight dedicated capture slots without changing the four ordinary slots" $ withContext do
            Job.maxConcurrency @DaysheetCaptureJob `shouldBe` 8
            Job.maxConcurrency @AppJob `shouldBe` 4
        it "hands legacy tasks off without waiting or creating duplicate dedicated tasks" $ withContext do
            withCleanDb do
                (_, manager, _, state) <- setup
                Right plan <- pure (Cutoff.planCutoff "Australia/Melbourne" day)
                -- A pre-upgrade day has only the legacy task, not a dedicated row.
                fetchCaptureJob >>= deleteRecord
                legacy <- newRecord @AppJob |> set #jobKind cutoffJobKind
                    |> set #payload (Aeson.toJSON (CutoffJobPayload (unpackId state.daysheet.id) day (Cutoff.cutoffAt plan)))
                    |> set #venueId (Just manager.venueId) |> set #relatedTable (Just "daysheets")
                    |> set #relatedId (Just (unpackId state.daysheet.id)) |> createRecord
                let clock = CutoffClock (pure (Cutoff.armAt plan)) (\_ -> expectationFailure "Legacy handoff must not wait until cutoff")
                handoffCutoffCaptureJobWith clock legacy
                handoffCutoffCaptureJobWith clock legacy
                completed <- fetch legacy.id
                completed.result `shouldBe` Aeson.object ["status" Aeson..= ("delegated" :: Text)]
                query @DaysheetCaptureJob |> fetchCount >>= (`shouldBe` 1)
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 0)
                dedicated <- fetchCaptureJob
                _ <- dedicated |> set #status JobStatusSucceeded |> updateRecord
                handoffCutoffCaptureJobWith clock legacy
                query @DaysheetCaptureJob |> fetchCount >>= (`shouldBe` 1)
                retained <- fetchCaptureJob
                retained.status `shouldBe` JobStatusSucceeded
                invalid <- try @SomeException (handoffCutoffCaptureJobWith clock (legacy |> set #requestedByUserId (Just manager.userId)))
                isLeft invalid `shouldBe` True
                deleteRecord retained
                handoffCutoffCaptureJobWith (clock { now = pure (addUTCTime 1 (Cutoff.cutoffAt plan)) }) legacy
                query @DaysheetCaptureJob |> fetchCount >>= (`shouldBe` 0)
                late <- fetch legacy.id
                late.result `shouldBe` Aeson.object ["status" Aeson..= ("skipped" :: Text)]
        it "captures eight concurrent venues, keeps ordinary work free and skips a ninth admitted late" $ withContext do
            withCleanDb do
                (owner, manager, version, first) <- setup
                Right _ <- submitDailySheet (memberAccess manager) first.daysheet.id
                ownerUser <- fetch (Id owner.userId :: Id User)
                managerUser <- fetch (Id manager.userId :: Id User)
                Right definition <- pure (decodeDefinition version.definition)
                forM_ [2..9 :: Int] \index -> do
                    venue <- createVenueWithConfig ("Capture capacity " <> tshow index)
                    venueOwner <- createVenueMembershipRecord venue ownerUser VenueOwner
                    venueManager <- createVenueMembershipRecord venue managerUser Manager
                    Right _ <- saveDraft (memberAccess venueOwner) 0 Nothing definition Fixture.references
                    Right _ <- publishDraft (memberAccess venueOwner) 0 0
                    Right state <- createDailySheet (memberAccess venueManager) day
                    Right _ <- submitDailySheet (memberAccess venueManager) state.daysheet.id
                    pure ()
                jobs <- query @DaysheetCaptureJob |> fetch
                Right plan <- pure (Cutoff.planCutoff "Australia/Melbourne" day)
                globalTime <- newIORef (Cutoff.armAt plan)
                arrivals <- newMVar (0 :: Int)
                allWaiting <- newEmptyMVar
                release <- newEmptyMVar
                slots <- newQSem (Job.maxConcurrency @DaysheetCaptureJob)
                -- Deterministic bounded executor using the actual configured
                -- limit, not a production-server throughput benchmark.
                let run job = Exception.bracket_ (waitQSem slots) (signalQSem slots) do
                        start <- readIORef globalTime
                        (base, _) <- makeClock start
                        let clock = base { sleep = \duration -> do
                                when (duration > 1) do
                                    modifyMVar_ arrivals \count -> do
                                        when (count + 1 == Job.maxConcurrency @DaysheetCaptureJob) (putMVar allWaiting ())
                                        pure (count + 1)
                                    readMVar release
                                base.sleep duration }
                        performCutoffCaptureJobWith clock job
                withAsync (mapConcurrently_ run jobs) \running -> do
                    timeout 10000000 (readMVar allWaiting) `shouldReturn` Just ()
                    heartbeat <- newRecord @AppJob |> set #jobKind "worker_heartbeat" |> createRecord
                    performWorkerHeartbeatJob heartbeat
                    completed <- fetch heartbeat.id
                    completed.status `shouldBe` JobStatusSucceeded
                    writeIORef globalTime (addUTCTime 1 (Cutoff.cutoffAt plan))
                    putMVar release ()
                    timeout 10000000 (wait running) `shouldReturn` Just ()
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 8)
                completed <- query @DaysheetCaptureJob |> fetch
                length (filter (\job -> job.result == Aeson.object ["status" Aeson..= ("skipped" :: Text), "snapshotCount" Aeson..= (0 :: Int)]) completed) `shouldBe` 1
                query @AppJob |> filterWhere (#jobKind, "email_delivery") |> fetchCount >>= (`shouldBe` 0)
        it "enqueues one pre-armed job with explicit creation, but no historical catch-up" $ withContext do
            withCleanDb do
                (_, manager, _, state) <- setup
                job <- fetchCaptureJob
                Right plan <- pure (Cutoff.planCutoff "Australia/Melbourne" day)
                job.runAt `shouldBe` Cutoff.armAt plan
                job.daysheetId `shouldBe` state.daysheet.id
                Right _ <- createDailySheet (memberAccess manager) day
                Right _ <- createDailySheet (memberAccess manager) (fromGregorian 2020 1 1)
                query @DaysheetCaptureJob |> fetchCount >>= (`shouldBe` 1)
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 0)
                query @AppJob |> filterWhere (#jobKind, "email_delivery") |> fetchCount >>= (`shouldBe` 0)
        it "captures and queues once, then acknowledges committed results without rebuilding on late retry" $ withContext do
            withCleanDb do
                (owner, manager, version, state) <- setup
                Right _ <- addReportRecipient (memberAccess owner) version.id reportKey "cutoff@example.test"
                Right _ <- submitDailySheet (memberAccess manager) state.daysheet.id
                job <- fetchCaptureJob
                Right plan <- pure (Cutoff.planCutoff "Australia/Melbourne" day)
                (clock, _) <- makeClock (Cutoff.armAt plan)
                performCutoffCaptureJobWith clock job
                first <- query @DaysheetReportSnapshot |> fetchOne
                completed <- fetch job.id
                completed.status `shouldBe` JobStatusSucceeded
                completed.result `shouldBe` Aeson.object ["status" Aeson..= ("captured" :: Text), "snapshotCount" Aeson..= (1 :: Int)]
                Right _ <- editDailyCell (memberAccess manager) state.daysheet.id (Daily.RootCell (Fixture.field 1)) 0 (Fixture.text "Later live value")
                (late, _) <- makeClock (addUTCTime 600 (Cutoff.cutoffAt plan))
                performCutoffCaptureJobWith late job
                retained <- fetch first.id
                retained.content `shouldBe` first.content
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 1)
                query @AppJob |> filterWhere (#jobKind, "email_delivery") |> fetchCount >>= (`shouldBe` 1)
        it "silently skips unsubmitted and missed cutoffs without later submission catch-up" $ withContext do
            withCleanDb do
                (_, manager, _, state) <- setup
                job <- fetchCaptureJob
                Right plan <- pure (Cutoff.planCutoff "Australia/Melbourne" day)
                (clock, _) <- makeClock (Cutoff.armAt plan)
                performCutoffCaptureJobWith clock job
                Right _ <- submitDailySheet (memberAccess manager) state.daysheet.id
                (late, _) <- makeClock (addUTCTime 600 (Cutoff.cutoffAt plan))
                performCutoffCaptureJobWith late job
                completed <- fetch job.id
                completed.result `shouldBe` Aeson.object ["status" Aeson..= ("skipped" :: Text), "snapshotCount" Aeson..= (0 :: Int)]
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 0)
                query @AppJob |> filterWhere (#jobKind, "email_delivery") |> fetchCount >>= (`shouldBe` 0)
        it "rejects forged queue provenance and deadlines before capture" $ withContext do
            withCleanDb do
                (_, manager, _, state) <- setup
                Right _ <- submitDailySheet (memberAccess manager) state.daysheet.id
                job <- fetchCaptureJob
                Right plan <- pure (Cutoff.planCutoff "Australia/Melbourne" day)
                (clock, _) <- makeClock (Cutoff.armAt plan)
                forM_ [ job |> set #daysheetId (Id (nonce 999))
                      , job |> set #cutoffAt (addUTCTime 3600 (Cutoff.cutoffAt plan))
                      ] \forged -> do
                    result <- try @SomeException (performCutoffCaptureJobWith clock forged)
                    isLeft result `shouldBe` True
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 0)
