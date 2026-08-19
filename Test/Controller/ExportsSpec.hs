module Test.Controller.ExportsSpec where

import Application.Fixture.PayrollFixtures (createAndApproveEntry,
                                            createPayrollSnapshot,
                                            seedWeekDayNames)
import Application.Helper.Export
import Application.Helper.FrontendContract.Surface.Admin.Resource (adminExportsResource)
import Application.Helper.SurfaceResource
import qualified Codec.Archive.Zip as Zip
import Config
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Time.Calendar (Day, fromGregorian)
import Data.Time.Clock (UTCTime (..), addUTCTime, secondsToDiffTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Header (hContentDisposition, hContentType)
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders)
import Test.Hspec
import Test.Support
import Web.Controller.Exports ()
import Web.Exports.Mutations (exportJobTouchedResources)
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "ExportsController" do
        it "redirects unauthenticated users from export jobs page" $ withContext do
            response <- callAction ExportJobsAction
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from create export job action" $ withContext do
            response <- callAction CreateExportJobAction
            response `responseStatusShouldBe` status302

        it "redirects unauthenticated users from download export job action" $ withContext do
            let exportJobId = Id "00000000-0000-0000-0000-000000000000"
            response <- callAction DownloadExportJobAction { exportJobId }
            response `responseStatusShouldBe` status302

        it "creates an approved-timesheets export job and audits generation" $ withContext do
            withCleanDb do
                let approvedAt = UTCTime (fromGregorian 2025 1 12) (secondsToDiffTime 3600)
                venue <- createVenueWithConfig "Export Venue"
                admin <- createUserRecord "exports-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Ava" "Hours"
                approvedEntry <- createApprovedTimesheetEntryRecordAt venue staff admin (fromGregorian 2025 1 10) approvedAt
                let breakStartsAt = addUTCTime (60 * 60) approvedEntry.startsAt
                _ <- approvedEntry
                    |> set #breakStartsAt (Just breakStartsAt)
                    |> set #breakEndsAt (Just (addUTCTime 15 breakStartsAt))
                    |> updateRecord
                _ <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 11)

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("exportType", cs (exportJobTypeToText ApprovedTimesheetsCsv))
                        , ("rangeStart", "2025-01-06")
                        , ("rangeEnd", "2025-01-12")
                        ]

                response `responseStatusShouldBe` status302

                exportJob <- query @ExportJob |> fetchOne
                exportJob.venueId `shouldBe` unpackId venue.id
                exportJob.requestedByUserId `shouldBe` unpackId admin.id
                exportJob.exportType `shouldBe` exportJobTypeToText ApprovedTimesheetsCsv
                exportJob.schemaVersion `shouldBe` 3
                exportJob.status `shouldBe` exportJobStatusToText ExportReady
                exportJob.rangeStart `shouldBe` Just (fromGregorian 2025 1 6)
                exportJob.rangeEnd `shouldBe` Just (fromGregorian 2025 1 12)
                exportJob.payConfigVersionManifest `shouldSatisfy` isJust
                exportJob.fileName `shouldBe` Just "approved-timesheets-2025-01-06-to-2025-01-12.csv"
                exportJob.fileContents `shouldSatisfy` isJust
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    Text.isInfixOf "worked_on,staff_name,start_time,end_time,break_seconds,pay_config_version_manifest,approved_at,approved_by_email"
                fromMaybe "" exportJob.fileContents `shouldSatisfy` Text.isInfixOf ",15.0,"
                fromMaybe "" exportJob.fileContents `shouldSatisfy` Text.isInfixOf "2025-01-10"
                fromMaybe "" exportJob.fileContents `shouldSatisfy` Text.isInfixOf ("," <> fromMaybe "" exportJob.payConfigVersionManifest <> ",")
                fromMaybe "" exportJob.fileContents `shouldSatisfy` (not . Text.isInfixOf "2025-01-11")

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.eventType `shouldBe` "export_generated"
                auditEvent.targetTable `shouldBe` "export_jobs"
                auditEvent.targetId `shouldBe` unpackId exportJob.id

        it "records touched resources for export job changes" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Export Touch Venue"
                admin <- createUserRecord "exports-touch@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("exportType", cs (exportJobTypeToText ApprovedTimesheetsCsv))
                        , ("rangeStart", "2025-01-06")
                        , ("rangeEnd", "2025-01-12")
                        ]

                response `responseStatusShouldBe` status302
                exportJob <- query @ExportJob |> fetchOne
                exportJobTouchedResources exportJob `shouldBe` [adminExportsResource (unpackId venue.id)]

        it "creates a staff-hours payroll export grouped by effective pay level" $ withContext do
            withCleanDb do
                let approvedAt = UTCTime (fromGregorian 2025 1 12) (secondsToDiffTime 3600)
                venue <- createVenueWithConfig "Payroll Venue"
                admin <- createUserRecord "payroll-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                dayNames <- seedWeekDayNames venue
                levelOne <- createPayLevelRecord venue "LVL 1"
                levelTwo <- createPayLevelRecord venue "LVL 2"
                barShift <- createShiftTypeRecord venue levelOne "Bar"
                let friday =
                        dayNames
                            |> find (\dayName -> dayName.weekdayIndex == 5)
                            |> fromMaybe (error "Missing Friday day name")
                overrideRule <- createPayLevelDayRuleRecord barShift friday levelTwo
                staffUser <- createUserRecord "payroll-staff@example.com" "staff" True
                staff <- createStaffRecord venue (Just staffUser) "Ava" "Worker"
                trialStaff <- createStaffRecord venue Nothing "Trial" "Worker"
                snapshot <- createPayrollSnapshot venue admin [levelOne, levelTwo] [barShift] dayNames [overrideRule]

                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , setTestStartTime (TimeOfDay 9 0 0)
                    , setTestEndTime (TimeOfDay 17 0 0)
                    ]
                _ <- createAndApproveEntry venue staff (fromGregorian 2025 1 10) snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                        , setTestStartTime (TimeOfDay 19 0 0)
                        , setTestEndTime (TimeOfDay 1 0 0)
                    ]
                _ <- createAndApproveEntry venue trialStaff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , setTestStartTime (TimeOfDay 10 0 0)
                    , setTestEndTime (TimeOfDay 12 0 0)
                    ]

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("exportType", cs (exportJobTypeToText StaffPayCsv))
                        , ("rangeStart", "2025-01-06")
                        , ("rangeEnd", "2025-01-12")
                        ]

                response `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders response) `shouldSatisfy` maybe False (Text.isInfixOf "/DownloadExportJob" . cs)

                exportJob <- query @ExportJob |> orderByDesc #createdAt |> fetchOne
                exportJob.exportType `shouldBe` exportJobTypeToText StaffPayCsv
                exportJob.fileName `shouldBe` Just "staff_hrs_starting-2025-01-06.csv"
                exportJob.payConfigVersionManifest `shouldSatisfy` isJust
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    Text.isInfixOf "Employee,Mon Ord,Mon 7-12,Mon 12+"
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    Text.isInfixOf "\"Worker, Ava LVL 2\",8.000000,0.000000,0.000000"
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    (not . Text.isInfixOf "Trial")

        it "aggregates different shift types that resolve to the same pay level" $ withContext do
            withCleanDb do
                let approvedAt = UTCTime (fromGregorian 2025 1 12) (secondsToDiffTime 3600)
                venue <- createVenueWithConfig "Shared Level Payroll Venue"
                admin <- createUserRecord "shared-level-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                dayNames <- seedWeekDayNames venue
                levelOne <- createPayLevelRecord venue "LVL 1"
                barShift <- createShiftTypeRecord venue levelOne "Bar"
                floorShift <- createShiftTypeRecord venue levelOne "Floor"
                staffUser <- createUserRecord "shared-level-staff@example.com" "staff" True
                staff <- createStaffRecord venue (Just staffUser) "Ava" "Worker"
                snapshot <- createPayrollSnapshot venue admin [levelOne] [barShift, floorShift] dayNames []
                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , setTestStartTime (TimeOfDay 9 0 0)
                    , setTestEndTime (TimeOfDay 11 0 0)
                    ]
                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId floorShift.id)
                    , setTestStartTime (TimeOfDay 12 0 0)
                    , setTestEndTime (TimeOfDay 15 0 0)
                    ]

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("exportType", cs (exportJobTypeToText StaffPayCsv))
                        , ("rangeStart", "2025-01-06")
                        , ("rangeEnd", "2025-01-12")
                        ]

                response `responseStatusShouldBe` status302
                exportJob <- query @ExportJob |> orderByDesc #createdAt |> fetchOne
                let csvContents = fromMaybe "" exportJob.fileContents
                Text.count "\"Worker, Ava LVL 1\"," csvContents `shouldBe` 1
                csvContents `shouldSatisfy` Text.isInfixOf "\"Worker, Ava LVL 1\",5.000000,0.000000,0.000000"
                csvContents `shouldSatisfy` (not . Text.isInfixOf "Worker, Ava Bar")
                csvContents `shouldSatisfy` (not . Text.isInfixOf "Worker, Ava Floor")

        it "uses the approval-pinned Xero pay-item name for imported Staff Hours rows" $ withContext do
            withCleanDb do
                let approvedAt = UTCTime (fromGregorian 2025 1 12) (secondsToDiffTime 3600)
                venue <- createVenueWithConfig "Imported Payroll Venue"
                admin <- createUserRecord "imported-payroll-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                dayNames <- seedWeekDayNames venue
                levelOne <- createPayLevelRecord venue "LVL 1"
                importedItem <- createImportedXeroPayItemRecord venue admin "Xero Weekend Rate" "weekend-rate" 52
                shiftType <- createShiftTypeRecord venue levelOne "Bar"
                    >>= updateRecord
                        . set #payAssignmentMode XeroRate
                        . set #overrideAwardLevelId Nothing
                        . set #importedXeroPayItemId (Just importedItem.id)
                staffUser <- createUserRecord "imported-payroll-staff@example.com" "staff" True
                staff <- createStaffRecord venue (Just staffUser) "Ava" "Worker"
                snapshot <- createPayrollSnapshot venue admin [levelOne] [shiftType] dayNames []
                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId shiftType.id)
                    , setTestStartTime (TimeOfDay 9 0 0)
                    , setTestEndTime (TimeOfDay 17 0 0)
                    ]

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("exportType", cs (exportJobTypeToText StaffPayCsv))
                        , ("rangeStart", "2025-01-06")
                        , ("rangeEnd", "2025-01-12")
                        ]

                response `responseStatusShouldBe` status302
                exportJob <- query @ExportJob |> orderByDesc #createdAt |> fetchOne
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    Text.isInfixOf "\"Worker, Ava Xero Weekend Rate\",8.000000,0.000000,0.000000"
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    (not . Text.isInfixOf "Worker, Ava Bar")

        it "limits staff-hours payroll exports to the requested date range" $ withContext do
            withCleanDb do
                let approvedAt = UTCTime (fromGregorian 2025 1 12) (secondsToDiffTime 3600)
                venue <- createVenueWithConfig "Payroll Range Venue"
                admin <- createUserRecord "payroll-range-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                dayNames <- seedWeekDayNames venue
                levelOne <- createPayLevelRecord venue "LVL 1"
                barShift <- createShiftTypeRecord venue levelOne "Bar"
                staffUser <- createUserRecord "payroll-range-staff@example.com" "staff" True
                staff <- createStaffRecord venue (Just staffUser) "Ava" "Worker"
                snapshot <- createPayrollSnapshot venue admin [levelOne] [barShift] dayNames []

                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , setTestStartTime (TimeOfDay 9 0 0)
                    , setTestEndTime (TimeOfDay 17 0 0)
                    ]
                _ <- createAndApproveEntry venue staff (fromGregorian 2025 1 8) snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , setTestStartTime (TimeOfDay 10 0 0)
                    , setTestEndTime (TimeOfDay 13 0 0)
                    ]

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("exportType", cs (exportJobTypeToText StaffPayCsv))
                        , ("rangeStart", "2025-01-08")
                        , ("rangeEnd", "2025-01-08")
                        ]

                response `responseStatusShouldBe` status302

                exportJob <- query @ExportJob |> orderByDesc #createdAt |> fetchOne
                exportJob.fileName `shouldBe` Just "staff_hrs_starting-2025-01-06.csv"
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    Text.isInfixOf "\"Worker, Ava LVL 1\",0.000000,0.000000,0.000000,0.000000,0.000000,0.000000,3.000000"
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    (not . Text.isInfixOf "8.00")

        it "packages multi-week staff-hours payroll exports as weekly CSV files in a ZIP" $ withContext do
            withCleanDb do
                let approvedAt = UTCTime (fromGregorian 2025 1 19) (secondsToDiffTime 3600)
                venue <- createVenueWithConfig "Payroll Multi Week Venue"
                admin <- createUserRecord "payroll-multi-week-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                dayNames <- seedWeekDayNames venue
                levelOne <- createPayLevelRecord venue "LVL 1"
                barShift <- createShiftTypeRecord venue levelOne "Bar"
                staffUser <- createUserRecord "payroll-multi-week-staff@example.com" "staff" True
                staff <- createStaffRecord venue (Just staffUser) "Ava" "Worker"
                snapshot <- createPayrollSnapshot venue admin [levelOne] [barShift] dayNames []

                _ <- createAndApproveEntry venue staff (fromGregorian 2025 1 8) snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , setTestStartTime (TimeOfDay 10 0 0)
                    , setTestEndTime (TimeOfDay 13 0 0)
                    ]
                _ <- createAndApproveEntry venue staff (fromGregorian 2025 1 15) snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , setTestStartTime (TimeOfDay 9 0 0)
                    , setTestEndTime (TimeOfDay 17 0 0)
                    ]

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("exportType", cs (exportJobTypeToText StaffPayCsv))
                        , ("rangeStart", "2025-01-08")
                        , ("rangeEnd", "2025-01-15")
                        ]

                response `responseStatusShouldBe` status302

                exportJob <- query @ExportJob |> orderByDesc #createdAt |> fetchOne
                exportJob.exportType `shouldBe` exportJobTypeToText StaffPayCsv
                exportJob.fileName `shouldBe` Just "staff_hrs-2025-01-08-to-2025-01-15.zip"
                exportJob.contentType `shouldBe` Just "application/zip"
                exportJob.fileEncoding `shouldBe` "base64"
                exportJob.payConfigVersionManifest `shouldSatisfy` isJust

                let archive =
                        fromMaybe Zip.emptyArchive do
                            fileContents <- exportJob.fileContents
                            either (const Nothing) (Just . Zip.toArchive . LBS.fromStrict) (Base64.decode (encodeUtf8 fileContents))
                Zip.filesInArchive archive `shouldContain` ["2025-01-06-to-2025-01-12/staff_hrs_starting-2025-01-06.csv"]
                Zip.filesInArchive archive `shouldContain` ["2025-01-13-to-2025-01-19/staff_hrs_starting-2025-01-13.csv"]
                let firstWeekCsv =
                        archive
                            |> Zip.findEntryByPath "2025-01-06-to-2025-01-12/staff_hrs_starting-2025-01-06.csv"
                            |> fmap (decodeUtf8 . LBS.toStrict . Zip.fromEntry)
                            |> fromMaybe ""
                let secondWeekCsv =
                        archive
                            |> Zip.findEntryByPath "2025-01-13-to-2025-01-19/staff_hrs_starting-2025-01-13.csv"
                            |> fmap (decodeUtf8 . LBS.toStrict . Zip.fromEntry)
                            |> fromMaybe ""
                firstWeekCsv `shouldSatisfy` Text.isInfixOf "\"Worker, Ava LVL 1\",0.000000,0.000000,0.000000,0.000000,0.000000,0.000000,3.000000"
                firstWeekCsv `shouldSatisfy` (not . Text.isInfixOf "8.00")
                secondWeekCsv `shouldSatisfy` Text.isInfixOf "\"Worker, Ava LVL 1\",0.000000,0.000000,0.000000,0.000000,0.000000,0.000000,8.000000"
                secondWeekCsv `shouldSatisfy` (not . Text.isInfixOf "3.00")

        it "creates a payroll earnings export grouped by staff date earnings and tracking code" $ withContext do
            withCleanDb do
                let approvedAt = UTCTime (fromGregorian 2025 1 12) (secondsToDiffTime 7200)
                venue <- createVenueWithConfig "Payroll Earnings Venue"
                admin <- createUserRecord "payroll-earnings-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                dayNames <- seedWeekDayNames venue
                levelOne <- createPayLevelRecordWithRates venue "LVL 1" 30 0 0 1.25 1.5 1.75
                barShift <- createShiftTypeRecord venue levelOne "Bar"
                kitchenShift <- createShiftTypeRecord venue levelOne "Kitchen"
                staffUser <- createUserRecord "payroll-earnings-staff@example.com" "staff" True
                staff <- createStaffRecord venue (Just staffUser) "Rae" "Worker"
                trialStaff <- createStaffRecord venue Nothing "Trial" "Worker"
                snapshot <- createPayrollSnapshot venue admin [levelOne] [barShift, kitchenShift] dayNames []
                _ <- newRecord @PublicHoliday
                    |> set #jurisdiction "VIC"
                    |> set #holidayDate (fromGregorian 2025 1 10)
                    |> set #name "Test Holiday"
                    |> set #isRegional False
                    |> createRecord

                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , setTestStartTime (TimeOfDay 9 0 0)
                    , setTestEndTime (TimeOfDay 12 0 0)
                    ]
                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , setTestStartTime (TimeOfDay 13 0 0)
                    , setTestEndTime (TimeOfDay 15 0 0)
                    ]
                _ <- createAndApproveEntry venue staff (fromGregorian 2025 1 10) snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , setTestStartTime (TimeOfDay 9 0 0)
                    , setTestEndTime (TimeOfDay 13 0 0)
                    ]
                _ <- createAndApproveEntry venue staff (fromGregorian 2025 1 11) snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId kitchenShift.id)
                    , setTestStartTime (TimeOfDay 9 0 0)
                    , setTestEndTime (TimeOfDay 11 0 0)
                    ]
                _ <- createAndApproveEntry venue trialStaff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , setTestStartTime (TimeOfDay 10 0 0)
                    , setTestEndTime (TimeOfDay 12 0 0)
                    ]

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("exportType", cs (exportJobTypeToText PayrollEarningsCsv))
                        , ("rangeStart", "2025-01-06")
                        , ("rangeEnd", "2025-01-12")
                        ]

                response `responseStatusShouldBe` status302

                exportJob <- query @ExportJob |> orderByDesc #createdAt |> fetchOne
                let csvContents = fromMaybe "" exportJob.fileContents
                exportJob.exportType `shouldBe` exportJobTypeToText PayrollEarningsCsv
                exportJob.fileName `shouldBe` Just "payroll_earnings-2025-01-06-to-2025-01-12.csv"
                exportJob.contentType `shouldBe` Just "text/csv; charset=utf-8"
                exportJob.fileEncoding `shouldBe` "utf8"
                exportJob.payConfigVersionManifest `shouldSatisfy` isJust
                csvContents `shouldSatisfy`
                    Text.isInfixOf "staff_first_name,staff_last_name,work_date,earnings_rate_name,exact_quantity,quantity,unit,rate_per_unit,exact_amount,amount,tracking_code"
                csvContents `shouldSatisfy`
                    Text.isInfixOf "Rae,Worker,2025-01-06,Bar - Ordinary,5/1,5.000000,hours,"
                csvContents `shouldSatisfy`
                    Text.isInfixOf "Rae,Worker,2025-01-10,Bar - Public Holiday,4/1,4.000000,hours,"
                csvContents `shouldSatisfy`
                    Text.isInfixOf "Rae,Worker,2025-01-11,Kitchen - Saturday,2/1,2.000000,hours,"
                csvContents `shouldSatisfy`
                    Text.isInfixOf ",public_holiday,bepis-projection:award_level_penalty_rates:"
                csvContents `shouldSatisfy`
                    (not . Text.isInfixOf "Trial")

        it "rounds the venue window outward and expands it for approved timesheets" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Hourly Window Venue"
                venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
                configured <- venueConfig
                    |> set #timePickerStartMinuteOfDay (9 * 60 + 15)
                    |> set #timePickerFinalSelectableMinuteOfDay (2 * 60 + 45)
                    |> updateRecord
                buildHourlyReportWindow configured [] `shouldBe` HourlyReportWindow 9 27

                staff <- createStaffRecord venue Nothing "Window" "Worker"
                entry <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 6)
                    >>= updateRecord
                        . setTestStartTime (TimeOfDay 8 37 0)
                        . setTestEndTime (TimeOfDay 3 10 0)
                buildHourlyReportWindow configured [entry] `shouldBe` HourlyReportWindow 8 28

        it "buckets exact repeated and skipped DST hours in hourly breakdowns" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Hourly DST Venue"
                staff <- createStaffRecord venue Nothing "Hourly" "DST"
                level <- createPayLevelRecord venue "Level 1"
                shiftType <- createShiftTypeRecord venue level "Bar"
                autumnEntry <- createTimesheetEntryRecord venue staff (fromGregorian 2026 4 4)
                    >>= updateRecord
                        . set #shiftTypeId (unpackId shiftType.id)
                        . setTestTimesheetBoundaries (fromGregorian 2026 4 4) (TimeOfDay 22 0 0) (TimeOfDay 4 0 0)
                springEntry <- createTimesheetEntryRecord venue staff (fromGregorian 2026 10 3)
                    >>= updateRecord
                        . set #shiftTypeId (unpackId shiftType.id)
                        . setTestTimesheetBoundaries (fromGregorian 2026 10 3) (TimeOfDay 22 0 0) (TimeOfDay 4 0 0)

                let window = HourlyReportWindow 8 28
                let columns = [HourlyShiftTypeColumn (unpackId shiftType.id) "Bar"]
                let autumnCsv = Text.lines (renderHourlyBreakdownDateCsv (fromGregorian 2026 4 4) window columns [autumnEntry])
                let springCsv = Text.lines (renderHourlyBreakdownDateCsv (fromGregorian 2026 10 3) window columns [springEntry])

                autumnCsv `shouldContain` ["02:00-03:00+1,2.000000,2.000000"]
                autumnCsv `shouldContain` ["03:00-04:00+1,1.000000,1.000000"]
                springCsv `shouldContain` ["02:00-03:00+1,,0.000000"]
                springCsv `shouldContain` ["03:00-04:00+1,1.000000,1.000000"]

        it "creates and downloads an hourly breakdown ZIP export" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Hourly Venue"
                admin <- createUserRecord "hourly-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                dayNames <- seedWeekDayNames venue
                barLevel <- createPayLevelRecordWithRates venue "Bar Level" 30 0 0 1.25 1.5 1.75
                floorLevel <- createPayLevelRecordWithRates venue "Floor Level" 28 0 0 1.25 1.5 1.75
                barShift <- createShiftTypeRecord venue barLevel "Bar" >>= updateRecord . set #sortOrder 10
                floorShift <- createShiftTypeRecord venue floorLevel "Floor" >>= updateRecord . set #sortOrder 20
                let duplicateColumns = buildHourlyShiftTypeColumns [barShift, floorShift |> set #name "Bar"] [] [] Map.empty
                map (.hourlyShiftTypeLabel) duplicateColumns `shouldBe` ["Bar (1)", "Bar (2)"]
                let reservedColumns = buildHourlyShiftTypeColumns [barShift |> set #name "Time", floorShift |> set #name "Total"] [] [] Map.empty
                map (.hourlyShiftTypeLabel) reservedColumns `shouldBe` ["Time (1)", "Total (1)"]
                staff <- createStaffRecord venue Nothing "Nia" "Night"
                snapshot <- createPayrollSnapshot venue admin [barLevel, floorLevel] [barShift, floorShift] dayNames []
                let approvedAt = UTCTime (fromGregorian 2025 1 12) (secondsToDiffTime 0)
                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , setTestStartTime (TimeOfDay 8 0 0)
                    , setTestEndTime (TimeOfDay 10 30 0)
                    ]
                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId floorShift.id)
                    , setTestStartTime (TimeOfDay 9 0 0)
                    , setTestEndTime (TimeOfDay 11 0 0)
                    ]

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("exportType", cs (exportJobTypeToText HourlyBreakdownZip))
                        , ("rangeStart", "2025-01-06")
                        , ("rangeEnd", "2025-01-12")
                        ]

                response `responseStatusShouldBe` status302

                exportJob <- query @ExportJob |> orderByDesc #createdAt |> fetchOne
                exportJob.exportType `shouldBe` exportJobTypeToText HourlyBreakdownZip
                exportJob.fileName `shouldBe` Just "hourly_staff_hours-2025-01-06-to-2025-01-12.zip"
                exportJob.contentType `shouldBe` Just "application/zip"
                exportJob.fileEncoding `shouldBe` "base64"
                exportJob.payConfigVersionManifest `shouldSatisfy` isJust

                downloadResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (DownloadExportJobAction exportJob.id)
                        [("token", cs (tshow exportJob.downloadToken))]

                downloadResponse `responseStatusShouldBe` status200
                lookup hContentType (responseHeaders downloadResponse) `shouldBe` Just "application/zip"
                lookup hContentDisposition (responseHeaders downloadResponse) `shouldBe` Just "attachment; filename=\"hourly_staff_hours-2025-01-06-to-2025-01-12.zip\""

                downloadBody <- responseBody downloadResponse
                let archive = Zip.toArchive downloadBody
                Zip.filesInArchive archive `shouldContain` ["2025-01-06_Monday_staff_hours.csv"]
                let mondayCsv =
                        archive
                            |> Zip.findEntryByPath "2025-01-06_Monday_staff_hours.csv"
                            |> fmap (decodeUtf8 . LBS.toStrict . Zip.fromEntry)
                            |> fromMaybe ""
                mondayCsv `shouldSatisfy` Text.isInfixOf "Time,Bar,Floor,Total"
                mondayCsv `shouldSatisfy` Text.isInfixOf "08:00-09:00,1.000000,,1.000000"
                mondayCsv `shouldSatisfy` Text.isInfixOf "09:00-10:00,1.000000,1.000000,2.000000"
                mondayCsv `shouldSatisfy` Text.isInfixOf "10:00-11:00,0.500000,1.000000,1.500000"
                mondayCsv `shouldSatisfy` Text.isInfixOf "Total,2.500000,2.000000,4.500000"

                wageResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("exportType", cs (exportJobTypeToText HourlyWageTotalsZip))
                        , ("rangeStart", "2025-01-06")
                        , ("rangeEnd", "2025-01-12")
                        ]
                wageResponse `responseStatusShouldBe` status302

                wageExportJob <- query @ExportJob |> orderByDesc #createdAt |> fetchOne
                wageExportJob.exportType `shouldBe` exportJobTypeToText HourlyWageTotalsZip
                wageExportJob.fileName `shouldBe` Just "hourly_wage_totals-2025-01-06-to-2025-01-12.zip"
                wageDownloadResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (DownloadExportJobAction wageExportJob.id)
                        [("token", cs (tshow wageExportJob.downloadToken))]
                wageDownloadBody <- responseBody wageDownloadResponse
                let wageArchive = Zip.toArchive wageDownloadBody
                Zip.filesInArchive wageArchive `shouldContain` ["2025-01-06_Monday_wage_totals.csv"]
                let mondayWages =
                        wageArchive
                            |> Zip.findEntryByPath "2025-01-06_Monday_wage_totals.csv"
                            |> fmap (decodeUtf8 . LBS.toStrict . Zip.fromEntry)
                            |> fromMaybe ""
                mondayWages `shouldSatisfy` Text.isInfixOf "Time,Bar,Floor,Total"
                mondayWages `shouldSatisfy` Text.isInfixOf "08:00-09:00,37.50,,37.50"
                mondayWages `shouldSatisfy` Text.isInfixOf "09:00-10:00,37.50,37.50,75.00"
                mondayWages `shouldSatisfy` Text.isInfixOf "10:00-11:00,18.75,37.50,56.25"
                mondayWages `shouldSatisfy` Text.isInfixOf "Total,93.75,75.00,168.75"

        it "spreads minimum top-ups and commenced-hour additions across worked wage buckets" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Hourly Wage Attribution Venue"
                admin <- createUserRecord "hourly-attribution-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                dayNames <- seedWeekDayNames venue
                level <- createPayLevelRecordWithRates venue "Bar Level" 30 2.5 3 1 1.5 1.75
                shiftType <- createShiftTypeRecord venue level "Bar"
                staff <- createStaffRecord venue Nothing "Ari" "Attribution"
                snapshot <- createPayrollSnapshot venue admin [level] [shiftType] dayNames []
                let approvedAt = UTCTime (fromGregorian 2025 1 12) (secondsToDiffTime 0)
                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId shiftType.id)
                    , setTestStartTime (TimeOfDay 18 30 0)
                    , setTestEndTime (TimeOfDay 20 15 0)
                    ]

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("exportType", cs (exportJobTypeToText HourlyWageTotalsZip))
                        , ("rangeStart", "2025-01-06")
                        , ("rangeEnd", "2025-01-12")
                        ]
                response `responseStatusShouldBe` status302

                exportJob <- query @ExportJob |> orderByDesc #createdAt |> fetchOne
                downloadResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (DownloadExportJobAction exportJob.id)
                        [("token", cs (tshow exportJob.downloadToken))]
                downloadBody <- responseBody downloadResponse
                let archive = Zip.toArchive downloadBody
                let mondayWages =
                        archive
                            |> Zip.findEntryByPath "2025-01-06_Monday_wage_totals.csv"
                            |> fmap (decodeUtf8 . LBS.toStrict . Zip.fromEntry)
                            |> fromMaybe ""
                mondayWages `shouldSatisfy` Text.isInfixOf "18:00-19:00,21.43,21.43"
                mondayWages `shouldSatisfy` Text.isInfixOf "19:00-20:00,46.86,46.86"
                mondayWages `shouldSatisfy` Text.isInfixOf "20:00-21:00,11.71,11.71"
                mondayWages `shouldSatisfy` Text.isInfixOf "Total,80.00,80.00"

        it "allocates missed-meal-break additions only during the penalised interval" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Hourly Missed Break Venue"
                admin <- createUserRecord "hourly-missed-break-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                dayNames <- seedWeekDayNames venue
                level <- createPayLevelRecordWithRates venue "Bar Level" 30 0 0 1 1.5 1.75
                shiftType <- createShiftTypeRecord venue level "Bar"
                staff <- createStaffRecord venue Nothing "Mia" "Mealbreak"
                snapshot <- createPayrollSnapshot venue admin [level] [shiftType] dayNames []
                let approvedAt = UTCTime (fromGregorian 2025 1 12) (secondsToDiffTime 0)
                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId shiftType.id)
                    , setTestStartTime (TimeOfDay 9 0 0)
                    , setTestEndTime (TimeOfDay 16 0 0)
                    ]

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("exportType", cs (exportJobTypeToText HourlyWageTotalsZip))
                        , ("rangeStart", "2025-01-06")
                        , ("rangeEnd", "2025-01-12")
                        ]
                response `responseStatusShouldBe` status302
                exportJob <- query @ExportJob |> orderByDesc #createdAt |> fetchOne
                downloadResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (DownloadExportJobAction exportJob.id)
                        [("token", cs (tshow exportJob.downloadToken))]
                downloadBody <- responseBody downloadResponse
                let mondayWages =
                        Zip.toArchive downloadBody
                            |> Zip.findEntryByPath "2025-01-06_Monday_wage_totals.csv"
                            |> fmap (decodeUtf8 . LBS.toStrict . Zip.fromEntry)
                            |> fromMaybe ""
                mondayWages `shouldSatisfy` Text.isInfixOf "14:00-15:00,37.50,37.50"
                mondayWages `shouldSatisfy` Text.isInfixOf "15:00-16:00,52.50,52.50"
                mondayWages `shouldSatisfy` Text.isInfixOf "Total,277.50,277.50"

        it "downloads a ready export and audits the download" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Export Venue"
                admin <- createUserRecord "exports-download@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin
                staff <- createStaffRecord venue Nothing "Bea" "Hours"
                _ <- createApprovedTimesheetEntryRecordAt venue staff admin (fromGregorian 2025 1 10) (UTCTime (fromGregorian 2025 1 10) (secondsToDiffTime 0))
                _ <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("exportType", cs (exportJobTypeToText ApprovedTimesheetsCsv))
                        , ("rangeStart", "2025-01-06")
                        , ("rangeEnd", "2025-01-12")
                        ]
                exportJob <- query @ExportJob |> fetchOne

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (DownloadExportJobAction exportJob.id)
                        [("token", cs (tshow exportJob.downloadToken))]

                response `responseStatusShouldBe` status200
                lookup hContentType (responseHeaders response) `shouldBe` Just "text/csv; charset=utf-8"
                lookup hContentDisposition (responseHeaders response) `shouldBe` Just "attachment; filename=\"approved-timesheets-2025-01-06-to-2025-01-12.csv\""
                response `responseBodyShouldContain` "Hours, Bea"

                updatedExportJob <- fetch exportJob.id
                updatedExportJob.downloadedByUserId `shouldBe` Just (unpackId admin.id)
                updatedExportJob.downloadedAt `shouldSatisfy` isJust

                auditEvents <- query @AuditEvent |> orderByAsc #createdAt |> fetch
                map (.eventType) auditEvents `shouldBe` ["export_generated", "export_downloaded"]

        it "hides persisted recent export jobs from the simplified export surface" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                admin <- createUserRecord "exports-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA admin VenueOwner
                _ <- createVenueMembershipRecord venueB admin VenueOwner
                exportJobA <- newRecord @ExportJob
                    |> set #venueId (unpackId venueA.id)
                    |> set #requestedByUserId (unpackId admin.id)
                    |> set #exportType (exportJobTypeToText ApprovedTimesheetsCsv)
                    |> set #status (exportJobStatusToText ExportReady)
                    |> set #scope (Aeson.object [])
                    |> set #deliveryMethod browserDownloadMethod
                    |> set #destinationMetadata (Aeson.object [])
                    |> set #fileName (Just "venue-a.csv")
                    |> set #contentType (Just "text/csv; charset=utf-8")
                    |> set #fileContents (Just "header")
                    |> set #expiresAt (UTCTime (fromGregorian 2030 2 1) (secondsToDiffTime 0))
                    |> createRecord
                exportJobB <- newRecord @ExportJob
                    |> set #venueId (unpackId venueB.id)
                    |> set #requestedByUserId (unpackId admin.id)
                    |> set #exportType (exportJobTypeToText ApprovedTimesheetsCsv)
                    |> set #status (exportJobStatusToText ExportReady)
                    |> set #scope (Aeson.object [])
                    |> set #deliveryMethod browserDownloadMethod
                    |> set #destinationMetadata (Aeson.object [])
                    |> set #fileName (Just "venue-b.csv")
                    |> set #contentType (Just "text/csv; charset=utf-8")
                    |> set #fileContents (Just "header")
                    |> set #expiresAt (UTCTime (fromGregorian 2030 2 1) (secondsToDiffTime 0))
                    |> createRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venueB.id do
                    callAction ShowadminExportsLiveFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Staff Hours CSV"
                response `responseBodyShouldContain` "Download CSV"
                response `responseBodyShouldNotContain` "Recent Exports"
                response `responseBodyShouldNotContain` "venue-b.csv"
                response `responseBodyShouldNotContain` "venue-a.csv"

        it "redirects the legacy export jobs page to the admin exports section" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Export Venue"
                admin <- createUserRecord "exports-definitions@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ExportJobsAction

                response `responseStatusShouldBe` status302

        it "shows an error toast when the selected week has no approved staff hours" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Empty Staff Hours Venue"
                admin <- createUserRecord "empty-staff-hours@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    withRequestHeaders [("HX-Request", "true")] do
                        callActionWithParams CreateExportJobAction
                            [ ("exportType", cs (exportJobTypeToText StaffPayCsv))
                            , ("rangeStart", "2025-01-06")
                            , ("rangeEnd", "2025-01-12")
                            ]

                response `responseStatusShouldBe` status200
                lookup "HX-Reswap" (responseHeaders response) `shouldBe` Just "none"
                lookup "HX-Redirect" (responseHeaders response) `shouldBe` Nothing
                response `responseBodyShouldContain` "No approved staff hours were found for the selected roster week."
                exportJobCount <- query @ExportJob |> fetchCount
                exportJobCount `shouldBe` 0

        it "rejects invalid export date ranges without creating a job" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invalid Range Venue"
                admin <- createUserRecord "exports-invalid-range@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin VenueAdmin

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("exportType", cs (exportJobTypeToText ApprovedTimesheetsCsv))
                        , ("rangeStart", "2025-01-12")
                        , ("rangeEnd", "2025-01-06")
                        ]

                response `responseStatusShouldBe` status302
                exportJobCount <- query @ExportJob |> fetchCount
                exportJobCount `shouldBe` 0

        it "denies managers access to export generation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Manager Venue"
                manager <- createUserRecord "exports-manager@example.com" "staff" True
                _ <- createVenueMembershipRecord venue manager Manager
                dayNames <- seedWeekDayNames venue
                levelOne <- createPayLevelRecord venue "Level 1"
                barShift <- createShiftTypeRecord venue levelOne "Bar"
                staff <- createStaffRecord venue Nothing "Mira" "Worker"
                snapshot <- createPayrollSnapshot venue manager [levelOne] [barShift] dayNames []
                let approvedAt = UTCTime (fromGregorian 2025 1 12) (secondsToDiffTime 3600)
                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot manager approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , setTestStartTime (TimeOfDay 9 0 0)
                    , setTestEndTime (TimeOfDay 12 0 0)
                    ]

                pageResponse <- withUserAndCurrentVenue manager venue.id do
                    callAction ExportJobsAction

                pageResponse `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders pageResponse) `shouldBe` Just "http://localhost/RosterWeeks"

                createExportResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("exportType", cs (exportJobTypeToText StaffPayCsv))
                        , ("rangeStart", "2025-01-06")
                        , ("rangeEnd", "2025-01-12")
                        ]

                createExportResponse `responseStatusShouldBe` status302
                lookup "Location" (responseHeaders createExportResponse) `shouldBe` Just "http://localhost/RosterWeeks"

        it "denies downloading another venue's export job" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                admin <- createUserRecord "exports-foreign@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA admin VenueAdmin
                foreignJob <- newRecord @ExportJob
                    |> set #venueId (unpackId venueB.id)
                    |> set #requestedByUserId (unpackId admin.id)
                    |> set #exportType (exportJobTypeToText ApprovedTimesheetsCsv)
                    |> set #status (exportJobStatusToText ExportReady)
                    |> set #scope (Aeson.object [])
                    |> set #deliveryMethod browserDownloadMethod
                    |> set #destinationMetadata (Aeson.object [])
                    |> set #fileName (Just "foreign.csv")
                    |> set #contentType (Just "text/csv; charset=utf-8")
                    |> set #fileContents (Just "header")
                    |> set #expiresAt (UTCTime (fromGregorian 2030 2 1) (secondsToDiffTime 0))
                    |> createRecord

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venueA.id do
                    callActionWithParams (DownloadExportJobAction foreignJob.id)
                        [("token", cs (tshow foreignJob.downloadToken))]

                response `responseStatusShouldBe` status403
