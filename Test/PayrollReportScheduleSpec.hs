module Test.PayrollReportScheduleSpec where

import Application.PayrollReports.Schedule
import Application.PayrollReports.Generation
import Application.PayrollReports.Job
import Application.PayrollReports.Settings
import qualified Application.PayrollReports.Settings as Settings
import Application.Helper.Export.PayrollWorkbookConfiguration
import Control.Concurrent.Async (concurrently)
import Data.Time (fromGregorian)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking (withContext)
import Test.Hspec
import Test.Support
import Test.PayrollReportSettingsSpec (input)
import Test.PayrollWorkbookConfigurationSpec (asCurrentVenueUser, expectRight, newConfiguration)

instant :: Integer -> Int -> Int -> Integer -> UTCTime
instant year month day seconds = UTCTime (fromGregorian year month day) (fromInteger seconds)

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Payroll report scheduling" do
        it "shifts spring gaps to 03:00 and sends repeated 02:30 only at its first occurrence" $ withContext do
            nextReportOccurrence "Australia/Melbourne" 0 150 (instant 2026 10 3 0)
                `shouldBe` Right (instant 2026 10 3 (16 * 3600))
            nextReportOccurrence "Australia/Melbourne" 0 150 (instant 2026 4 4 0)
                `shouldBe` Right (instant 2026 4 4 (15 * 3600 + 30 * 60))
            next <- expectRight (nextReportOccurrence "Australia/Melbourne" 0 150 (instant 2026 4 4 (15 * 3600 + 30 * 60)))
            next `shouldBe` instant 2026 4 11 (16 * 3600 + 30 * 60)

        it "preserves the intended week and permits catch-up only before 24 hours" $ withContext do
            let due = instant 2025 1 13 (22 * 3600)
            reportWeekForOccurrence 1 due `shouldBe` fromGregorian 2025 1 6
            withinReportCatchUpWindow (addUTCTime 86399 due) due `shouldBe` True
            withinReportCatchUpWindow (addUTCTime 86400 due) due `shouldBe` False
            withinReportCatchUpWindow (addUTCTime (-1) due) due `shouldBe` False

        it "deduplicates automatic weeks, records missed sends, and does not let manual sends suppress scheduling" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Scheduling"
                admin <- createUserRecord "scheduler@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                template <- asCurrentVenueUser admin venue.id (createSavedPayrollWorkbookConfiguration (newConfiguration "Payroll" 1 ["summary"])) >>= expectRight
                setting <- asCurrentVenueUser admin venue.id (savePayrollReportSettings (input { Settings.enabled = True, Settings.configurationId = Just (unpackId template.savedPayrollWorkbookConfigurationRecord.id), Settings.weekday = 2 })) >>= expectRight
                setting <- setting |> set #scheduleActivatedAt (instant 2025 1 12 0) |> updateRecord
                let week = fromGregorian 2025 1 6
                Just (due, scheduledWeek) <- nextScheduledPayrollReport setting
                scheduledWeek `shouldBe` week
                _ <- generatePayrollReportSnapshot venue.id (unpackId admin.id) PayrollReportManual Nothing week (addUTCTime (-60) due) >>= expectRight
                nextScheduledPayrollReport setting `shouldReturn` Just (due, week)
                first <- generatePayrollReportSnapshot venue.id (unpackId admin.id) PayrollReportScheduled (Just due) week (addUTCTime 86400 due) >>= expectRight
                first.status `shouldBe` PayrollReportMissed
                repeated <- generatePayrollReportSnapshot venue.id (unpackId admin.id) PayrollReportScheduled (Just due) week (addUTCTime 86401 due) >>= expectRight
                repeated.id `shouldBe` first.id
                Just (_, nextWeek) <- nextScheduledPayrollReport setting
                nextWeek `shouldBe` addDays 7 week

        it "deduplicates simultaneous manual confirmation retries without suppressing future sends" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Concurrent sends"
                admin <- createUserRecord "scheduler@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                template <- asCurrentVenueUser admin venue.id (createSavedPayrollWorkbookConfiguration (newConfiguration "Payroll" 1 ["summary"])) >>= expectRight
                setting <- asCurrentVenueUser admin venue.id (savePayrollReportSettings (input { Settings.configurationId = Just (unpackId template.savedPayrollWorkbookConfigurationRecord.id) })) >>= expectRight
                let request = ReportGenerationRequest
                        { runId = "22222222-2222-4222-8222-222222222223"
                        , venueId = venue.id
                        , actorId = unpackId admin.id
                        , origin = PayrollReportManual
                        , scheduledAt = Nothing
                        , week = fromGregorian 2025 1 6
                        , now = instant 2025 1 14 0
                        , expectedRevision = Just setting.revision
                        , previousRunId = Nothing
                        }
                (first, second) <- concurrently (generatePayrollReportRequest request) (generatePayrollReportRequest request)
                firstRun <- expectRight first
                secondRun <- expectRight second
                firstRun.id `shouldBe` secondRun.id
                query @PayrollReportRun |> fetchCount `shouldReturn` 1

        it "cancels pending automatic sends on calendar change and resends historical dates after a week-start change" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Calendar change"
                admin <- createUserRecord "scheduler@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                template <- asCurrentVenueUser admin venue.id (createSavedPayrollWorkbookConfiguration (newConfiguration "Payroll" 1 ["summary"])) >>= expectRight
                setting <- asCurrentVenueUser admin venue.id (savePayrollReportSettings (input { Settings.enabled = True, Settings.configurationId = Just (unpackId template.savedPayrollWorkbookConfigurationRecord.id), Settings.weekday = 2 })) >>= expectRight
                setting <- setting |> set #scheduleActivatedAt (instant 2025 1 12 0) |> updateRecord
                Just (due, week) <- nextScheduledPayrollReport setting
                run <- generatePayrollReportSnapshot venue.id (unpackId admin.id) PayrollReportScheduled (Just due) week due >>= expectRight
                withTransaction (disablePayrollReportsForCalendarChange (unpackId venue.id))
                disabled <- fetch setting.id
                disabled.enabled `shouldBe` False
                cancelled <- fetch run.id
                cancelled.status `shouldBe` PayrollReportCancelled
                config <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                _ <- config |> set #rosterWeekStartsOn 3 |> updateRecord
                updated <- generatePayrollReportRequest ReportGenerationRequest
                    { runId = "22222222-2222-4222-8222-222222222222"
                    , venueId = venue.id
                    , actorId = unpackId admin.id
                    , origin = PayrollReportUpdated
                    , scheduledAt = Nothing
                    , week
                    , now = addUTCTime 60 due
                    , expectedRevision = Just disabled.revision
                    , previousRunId = Just (unpackId run.id)
                    } >>= expectRight
                updated.reportingWeek `shouldBe` week
                updated.rangeEnd `shouldBe` addDays 6 week
                updated.status `shouldBe` PayrollReportNoData
