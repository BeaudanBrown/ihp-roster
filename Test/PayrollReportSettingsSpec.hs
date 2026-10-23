module Test.PayrollReportSettingsSpec where

import Application.PayrollReports.Settings
import Application.PayrollReports.History
import Application.PayrollReports.Manual (requestManualPayrollReport)
import qualified Application.PayrollReports.Settings as Settings
import Application.Helper.Export.PayrollWorkbookConfiguration
import Data.Either (isLeft)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking (withContext)
import Test.Hspec
import Test.Support
import Test.PayrollWorkbookConfigurationSpec (asCurrentVenueUser, expectRight, newConfiguration)

input :: PayrollReportSettingsInput
input = PayrollReportSettingsInput
    { recipients = [" Payroll@Example.com ", "payroll@example.com"]
    , configurationId = Nothing
    , enabled = False
    , minuteOfDay = 540
    , expectedRevision = Nothing
    }

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Payroll report settings" do
        it "groups all executions in the latest four reporting weeks, not four executions" $ withContext do
            let week = fromGregorian 2025 1 6
            let run day = newRecord @PayrollReportRun
                    |> set #reportingWeek day
                    |> set #createdAt (UTCTime day 0)
            let runs = replicate 7 (run week) <> map (run . (`addDays` week)) [-7, -14, -21, -28]
            let history = groupPayrollReportHistory (reverse runs)
            map (.reportingWeek) history `shouldBe` map (`addDays` week) [0, -7, -14, -21]
            map (length . (.executions)) history `shouldBe` [7, 1, 1, 1]
            groupPayrollReportHistory [] |> length |> (`shouldBe` 0)

        it "never presents provider acceptance or uncertainty as confirmed inbox delivery" $ withContext do
            payrollReportStatusLabel PayrollReportAccepted `shouldBe` "Accepted by email provider — inbox delivery not confirmed"
            payrollReportStatusLabel PayrollReportAmbiguous `shouldBe` "Delivery uncertain — some recipients may have received the email"
            payrollReportStatusLabel PayrollReportBounced `shouldBe` "Delivery problem — some recipients may have received the email"

        it "normalizes recipients and rejects injection, malformed addresses and excessive lists" $ withContext do
            validatePayrollReportRecipients input.recipients `shouldBe` Right ["payroll@example.com"]
            mapM_ (\addresses -> validatePayrollReportRecipients addresses `shouldSatisfy` isLeft)
                [["missing-at"], ["x@example.com\r\nBcc: other@example.com"], ["Person <x@example.com>"], replicate 51 "x@example.com"]

        it "saves manual-only settings, rejects stale edits, and revokes changed recipient snapshots" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Reports"
                admin <- createUserRecord "reports-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                asCurrentVenueUser admin venue.id do
                    saved <- savePayrollReportSettings input >>= expectRight
                    saved.enabled `shouldBe` False
                    saved.recipients `shouldBe` ["payroll@example.com"]
                    savePayrollReportSettings input `shouldReturn` Left PayrollReportStaleSettings
                    let editInput = input { expectedRevision = Just saved.revision, recipients = ["new@example.com"] }
                    updated <- savePayrollReportSettings editInput >>= expectRight
                    updated.deliveryRevision `shouldBe` (saved.deliveryRevision + 1)
                    updated.scheduleActivatedAt `shouldSatisfy` (>= saved.scheduleActivatedAt)
                    query @PayrollReportSetting |> fetchCount `shouldReturn` 1

        it "requires a venue-owned template and derives the send day from the venue calendar without consent fields" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Reports"
                other <- createVenueWithConfig "Other"
                admin <- createUserRecord "reports-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                _ <- createVenueMembershipRecord other admin VenueAdmin
                foreignTemplate <- asCurrentVenueUser admin other.id (createSavedPayrollWorkbookConfiguration (newConfiguration "Foreign" 1 ["summary"])) >>= expectRight
                asCurrentVenueUser admin venue.id do
                    savePayrollReportSettings (input { Settings.enabled = True }) >>= (`shouldSatisfy` isLeft)
                    savePayrollReportSettings (input { Settings.configurationId = Just (unpackId foreignTemplate.savedPayrollWorkbookConfigurationRecord.id) })
                        `shouldReturn` Left PayrollReportTemplateUnavailable
                    template <- createSavedPayrollWorkbookConfiguration (newConfiguration "Local" 1 ["summary"]) >>= expectRight
                    let enabledInput :: PayrollReportSettingsInput
                        enabledInput = input { Settings.enabled = True, Settings.configurationId = Just (unpackId template.savedPayrollWorkbookConfigurationRecord.id) }
                    config <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                    _ <- config |> set #rosterWeekStartsOn 3 |> updateRecord
                    saved <- savePayrollReportSettings enabledInput >>= expectRight
                    saved.enabled `shouldBe` True
                    saved.weekday `shouldBe` 3
                    saved.minuteOfDay `shouldBe` 540

        it "denies managers and keeps settings venue-scoped" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Reports"
                other <- createVenueWithConfig "Other"
                manager <- createUserRecord "reports-manager@example.com" "manager" True
                _ <- createVenueMembershipRecord venue manager Manager
                asCurrentVenueUser manager venue.id do
                    savePayrollReportSettings input `shouldReturn` Left PayrollReportAccessDenied
                    fetchPayrollReportSettings `shouldReturn` Left PayrollReportAccessDenied
                    fetchPayrollReportHistory >>= \case
                        Left failure -> failure `shouldBe` PayrollReportAccessDenied
                        Right _ -> expectationFailure "Manager could read payroll report history"
                    requestManualPayrollReport "22222222-2222-4222-8222-222222222224" 0 (fromGregorian 2025 1 6) Nothing
                        `shouldReturn` Left "Payroll report access denied."
                admin <- createUserRecord "reports-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueOwner
                _ <- createVenueMembershipRecord other admin VenueAdmin
                _ <- asCurrentVenueUser admin venue.id (savePayrollReportSettings input) >>= expectRight
                asCurrentVenueUser admin other.id fetchPayrollReportSettings `shouldReturn` Right Nothing

        it "requires deletion confirmation and atomically disables and detaches the selected template" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Reports"
                admin <- createUserRecord "reports-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                asCurrentVenueUser admin venue.id do
                    template <- createSavedPayrollWorkbookConfiguration (newConfiguration "Payroll" 1 ["summary"]) >>= expectRight
                    let templateId = template.savedPayrollWorkbookConfigurationRecord.id
                    saved <- savePayrollReportSettings (input { Settings.enabled = True, Settings.configurationId = Just (unpackId templateId) }) >>= expectRight
                    deleteSavedPayrollWorkbookConfiguration templateId `shouldReturn` Left PayrollWorkbookConfigurationScheduleConfirmationRequired
                    deleteSavedPayrollWorkbookConfigurationConfirmingScheduleDisable True templateId `shouldReturn` Right ()
                    updated <- fetch saved.id
                    updated.enabled `shouldBe` False
                    updated.configurationId `shouldBe` Nothing
                    updated.recipients `shouldBe` saved.recipients
                    updated.weekday `shouldBe` saved.weekday
                    updated.deliveryRevision `shouldBe` (saved.deliveryRevision + 1)
