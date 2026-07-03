module Test.Controller.ExportsSpec where

import Application.Helper.Export
import Application.Helper.LiveResource
import qualified Codec.Archive.Zip as Zip
import Config
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Base64 as Base64
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8, encodeUtf8)
import Data.Time.Calendar (Day, fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
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
import Test.Support.PayrollFixtures (createAndApproveEntry,
                                     createPayrollSnapshot, seedWeekDayNames)
import Web.Controller.Exports ()
import Web.Exports.Mutations (exportJobTouchedResources)
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = beforeAll testContext do
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
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                staff <- createStaffRecord venue Nothing "Ava" "Hours"
                _ <- createApprovedTimesheetEntryRecordAt venue staff admin (fromGregorian 2025 1 10) approvedAt
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
                exportJob.status `shouldBe` exportJobStatusToText ExportReady
                exportJob.rangeStart `shouldBe` Just (fromGregorian 2025 1 6)
                exportJob.rangeEnd `shouldBe` Just (fromGregorian 2025 1 12)
                exportJob.payConfigVersionManifest `shouldSatisfy` isJust
                exportJob.fileName `shouldBe` Just "approved-timesheets-2025-01-06-to-2025-01-12.csv"
                exportJob.fileContents `shouldSatisfy` isJust
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    Text.isInfixOf "worked_on,staff_name,start_time,end_time,break_minutes,pay_config_version_manifest,approved_at,approved_by_email"
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
                _ <- createVenueMembershipRecord venue admin "venue_admin"

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
                _ <- createVenueMembershipRecord venue admin "venue_admin"
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
                    , set #startTime (TimeOfDay 9 0 0)
                    , set #endTime (TimeOfDay 17 0 0)
                    ]
                _ <- createAndApproveEntry venue staff (fromGregorian 2025 1 10) snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                        , set #startTime (TimeOfDay 19 0 0)
                        , set #endTime (TimeOfDay 1 0 0)
                    ]
                _ <- createAndApproveEntry venue trialStaff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , set #startTime (TimeOfDay 10 0 0)
                    , set #endTime (TimeOfDay 12 0 0)
                    ]

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("exportType", cs (exportJobTypeToText StaffPayCsv))
                        , ("rangeStart", "2025-01-06")
                        , ("rangeEnd", "2025-01-12")
                        ]

                response `responseStatusShouldBe` status302

                exportJob <- query @ExportJob |> orderByDesc #createdAt |> fetchOne
                exportJob.exportType `shouldBe` exportJobTypeToText StaffPayCsv
                exportJob.fileName `shouldBe` Just "staff_hours-2025-01-06-to-2025-01-12.csv"
                exportJob.payConfigVersionManifest `shouldSatisfy` isJust
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    Text.isInfixOf "Name/Type,Mond Ord,Mond 7-12,Mond 12+"
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    Text.isInfixOf "Ava LVL 2,8.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,5.00,0.00,0.00,1.00,0.00"
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    (not . Text.isInfixOf "Trial")

        it "limits staff-hours payroll exports to the requested date range" $ withContext do
            withCleanDb do
                let approvedAt = UTCTime (fromGregorian 2025 1 12) (secondsToDiffTime 3600)
                venue <- createVenueWithConfig "Payroll Range Venue"
                admin <- createUserRecord "payroll-range-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                dayNames <- seedWeekDayNames venue
                levelOne <- createPayLevelRecord venue "LVL 1"
                barShift <- createShiftTypeRecord venue levelOne "Bar"
                staffUser <- createUserRecord "payroll-range-staff@example.com" "staff" True
                staff <- createStaffRecord venue (Just staffUser) "Ava" "Worker"
                snapshot <- createPayrollSnapshot venue admin [levelOne] [barShift] dayNames []

                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , set #startTime (TimeOfDay 9 0 0)
                    , set #endTime (TimeOfDay 17 0 0)
                    ]
                _ <- createAndApproveEntry venue staff (fromGregorian 2025 1 8) snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , set #startTime (TimeOfDay 10 0 0)
                    , set #endTime (TimeOfDay 13 0 0)
                    ]

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("exportType", cs (exportJobTypeToText StaffPayCsv))
                        , ("rangeStart", "2025-01-08")
                        , ("rangeEnd", "2025-01-08")
                        ]

                response `responseStatusShouldBe` status302

                exportJob <- query @ExportJob |> orderByDesc #createdAt |> fetchOne
                exportJob.fileName `shouldBe` Just "staff_hours-2025-01-08-to-2025-01-08.csv"
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    Text.isInfixOf "Ava LVL 1,0.00,0.00,0.00,0.00,0.00,0.00,3.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00"
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    (not . Text.isInfixOf "8.00")

        it "packages multi-week staff-hours payroll exports as weekly CSV files in a ZIP" $ withContext do
            withCleanDb do
                let approvedAt = UTCTime (fromGregorian 2025 1 19) (secondsToDiffTime 3600)
                venue <- createVenueWithConfig "Payroll Multi Week Venue"
                admin <- createUserRecord "payroll-multi-week-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                dayNames <- seedWeekDayNames venue
                levelOne <- createPayLevelRecord venue "LVL 1"
                barShift <- createShiftTypeRecord venue levelOne "Bar"
                staffUser <- createUserRecord "payroll-multi-week-staff@example.com" "staff" True
                staff <- createStaffRecord venue (Just staffUser) "Ava" "Worker"
                snapshot <- createPayrollSnapshot venue admin [levelOne] [barShift] dayNames []

                _ <- createAndApproveEntry venue staff (fromGregorian 2025 1 8) snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , set #startTime (TimeOfDay 10 0 0)
                    , set #endTime (TimeOfDay 13 0 0)
                    ]
                _ <- createAndApproveEntry venue staff (fromGregorian 2025 1 15) snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , set #startTime (TimeOfDay 9 0 0)
                    , set #endTime (TimeOfDay 17 0 0)
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
                exportJob.fileName `shouldBe` Just "staff_hours-2025-01-08-to-2025-01-15.zip"
                exportJob.contentType `shouldBe` Just "application/zip"
                exportJob.fileEncoding `shouldBe` "base64"
                exportJob.payConfigVersionManifest `shouldSatisfy` isJust

                let archive =
                        fromMaybe Zip.emptyArchive do
                            fileContents <- exportJob.fileContents
                            either (const Nothing) (Just . Zip.toArchive . LBS.fromStrict) (Base64.decode (encodeUtf8 fileContents))
                Zip.filesInArchive archive `shouldContain` ["2025-01-06-to-2025-01-12/staff_hours.csv"]
                Zip.filesInArchive archive `shouldContain` ["2025-01-13-to-2025-01-19/staff_hours.csv"]
                let firstWeekCsv =
                        archive
                            |> Zip.findEntryByPath "2025-01-06-to-2025-01-12/staff_hours.csv"
                            |> fmap (decodeUtf8 . LBS.toStrict . Zip.fromEntry)
                            |> fromMaybe ""
                let secondWeekCsv =
                        archive
                            |> Zip.findEntryByPath "2025-01-13-to-2025-01-19/staff_hours.csv"
                            |> fmap (decodeUtf8 . LBS.toStrict . Zip.fromEntry)
                            |> fromMaybe ""
                firstWeekCsv `shouldSatisfy` Text.isInfixOf "Ava LVL 1,0.00,0.00,0.00,0.00,0.00,0.00,3.00"
                firstWeekCsv `shouldSatisfy` (not . Text.isInfixOf "8.00")
                secondWeekCsv `shouldSatisfy` Text.isInfixOf "Ava LVL 1,0.00,0.00,0.00,0.00,0.00,0.00,8.00"
                secondWeekCsv `shouldSatisfy` (not . Text.isInfixOf "3.00")

        it "creates a payroll earnings export grouped by staff date earnings and tracking code" $ withContext do
            withCleanDb do
                let approvedAt = UTCTime (fromGregorian 2025 1 12) (secondsToDiffTime 7200)
                venue <- createVenueWithConfig "Payroll Earnings Venue"
                admin <- createUserRecord "payroll-earnings-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
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
                    , set #startTime (TimeOfDay 9 0 0)
                    , set #endTime (TimeOfDay 12 0 0)
                    ]
                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , set #startTime (TimeOfDay 13 0 0)
                    , set #endTime (TimeOfDay 15 0 0)
                    ]
                _ <- createAndApproveEntry venue staff (fromGregorian 2025 1 10) snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , set #startTime (TimeOfDay 9 0 0)
                    , set #endTime (TimeOfDay 13 0 0)
                    ]
                _ <- createAndApproveEntry venue staff (fromGregorian 2025 1 11) snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId kitchenShift.id)
                    , set #startTime (TimeOfDay 9 0 0)
                    , set #endTime (TimeOfDay 11 0 0)
                    ]
                _ <- createAndApproveEntry venue trialStaff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , set #startTime (TimeOfDay 10 0 0)
                    , set #endTime (TimeOfDay 12 0 0)
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
                    Text.isInfixOf "staff_first_name,staff_last_name,work_date,earnings_rate_name,hours,tracking_code,description,staff_id,timesheet_entry_ids,pay_config_version_manifest,source_penalty_kind,source_pay_level_name,source_shift_type_name"
                csvContents `shouldSatisfy`
                    Text.isInfixOf "Rae,Worker,2025-01-06,LVL 1 - Ordinary,5.00,Bar,"
                csvContents `shouldSatisfy`
                    Text.isInfixOf "Rae,Worker,2025-01-10,LVL 1 - Public Holiday,4.00,Bar,"
                csvContents `shouldSatisfy`
                    Text.isInfixOf "Rae,Worker,2025-01-11,LVL 1 - Saturday,2.00,Kitchen,"
                csvContents `shouldSatisfy`
                    Text.isInfixOf ",public_holiday_penalty,LVL 1,Bar"
                csvContents `shouldSatisfy`
                    (not . Text.isInfixOf "Trial")

        it "creates and downloads an hourly breakdown ZIP export" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Hourly Venue"
                admin <- createUserRecord "hourly-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                dayNames <- seedWeekDayNames venue
                barLevel <- createPayLevelRecordWithRates venue "Bar Level" 30 0 0 1.25 1.5 1.75
                floorLevel <- createPayLevelRecordWithRates venue "Floor Level" 28 0 0 1.25 1.5 1.75
                barShift <- createShiftTypeRecord venue barLevel "Bar" >>= updateRecord . set #sortOrder 10
                floorShift <- createShiftTypeRecord venue floorLevel "Floor" >>= updateRecord . set #sortOrder 20
                staff <- createStaffRecord venue Nothing "Nia" "Night"
                snapshot <- createPayrollSnapshot venue admin [barLevel, floorLevel] [barShift, floorShift] dayNames []
                let approvedAt = UTCTime (fromGregorian 2025 1 12) (secondsToDiffTime 0)
                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , set #startTime (TimeOfDay 8 0 0)
                    , set #endTime (TimeOfDay 10 30 0)
                    ]
                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId floorShift.id)
                    , set #startTime (TimeOfDay 9 0 0)
                    , set #endTime (TimeOfDay 11 0 0)
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
                exportJob.fileName `shouldBe` Just "hourly_breakdown-2025-01-06-to-2025-01-12.zip"
                exportJob.contentType `shouldBe` Just "application/zip"
                exportJob.fileEncoding `shouldBe` "base64"
                exportJob.payConfigVersionManifest `shouldSatisfy` isJust

                downloadResponse <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callActionWithParams (DownloadExportJobAction exportJob.id)
                        [("token", cs (tshow exportJob.downloadToken))]

                downloadResponse `responseStatusShouldBe` status200
                lookup hContentType (responseHeaders downloadResponse) `shouldBe` Just "application/zip"
                lookup hContentDisposition (responseHeaders downloadResponse) `shouldBe` Just "attachment; filename=\"hourly_breakdown-2025-01-06-to-2025-01-12.zip\""

                downloadBody <- responseBody downloadResponse
                let archive = Zip.toArchive downloadBody
                Zip.filesInArchive archive `shouldContain` ["2025-01-06_Monday.csv"]
                let mondayCsv =
                        archive
                            |> Zip.findEntryByPath "2025-01-06_Monday.csv"
                            |> fmap (decodeUtf8 . LBS.toStrict . Zip.fromEntry)
                            |> fromMaybe ""
                mondayCsv `shouldSatisfy` Text.isInfixOf "Time,Bar,Floor"
                mondayCsv `shouldSatisfy` Text.isInfixOf "08:00,1.0,"
                mondayCsv `shouldSatisfy` Text.isInfixOf "09:00,1.0,1.0"
                mondayCsv `shouldSatisfy` Text.isInfixOf "10:00,0.5,1.0"

        it "downloads a ready export and audits the download" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Export Venue"
                admin <- createUserRecord "exports-download@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
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

        it "shows only current-venue export jobs" $ withContext do
            withCleanDb do
                venueA <- createVenueWithConfig "Venue A"
                venueB <- createVenueWithConfig "Venue B"
                admin <- createUserRecord "exports-scope@example.com" "staff" True
                _ <- createVenueMembershipRecord venueA admin "venue_owner"
                _ <- createVenueMembershipRecord venueB admin "venue_owner"
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
                    callAction ShowAdminExportsFragmentAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Exports"
                response `responseBodyShouldContain` "Approved Timesheets CSV"
                response `responseBodyShouldContain` "data-disable-javascript-submission=\"true\""
                response `responseBodyShouldContain` "venue-b.csv"
                response `responseBodyShouldNotContain` "venue-a.csv"

        it "redirects the legacy export jobs page to the admin exports section" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Export Venue"
                admin <- createUserRecord "exports-definitions@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

                response <- withPasskeyVerifiedUserAndCurrentVenue admin venue.id do
                    callAction ExportJobsAction

                response `responseStatusShouldBe` status302

        it "rejects invalid export date ranges without creating a job" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invalid Range Venue"
                admin <- createUserRecord "exports-invalid-range@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"

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
                _ <- createVenueMembershipRecord venue manager "manager"
                dayNames <- seedWeekDayNames venue
                levelOne <- createPayLevelRecord venue "Level 1"
                barShift <- createShiftTypeRecord venue levelOne "Bar"
                staff <- createStaffRecord venue Nothing "Mira" "Worker"
                snapshot <- createPayrollSnapshot venue manager [levelOne] [barShift] dayNames []
                let approvedAt = UTCTime (fromGregorian 2025 1 12) (secondsToDiffTime 3600)
                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot manager approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , set #startTime (TimeOfDay 9 0 0)
                    , set #endTime (TimeOfDay 12 0 0)
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
                _ <- createVenueMembershipRecord venueA admin "venue_admin"
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
