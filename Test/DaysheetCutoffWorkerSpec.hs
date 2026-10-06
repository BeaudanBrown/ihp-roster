module Test.DaysheetCutoffWorkerSpec where

import qualified Application.Daysheet.Cutoff as Cutoff
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

fetchCaptureJob :: (?modelContext :: ModelContext) => IO AppJob
fetchCaptureJob = query @AppJob |> filterWhere (#jobKind, cutoffJobKind) |> fetchOne

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Daysheet cutoff queue" do
        it "enqueues one pre-armed job with explicit creation, but no historical catch-up" $ withContext do
            withCleanDb do
                (_, manager, _, state) <- setup
                job <- fetchCaptureJob
                Right plan <- pure (Cutoff.planCutoff "Australia/Melbourne" day)
                job.runAt `shouldBe` Cutoff.armAt plan
                job.requestedByUserId `shouldBe` Nothing
                job.relatedId `shouldBe` Just (unpackId state.daysheet.id)
                job.venueId `shouldBe` Just manager.venueId
                Right _ <- createDailySheet manager day
                Right _ <- createDailySheet manager (fromGregorian 2020 1 1)
                query @AppJob |> filterWhere (#jobKind, cutoffJobKind) |> fetchCount >>= (`shouldBe` 1)
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 0)
                query @AppJob |> filterWhere (#jobKind, "email_delivery") |> fetchCount >>= (`shouldBe` 0)
        it "captures and queues once, then acknowledges committed results without rebuilding on late retry" $ withContext do
            withCleanDb do
                (owner, manager, version, state) <- setup
                Right _ <- addReportRecipient owner version.id reportKey "cutoff@example.test"
                Right _ <- submitDailySheet manager state.daysheet.id
                job <- fetchCaptureJob
                Right plan <- pure (Cutoff.planCutoff "Australia/Melbourne" day)
                (clock, _) <- makeClock (Cutoff.armAt plan)
                performCutoffCaptureJobWith clock job
                first <- query @DaysheetReportSnapshot |> fetchOne
                completed <- fetch job.id
                completed.status `shouldBe` JobStatusSucceeded
                completed.result `shouldBe` Aeson.object ["status" Aeson..= ("captured" :: Text), "snapshotCount" Aeson..= (1 :: Int)]
                Right _ <- editDailyCell manager state.daysheet.id (Daily.RootCell (Fixture.field 1)) 0 (Fixture.text "Later live value")
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
                Right _ <- submitDailySheet manager state.daysheet.id
                (late, _) <- makeClock (addUTCTime 600 (Cutoff.cutoffAt plan))
                performCutoffCaptureJobWith late job
                completed <- fetch job.id
                completed.result `shouldBe` Aeson.object ["status" Aeson..= ("skipped" :: Text), "snapshotCount" Aeson..= (0 :: Int)]
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 0)
                query @AppJob |> filterWhere (#jobKind, "email_delivery") |> fetchCount >>= (`shouldBe` 0)
        it "rejects forged queue provenance and deadlines before capture" $ withContext do
            withCleanDb do
                (_, manager, _, state) <- setup
                Right _ <- submitDailySheet manager state.daysheet.id
                job <- fetchCaptureJob
                Right plan <- pure (Cutoff.planCutoff "Australia/Melbourne" day)
                (clock, _) <- makeClock (Cutoff.armAt plan)
                forM_ [ job |> set #relatedId (Just (nonce 999))
                      , job |> set #requestedByUserId (Just manager.userId)
                      , job |> set #payload (Aeson.toJSON (CutoffJobPayload (unpackId state.daysheet.id) day (addUTCTime 3600 (Cutoff.cutoffAt plan))))
                      ] \forged -> do
                    result <- try @SomeException (performCutoffCaptureJobWith clock forged)
                    isLeft result `shouldBe` True
                query @DaysheetReportSnapshot |> fetchCount >>= (`shouldBe` 0)
