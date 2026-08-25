module Test.XeroTimesheetReadinessSpec where

import Application.Fixture.PayrollFixtures (createAndApproveEntry)
import Application.Helper.TimesheetPayLedger (ApprovedPayLedgerError (..))
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroPayItems
import Application.Helper.XeroTimesheetReadiness hiding
                                                 (validateXeroTimesheetReadiness)
import qualified Application.Helper.XeroTimesheetReadiness as Readiness
import Application.Xero.Admin.ReadModel (xeroPeriodOverlapsDefaultWindow,
                                         xeroTimesheetReadinessView)
import Application.Xero.Timesheets.Buckets (XeroAvailableBuckets (..),
                                            XeroBucketError (..),
                                            XeroBucketOutcome (..),
                                            XeroBucketProblem (..),
                                            bucketErrorCode,
                                            bucketErrorSafeMessage,
                                            fetchPeriodXeroLocalEarningsBuckets)
import Application.Xero.Timesheets.Prepare.Helpers (SelectedPreparationPeriodError (..),
                                                    selectedPreparationPeriod)
import qualified Application.Xero.Timesheets.Preview as Preview
import qualified Control.Exception as Exception
import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (addDays, fromGregorian)
import Generated.Types hiding (xeroTimesheetId)
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

validateXeroTimesheetReadiness :: (?modelContext :: ModelContext) => XeroTimesheetReadinessRequest -> IO XeroTimesheetReadiness
validateXeroTimesheetReadiness request =
    Readiness.validateXeroTimesheetReadiness request >>= expectAppResult

expectAppResult :: Show error => Either error value -> IO value
expectAppResult = either (\err -> expectationFailure (cs (show err)) >> fail "expected successful application result") pure

expectBucketsAvailable :: Either error XeroBucketOutcome -> IO [XeroLocalEarningsBucket]
expectBucketsAvailable = \case
    Left _ -> expectationFailure "expected bucket operation success" >> fail "bucket operation failed"
    Right (XeroBucketsBlocked _) -> expectationFailure "expected available buckets" >> fail "buckets blocked"
    Right (XeroBucketsAvailable available) -> pure available.xeroAvailableBucketValues

tests :: Spec
tests = do
    describe "Xero preparation modal states" do
        it "maps persisted preparation statuses to typed modal states" do
            xeroPreparationStateFromStatus NeedsReconnect `shouldBe` XeroPreparationNeedsReconnect
            xeroPreparationStateFromStatus NeedsApproval `shouldBe` XeroPreparationNeedsDecision
            xeroPreparationStateFromStatus XeroTimesheetPreparationRunStatusEnumBlocked `shouldBe` XeroPreparationBlocked
            xeroPreparationStateFromStatus ReadyForPreview `shouldBe` XeroPreparationReadyForPreview
            xeroPreparationStateFromStatus XeroTimesheetPreparationRunStatusEnumPreviewed `shouldBe` XeroPreparationPreviewed
            xeroPreparationStateFromStatus XeroTimesheetPreparationRunStatusEnumSubmitted `shouldBe` XeroPreparationSubmitted
            xeroPreparationStateFromStatus XeroTimesheetPreparationRunStatusEnumFailed `shouldBe` XeroPreparationFailed
            xeroPreparationStateFromStatus Preparing `shouldBe` XeroPreparationPreparing

    describe "Xero pay-period display window" do
        it "includes periods overlapping today plus or minus seven days" do
            let today = fromGregorian 2026 8 9
            xeroPeriodOverlapsDefaultWindow today (addDays (-14) today) (addDays (-7) today) `shouldBe` True
            xeroPeriodOverlapsDefaultWindow today (addDays 7 today) (addDays 13 today) `shouldBe` True
            xeroPeriodOverlapsDefaultWindow today (addDays (-15) today) (addDays (-8) today) `shouldBe` False
            xeroPeriodOverlapsDefaultWindow today (addDays 8 today) (addDays 14 today) `shouldBe` False

    describe "Xero bucket error causes" do
        it "keeps every nested cause focused and safely renderable" do
            let causes =
                    [ XeroBucketPayLedgerError ApprovedPayLedgerCalculationNotSealed
                    , XeroBucketMissingSealedCalculation
                    , XeroBucketMissingStaff
                    , XeroBucketMissingOperationalWindowFacts
                    , XeroBucketKeyDerivationFailed "private derivation detail"
                    , XeroBucketMissingSealedEarningsMapping
                    , XeroBucketIncompleteSealedEarningsMapping
                    ]
            map bucketErrorCode causes `shouldBe`
                [ "approved_pay_ledger_invalid"
                , "approved_pay_ledger_missing"
                , "approved_entry_staff_missing"
                , "approved_operational_facts_missing"
                , "approved_bucket_key_invalid"
                , "approved_xero_mapping_missing"
                , "approved_xero_mapping_incomplete"
                ]
            map bucketErrorSafeMessage causes `shouldSatisfy` all (not . Text.isInfixOf "private derivation detail")

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

        it "normalizes Xero ISO date-time variants to calendar dates" do
            let variants :: [Text]
                variants =
                    [ "2026-08-10T00:00:00"
                    , "2026-08-10T00:00:00.000"
                    , "2026-08-10T00:00:00.123456Z"
                    , "2026-08-10T00:00:00+10:00"
                    , "2026-08-10T00:00:00+1000"
                    ]
            forM_ variants \dateValue -> do
                let payload = Aeson.object
                        [ "Timesheets" Aeson..=
                            [ Aeson.object
                                [ "TimesheetID" Aeson..= ("ts-datetime" :: Text)
                                , "EmployeeID" Aeson..= ("employee-datetime" :: Text)
                                , "StartDate" Aeson..= dateValue
                                , "EndDate" Aeson..= dateValue
                                , "Status" Aeson..= ("DRAFT" :: Text)
                                , "TimesheetLines" Aeson..= ([] :: [Aeson.Value])
                                ]
                            ]
                        ]
                    decoded = Aeson.fromJSON payload :: Aeson.Result XeroTimesheetsResponse
                fmap (map (\timesheet -> (timesheet.xeroTimesheetStartDate, timesheet.xeroTimesheetEndDate)) . unXeroTimesheetsResponse) decoded
                    `shouldBe` Aeson.Success [(fromGregorian 2026 8 10, fromGregorian 2026 8 10)]

        it "rejects malformed values instead of truncating a date prefix" do
            let payload = "{\"Timesheet\":{\"TimesheetID\":\"ts-invalid\",\"EmployeeID\":\"employee-invalid\",\"StartDate\":\"2026-08-10-not-a-date\",\"EndDate\":\"2026-08-10\",\"Status\":\"DRAFT\",\"TimesheetLines\":[]}}"
                decoded = Aeson.eitherDecode payload :: Either String XeroTimesheetObjectResponse
            case decoded of
                Left message -> cs message `shouldSatisfy` Text.isInfixOf "could not parse Xero date"
                Right _      -> expectationFailure "expected malformed Xero date to be rejected"

        it "preserves unknown provider-owned statuses for forward compatibility" do
            let timesheetPayload = "{\"Timesheets\":[{\"TimesheetID\":\"ts-future\",\"EmployeeID\":\"employee-future\",\"StartDate\":\"2026-04-27\",\"EndDate\":\"2026-05-03\",\"Status\":\"FUTURE_TIMESHEET_STATUS\",\"TimesheetLines\":[]}]}"
                payRunPayload = "{\"PayRuns\":[{\"PayRunID\":\"pr-future\",\"PayrollCalendarID\":\"calendar-future\",\"PayRunPeriodStartDate\":\"2026-04-27\",\"PayRunPeriodEndDate\":\"2026-05-03\",\"PayRunStatus\":\"FUTURE_PAY_RUN_STATUS\"}]}"
                decodedTimesheets = Aeson.eitherDecode timesheetPayload :: Either String XeroTimesheetsResponse
                decodedPayRuns = Aeson.eitherDecode payRunPayload :: Either String XeroPayRunsResponse
            fmap (map (.xeroTimesheetStatus) . unXeroTimesheetsResponse) decodedTimesheets
                `shouldBe` Right [Just "FUTURE_TIMESHEET_STATUS"]
            fmap (map (.xeroPayRunStatus) . unXeroPayRunsResponse) decodedPayRuns
                `shouldBe` Right [Just "FUTURE_PAY_RUN_STATUS"]

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

    aroundAll withDatabaseTestContext do
      describe "Xero draft-timesheet readiness" do
        it "rejects incomplete persisted preparation periods without a partial constructor" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Incomplete Xero period venue"
                owner <- createUserRecord "incomplete-xero-period@example.com" "staff" True
                let run = newRecord @XeroTimesheetPreparationRun
                        |> set #venueId (unpackId venue.id)
                        |> set #createdByUserId (unpackId owner.id)
                        |> set #selectedPeriodKey (Just "calendar:2026-04-27:2026-05-03")
                selectedPreparationPeriod run `shouldBe` Left PreparationPeriodIncomplete
                let invertedRun =
                        run
                            |> set #selectedPayrollCalendarId (Just "calendar")
                            |> set #selectedPeriodKey (Just "calendar:2026-05-03:2026-04-27")
                            |> set #payPeriodStart (Just (fromGregorian 2026 5 3))
                            |> set #payPeriodEnd (Just (fromGregorian 2026 4 27))
                selectedPreparationPeriod invertedRun `shouldBe` Left PreparationPeriodInvalid

        it "collects every affected entry when approved ledgers are unsealed" $ withContext do
            withCleanDb do
                let periodStart = fromGregorian 2026 4 27
                    periodEnd = fromGregorian 2026 5 3
                fixture <- createReadyMappedFixture "weekly" periodStart periodEnd
                secondEntry <- createApprovedTimesheetEntryRecord fixture.venue fixture.staff fixture.owner (addDays 1 periodStart)
                entries <- query @TimesheetEntry |> filterWhere (#venueId, unpackId fixture.venue.id) |> fetch
                calculations <- query @TimesheetPayCalculation
                    |> filterWhereIn (#id, mapMaybe (.activePayCalculationId) entries)
                    |> fetch
                Exception.bracket_
                    (sqlExecDiscardResult "ALTER TABLE timesheet_pay_calculations DISABLE TRIGGER enforce_timesheet_pay_calculations_immutable" ())
                    (sqlExecDiscardResult "ALTER TABLE timesheet_pay_calculations ENABLE TRIGGER enforce_timesheet_pay_calculations_immutable" ())
                    (forM_ calculations \calculation -> calculation |> set #sealedAt Nothing |> updateRecord >>= const (pure ()))

                outcome <- fetchPeriodXeroLocalEarningsBuckets fixture.venue.id periodStart periodEnd [] >>= expectAppResult

                case outcome of
                    XeroBucketsAvailable _ -> expectationFailure "unsealed ledgers must block bucket preparation"
                    XeroBucketsBlocked problems -> do
                        map (.xeroBucketProblemEntryId) problems `shouldMatchList` map (unpackId . (.id)) entries
                        map (.xeroBucketProblemCause) problems
                            `shouldMatchList` replicate 2 (XeroBucketPayLedgerError ApprovedPayLedgerCalculationNotSealed)
                        map (.xeroBucketProblemEntryId) problems `shouldSatisfy` elem (unpackId secondEntry.id)
                readiness <- validateXeroTimesheetReadiness fixture.request
                let issueEntries =
                        xeroTimesheetReadinessView readiness
                            |> (.timesheetReadinessBlockers)
                            |> filter ((== "wage_publication_failed") . (.timesheetIssueCode))
                            |> map (.timesheetIssueTimesheetEntryId)
                issueEntries `shouldMatchList` map (Just . unpackId . (.id)) entries

        it "accepts a verified mapping added after approval for late binding" $ withContext do
            withCleanDb do
                fixture <- createReadinessFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                requirements <- query @XeroPayItemRequirementRecord |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ requirements \requirement ->
                    newRecord @XeroEarningsRateMapping
                        |> set #venueId (unpackId fixture.venue.id)
                        |> set #xeroConnectionId (unpackId fixture.connection.id)
                        |> set #localBucketKey requirement.requirementKey
                        |> set #localBucketLabel requirement.displayName
                        |> set #xeroEarningsRateId (Just ("late-" <> requirement.requirementKey))
                        |> set #xeroEarningsRateName (Just requirement.displayName)
                        |> set #mappingStatus XeroEarningsRateMappingStatusEnumVerified
                        |> createRecord
                        >>= const (pure ())

                readiness <- validateXeroTimesheetReadiness fixture.request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "staff_mapping_not_verified"
                map (.xeroBlockerCode) readiness.xeroReadinessWarnings `shouldSatisfy` elem "staff_mapping_not_verified"
                readinessBlockerCodes readiness `shouldNotSatisfy` elem "wage_publication_failed"
                readinessBlockerCodes readiness `shouldNotSatisfy` elem "earnings_mapping_not_verified"
                readiness.xeroTimesheetReady `shouldBe` True

        it "uses a fresh successful snapshot even when a later maintenance attempt failed" $ withContext do
            withCleanDb do
                fixture <- createReadinessFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                now <- getCurrentTime
                _ <- fixture.connection |> set #lastSyncAt (Just now) |> updateRecord
                _ <-
                    newRecord @XeroSyncRun
                        |> set #venueId (unpackId fixture.venue.id)
                        |> set #xeroConnectionId (unpackId fixture.connection.id)
                        |> set #syncStatus XeroSyncStatusEnumFailed
                        |> set #syncKind PayrollReferenceData
                        |> set #startedAt (addUTCTime 1 now)
                        |> createRecord

                readiness <- validateXeroTimesheetReadiness fixture.request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "latest_reference_sync_not_successful"
                readinessBlockerCodes readiness `shouldNotSatisfy` elem "stale_reference_snapshot"

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

        it "uses the approval-pinned rate source for persisted-period pay bucket keys" $ withContext do
            withCleanDb do
                let periodStart = fromGregorian 2026 7 15
                    periodEnd = fromGregorian 2026 7 21
                fixture <- createReadyMappedFixture "weekly" periodStart periodEnd
                entries <- query @TimesheetEntry |> filterWhere (#venueId, unpackId fixture.venue.id) |> fetch
                sealedComponents <- query @TimesheetPayEarningsComponent
                    |> filterWhereIn (#timesheetPayCalculationId, mapMaybe (fmap unpackId . (.activePayCalculationId)) entries)
                    |> fetch
                sealedRateBoundary <- case nub (mapMaybe (.resolvedRateBoundaryDate) sealedComponents) of
                    [value] -> pure value
                    _ -> expectationFailure "expected one sealed rate boundary" >> error "unreachable"
                pinnedStaffVersions <- forM entries \entry ->
                    maybe (expectationFailure "expected approved entry staff pay version" >> error "unreachable") (fetch . (Id :: UUID -> Id StaffPayVersion)) entry.staffPayVersionId
                pinnedShiftVersions <- forM entries \entry ->
                    maybe (expectationFailure "expected approved entry shift pay version" >> error "unreachable") (fetch . (Id :: UUID -> Id ShiftTypePayVersion)) entry.shiftTypePayVersionId
                payLevelUuid <-
                    case nub (zipWith (\staffVersion shiftVersion -> shiftVersion.overrideAwardLevelId <|> staffVersion.defaultAwardLevelId) pinnedStaffVersions pinnedShiftVersions) of
                        [Just value] -> pure value
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
                map (.operativeFrom) selectedRates `shouldBe` [Just (fromGregorian 2025 7 1), Just (fromGregorian 2026 7 1)]
                zipWith (\staffVersion shiftVersion -> shiftVersion.overrideAwardLevelId <|> staffVersion.defaultAwardLevelId) pinnedStaffVersions pinnedShiftVersions
                    `shouldSatisfy` all (== Just (unpackId awardLevelId))

                buckets <- fetchPeriodXeroLocalEarningsBuckets fixture.venue.id periodStart periodEnd [] >>= expectBucketsAvailable

                map (.localBucketKey) buckets `shouldSatisfy` (not . null)
                map (.localBucketKey) buckets `shouldSatisfy` all (Text.isInfixOf (":effective:" <> tshow sealedRateBoundary <> ":"))

        it "keeps a sealed penalty bucket usable after its projection source refreshes" $ withContext do
            withCleanDb do
                let periodStart = fromGregorian 2026 5 2
                    periodEnd = fromGregorian 2026 5 8
                fixture <- createReadyMappedFixture "weekly" periodStart periodEnd
                penaltyRates <-
                    query @AwardLevelPenaltyRate
                        |> filterWhere (#employmentBasis, Permanent)
                        |> filterWhere (#penaltyKind, SaturdayPenalty)
                        |> fetch
                refreshedSource <-
                    newRecord @FwcMapdPenaltyRate
                        |> set #awardFixedId (9 :: Int)
                        |> set #classificationFixedId (Just 246)
                        |> set #classification ("Level 2" :: Text)
                        |> set #penaltyDescription (Just "Saturday penalty refresh")
                        |> createRecord
                forM_ penaltyRates \penaltyRate ->
                    penaltyRate
                        |> set #fwcMapdPenaltyRateId (unpackId refreshedSource.id)
                        |> updateRecord
                        >>= const (pure ())

                buckets <- fetchPeriodXeroLocalEarningsBuckets fixture.venue.id periodStart periodEnd [] >>= expectBucketsAvailable

                map (.localBucketKey) buckets `shouldSatisfy` any (Text.isInfixOf ":penalty:saturday_penalty:")

        it "keeps late-bindable components blocked when requirements are ignored" $ withContext do
            withCleanDb do
                fixture <- createReadinessFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                requirements <- query @XeroPayItemRequirementRecord |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ requirements \requirement ->
                    requirement |> set #requirementStatus Ignored |> updateRecord >>= const (pure ())

                readiness <- validateXeroTimesheetReadiness fixture.request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "wage_publication_failed"
                readinessBlockerCodes readiness `shouldSatisfy` elem "earnings_mapping_not_verified"

        it "ignores deleted approved history when active approved entries remain" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                deletedEntry <- query @TimesheetEntry |> filterWhere (#venueId, unpackId fixture.venue.id) |> fetchOne
                now <- getCurrentTime
                _ <- deletedEntry |> set #deletedAt (Just now) |> updateRecord
                activeEntry <- createApprovedTimesheetEntryRecord fixture.venue fixture.staff fixture.owner (fromGregorian 2026 4 28)

                readiness <- validateXeroTimesheetReadiness fixture.request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "entry_deleted"
                readiness.xeroReadinessEntryCount `shouldBe` 1
                readiness.xeroTimesheetReady `shouldBe` True
                previewInput <- Preview.fetchPreviewInput fixture.request fixture.connection
                map (.id) previewInput.previewTimesheetEntries `shouldBe` [activeEntry.id]

        it "keeps the general unapproved warning when deleted history and active entries coexist" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                deletedEntry <- query @TimesheetEntry |> filterWhere (#venueId, unpackId fixture.venue.id) |> fetchOne
                now <- getCurrentTime
                _ <- deletedEntry |> set #deletedAt (Just now) |> updateRecord
                _ <- createApprovedTimesheetEntryRecord fixture.venue fixture.staff fixture.owner (fromGregorian 2026 4 28)
                _ <- createTimesheetEntryRecord fixture.venue fixture.staff (fromGregorian 2026 4 29)

                readiness <- validateXeroTimesheetReadiness fixture.request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "entry_deleted"
                map (.xeroBlockerCode) readiness.xeroReadinessWarnings `shouldBe` ["entry_not_approved"]
                readiness.xeroTimesheetReady `shouldBe` True

        it "reports no entries when the selected period contains only deleted history" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                deletedEntry <- query @TimesheetEntry |> filterWhere (#venueId, unpackId fixture.venue.id) |> fetchOne
                now <- getCurrentTime
                _ <- deletedEntry |> set #deletedAt (Just now) |> updateRecord

                readiness <- validateXeroTimesheetReadiness fixture.request

                readinessBlockerCodes readiness `shouldBe` ["missing_approved_entries"]
                map (.xeroBlockerMessage) readiness.xeroReadinessBlockers
                    `shouldBe` ["There are no timesheet entries in the selected period."]
                readiness.xeroReadinessWarnings `shouldBe` []
                readiness.xeroTimesheetReady `shouldBe` False

        it "warns once when unapproved entries remain in the pay period" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                _ <- createTimesheetEntryRecord fixture.venue fixture.staff (fromGregorian 2026 4 28)
                _ <- createTimesheetEntryRecord fixture.venue fixture.staff (fromGregorian 2026 4 29)

                readiness <- validateXeroTimesheetReadiness fixture.request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "entry_not_approved"
                filter (== "entry_not_approved") (map (.xeroBlockerCode) readiness.xeroReadinessWarnings) `shouldBe` ["entry_not_approved"]
                readiness.xeroTimesheetReady `shouldBe` True

        it "preserves affected entry identity for every missing earnings mapping blocker" $ withContext do
            withCleanDb do
                let periodStart = fromGregorian 2026 4 27
                fixture <- createReadyMappedFixture "weekly" periodStart (fromGregorian 2026 5 3)
                secondEntry <- createApprovedTimesheetEntryRecord fixture.venue fixture.staff fixture.owner (addDays 1 periodStart)
                mappings <- query @XeroEarningsRateMapping |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ mappings \mapping -> mapping |> set #mappingStatus XeroEarningsRateMappingStatusEnumStale |> updateRecord >>= const (pure ())
                requirements <- query @XeroPayItemRequirementRecord |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ requirements \requirement -> requirement |> set #requirementStatus Ignored |> updateRecord >>= const (pure ())

                readiness <- validateXeroTimesheetReadiness fixture.request

                entries <- query @TimesheetEntry |> filterWhere (#venueId, unpackId fixture.venue.id) |> fetch
                let mappingBlockers = filter ((== "earnings_mapping_not_verified") . (.xeroBlockerCode)) readiness.xeroReadinessBlockers
                    affectedEntryIds = mapMaybe (.xeroBlockerTimesheetEntryId) mappingBlockers
                    expectedEntryIds = map (unpackId . (.id)) entries
                mappingBlockers `shouldSatisfy` (not . null)
                affectedEntryIds `shouldSatisfy` all (`elem` expectedEntryIds)
                expectedEntryIds `shouldSatisfy` all (`elem` affectedEntryIds)
                affectedEntryIds `shouldSatisfy` elem (unpackId secondEntry.id)

        it "accepts matched managed pay item requirements as earnings-rate mappings" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                mappings <- query @XeroEarningsRateMapping |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ mappings \mapping ->
                    mapping |> set #mappingStatus XeroEarningsRateMappingStatusEnumStale |> updateRecord >>= const (pure ())

                readiness <- validateXeroTimesheetReadiness fixture.request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "earnings_mapping_not_verified"
                readiness.xeroTimesheetReady `shouldBe` True

        it "accepts admin-imported Xero mappings without requiring managed pay item creation" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                requirements <- query @XeroPayItemRequirementRecord |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ requirements \requirement ->
                    requirement
                        |> set #requirementStatus XeroPayItemRequirementStatusEnumProposed
                        |> set #xeroEarningsRateId Nothing
                        |> updateRecord
                        >>= const (pure ())
                selections <- query @XeroPayItemAccountCodeSelection |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                forM_ selections \selection ->
                    selection |> set #selectionStatus XeroPayItemAccountCodeSelectionStatusEnumStale |> updateRecord >>= const (pure ())

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
                        |> set #mappingStatus XeroStaffMappingStatusEnumVerified
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
                importedUser <- createUserRecord "imported-ready@example.com" "staff" True
                _ <- createVenueMembershipRecord fixture.venue importedUser Worker
                importedStaff <- createStaffRecord fixture.venue (Just importedUser) "Imported" "Worker"
                    >>= updateRecord . set #payAssignmentMode XeroRate . set #importedXeroPayItemId (Just importedPayItem.id)
                _ <-
                    newRecord @XeroStaffMapping
                        |> set #venueId (unpackId fixture.venue.id)
                        |> set #staffId (unpackId importedStaff.id)
                        |> set #xeroConnectionId (unpackId fixture.connection.id)
                        |> set #xeroEmployeeId (Just "employee-imported")
                        |> set #xeroEmployeeName (Just "Imported Worker")
                        |> set #mappingStatus XeroStaffMappingStatusEnumVerified
                        |> createRecord
                _ <- createReadinessXeroEmployee fixture "employee-imported" (Just "calendar-ready")
                now <- getCurrentTime
                importedEntry <- createAndApproveEntry fixture.venue importedStaff (fromGregorian 2026 4 27) () fixture.owner now []
                importedEntry.staffPayVersionId `shouldSatisfy` isJust
                let request = fixture.request { readinessSkippedStaffIds = [unpackId fixture.staff.id] }

                readiness <- validateXeroTimesheetReadiness request

                readinessBlockerCodes readiness `shouldNotSatisfy` elem "earnings_mapping_not_verified"
                readinessBlockerCodes readiness `shouldNotSatisfy` elem "managed_pay_item_not_ready"
                readiness.xeroReadinessPayBucketCount `shouldBe` 1
                readiness.xeroTimesheetReady `shouldBe` True

                _ <- importedPayItem
                    |> set #providerAvailable False
                    |> set #providerUnavailableAt (Just now)
                    |> updateRecord
                unavailableReadiness <- validateXeroTimesheetReadiness request
                readinessBlockerCodes unavailableReadiness `shouldSatisfy` elem "wage_source_policy"
                map (.xeroBlockerMessage) unavailableReadiness.xeroReadinessBlockers
                    `shouldSatisfy` any (Text.isInfixOf "Approved entry is pinned")
                map (.xeroBlockerMessage) unavailableReadiness.xeroReadinessBlockers
                    `shouldSatisfy` any (Text.isInfixOf "correct and reapprove")
                unavailableReadiness.xeroTimesheetReady `shouldBe` False

        it "warns and excludes approved entries pinned to a previous Xero connection" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                previousConnection <-
                    newRecord @XeroConnection
                        |> set #venueId (unpackId fixture.venue.id)
                        |> set #tenantId ("previous-tenant" :: Text)
                        |> set #tenantName (Just "Previous Company")
                        |> set #connectionStatus ("disconnected" :: Text)
                        |> set #scopes requiredXeroScopesText
                        |> set #encryptedRefreshToken ("previous-encrypted-token" :: Text)
                        |> set #connectedByUserId (Just (unpackId fixture.owner.id))
                        |> createRecord
                previousPayItem <-
                    newRecord @XeroImportedPayItem
                        |> set #venueId (unpackId fixture.venue.id)
                        |> set #xeroConnectionId (unpackId previousConnection.id)
                        |> set #xeroEarningsRateId ("previous-earnings" :: Text)
                        |> set #name ("Previous connection ordinary hours" :: Text)
                        |> set #earningsType ("ordinarytimeearnings" :: Text)
                        |> set #rateType ("rateperunit" :: Text)
                        |> set #typeOfUnits ("hours" :: Text)
                        |> set #ratePerUnit 34.5
                        |> set #rawPayload Aeson.Null
                        |> set #importedByUserId (unpackId fixture.owner.id)
                        |> createRecord
                previousUser <- createUserRecord "previous-connection@example.com" "staff" True
                _ <- createVenueMembershipRecord fixture.venue previousUser Worker
                previousStaff <- createStaffRecord fixture.venue (Just previousUser) "Previous" "Worker"
                    >>= updateRecord . set #payAssignmentMode XeroRate . set #importedXeroPayItemId (Just previousPayItem.id)
                _ <-
                    newRecord @XeroStaffMapping
                        |> set #venueId (unpackId fixture.venue.id)
                        |> set #staffId (unpackId previousStaff.id)
                        |> set #xeroConnectionId (unpackId fixture.connection.id)
                        |> set #xeroEmployeeId (Just "employee-previous")
                        |> set #xeroEmployeeName (Just "Previous Worker")
                        |> set #mappingStatus XeroStaffMappingStatusEnumVerified
                        |> createRecord
                _ <- createReadinessXeroEmployee fixture "employee-previous" (Just "calendar-ready")
                now <- getCurrentTime
                _ <- createAndApproveEntry fixture.venue previousStaff (fromGregorian 2026 4 28) () fixture.owner now []

                readiness <- validateXeroTimesheetReadiness fixture.request

                readiness.xeroTimesheetReady `shouldBe` True
                readiness.xeroReadinessEntryCount `shouldBe` 1
                map (.xeroBlockerCode) readiness.xeroReadinessWarnings
                    `shouldSatisfy` elem "imported_pay_item_previous_connection"
                map (.xeroBlockerMessage) readiness.xeroReadinessWarnings
                    `shouldSatisfy` any (Text.isInfixOf "excluded from Xero submission")
                previewInput <- Preview.fetchPreviewInput fixture.request fixture.connection
                map (.staffId) previewInput.previewTimesheetEntries `shouldBe` [unpackId fixture.staff.id]

                let onlyPreviousConnectionRequest = fixture.request { readinessSkippedStaffIds = [unpackId fixture.staff.id] }
                onlyPreviousConnection <- validateXeroTimesheetReadiness onlyPreviousConnectionRequest
                onlyPreviousConnection.xeroTimesheetReady `shouldBe` False
                onlyPreviousConnection.xeroReadinessEntryCount `shouldBe` 0
                readinessBlockerCodes onlyPreviousConnection `shouldSatisfy` elem "missing_approved_entries"
                map (.xeroBlockerCode) onlyPreviousConnection.xeroReadinessWarnings
                    `shouldSatisfy` elem "imported_pay_item_previous_connection"

        it "allows a Xero period to include multiple relational pay versions" $ withContext do
            withCleanDb do
                fixture <- createReadyMappedFixture "weekly" (fromGregorian 2026 4 27) (fromGregorian 2026 5 3)
                secondEntry <- createApprovedTimesheetEntryRecord fixture.venue fixture.staff fixture.owner (fromGregorian 2026 4 28)
                secondStaffVersion <-
                    newRecord @StaffPayVersion
                        |> set #venueId (unpackId fixture.venue.id)
                        |> set #staffId (unpackId fixture.staff.id)
                        |> set #payAssignmentMode fixture.staff.payAssignmentMode
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
createReadinessFixture = createReadinessFixtureWithMappings False

createReadyMappedFixture :: (?modelContext :: ModelContext) => Text -> Day -> Day -> IO ReadinessFixture
createReadyMappedFixture = createReadinessFixtureWithMappings True

createReadinessFixtureWithMappings :: (?modelContext :: ModelContext) => Bool -> Text -> Day -> Day -> IO ReadinessFixture
createReadinessFixtureWithMappings readyMapped calendarType periodStart periodEnd = do
    venue <- createVenueWithConfig "Xero Readiness Venue"
    owner <- createUserRecord "owner@example.com" "admin" True
    _ <- createVenueMembershipRecord venue owner VenueOwner
    awardLevel <- createPayLevelRecordWithRates venue "Level 2" 25 2 3 1 1.25 1.5
    staff <- createStaffRecord venue Nothing "Ada" "Lovelace"
    staff <- staff |> set #employmentBasis Permanent |> set #payAssignmentMode AwardRate |> set #defaultAwardLevelId (Just awardLevel.id) |> updateRecord
    _ <- createShiftTypeRecord venue awardLevel "Readiness Shift"
    connection <- createReadinessXeroConnection venue owner
    _ <- createSucceededXeroSyncRun venue connection
    _ <- createReadinessPayrollCalendar venue connection calendarType periodStart
    buckets <- currentVenueBuckets venue periodStart
    requirements <- forM buckets \bucket ->
        newRecord @XeroPayItemRequirementRecord
            |> set #venueId (unpackId venue.id)
            |> set #xeroConnectionId (unpackId connection.id)
            |> set #requirementKey bucket.localBucketKey
            |> set #displayName bucket.localBucketLabel
            |> set #rateType ("RATEPERUNIT" :: Text)
            |> set #ratePerUnit (Just 25)
            |> set #sourceDescription ("test readiness requirement" :: Text)
            |> set #requirementStatus XeroPayItemRequirementStatusEnumProposed
            |> createRecord
    let fixture = ReadinessFixture
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
    when readyMapped do
        _ <- newRecord @XeroStaffMapping
            |> set #venueId (unpackId venue.id)
            |> set #staffId (unpackId staff.id)
            |> set #xeroConnectionId (unpackId connection.id)
            |> set #xeroEmployeeId (Just "employee-ready")
            |> set #xeroEmployeeName (Just "Ada Lovelace")
            |> set #mappingStatus XeroStaffMappingStatusEnumVerified
            |> createRecord
        _ <- createReadinessXeroEmployee fixture "employee-ready" (Just "calendar-ready")
        forM_ (zip buckets requirements) \(bucket, requirement) -> do
            _ <- newRecord @XeroEarningsRateMapping
                |> set #venueId (unpackId venue.id)
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #localBucketKey bucket.localBucketKey
                |> set #localBucketLabel bucket.localBucketLabel
                |> set #xeroEarningsRateId (Just ("earnings-" <> bucket.localBucketKey))
                |> set #xeroEarningsRateName (Just bucket.localBucketLabel)
                |> set #mappingStatus XeroEarningsRateMappingStatusEnumVerified
                |> createRecord
            _ <- requirement
                |> set #requirementStatus Matched
                |> set #xeroEarningsRateId (Just ("earnings-" <> bucket.localBucketKey))
                |> updateRecord
            pure ()
        _ <- newRecord @XeroPayItemAccountCodeSelection
            |> set #venueId (unpackId venue.id)
            |> set #xeroConnectionId (unpackId connection.id)
            |> set #accountCode (Just "477")
            |> set #selectionStatus XeroPayItemAccountCodeSelectionStatusEnumVerified
            |> createRecord
        pure ()
    _ <- createApprovedTimesheetEntryRecord venue staff owner periodStart
    pure fixture

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
createSucceededXeroSyncRun venue connection = do
    now <- getCurrentTime
    _ <- connection |> set #lastSyncAt (Just now) |> updateRecord
    newRecord @XeroSyncRun
        |> set #venueId (unpackId venue.id)
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #syncStatus Succeeded
        |> set #syncKind PayrollReferenceData
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
