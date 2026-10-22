module Test.PayrollReportSettingsSpec where

import Application.PayrollReports.Settings
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
    , weekday = 1
    , minuteOfDay = 540
    , expectedRevision = Nothing
    , sharingConfirmed = True
    }

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Payroll report settings" do
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
                    let editInput = input { expectedRevision = Just saved.revision, recipients = ["new@example.com"], sharingConfirmed = False }
                    savePayrollReportSettings editInput `shouldReturn` Left PayrollReportSharingConfirmationRequired
                    updated <- savePayrollReportSettings (editInput { sharingConfirmed = True }) >>= expectRight
                    updated.deliveryRevision `shouldBe` (saved.deliveryRevision + 1)
                    updated.scheduleActivatedAt `shouldBe` saved.scheduleActivatedAt
                    query @PayrollReportSetting |> fetchCount `shouldReturn` 1

        it "requires a venue-owned template and confirmed sharing before enabling" $ withContext do
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
                    savePayrollReportSettings (enabledInput { sharingConfirmed = False }) `shouldReturn` Left PayrollReportSharingConfirmationRequired
                    saved <- savePayrollReportSettings enabledInput >>= expectRight
                    saved.enabled `shouldBe` True

        it "denies managers and keeps settings venue-scoped" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Reports"
                other <- createVenueWithConfig "Other"
                manager <- createUserRecord "reports-manager@example.com" "manager" True
                _ <- createVenueMembershipRecord venue manager Manager
                asCurrentVenueUser manager venue.id do
                    savePayrollReportSettings input `shouldReturn` Left PayrollReportAccessDenied
                    fetchPayrollReportSettings `shouldReturn` Left PayrollReportAccessDenied
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
