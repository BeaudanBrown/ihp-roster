module Test.Controller.ExportsSpec where

import Application.Helper.Export
import qualified Codec.Archive.Zip as Zip
import Config
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import Data.Text.Encoding (decodeUtf8)
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
                snapshot <- createPayConfigSnapshotRecord venue admin 1 (Aeson.object [])
                _ <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 10)
                    >>= updateRecord
                        . set #payConfigSnapshotId (Just (unpackId snapshot.id))
                        . set #isApproved True
                        . set #approvedAt (Just approvedAt)
                        . set #approvedByUserId (Just (unpackId admin.id))
                _ <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 11)

                response <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("rangeStart", "2025-01-06")
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
                exportJob.payConfigSnapshotVersion `shouldBe` Just "v1"
                exportJob.fileName `shouldBe` Just "approved-timesheets-2025-01-06-to-2025-01-12.csv"
                exportJob.fileContents `shouldSatisfy` isJust
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    Text.isInfixOf "worked_on,staff_name,start_time,end_time,break_minutes,pay_config_snapshot_version,approved_at,approved_by_email"
                fromMaybe "" exportJob.fileContents `shouldSatisfy` Text.isInfixOf "2025-01-10"
                fromMaybe "" exportJob.fileContents `shouldSatisfy` Text.isInfixOf ",v1,"
                fromMaybe "" exportJob.fileContents `shouldSatisfy` (not . Text.isInfixOf "2025-01-11")

                auditEvent <- query @AuditEvent |> fetchOne
                auditEvent.eventType `shouldBe` "export_generated"
                auditEvent.targetTable `shouldBe` "export_jobs"
                auditEvent.targetId `shouldBe` unpackId exportJob.id

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

                response <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("reportSlug", "staff_hours")
                        , ("weekOffset", "0")
                        ]

                response `responseStatusShouldBe` status302

                exportJob <- query @ExportJob |> orderByDesc #createdAt |> fetchOne
                exportJob.exportType `shouldBe` exportJobTypeToText StaffPayCsv
                exportJob.fileName `shouldBe` Just "staff_hours-2025-01-06.csv"
                exportJob.payConfigSnapshotVersion `shouldBe` Just "v1"
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    Text.isInfixOf "Name/Type,Mond Ord,Mond 7-12,Mond 12+"
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    Text.isInfixOf "Ava LVL 2,8.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,0.00,5.00,0.00,0.00,1.00,0.00"
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    (not . Text.isInfixOf "Trial")

        it "creates the filtered kitchen payroll export with a blank type column" $ withContext do
            withCleanDb do
                let approvedAt = UTCTime (fromGregorian 2025 1 12) (secondsToDiffTime 7200)
                venue <- createVenueWithConfig "Kitchen Venue"
                admin <- createUserRecord "kitchen-admin@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                dayNames <- seedWeekDayNames venue
                levelOne <- createPayLevelRecord venue "LVL 1"
                barShift <- createShiftTypeRecord venue levelOne "Bar"
                kitchenShift <- createShiftTypeRecord venue levelOne "Kitchen"
                staffUser <- createUserRecord "kitchen-staff@example.com" "staff" True
                staff <- createStaffRecord venue (Just staffUser) "Kai" "Cook"
                snapshot <- createPayrollSnapshot venue admin [levelOne] [barShift, kitchenShift] dayNames []

                _ <- createAndApproveEntry venue staff defaultWeekEpoch snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId barShift.id)
                    , set #startTime (TimeOfDay 9 0 0)
                    , set #endTime (TimeOfDay 12 0 0)
                    ]
                _ <- createAndApproveEntry venue staff (fromGregorian 2025 1 7) snapshot admin approvedAt
                    [ set #shiftTypeId (unpackId kitchenShift.id)
                    , set #startTime (TimeOfDay 10 0 0)
                    , set #endTime (TimeOfDay 14 0 0)
                    ]

                response <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("reportSlug", "kitchen")
                        , ("weekOffset", "0")
                        ]

                response `responseStatusShouldBe` status302

                exportJob <- query @ExportJob |> orderByDesc #createdAt |> fetchOne
                exportJob.fileName `shouldBe` Just "kitchen-2025-01-06.csv"
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    Text.isInfixOf "Kai,0.00,0.00,0.00,4.00,0.00,0.00"
                fromMaybe "" exportJob.fileContents `shouldSatisfy`
                    (not . Text.isInfixOf "3.00")

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

                response <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("reportSlug", "wage")
                        , ("weekOffset", "0")
                        ]

                response `responseStatusShouldBe` status302

                exportJob <- query @ExportJob |> orderByDesc #createdAt |> fetchOne
                exportJob.exportType `shouldBe` exportJobTypeToText HourlyBreakdownZip
                exportJob.fileName `shouldBe` Just "wage-2025-01-06.zip"
                exportJob.contentType `shouldBe` Just "application/zip"
                exportJob.fileEncoding `shouldBe` "base64"
                exportJob.payConfigSnapshotVersion `shouldBe` Just "v1"

                downloadResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams (DownloadExportJobAction exportJob.id)
                        [("token", cs (tshow exportJob.downloadToken))]

                downloadResponse `responseStatusShouldBe` status200
                lookup hContentType (responseHeaders downloadResponse) `shouldBe` Just "application/zip"
                lookup hContentDisposition (responseHeaders downloadResponse) `shouldBe` Just "attachment; filename=\"wage-2025-01-06.zip\""

                downloadBody <- responseBody downloadResponse
                let archive = Zip.toArchive downloadBody
                Zip.filesInArchive archive `shouldBe` ["Monday.csv", "Tuesday.csv", "Wednesday.csv", "Thursday.csv", "Friday.csv", "Saturday.csv", "Sunday.csv"]
                let mondayCsv =
                        archive
                            |> Zip.findEntryByPath "Monday.csv"
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
                snapshot <- createPayConfigSnapshotRecord venue admin 1 (Aeson.object [])
                _ <- createTimesheetEntryRecord venue staff (fromGregorian 2025 1 10)
                    >>= updateRecord
                        . set #payConfigSnapshotId (Just (unpackId snapshot.id))
                        . set #isApproved True
                        . set #approvedAt (Just (UTCTime (fromGregorian 2025 1 10) (secondsToDiffTime 0)))
                        . set #approvedByUserId (Just (unpackId admin.id))
                _ <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("rangeStart", "2025-01-06")
                        , ("rangeEnd", "2025-01-12")
                        ]
                exportJob <- query @ExportJob |> fetchOne

                response <- withUserAndCurrentVenue admin venue.id do
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
                _ <- createVenueMembershipRecord venueA admin "venue_admin"
                _ <- createVenueMembershipRecord venueB admin "venue_admin"
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

                response <- withUserAndCurrentVenue admin venueB.id do
                    callAction ExportJobsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Payroll Reports"
                response `responseBodyShouldContain` "Week of"
                response `responseBodyShouldContain` "data-disable-javascript-submission=\"true\""
                response `responseBodyShouldContain` tshow exportJobB.id
                response `responseBodyShouldNotContain` tshow exportJobA.id

        it "bootstraps legacy payroll report definitions for the current venue" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Export Venue"
                admin <- createUserRecord "exports-definitions@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                payLevel <- createPayLevelRecord venue "Level 2"
                _ <- createShiftTypeRecord venue payLevel "Bar"
                _ <- createShiftTypeRecord venue payLevel "Kitchen"

                response <- withUserAndCurrentVenue admin venue.id do
                    callAction ExportJobsAction

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Wage Report"
                response `responseBodyShouldContain` "hourly_breakdown_zip"
                response `responseBodyShouldContain` "Staff Hours Report"
                response `responseBodyShouldContain` "Kitchen Report"
                response `responseBodyShouldContain` "Shift-type filter: Kitchen"
                response `responseBodyShouldContain` "Generate CSV"
                response `responseBodyShouldContain` "Generate ZIP"
                response `responseBodyShouldContain` "Manage Report Definitions"

                storedDefinitions <- query @ReportDefinition |> orderByAsc #sortOrder |> fetch
                map (.slug) storedDefinitions `shouldBe` ["wage", "staff_hours", "kitchen"]

        it "lets managers generate payroll exports but not manage report definitions" $ withContext do
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

                pageResponse `responseStatusShouldBe` status200
                pageResponse `responseBodyShouldContain` "Payroll Reports"
                pageResponse `responseBodyShouldNotContain` "Manage Report Definitions"

                createExportResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateExportJobAction
                        [ ("reportSlug", "staff_hours")
                        , ("weekOffset", "0")
                        ]

                createExportResponse `responseStatusShouldBe` status302

                createDefinitionResponse <- withUserAndCurrentVenue manager venue.id do
                    callActionWithParams CreateReportDefinitionAction
                        [ ("slug", "manager-made")
                        , ("name", "Manager Made")
                        , ("engine", "staff_pay_csv")
                        ]

                createDefinitionResponse `responseStatusShouldBe` status403

        it "lets venue admins create and update report definitions and shift-type filters" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Definition Venue"
                admin <- createUserRecord "exports-admin-definitions@example.com" "staff" True
                _ <- createVenueMembershipRecord venue admin "venue_admin"
                payLevel <- createPayLevelRecord venue "Level 1"
                barShift <- createShiftTypeRecord venue payLevel "Bar"
                kitchenShift <- createShiftTypeRecord venue payLevel "Kitchen"

                createResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams CreateReportDefinitionAction
                        [ ("slug", "front-bar")
                        , ("name", "Front Bar")
                        , ("description", "Front bar only")
                        , ("engine", "staff_pay_csv")
                        , ("sortOrder", "25")
                        , ("isActive", "true")
                        , ("shiftTypeIds", cs (tshow barShift.id))
                        ]

                createResponse `responseStatusShouldBe` status302

                createdDefinition <- query @ReportDefinition
                    |> filterWhere (#venueId, unpackId venue.id)
                    |> filterWhere (#slug, "front-bar")
                    |> fetchOne
                createdDefinition.name `shouldBe` "Front Bar"
                createdDefinition.description `shouldBe` Just "Front bar only"
                createdDefinition.engine `shouldBe` "staff_pay_csv"
                createdDefinition.sortOrder `shouldBe` 25
                createdDefinition.isActive `shouldBe` True

                createdFilters <- query @ReportDefinitionShiftTypeFilter
                    |> filterWhere (#reportDefinitionId, unpackId createdDefinition.id)
                    |> fetch
                map (.shiftTypeId) createdFilters `shouldBe` [unpackId barShift.id]

                updateResponse <- withUserAndCurrentVenue admin venue.id do
                    callActionWithParams (UpdateReportDefinitionAction createdDefinition.id)
                        [ ("slug", "front-house")
                        , ("name", "Front House")
                        , ("description", "")
                        , ("engine", "hourly_breakdown_zip")
                        , ("sortOrder", "5")
                        , ("isActive", "false")
                        , ("shiftTypeIds", cs (tshow kitchenShift.id))
                        ]

                updateResponse `responseStatusShouldBe` status302

                updatedDefinition <- fetch createdDefinition.id
                updatedDefinition.slug `shouldBe` "front-house"
                updatedDefinition.name `shouldBe` "Front House"
                updatedDefinition.description `shouldBe` Nothing
                updatedDefinition.engine `shouldBe` "hourly_breakdown_zip"
                updatedDefinition.sortOrder `shouldBe` 5
                updatedDefinition.isActive `shouldBe` False

                updatedFilters <- query @ReportDefinitionShiftTypeFilter
                    |> filterWhere (#reportDefinitionId, unpackId createdDefinition.id)
                    |> fetch
                map (.shiftTypeId) updatedFilters `shouldBe` [unpackId kitchenShift.id]

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

                response <- withUserAndCurrentVenue admin venueA.id do
                    callActionWithParams (DownloadExportJobAction foreignJob.id)
                        [("token", cs (tshow foreignJob.downloadToken))]

                response `responseStatusShouldBe` status403
