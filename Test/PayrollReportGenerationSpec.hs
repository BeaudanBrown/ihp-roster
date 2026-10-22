module Test.PayrollReportGenerationSpec where

import Application.Helper.Export.PayrollWorkbookConfiguration
import Application.Helper.Export.Service (requestPayrollWorkbookXlsxExportWithDefinition)
import Application.PayrollReports.Generation
import Application.PayrollReports.Settings
import qualified Application.PayrollReports.Settings as Settings
import Data.Either (isLeft)
import Data.Time.Calendar (fromGregorian)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking (withContext)
import Test.Hspec
import Test.Support
import Test.PayrollReportSettingsSpec (input)
import Test.PayrollWorkbookConfigurationSpec (asCurrentVenueUser, expectRight, newConfiguration, updateConfiguration)

week :: Day
week = fromGregorian 2025 1 6

now :: UTCTime
now = UTCTime (fromGregorian 2025 1 14) 0

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Payroll report generation" do
        it "accepts only aligned completed roster weeks" $ withContext do
            validCompletedReportWeek 1 (fromGregorian 2025 1 13) week `shouldBe` True
            validCompletedReportWeek 1 (fromGregorian 2025 1 12) week `shouldBe` False
            validCompletedReportWeek 1 (fromGregorian 2025 1 20) (addDays 1 week) `shouldBe` False

        it "records no-approved-data without fabricating an attachment, including outstanding entries" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Report Generation"
                admin <- createUserRecord "report-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue (Just admin) "Payroll" "Person"
                _ <- createTimesheetEntryRecord venue staff week
                template <- asCurrentVenueUser admin venue.id (createSavedPayrollWorkbookConfiguration (newConfiguration "Payroll" 1 ["summary"])) >>= expectRight
                _ <- asCurrentVenueUser admin venue.id (savePayrollReportSettings (input { Settings.configurationId = Just (unpackId template.savedPayrollWorkbookConfigurationRecord.id) })) >>= expectRight
                run <- generatePayrollReportSnapshot venue.id (unpackId admin.id) PayrollReportManual Nothing week now >>= expectRight
                run.status `shouldBe` PayrollReportNoData
                run.excludedEntryCount `shouldBe` 1
                run.approvedEntryCount `shouldBe` 0
                run.exportJobId `shouldBe` Nothing
                query @ExportJob |> fetchCount `shouldReturn` 0
                generatePayrollReportSnapshot venue.id (unpackId admin.id) PayrollReportManual Nothing (fromGregorian 2025 1 13) now >>= (`shouldSatisfy` isLeft)

        it "shares download workbook bytes and keeps generated data and recipients unchanged after settings edits" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Report Generation"
                admin <- createUserRecord "report-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue (Just admin) "Payroll" "Person"
                _ <- createApprovedTimesheetEntryRecordAt venue staff admin week now
                template <- asCurrentVenueUser admin venue.id (createSavedPayrollWorkbookConfiguration (newConfiguration "Payroll" 1 ["summary"])) >>= expectRight
                let configured = input { Settings.configurationId = Just (unpackId template.savedPayrollWorkbookConfigurationRecord.id) }
                settings <- asCurrentVenueUser admin venue.id (savePayrollReportSettings configured) >>= expectRight
                run <- generatePayrollReportSnapshot venue.id (unpackId admin.id) PayrollReportManual Nothing week now >>= expectRight
                run.status `shouldBe` PayrollReportReady
                exportId <- maybe (expectationFailure "Expected export" >> fail "Missing export") pure run.exportJobId
                export <- fetch (Id exportId :: Id ExportJob)
                download <- asCurrentVenueUser admin venue.id (requestPayrollWorkbookXlsxExportWithDefinition "Payroll" template.savedPayrollWorkbookConfigurationDefinition week (addDays 6 week)) >>= expectRight
                export.fileContents `shouldBe` download.fileContents
                export.deliveryMethod `shouldBe` "payroll_email"
                query @ExportJobEntry |> filterWhere (#exportJobId, exportId) |> fetchCount `shouldReturn` 1
                _ <- asCurrentVenueUser admin venue.id (savePayrollReportSettings (configured { expectedRevision = Just settings.revision, Settings.recipients = ["changed@example.com"] })) >>= expectRight
                retained <- fetch run.id
                retained.recipients `shouldBe` ["payroll@example.com"]
                retained.templateSnapshot `shouldBe` run.templateSnapshot
                currentExport <- fetch export.id
                currentExport.fileContents `shouldBe` export.fileContents
                _ <- asCurrentVenueUser admin venue.id (withTransaction (updateSavedPayrollWorkbookConfigurationInCurrentTransaction template.savedPayrollWorkbookConfigurationRecord.id (updateConfiguration "Changed Payroll" 1 ["shift-type-hours"] 0))) >>= expectRight
                updated <- generatePayrollReportSnapshot venue.id (unpackId admin.id) PayrollReportUpdated Nothing week now >>= expectRight
                updated.templateSnapshot `shouldNotBe` run.templateSnapshot
                updated.recipients `shouldBe` ["changed@example.com"]
                updated.id `shouldNotBe` run.id
