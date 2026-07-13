module Test.XeroTimesheetReadinessSpec where

import Application.Helper.Pay (TimesheetPayResult (..),
                               fetchTimesheetPayResultsForEntries)
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroPayItems
import Application.Helper.XeroTimesheetReadiness
import Application.Xero.Timesheets.Buckets (fetchPeriodXeroLocalEarningsBuckets)
import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (fromGregorian)
import Generated.Types hiding (xeroTimesheetId)
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests = do
    describe "Xero preparation modal states" do
        it "maps persisted preparation statuses to typed modal states" do
            xeroPreparationStateFromStatus "needs_reconnect" `shouldBe` XeroPreparationNeedsReconnect
            xeroPreparationStateFromStatus "needs_approval" `shouldBe` XeroPreparationNeedsDecision
            xeroPreparationStateFromStatus "blocked" `shouldBe` XeroPreparationBlocked
            xeroPreparationStateFromStatus "ready_for_preview" `shouldBe` XeroPreparationReadyForPreview
            xeroPreparationStateFromStatus "previewed" `shouldBe` XeroPreparationPreviewed
            xeroPreparationStateFromStatus "submitted" `shouldBe` XeroPreparationSubmitted
            xeroPreparationStateFromStatus "failed" `shouldBe` XeroPreparationFailed
            xeroPreparationStateFromStatus "preparing" `shouldBe` XeroPreparationPreparing

    describe "Xero timesheet API parsing" do
        it "parses Timesheets envelopes with Microsoft JSON dates and line units" do
            let payload = "{\"Timesheets\":[{\"TimesheetID\":\"ts-1\",\"EmployeeID\":\"employee-1\",\"StartDate\":\"/Date(1777248000000+0000)/\",\"EndDate\":\"/Date(1777766400000+0000)/\",\"Status\":\"DRAFT\",\"Hours\":17.0,\"TimesheetLines\":[{\"EarningsRateID\":\"earnings-1\",\"NumberOfUnits\":[2.0,10.0,0.0,0.0,5.0,0.0,0.0]}]}]}"
            let decoded = Aeson.eitherDecode payload :: Either String XeroTimesheetsResponse
            fmap (map (.xeroTimesheetId) . unXeroTimesheetsResponse) decoded `shouldBe` Right [Just "ts-1"]
            case decoded of
                Left err -> expectationFailure err
                Right response ->
                    case unXeroTimesheetsResponse response of
                        timesheet : _ -> do
                            timesheet.xeroTimesheetStartDate `shouldBe` fromGregorian 2026 4 27
                            timesheet.xeroTimesheetEndDate `shouldBe` fromGregorian 2026 5 3
                            map (.xeroTimesheetLineUnits) timesheet.xeroTimesheetLines `shouldBe` [[2, 10, 0, 0, 5, 0, 0]]
                        [] -> expectationFailure "expected parsed timesheet"

        it "parses single Timesheet envelopes" do
            let payload = "{\"Timesheet\":{\"TimesheetID\":\"ts-2\",\"EmployeeID\":\"employee-2\",\"StartDate\":\"2026-04-27\",\"EndDate\":\"2026-05-03\",\"Status\":\"DRAFT\",\"TimesheetLines\":[]}}"
            let decoded = Aeson.eitherDecode payload :: Either String XeroTimesheetObjectResponse
            fmap (xeroTimesheetId . unXeroTimesheetObjectResponse) decoded `shouldBe` Right (Just "ts-2")

        it "parses PayRuns envelopes with period status" do
            let payload = "{\"PayRuns\":[{\"PayRunID\":\"pr-1\",\"PayrollCalendarID\":\"calendar-1\",\"PayRunPeriodStartDate\":\"/Date(1777852800000+0000)/\",\"PayRunPeriodEndDate\":\"/Date(1778371200000+0000)/\",\"PaymentDate\":\"2026-05-11\",\"PayRunStatus\":\"POSTED\"}]}"
            let decoded = Aeson.eitherDecode payload :: Either String XeroPayRunsResponse
            fmap (map (.xeroPayRunId) . unXeroPayRunsResponse) decoded `shouldBe` Right ["pr-1"]
            fmap (map (.xeroPayRunPeriodStart) . unXeroPayRunsResponse) decoded `shouldBe` Right [fromGregorian 2026 5 4]
            fmap (map (.xeroPayRunStatus) . unXeroPayRunsResponse) decoded `shouldBe` Right [Just "POSTED"]

        it "generates encoded PayRuns query URLs" do
            xeroPayRunsUrl
                XeroPayRunQuery
                    { xeroPayRunIfModifiedSince = Nothing
                    , xeroPayRunWhere = Just "PayrollCalendarID==Guid(\"calendar-1\")"
                    , xeroPayRunOrder = Just "PayRunPeriodStartDate DESC"
                    , xeroPayRunPage = Just 2
                    }
                `shouldBe` "https://api.xero.com/payroll.xro/1.0/PayRuns?where=PayrollCalendarID%3D%3DGuid%28%22calendar-1%22%29&order=PayRunPeriodStartDate%20DESC&page=2"

        it "generates encoded Timesheets query URLs" do
            xeroTimesheetsUrl
                XeroTimesheetQuery
                    { xeroTimesheetIfModifiedSince = Nothing
                    , xeroTimesheetWhere = Just "EmployeeID==Guid(\"employee-1\")"
                    , xeroTimesheetOrder = Just "StartDate DESC"
                    , xeroTimesheetPage = Just 2
                    }
                `shouldBe` "https://api.xero.com/payroll.xro/1.0/Timesheets?where=EmployeeID%3D%3DGuid%28%22employee-1%22%29&order=StartDate%20DESC&page=2"

    beforeAll testContext do
      describe "Xero draft-timesheet readiness" do
        it "warns on missing staff mapping and blocks proposed managed pay item readiness without duplicate bucket noise" $ withContext do
            withCleanDb do
                fixture <- createReadinessFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)

                readiness <- validateXeroTimesheetReadiness fixture.request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "staff_mapping_not_verified"
                map (.xeroBlockerCode) readiness.xeroReadinessWarnings `shouldSatisfy` elem "staff_mapping_not_verified"
                readinessBlockerCodes readiness `shouldNotSatisfy` elem "earnings_mapping_not_verified"
                readinessBlockerCodes readiness `shouldSatisfy` elem "managed_pay_item_not_ready"

        it "uses venue-effective dates in local award pay item bucket keys" $ withContext do
            withCleanDb do
                fixture <- createReadinessFixture "weekly" (fromGregorian 2026 7 6) (fromGregorian 2026 7 12)
                awardLevel <- query @AwardLevel |> filterWhere (#classification, "Level 2" :: Text) |> fetchOne
                oldBaseRate <- query @AwardLevelBaseRate
                    |> filterWhere (#awardLevelId, unpackId awardLevel.id)
                    |> filterWhere (#employmentBasis, Permanent)
                    |> fetchOne
                _ <- oldBaseRate
                    |> set #operativeFrom (Just (fromGregorian 2025 7 1))
                    |> set #operativeTo (Just (fromGregorian 2026 6 30))
                    |> updateRecord
                newerPayRate <-
                    newRecord @FwcMapdPayRate
                        |> set #awardFixedId awardLevel.awardFixedId
                        |> set #classificationFixedId (Just awardLevel.classificationFixedId)
                        |> set #classification awardLevel.classification
                        |> set #employeeRateTypeCode (Just "AD")
                        |> set #calculatedRate (Just 30)
                        |> set #calculatedRateType (Just "Hourly")
                        |> createRecord
                _ <-
                    newRecord @AwardLevelBaseRate
                        |> set #awardLevelId (unpackId awardLevel.id)
                        |> set #employmentBasis Permanent
                        |> set #fwcMapdPayRateId (unpackId newerPayRate.id)
                        |> set #hourlyRate 30
                        |> set #rateLabel ("Hourly" :: Text)
                        |> set #operativeFrom (Just (fromGregorian 2026 7 1))
                        |> createRecord

                beforeRolloverBuckets <- currentVenueBuckets fixture.venue (fromGregorian 2026 7 3)
                afterRolloverBuckets <- currentVenueBuckets fixture.venue (fromGregorian 2026 7 6)

                map (.localBucketKey) beforeRolloverBuckets `shouldSatisfy` any (Text.isInfixOf ":effective:2025-07-07:")
                map (.localBucketKey) beforeRolloverBuckets `shouldNotSatisfy` any (Text.isInfixOf ":effective:2026-07-06:")
                map (.localBucketKey) afterRolloverBuckets `shouldSatisfy` any (Text.isInfixOf ":effective:2026-07-06:")

        it "uses the latest venue-effective rate for persisted-period pay bucket keys" $ withContext do
            withCleanDb do
                let periodStart = fromGregorian 2026 7 15
                    periodEnd = fromGregorian 2026 7 21
                fixture <- createReadinessFixture "weekly" periodStart periodEnd
                entries <- query @TimesheetEntry |> filterWhere (#venueId, unpackId fixture.venue.id) |> fetch
                initialPayResults <- fetchTimesheetPayResultsForEntries entries
                payLevelUuid <-
                    case nub (mapMaybe (.payLevelId) (Map.elems initialPayResults)) of
                        [value] -> pure value
                        _ -> expectationFailure "expected one fixture pay level" >> error "unreachable"
                let awardLevelId = Id payLevelUuid :: Id AwardLevel
                oldBaseRates <-
                    query @AwardLevelBaseRate
                        |> filterWhere (#awardLevelId, unpackId awardLevelId)
                        |> filterWhere (#employmentBasis, Permanent)
                        |> fetch
                forM_ oldBaseRates \oldBaseRate ->
                    oldBaseRate
                        |> set #operativeFrom (Just (fromGregorian 2025 7 1))
                        |> set #operativeTo Nothing
                        |> updateRecord
                        >>= const (pure ())
                newerPayRate <-
                    newRecord @FwcMapdPayRate
                        |> set #awardFixedId (1 :: Int)
                        |> set #classificationFixedId (Just 1)
                        |> set #classification ("Level 2" :: Text)
                        |> set #employeeRateTypeCode (Just "AD")
                        |> set #calculatedRate (Just 40)
                        |> set #calculatedRateType (Just "Hourly")
                        |> createRecord
                _ <-
                    newRecord @AwardLevelBaseRate
                        |> set #awardLevelId (unpackId awardLevelId)
                        |> set #employmentBasis Permanent
                        |> set #fwcMapdPayRateId (unpackId newerPayRate.id)
                        |> set #hourlyRate 40
                        |> set #rateLabel ("Hourly" :: Text)
                        |> set #operativeFrom (Just (fromGregorian 2026 7 1))
                        |> createRecord

                selectedRates <-
                    query @AwardLevelBaseRate
                        |> filterWhere (#awardLevelId, unpackId awardLevelId)
                        |> filterWhere (#employmentBasis, Permanent)
                        |> orderBy #operativeFrom
                        |> fetch
                payResults <- fetchTimesheetPayResultsForEntries entries
                map (.operativeFrom) selectedRates `shouldBe` [Just (fromGregorian 2025 7 1), Just (fromGregorian 2026 7 1)]
                map (.payLevelId) (Map.elems payResults) `shouldSatisfy` all (== Just (unpackId awardLevelId))

                buckets <- fetchPeriodXeroLocalEarningsBuckets fixture.venue.id periodStart periodEnd []

                map (.localBucketKey) buckets `shouldSatisfy` (not . null)
                map (.localBucketKey) buckets `shouldSatisfy` all (Text.isInfixOf ":effective:2026-07-06:")

        it "blocks missing earnings mapping when no managed requirement covers the bucket" $ withContext do
            withCleanDb do
                fixture <- createReadinessFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                requirements <- query @XeroPayItemRequirementRecord |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ requirements \requirement ->
                    requirement |> set #requirementStatus ("ignored" :: Text) |> updateRecord >>= const (pure ())

                readiness <- validateXeroTimesheetReadiness fixture.request

                readinessBlockerCodes readiness `shouldSatisfy` elem "earnings_mapping_not_verified"
                readinessBlockerCodes readiness `shouldNotSatisfy` elem "managed_pay_item_not_ready"

        it "warns once when unapproved entries remain in the pay period" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                _ <- createTimesheetEntryRecord fixture.venue fixture.staff (fromGregorian 2026 4 28)
                _ <- createTimesheetEntryRecord fixture.venue fixture.staff (fromGregorian 2026 4 29)

                readiness <- validateXeroTimesheetReadiness fixture.request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "entry_not_approved"
                filter (== "entry_not_approved") (map (.xeroBlockerCode) readiness.xeroReadinessWarnings) `shouldBe` ["entry_not_approved"]
                readiness.xeroTimesheetReady `shouldBe` True

        it "accepts matched managed pay item requirements as earnings-rate mappings" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                mappings <- query @XeroEarningsRateMapping |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ mappings \mapping ->
                    mapping |> set #mappingStatus ("stale" :: Text) |> updateRecord >>= const (pure ())

                readiness <- validateXeroTimesheetReadiness fixture.request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "earnings_mapping_not_verified"
                readiness.xeroTimesheetReady `shouldBe` True

        it "accepts admin-imported Xero mappings without requiring managed pay item creation" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                requirements <- query @XeroPayItemRequirementRecord |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ requirements \requirement ->
                    requirement
                        |> set #requirementStatus ("proposed" :: Text)
                        |> set #xeroEarningsRateId Nothing
                        |> updateRecord
                        >>= const (pure ())
                selections <- query @XeroPayItemAccountCodeSelection |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ selections \selection ->
                    selection |> set #selectionStatus ("stale" :: Text) |> updateRecord >>= const (pure ())

                readiness <- validateXeroTimesheetReadiness fixture.request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "earnings_mapping_not_verified"
                readinessBlockerCodes readiness `shouldNotSatisfy` elem "managed_pay_item_not_ready"
                readinessBlockerCodes readiness `shouldNotSatisfy` elem "missing_pay_item_account_code"
                readiness.xeroTimesheetReady `shouldBe` True

        it "accepts locked imported Xero pay items without requiring managed award buckets" $ withContext do
            withCleanDb do
                fixture <- createReadinessFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                _ <-
                    newRecord @XeroStaffMapping
                        |> set #venueId (unpackId fixture.venue.id)
                        |> set #staffId (unpackId fixture.staff.id)
                        |> set #xeroConnectionId (unpackId fixture.connection.id)
                        |> set #xeroEmployeeId (Just "employee-ready")
                        |> set #xeroEmployeeName (Just "Ada Lovelace")
                        |> set #mappingStatus ("verified" :: Text)
                        |> createRecord
                _ <- createReadinessXeroEmployee fixture "employee-ready" (Just "calendar-ready")
                importedPayItem <-
                    newRecord @XeroImportedPayItem
                        |> set #venueId (unpackId fixture.venue.id)
                        |> set #xeroConnectionId (unpackId fixture.connection.id)
                        |> set #xeroEarningsRateId ("earnings-imported" :: Text)
                        |> set #name ("Imported owner pay" :: Text)
                        |> set #earningsType ("ordinarytimeearnings" :: Text)
                        |> set #rateType ("rateperunit" :: Text)
                        |> set #typeOfUnits ("hours" :: Text)
                        |> set #ratePerUnit 25
                        |> set #rawPayload Aeson.Null
                        |> set #importedByUserId (unpackId fixture.owner.id)
                        |> createRecord
                entry <- query @TimesheetEntry |> filterWhere (#venueId, unpackId fixture.venue.id) |> fetchOne
                case entry.staffPayVersionId of
                    Nothing -> expectationFailure "expected approved entry to lock a staff pay version"
                    Just staffPayVersionId -> do
                        staffPayVersion <- fetch (Id staffPayVersionId :: Id StaffPayVersion)
                        staffPayVersion |> set #importedXeroPayItemId (Just importedPayItem.id) |> updateRecord >>= const (pure ())

                readiness <- validateXeroTimesheetReadiness fixture.request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "earnings_mapping_not_verified"
                readinessBlockerCodes readiness `shouldNotSatisfy` elem "managed_pay_item_not_ready"
                readiness.xeroReadinessPayBucketCount `shouldBe` 0
                readiness.xeroTimesheetReady `shouldBe` True

        it "allows a Xero period to include multiple relational pay versions" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                secondEntry <- createApprovedTimesheetEntryRecord fixture.venue fixture.staff fixture.owner (fromGregorian 2026 4 28)
                secondStaffVersion <-
                    newRecord @StaffPayVersion
                        |> set #venueId (unpackId fixture.venue.id)
                        |> set #staffId (unpackId fixture.staff.id)
                        |> set #defaultAwardLevelId (fmap unpackId fixture.staff.defaultAwardLevelId)
                        |> set #employmentBasis fixture.staff.employmentBasis
                        |> set #effectiveFrom (fromGregorian 2026 4 28)
                        |> set #effectiveTo (Just (fromGregorian 2026 4 28))
                        |> set #createdByUserId (unpackId fixture.owner.id)
                        |> createRecord
                secondEntry
                    |> set #staffPayVersionId (Just (unpackId secondStaffVersion.id))
                    |> updateRecord

                readiness <- validateXeroTimesheetReadiness fixture.request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "mixed_pay_config_versions"
                xeroTimesheetReady readiness `shouldBe` True

        it "warns and allows updating an existing Xero draft timesheet for the same employee and period" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                let request =
                        fixture.request
                            { readinessRemoteTimesheets =
                                [ XeroTimesheetRef
                                    { xeroTimesheetId = Just "ts-existing"
                                    , xeroTimesheetEmployeeId = "employee-ready"
                                    , xeroTimesheetStartDate = fromGregorian 2026 4 27
                                    , xeroTimesheetEndDate = fromGregorian 2026 5 3
                                    , xeroTimesheetStatus = Just "DRAFT"
                                    , xeroTimesheetHours = Nothing
                                    , xeroTimesheetLines = []
                                    , xeroTimesheetRaw = Aeson.Null
                                    }
                                ]
                            }

                readiness <- validateXeroTimesheetReadiness request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "existing_xero_timesheet"
                map (.xeroBlockerCode) readiness.xeroReadinessWarnings `shouldSatisfy` elem "existing_xero_draft_timesheet"
                readiness.xeroTimesheetReady `shouldBe` True

        it "blocks an existing non-draft Xero timesheet for the same employee and period" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                let request =
                        fixture.request
                            { readinessRemoteTimesheets =
                                [ XeroTimesheetRef
                                    { xeroTimesheetId = Just "ts-existing"
                                    , xeroTimesheetEmployeeId = "employee-ready"
                                    , xeroTimesheetStartDate = fromGregorian 2026 4 27
                                    , xeroTimesheetEndDate = fromGregorian 2026 5 3
                                    , xeroTimesheetStatus = Just "APPROVED"
                                    , xeroTimesheetHours = Nothing
                                    , xeroTimesheetLines = []
                                    , xeroTimesheetRaw = Aeson.Null
                                    }
                                ]
                            }

                readiness <- validateXeroTimesheetReadiness request

                readinessBlockerCodes readiness `shouldSatisfy` elem "existing_xero_timesheet"
                map (.xeroBlockerCode) readiness.xeroReadinessWarnings `shouldNotSatisfy` elem "existing_xero_draft_timesheet"

        it "does not block unrelated employee timesheets in the same period" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                let request =
                        fixture.request
                            { readinessRemoteTimesheets =
                                [ XeroTimesheetRef
                                    { xeroTimesheetId = Just "ts-other-employee"
                                    , xeroTimesheetEmployeeId = "employee-someone-else"
                                    , xeroTimesheetStartDate = fromGregorian 2026 4 27
                                    , xeroTimesheetEndDate = fromGregorian 2026 5 3
                                    , xeroTimesheetStatus = Just "DRAFT"
                                    , xeroTimesheetHours = Nothing
                                    , xeroTimesheetLines = []
                                    , xeroTimesheetRaw = Aeson.Null
                                    }
                                ]
                            }

                readiness <- validateXeroTimesheetReadiness request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "existing_xero_timesheet"
                readiness.xeroTimesheetReady `shouldBe` True

        it "excludes matched Xero employees without a payroll calendar from the selected period" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                employees <- query @XeroEmployee |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ employees \employee ->
                    employee
                        |> set #rawPayload (Aeson.object ["EmployeeID" Aeson..= employee.xeroEmployeeId])
                        |> updateRecord
                        >>= const (pure ())

                readiness <- validateXeroTimesheetReadiness fixture.request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "xero_employee_payroll_calendar_missing"
                readinessBlockerCodes readiness `shouldSatisfy` elem "missing_approved_entries"
                readiness.xeroReadinessStaffCount `shouldBe` 0
                readiness.xeroReadinessEntryCount `shouldBe` 0

        it "ignores entries for matched Xero employees assigned to a different payroll calendar" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                employees <- query @XeroEmployee |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ employees \employee ->
                    employee
                        |> set #rawPayload (Aeson.object ["EmployeeID" Aeson..= employee.xeroEmployeeId, "PayrollCalendarID" Aeson..= ("calendar-other" :: Text)])
                        |> updateRecord
                        >>= const (pure ())

                readiness <- validateXeroTimesheetReadiness fixture.request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "xero_employee_payroll_calendar_mismatch"
                readiness.xeroTimesheetReady `shouldBe` False
                readinessBlockerCodes readiness `shouldSatisfy` elem "missing_approved_entries"

        it "requires the preparation request to identify its selected payroll calendar" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                let request =
                        fixture.request
                            { readinessPayrollCalendarId = Nothing
                            , readinessPayrollCalendarName = Nothing
                            , readinessSelectedPeriodKey = Nothing
                            }

                readiness <- validateXeroTimesheetReadiness request

                readinessBlockerCodes readiness `shouldSatisfy` elem "missing_payroll_calendar_selection"
                readiness.xeroTimesheetReady `shouldBe` False

        it "keeps a mapped employee on the selected payroll calendar ready" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)

                readiness <- validateXeroTimesheetReadiness fixture.request

                readiness.xeroTimesheetReady `shouldBe` True

        it "permits fully mapped weekly and fortnightly periods" $ withContext do
            withCleanDb do
                weekly <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                weeklyReadiness <- validateXeroTimesheetReadiness weekly.request
                weeklyReadiness.xeroTimesheetReady `shouldBe` True

            withCleanDb do
                fortnightly <- createReadyMappedFixture "fortnightly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 10)
                fortnightlyReadiness <- validateXeroTimesheetReadiness fortnightly.request
                fortnightlyReadiness.xeroTimesheetReady `shouldBe` True

        it "blocks tampered selected period keys" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                let request = fixture.request { readinessSelectedPeriodKey = Just "calendar-ready:2026-05-04:2026-05-10" }

                readiness <- validateXeroTimesheetReadiness request

                readinessBlockerCodes readiness `shouldSatisfy` elem "selected_period_key_mismatch"
                readiness.xeroTimesheetReady `shouldBe` False

data ReadinessFixture = ReadinessFixture
    { venue      :: Venue
    , owner      :: User
    , staff      :: Staff
    , connection :: XeroConnection
    , request    :: XeroTimesheetReadinessRequest
    }

createReadinessFixture :: (?modelContext :: ModelContext) => Text -> Day -> Day -> IO ReadinessFixture
createReadinessFixture calendarType periodStart periodEnd = do
    venue <- createVenueWithConfig "Xero Readiness Venue"
    owner <- createUserRecord "owner@example.com" "admin" True
    _ <- createVenueMembershipRecord venue owner "venue_owner"
    awardLevel <- createPayLevelRecordWithRates venue "Level 2" 25 2 3 1 1.25 1.5
    staff <- createStaffRecord venue Nothing "Ada" "Lovelace"
    staff <- staff |> set #employmentBasis Permanent |> set #defaultAwardLevelId (Just awardLevel.id) |> updateRecord
    _ <- createApprovedTimesheetEntryRecord venue staff owner periodStart
    connection <- createReadinessXeroConnection venue owner
    _ <- createSucceededXeroSyncRun venue connection
    _ <- createReadinessPayrollCalendar venue connection calendarType periodStart
    buckets <- currentVenueBuckets venue periodStart
    forM_ buckets \bucket -> do
        _ <-
            newRecord @XeroPayItemRequirementRecord
                |> set #venueId (unpackId venue.id)
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #requirementKey bucket.localBucketKey
                |> set #displayName bucket.localBucketLabel
                |> set #rateType ("RATEPERUNIT" :: Text)
                |> set #ratePerUnit (Just 25)
                |> set #sourceDescription ("test readiness requirement" :: Text)
                |> set #requirementStatus ("proposed" :: Text)
                |> createRecord
        pure ()
    pure ReadinessFixture
        { venue
        , owner
        , staff
        , connection
        , request =
            XeroTimesheetReadinessRequest
                { readinessVenueId = venue.id
                , readinessPayrollCalendarId = Just "calendar-ready"
                , readinessPayrollCalendarName = Just "Ready Calendar"
                , readinessSelectedPeriodKey = Just ("calendar-ready:" <> tshow periodStart <> ":" <> tshow periodEnd)
                , readinessPeriodStart = periodStart
                , readinessPeriodEnd = periodEnd
                , readinessPaymentDate = Nothing
                , readinessXeroPayRunId = Nothing
                , readinessXeroPayRunStatus = Nothing
                , readinessRemoteTimesheets = []
                , readinessSkippedStaffIds = []
                }
        }

createReadyMappedFixture :: (?modelContext :: ModelContext) => Text -> Day -> Day -> IO ReadinessFixture
createReadyMappedFixture calendarType periodStart periodEnd = do
    fixture <- createReadinessFixture calendarType periodStart periodEnd
    _ <-
        newRecord @XeroStaffMapping
            |> set #venueId (unpackId fixture.venue.id)
            |> set #staffId (unpackId fixture.staff.id)
            |> set #xeroConnectionId (unpackId fixture.connection.id)
            |> set #xeroEmployeeId (Just "employee-ready")
            |> set #xeroEmployeeName (Just "Ada Lovelace")
            |> set #mappingStatus ("verified" :: Text)
            |> createRecord
    _ <- createReadinessXeroEmployee fixture "employee-ready" (Just "calendar-ready")
    buckets <- currentFixtureBuckets fixture periodStart
    existingRequirements <-
        query @XeroPayItemRequirementRecord
            |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id)
            |> fetch
    forM_ buckets \bucket -> do
        _ <-
            newRecord @XeroEarningsRateMapping
                |> set #venueId (unpackId fixture.venue.id)
                |> set #xeroConnectionId (unpackId fixture.connection.id)
                |> set #localBucketKey bucket.localBucketKey
                |> set #localBucketLabel bucket.localBucketLabel
                |> set #xeroEarningsRateId (Just ("earnings-" <> bucket.localBucketKey))
                |> set #xeroEarningsRateName (Just bucket.localBucketLabel)
                |> set #mappingStatus ("verified" :: Text)
                |> createRecord
        case find (\record -> record.requirementKey == bucket.localBucketKey) existingRequirements of
            Just requirement ->
                requirement
                    |> set #requirementStatus ("matched" :: Text)
                    |> set #xeroEarningsRateId (Just ("earnings-" <> bucket.localBucketKey))
                    |> updateRecord
                    >>= const (pure ())
            Nothing ->
                newRecord @XeroPayItemRequirementRecord
                    |> set #venueId (unpackId fixture.venue.id)
                    |> set #xeroConnectionId (unpackId fixture.connection.id)
                    |> set #requirementKey bucket.localBucketKey
                    |> set #displayName bucket.localBucketLabel
                    |> set #rateType ("RATEPERUNIT" :: Text)
                    |> set #ratePerUnit (Just 25)
                    |> set #sourceDescription ("test readiness requirement" :: Text)
                    |> set #requirementStatus ("matched" :: Text)
                    |> set #xeroEarningsRateId (Just ("earnings-" <> bucket.localBucketKey))
                    |> createRecord
                    >>= const (pure ())
        pure ()
    _ <-
        newRecord @XeroPayItemAccountCodeSelection
            |> set #venueId (unpackId fixture.venue.id)
            |> set #xeroConnectionId (unpackId fixture.connection.id)
            |> set #accountCode (Just "477")
            |> set #selectionStatus ("verified" :: Text)
            |> createRecord
    pure fixture

currentFixtureBuckets :: (?modelContext :: ModelContext) => ReadinessFixture -> Day -> IO [XeroLocalEarningsBucket]
currentFixtureBuckets fixture = currentVenueBuckets fixture.venue

currentVenueBuckets :: (?modelContext :: ModelContext) => Venue -> Day -> IO [XeroLocalEarningsBucket]
currentVenueBuckets venue effectiveDay = do
    staffMembers <-
        query @Staff
            |> filterWhere (#venueId, unpackId venue.id)
            |> fetch
    shiftTypes <-
        query @ShiftType
            |> filterWhere (#venueId, unpackId venue.id)
            |> fetch
    awardLevels <- query @AwardLevel |> fetch
    baseRates <- query @AwardLevelBaseRate |> fetch
    penaltyRates <- query @AwardLevelPenaltyRate |> fetch
    timeAllowances <- query @AwardTimePenaltyAllowance |> fetch
    pure
        ( deriveXeroLocalEarningsBuckets
            1
            effectiveDay
            (deriveXeroUsedAwardPayScopes staffMembers shiftTypes)
            awardLevels
            baseRates
            penaltyRates
            timeAllowances
        )

createReadinessXeroConnection :: (?modelContext :: ModelContext) => Venue -> User -> IO XeroConnection
createReadinessXeroConnection venue owner =
    newRecord @XeroConnection
        |> set #venueId (unpackId venue.id)
        |> set #tenantId ("tenant-ready" :: Text)
        |> set #tenantName (Just "Demo Company")
        |> set #connectionStatus ("active" :: Text)
        |> set #scopes requiredXeroScopesText
        |> set #encryptedRefreshToken ("encrypted-refresh-token" :: Text)
        |> set #connectedByUserId (Just (unpackId owner.id))
        |> createRecord

createSucceededXeroSyncRun :: (?modelContext :: ModelContext) => Venue -> XeroConnection -> IO XeroSyncRun
createSucceededXeroSyncRun venue connection =
    newRecord @XeroSyncRun
        |> set #venueId (unpackId venue.id)
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #syncStatus ("succeeded" :: Text)
        |> set #syncKind ("payroll_reference_data" :: Text)
        |> createRecord

createReadinessPayrollCalendar :: (?modelContext :: ModelContext) => Venue -> XeroConnection -> Text -> Day -> IO XeroPayrollCalendar
createReadinessPayrollCalendar venue connection calendarType periodStart = do
    calendar <-
        newRecord @XeroPayrollCalendar
            |> set #venueId (unpackId venue.id)
            |> set #xeroConnectionId (unpackId connection.id)
            |> set #xeroPayrollCalendarId ("calendar-ready" :: Text)
            |> set #name ("Ready Calendar" :: Text)
            |> set #calendarType (Just calendarType)
            |> set #startDate (Just periodStart)
            |> set #rawPayload (Aeson.object ["PayrollCalendarID" Aeson..= ("calendar-ready" :: Text)])
            |> createRecord
    pure calendar

createReadinessXeroEmployee :: (?modelContext :: ModelContext) => ReadinessFixture -> Text -> Maybe Text -> IO XeroEmployee
createReadinessXeroEmployee fixture employeeId maybeCalendarId = do
    now <- getCurrentTime
    newRecord @XeroEmployee
        |> set #venueId (unpackId fixture.venue.id)
        |> set #xeroConnectionId (unpackId fixture.connection.id)
        |> set #xeroEmployeeId employeeId
        |> set #displayName ("Ada Lovelace" :: Text)
        |> set #email (Just "ada@example.com")
        |> set #status (Just "ACTIVE")
        |> set #rawPayload (Aeson.object ["EmployeeID" Aeson..= employeeId, "PayrollCalendarID" Aeson..= maybeCalendarId])
        |> set #syncedAt now
        |> createRecord
