module Test.XeroTimesheetPreviewSpec where

import Application.Fixture.PayrollFixtures (TimesheetFixtureValues,
                                            createAndApproveEntry)
import Application.Helper.Pay
import Application.Helper.TimesheetPayLedger (loadApprovedTimesheetPayCalculation)
import Application.Helper.WeekBoundaries (defaultWeekOffsetEpochForStartDay)
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroPayItems
import Application.Helper.XeroTimesheetReadiness
import Application.WageEngine (EarningsComponent (..), WageCalculation (..))
import Application.Xero.Timesheets.Preview
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, diffDays, fromGregorian)
import Data.Time.Clock (addUTCTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests =
    aroundAll withDatabaseTestContext do
        describe "Xero timesheet preview payloads" do
            it "builds weekly daily units in period order and zero-fills missing days" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    previewRun <- buildFixturePreview fixture

                    let line = onlyPreviewLine previewRun
                    line.previewLineNumberOfUnits `shouldBe` [4, 0, 0, 0, 0, 0, 0]

            it "allocates every final-day overnight component to its Operational-day position" $ withContext do
                withCleanDb do
                    fixture <-
                        createPreviewFixture
                            "weekly"
                            [ EntrySpecWithBreak
                                6
                                fixtureStaffA
                                (TimeOfDay 15 0 0)
                                (TimeOfDay 1 14 0)
                                (TimeOfDay 20 30 0)
                                (TimeOfDay 21 0 0)
                            ]
                    previewRun <- buildFixturePreview fixture

                    let lines = (onlyPreview previewRun).previewLines
                        lineFor keyPart =
                            case find (Text.isInfixOf keyPart . (.previewLineLocalBucketKey)) lines of
                                Just line -> line
                                Nothing   -> error ("expected Xero line containing " <> cs keyPart)
                    (lineFor "penalty:sunday_penalty").previewLineNumberOfUnits `shouldBe` replicate 6 0 <> [8.5]
                    (lineFor ":ordinary:").previewLineNumberOfUnits `shouldBe` replicate 6 0 <> [1.233333333333]
                    (lineFor "penalty:late_night_after_midnight").previewLineNumberOfUnits `shouldBe` replicate 6 0 <> [2]
                    map (.previewLineLocalBucketKey) lines `shouldSatisfy` all (not . Text.isInfixOf "penalty:missed_meal_break_addition")

            it "keeps a mid-period overnight shift in its Operational-day Xero position" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 2 fixtureStaffA (TimeOfDay 22 0 0) (TimeOfDay 2 0 0)]
                    previewRun <- buildFixturePreview fixture

                    let lines = (onlyPreview previewRun).previewLines
                    lines `shouldSatisfy` all (\line -> take 2 line.previewLineNumberOfUnits == [0, 0])
                    lines `shouldSatisfy` all (\line -> drop 3 line.previewLineNumberOfUnits == replicate 4 0)
                    lines `shouldSatisfy` all (\line -> line.previewLineNumberOfUnits !! 2 > 0)

            it "allocates a final-day cross-midnight shift in full to its Operational-day position" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixtureWithRosterStart 4 "weekly" [EntrySpec 6 fixtureStaffA (TimeOfDay 22 0 0) (TimeOfDay 2 0 0)]
                    previewRun <- buildFixturePreview fixture

                    let lines = (onlyPreview previewRun).previewLines
                        unitsAt index = sum [line.previewLineNumberOfUnits !! index | line <- lines]
                    payCalculation <- query @TimesheetPayCalculation |> filterWhere (#timesheetEntryId, unpackId (fromMaybe (error "expected entry") (head fixture.entries)).id) |> fetchOne
                    payCalculation.rosterWindowStart `shouldNotBe` fixture.periodStart
                    payCalculation.rosterWeekStartsOn `shouldBe` 4
                    map unitsAt [0 .. 5] `shouldBe` replicate 6 0
                    unitsAt 6 `shouldBe` 6

            it "preserves minute-level hourly Xero quantities" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 30)]
                    previewRun <- buildFixturePreview fixture

                    let line = onlyPreviewLine previewRun
                    line.previewLineNumberOfUnits `shouldBe` [4.008333333333, 0, 0, 0, 0, 0, 0]

            it "aggregates exact components before serializing the Xero bucket" $ withContext do
                withCleanDb do
                    fixture <-
                        createPreviewFixture
                            "weekly"
                            [ EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 9 0 30)
                            , EntrySpec 0 fixtureStaffA (TimeOfDay 9 1 0) (TimeOfDay 9 1 30)
                            ]
                    previewRun <- buildFixturePreview fixture

                    let line = onlyPreviewLine previewRun
                    line.previewLineNumberOfUnits `shouldBe` [0.016666666666, 0, 0, 0, 0, 0, 0]

            it "uses the approval-pinned source rather than a newer overlapping rate in preview bucket keys" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    input <- fetchPreviewInput fixture.request fixture.connection
                    let firstEntry = fromMaybe (error "expected preview entry") (head fixture.entries)
                    payLevelUuid <- case do
                        staffVersionId <- firstEntry.staffPayVersionId
                        shiftVersionId <- firstEntry.shiftTypePayVersionId
                        staffVersion <- find (\version -> unpackId version.id == staffVersionId) input.previewStaffPayVersions
                        shiftVersion <- find (\version -> unpackId version.id == shiftVersionId) input.previewShiftTypePayVersions
                        shiftVersion.overrideAwardLevelId <|> staffVersion.defaultAwardLevelId of
                            Just value -> pure value
                            Nothing -> expectationFailure "expected one preview pay level" >> error "unreachable"
                    staff <-
                        case find (\candidate -> unpackId candidate.id == firstEntry.staffId) input.previewStaff of
                            Just value -> pure value
                            Nothing -> expectationFailure "expected preview staff" >> error "unreachable"
                    awardLevel <-
                        case find (\candidate -> unpackId candidate.id == payLevelUuid) input.previewAwardLevels of
                            Just value -> pure value
                            Nothing -> expectationFailure "expected preview award level" >> error "unreachable"
                    baseRate <- query @AwardLevelBaseRate
                        |> filterWhere (#awardLevelId, payLevelUuid)
                        |> filterWhere (#employmentBasis, staff.employmentBasis)
                        |> fetchOne
                    mapping <-
                        case find (Text.isInfixOf ":ordinary:source:" . (.localBucketKey)) input.previewEarningsMappings of
                            Just value -> pure value
                            Nothing -> expectationFailure "expected ordinary earnings mapping" >> error "unreachable"
                    sealedRateBoundary <- case do
                        calculation <- (Map.lookup (unpackId firstEntry.id) input.previewCalculationsByEntryId :: Maybe WageCalculation)
                        component <- (head calculation.earningsComponents :: Maybe EarningsComponent)
                        component.publishedRateBoundaryDate of
                            Just value -> pure value
                            Nothing -> expectationFailure "expected sealed rate boundary" >> error "unreachable"
                    let sourceIdentity =
                            "bepis-projection:award_level_base_rates:"
                                <> tshow (unpackId baseRate.id)
                                <> "/source:fwc_mapd_pay_rates:"
                                <> tshow baseRate.fwcMapdPayRateId
                        expectedKey =
                            "xero:pay-item:classification:"
                                <> tshow awardLevel.classificationFixedId
                                <> ":basis:"
                                <> inputValue staff.employmentBasis
                                <> ":effective:"
                                <> tshow sealedRateBoundary
                                <> ":ordinary:source:"
                                <> sourceIdentity
                                <> ":rate:"
                                <> tshow baseRate.hourlyRate
                        preparedInput =
                            input
                                { previewPayCalculationsByEntryId = fmap (withSealedRosterWeekStartsOn 1) input.previewPayCalculationsByEntryId
                                , previewEarningsMappings = [mapping |> set #localBucketKey expectedKey]
                                , previewPayItemRequirements = []
                                }
                    _ <- baseRate |> set #operativeFrom (Just (fromGregorian 2026 7 1)) |> set #hourlyRate 40 |> updateRecord

                    case buildXeroTimesheetPreviewRun preparedInput of
                        Left err -> expectationFailure (cs err)
                        Right previewRun -> (onlyPreviewLine previewRun).previewLineLocalBucketKey `shouldBe` expectedKey

            it "keeps approved Xero bucket mappings after the venue start day changes" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    originalPreview <- buildFixturePreview fixture
                    sealedComponents <- query @TimesheetPayEarningsComponent
                        |> filterWhereIn (#timesheetPayCalculationId, mapMaybe (fmap unpackId . (.activePayCalculationId)) fixture.entries)
                        |> fetch
                    sealedComponents `shouldSatisfy` all (isJust . (.xeroLocalBucketKey))
                    sealedComponents `shouldSatisfy` all (isJust . (.xeroEarningsRateId))
                    venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId fixture.venue.id) |> fetchOne
                    _ <- venueConfig |> set #rosterWeekStartsOn 4 |> updateRecord
                    mappings <- query @XeroEarningsRateMapping |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                    forM_ mappings \mapping ->
                        mapping |> set #xeroEarningsRateId (Just "changed-after-approval") |> updateRecord >>= const (pure ())

                    changedInput <- fetchPreviewInput fixture.request fixture.connection
                    changedPreview <- case buildXeroTimesheetPreviewRun changedInput of
                        Left err -> expectationFailure (cs err) >> error "unreachable"
                        Right value -> pure value

                    map (.previewLineLocalBucketKey) (onlyPreview originalPreview).previewLines
                        `shouldBe` map (.previewLineLocalBucketKey) (onlyPreview changedPreview).previewLines
                    map (.previewLineXeroEarningsRateId) (onlyPreview originalPreview).previewLines
                        `shouldBe` map (.previewLineXeroEarningsRateId) (onlyPreview changedPreview).previewLines
                    map (.previewLineXeroEarningsRateId) (onlyPreview changedPreview).previewLines
                        `shouldNotSatisfy` elem "changed-after-approval"

            it "builds fortnightly daily units in selected payroll-calendar order" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "fortnightly" [EntrySpec 13 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    previewRun <- buildFixturePreview fixture

                    let line = onlyPreviewLine previewRun
                    length line.previewLineNumberOfUnits `shouldBe` 14
                    line.previewLineNumberOfUnits `shouldBe` replicate 13 0 <> [4]

            it "aggregates multiple entries for one employee and EarningsRateID into one line" $ withContext do
                withCleanDb do
                    fixture <-
                        createPreviewFixture
                            "weekly"
                            [ EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 12 0 0)
                            , EntrySpec 0 fixtureStaffA (TimeOfDay 13 0 0) (TimeOfDay 17 0 0)
                            ]
                    previewRun <- buildFixturePreview fixture

                    previewRun.previewRunTimesheets `shouldSatisfy` ((== 1) . length)
                    let line = onlyPreviewLine previewRun
                    line.previewLineNumberOfUnits `shouldBe` [7, 0, 0, 0, 0, 0, 0]
                    length line.previewLineSourceEntryIds `shouldBe` 2

            it "builds one timesheet object per Xero employee" $ withContext do
                withCleanDb do
                    fixture <-
                        createPreviewFixture
                            "weekly"
                            [ EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)
                            , EntrySpec 1 fixtureStaffB (TimeOfDay 9 0 0) (TimeOfDay 12 0 0)
                            ]
                    previewRun <- buildFixturePreview fixture

                    map (.previewXeroEmployeeId) previewRun.previewRunTimesheets `shouldBe` ["employee-a", "employee-b"]
                    previewRun.previewRunRequestArrayJson `shouldSatisfy` isArrayOfLength 2

            it "filters preview input by the selected synced Xero employee payroll calendar" $ withContext do
                withCleanDb do
                    fixture <-
                        createPreviewFixture
                            "weekly"
                            [ EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)
                            , EntrySpec 1 fixtureStaffB (TimeOfDay 9 0 0) (TimeOfDay 12 0 0)
                            ]
                    overwritePreviewEmployeeRawCalendar fixture "employee-b" "calendar-other"

                    input <- fetchPreviewInput fixture.request fixture.connection
                    case buildXeroTimesheetPreviewRun input of
                        Left err -> expectationFailure (cs err)
                        Right previewRun -> do
                            let previews :: [XeroTimesheetPreview]
                                previews = previewRun.previewRunTimesheets
                                firstEntry :: TimesheetEntry
                                firstEntry = fromMaybe (error "expected first entry") (head fixture.entries)
                            map (.previewXeroEmployeeId) previews `shouldBe` ["employee-a"]
                            case previews of
                                [timesheetPreview] -> previewSourceEntryIds timesheetPreview `shouldBe` [unpackId firstEntry.id]
                                _ -> expectationFailure "expected one preview"

            it "excludes employees without a payroll calendar from selected-calendar preview input" $ withContext do
                withCleanDb do
                    fixture <-
                        createPreviewFixture
                            "weekly"
                            [ EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)
                            , EntrySpec 1 fixtureStaffB (TimeOfDay 9 0 0) (TimeOfDay 12 0 0)
                            ]
                    employeeB <-
                        query @XeroEmployee
                            |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id)
                            |> filterWhere (#xeroEmployeeId, "employee-b" :: Text)
                            |> fetchOne
                    _ <-
                        employeeB
                            |> set #rawPayload (Aeson.object ["EmployeeID" Aeson..= employeeB.xeroEmployeeId])
                            |> updateRecord

                    input <- fetchPreviewInput fixture.request fixture.connection

                    map (.staffId) input.previewTimesheetEntries `shouldBe` [unpackId fixture.staffA.id]

            it "keeps source entry ids and pay version ids in metadata but omits TrackingItemID from Xero request JSON" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    previewRun <- buildFixturePreview fixture

                    let preview = onlyPreview previewRun
                    preview.previewSourceEntryIds `shouldBe` map (unpackId . (.id)) fixture.entries
                    preview.previewStaffPayVersionIds `shouldBe` sort (nub (mapMaybe (.staffPayVersionId) fixture.entries))
                    preview.previewShiftPayVersionIds `shouldBe` sort (nub (mapMaybe (.shiftTypePayVersionId) fixture.entries))
                    preview.previewRequestObjectJson `shouldSatisfy` not . jsonContainsKey "TrackingItemID"

            it "marks matching Xero draft timesheets as update previews" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    let remote = remoteTimesheetRef "remote-timesheet-a" "employee-a" fixture.periodStart fixture.periodEnd (Just "DRAFT")
                    previewRun <- buildFixturePreviewWithRemotes fixture [remote]

                    let preview = onlyPreview previewRun
                    preview.previewExistingXeroTimesheetId `shouldBe` Just "remote-timesheet-a"
                    preview.previewRequestObjectJson `shouldSatisfy` jsonContainsKey "TimesheetID"
                    xeroTimesheetPreviewRunJson previewRun `shouldSatisfy` jsonContainsKey "operation"

            it "uses matched managed pay item requirements when explicit earnings mappings are absent" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    mappings <- query @XeroEarningsRateMapping |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
                    forM_ mappings \mapping ->
                        mapping |> set #mappingStatus XeroEarningsRateMappingStatusEnumStale |> updateRecord >>= const (pure ())

                    previewRun <- buildFixturePreview fixture

                    (onlyPreviewLine previewRun).previewLineXeroEarningsRateId `shouldSatisfy` Text.isPrefixOf "earnings-"

            it "maps the separate missed meal break 50% component to its managed pay item bucket" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 17 0 0)]

                    previewRun <- buildFixturePreview fixture

                    let lines = (onlyPreview previewRun).previewLines
                    map (.previewLineLocalBucketKey) lines `shouldSatisfy` any (Text.isInfixOf "penalty:missed_meal_break_addition")
                    delayedLine <-
                        case find (Text.isInfixOf "penalty:missed_meal_break_addition" . (.previewLineLocalBucketKey)) lines of
                            Just line -> pure line
                            Nothing   -> expectationFailure "expected a missed meal break preview line" >> error "unreachable"
                    delayedLine.previewLineNumberOfUnits `shouldBe` [2, 0, 0, 0, 0, 0, 0]

            it "persists preview payload, readiness snapshot, and duplicate-check snapshot without posting to Xero" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    readiness <- validateXeroTimesheetReadiness fixture.request
                    let duplicateCheck = Aeson.object ["remoteTimesheets" Aeson..= ([] :: [Aeson.Value])]

                    result <- createPersistedXeroTimesheetPreview fixture.owner.id fixture.request readiness duplicateCheck

                    case result of
                        Left err -> expectationFailure (cs err)
                        Right run -> do
                            run.status `shouldBe` XeroSubmissionRunStatusEnumPreviewed
                            run.readinessSnapshotJson `shouldSatisfy` jsonContainsKey "ready"
                            run.xeroDuplicateCheckJson `shouldBe` duplicateCheck
                            run.previewPayloadJson `shouldSatisfy` jsonContainsKey "requestPayload"
                            run.selectedPayrollCalendarId `shouldBe` Just "calendar-preview"
                            run.selectedPeriodKey `shouldBe` fixture.request.readinessSelectedPeriodKey

            it "previews a historical selected Xero period without a global calendar selection" $ withContext do
                withCleanDb do
                    let historicalStart = fromGregorian 2026 1 5
                    fixture <- createPreviewFixtureAtPeriod "weekly" historicalStart [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    readiness <- validateXeroTimesheetReadiness fixture.request
                    result <- createPersistedXeroTimesheetPreview fixture.owner.id fixture.request readiness (Aeson.object [])

                    case result of
                        Left err -> expectationFailure (cs err)
                        Right run -> do
                            run.payPeriodStart `shouldBe` historicalStart
                            run.payPeriodEnd `shouldBe` addDays 6 historicalStart
                            run.selectedPayrollCalendarId `shouldBe` Just "calendar-preview"
                            run.previewPayloadJson `shouldSatisfy` jsonContainsKey "requestPayload"

data FixtureStaff = FixtureStaffA | FixtureStaffB
    deriving (Eq, Show)

fixtureStaffA :: FixtureStaff
fixtureStaffA = FixtureStaffA

fixtureStaffB :: FixtureStaff
fixtureStaffB = FixtureStaffB

data EntrySpec
    = EntrySpec
        { entryDayOffset :: !Integer
        , entryStaff     :: !FixtureStaff
        , entryStartTime :: !TimeOfDay
        , entryEndTime   :: !TimeOfDay
        }
    | EntrySpecWithBreak
        { entryDayOffset      :: !Integer
        , entryStaff          :: !FixtureStaff
        , entryStartTime      :: !TimeOfDay
        , entryEndTime        :: !TimeOfDay
        , entryBreakStartTime :: !TimeOfDay
        , entryBreakEndTime   :: !TimeOfDay
        }

data PreviewFixture = PreviewFixture
    { venue       :: !Venue
    , owner       :: !User
    , connection  :: !XeroConnection
    , request     :: !XeroTimesheetReadinessRequest
    , periodStart :: !Day
    , periodEnd   :: !Day
    , staffA      :: !Staff
    , staffB      :: !Staff
    , entries     :: ![TimesheetEntry]
    }

createPreviewFixture :: (?modelContext :: ModelContext) => Text -> [EntrySpec] -> IO PreviewFixture
createPreviewFixture = createPreviewFixtureWithRosterStart 1

createPreviewFixtureWithRosterStart :: (?modelContext :: ModelContext) => Int -> Text -> [EntrySpec] -> IO PreviewFixture
createPreviewFixtureWithRosterStart rosterWeekStartsOn calendarType entrySpecs = do
    today <- utctDay <$> getCurrentTime
    let anchorStart = fromGregorian 2026 5 4
        periodLength = if calendarType == "fortnightly" then 14 else 7
        periodsElapsed = diffDays today anchorStart `div` periodLength
        periodStart = addDays (periodsElapsed * periodLength) anchorStart
    fixture <- createPreviewFixtureAtPeriodWithRosterStart rosterWeekStartsOn calendarType periodStart entrySpecs
    _ <- createPreviewPayRun fixture "DRAFT"
    pure fixture

createPreviewFixtureAtPeriod :: (?modelContext :: ModelContext) => Text -> Day -> [EntrySpec] -> IO PreviewFixture
createPreviewFixtureAtPeriod = createPreviewFixtureAtPeriodWithRosterStart 1

createPreviewFixtureAtPeriodWithRosterStart :: (?modelContext :: ModelContext) => Int -> Text -> Day -> [EntrySpec] -> IO PreviewFixture
createPreviewFixtureAtPeriodWithRosterStart rosterWeekStartsOn calendarType periodStart entrySpecs = do
    let periodLength = if calendarType == "fortnightly" then 14 else 7
        periodEnd = addDays (periodLength - 1) periodStart
    venue <- createVenueWithConfig "Xero Preview Venue"
    venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
    _ <- venueConfig
        |> set #rosterWeekStartsOn rosterWeekStartsOn
        |> set #weekOffsetEpoch (defaultWeekOffsetEpochForStartDay rosterWeekStartsOn)
        |> updateRecord
    owner <- createUserRecord "preview-owner@example.com" "admin" True
    _ <- createVenueMembershipRecord venue owner VenueOwner
    awardLevel <- createPayLevelRecordWithRates venue "Level 2" 25 2 3 1 1.25 1.5
    staffA <- createMappedStaff venue awardLevel "Ada" "Lovelace"
    staffB <- createMappedStaff venue awardLevel "Grace" "Hopper"
    shiftType <- createShiftTypeRecord venue awardLevel "Preview Shift"
    connection <- createPreviewXeroConnection venue owner
    _ <- createPreviewSyncRun venue connection
    _ <- createPreviewPayrollCalendar venue connection calendarType periodStart
    buckets <- currentVenueBuckets venue periodStart
    createPreviewMappings venue connection periodStart staffA staffB buckets
    entries <- mapM (createFixtureEntry venue owner staffA staffB shiftType periodStart) entrySpecs
    pure PreviewFixture
        { venue
        , owner
        , connection
        , request =
            XeroTimesheetReadinessRequest
                { readinessVenueId = venue.id
                , readinessPayrollCalendarId = Just "calendar-preview"
                , readinessPayrollCalendarName = Just "Preview Calendar"
                , readinessSelectedPeriodKey = Just ("calendar-preview:" <> tshow periodStart <> ":" <> tshow periodEnd)
                , readinessPeriodStart = periodStart
                , readinessPeriodEnd = periodEnd
                , readinessPaymentDate = Nothing
                , readinessXeroPayRunId = Nothing
                , readinessXeroPayRunStatus = Nothing
                , readinessRemoteTimesheets = []
                , readinessSkippedStaffIds = []
                }
        , periodStart
        , periodEnd
        , staffA
        , staffB
        , entries
        }

createMappedStaff :: (?modelContext :: ModelContext) => Venue -> AwardLevel -> Text -> Text -> IO Staff
createMappedStaff venue awardLevel firstName lastName = do
    user <- createUserRecord ("xero-preview-staff-" <> Text.toLower firstName <> "-" <> Text.toLower lastName <> "@example.com") "staff" True
    _ <- createVenueMembershipRecord venue user Worker
    staff <- createStaffRecord venue (Just user) firstName lastName
    staff
        |> set #employmentBasis Permanent
        |> set #payAssignmentMode AwardRate
        |> set #defaultAwardLevelId (Just awardLevel.id)
        |> updateRecord

createFixtureEntry :: (?modelContext :: ModelContext) => Venue -> User -> Staff -> Staff -> ShiftType -> Day -> EntrySpec -> IO TimesheetEntry
createFixtureEntry venue owner staffA staffB shiftType periodStart spec = do
    let staff = if spec.entryStaff == FixtureStaffA then staffA else staffB
    approvedAt <- getCurrentTime
    createAndApproveEntry venue staff (addDays spec.entryDayOffset periodStart) () owner approvedAt (entryTransforms shiftType spec)

entryTransforms :: ShiftType -> EntrySpec -> [TimesheetFixtureValues -> TimesheetFixtureValues]
entryTransforms shiftType spec =
    [ set #shiftTypeId (unpackId shiftType.id)
    , setTestStartTime spec.entryStartTime
    , setTestEndTime spec.entryEndTime
    ]
        <> case spec of
            EntrySpec {} -> []
            EntrySpecWithBreak { entryBreakStartTime, entryBreakEndTime } ->
                [ setTestHadBreak True
                , setTestBreakMinutes 30
                , setTestBreakStartTime (Just entryBreakStartTime)
                , setTestBreakEndTime (Just entryBreakEndTime)
                ]

createPreviewXeroConnection :: (?modelContext :: ModelContext) => Venue -> User -> IO XeroConnection
createPreviewXeroConnection venue owner =
    newRecord @XeroConnection
        |> set #venueId (unpackId venue.id)
        |> set #tenantId ("tenant-preview" :: Text)
        |> set #tenantName (Just "Demo Company")
        |> set #connectionStatus ("active" :: Text)
        |> set #scopes requiredXeroScopesText
        |> set #encryptedRefreshToken ("encrypted-refresh-token" :: Text)
        |> set #connectedByUserId (Just (unpackId owner.id))
        |> createRecord

createPreviewPayRun :: (?modelContext :: ModelContext) => PreviewFixture -> Text -> IO XeroPayRun
createPreviewPayRun fixture status = do
    now <- getCurrentTime
    newRecord @XeroPayRun
        |> set #venueId (unpackId fixture.venue.id)
        |> set #xeroConnectionId (unpackId fixture.connection.id)
        |> set #xeroPayRunId ("pay-run-" <> Text.toLower status)
        |> set #xeroPayrollCalendarId ("calendar-preview" :: Text)
        |> set #payPeriodStart fixture.periodStart
        |> set #payPeriodEnd fixture.periodEnd
        |> set #payRunStatus (Just status)
        |> set #rawPayload (Aeson.object ["PayRunID" Aeson..= ("pay-run-" <> Text.toLower status)])
        |> set #syncedAt now
        |> createRecord

createPreviewSyncRun :: (?modelContext :: ModelContext) => Venue -> XeroConnection -> IO XeroSyncRun
createPreviewSyncRun venue connection = do
    now <- getCurrentTime
    _ <- connection |> set #lastSyncAt (Just now) |> updateRecord
    newRecord @XeroSyncRun
        |> set #venueId (unpackId venue.id)
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #syncStatus Succeeded
        |> set #syncKind PayrollReferenceData
        |> createRecord

createPreviewPayrollCalendar :: (?modelContext :: ModelContext) => Venue -> XeroConnection -> Text -> Day -> IO XeroPayrollCalendar
createPreviewPayrollCalendar venue connection calendarType periodStart = do
    calendar <-
        newRecord @XeroPayrollCalendar
            |> set #venueId (unpackId venue.id)
            |> set #xeroConnectionId (unpackId connection.id)
            |> set #xeroPayrollCalendarId ("calendar-preview" :: Text)
            |> set #name ("Preview Calendar" :: Text)
            |> set #calendarType (Just calendarType)
            |> set #startDate (Just periodStart)
            |> set #rawPayload (Aeson.object ["PayrollCalendarID" Aeson..= ("calendar-preview" :: Text)])
            |> createRecord
    pure calendar

createPreviewMappings :: (?modelContext :: ModelContext) => Venue -> XeroConnection -> Day -> Staff -> Staff -> [XeroLocalEarningsBucket] -> IO ()
createPreviewMappings venue connection periodStart staffA staffB buckets = do
    createStaffMapping staffA "employee-a"
    createStaffMapping staffB "employee-b"
    createXeroEmployee staffA "employee-a"
    createXeroEmployee staffB "employee-b"
    forM_ buckets \bucket -> do
        let earningsRateId = "earnings-" <> bucket.localBucketKey
        let earningsRateName = bucket.localBucketLabel
        _ <-
            newRecord @XeroEarningsRate
                |> set #venueId (unpackId venue.id)
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #xeroEarningsRateId earningsRateId
                |> set #name earningsRateName
                |> set #earningsType (Just "REGULAR")
                |> set #rateType Nothing
                |> set #accountCode (Just "477")
                |> set #isActive True
                |> set #rawPayload (Aeson.object ["EarningsRateID" Aeson..= earningsRateId])
                |> createRecord
        _ <-
            newRecord @XeroEarningsRateMapping
                |> set #venueId (unpackId venue.id)
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #localBucketKey bucket.localBucketKey
                |> set #localBucketLabel bucket.localBucketLabel
                |> set #xeroEarningsRateId (Just earningsRateId)
                |> set #xeroEarningsRateName (Just earningsRateName)
                |> set #mappingStatus XeroEarningsRateMappingStatusEnumVerified
                |> createRecord
        pure ()
    xeroEarningsRates <-
        query @XeroEarningsRate
            |> filterWhere (#venueId, unpackId venue.id)
            |> filterWhere (#xeroConnectionId, unpackId connection.id)
            |> fetch
    awardLevels <- query @AwardLevel |> fetch
    baseRates <- query @AwardLevelBaseRate |> fetch
    penaltyRates <- query @AwardLevelPenaltyRate |> fetch
    timeAllowances <- query @AwardTimePenaltyAllowance |> fetch
    staffMembers <-
        query @Staff
            |> filterWhere (#venueId, unpackId venue.id)
            |> fetch
    shiftTypes <-
        query @ShiftType
            |> filterWhere (#venueId, unpackId venue.id)
            |> fetch
    let requirements =
            deriveXeroPayItemRequirements
                1
                periodStart
                (deriveXeroUsedAwardPayScopes staffMembers shiftTypes)
                awardLevels
                baseRates
                penaltyRates
                timeAllowances
                xeroEarningsRates
    _ <- syncXeroPayItemRequirementRecords connection.id venue.id Nothing requirements
    _ <-
        newRecord @XeroPayItemAccountCodeSelection
            |> set #venueId (unpackId venue.id)
            |> set #xeroConnectionId (unpackId connection.id)
            |> set #accountCode (Just "477")
            |> set #selectionStatus XeroPayItemAccountCodeSelectionStatusEnumVerified
            |> createRecord
    pure ()
    where
        createStaffMapping staff employeeId =
            newRecord @XeroStaffMapping
                |> set #venueId (unpackId venue.id)
                |> set #staffId (unpackId staff.id)
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #xeroEmployeeId (Just employeeId)
                |> set #xeroEmployeeName (Just (staff.firstName <> " " <> staff.lastName))
                |> set #mappingStatus XeroStaffMappingStatusEnumVerified
                |> createRecord
        createXeroEmployee staff employeeId = do
            now <- getCurrentTime
            newRecord @XeroEmployee
                |> set #venueId (unpackId venue.id)
                |> set #xeroConnectionId (unpackId connection.id)
                |> set #xeroEmployeeId employeeId
                |> set #displayName (staff.firstName <> " " <> staff.lastName)
                |> set #email Nothing
                |> set #status (Just "ACTIVE")
                |> set #rawPayload (Aeson.object ["EmployeeID" Aeson..= employeeId, "PayrollCalendarID" Aeson..= ("calendar-preview" :: Text)])
                |> set #syncedAt now
                |> createRecord

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
    venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
    pure (deriveXeroLocalEarningsBuckets venueConfig.rosterWeekStartsOn effectiveDay (deriveXeroUsedAwardPayScopes staffMembers shiftTypes) awardLevels baseRates penaltyRates timeAllowances)

withSealedRosterWeekStartsOn :: Int -> TimesheetPayCalculation -> TimesheetPayCalculation
withSealedRosterWeekStartsOn startsOn calculation = calculation |> set #rosterWeekStartsOn startsOn

buildFixturePreview :: (?modelContext :: ModelContext) => PreviewFixture -> IO XeroTimesheetPreviewRun
buildFixturePreview fixture = buildFixturePreviewWithRemotes fixture []

buildFixturePreviewWithRemotes :: (?modelContext :: ModelContext) => PreviewFixture -> [XeroTimesheetRef] -> IO XeroTimesheetPreviewRun
buildFixturePreviewWithRemotes fixture remoteTimesheets = do
    calculations <- fmap Map.fromList $ forM fixture.entries \entry -> do
        loaded <- loadApprovedTimesheetPayCalculation entry
        case loaded of
            Right (Just calculation) -> pure (unpackId entry.id, calculation)
            _                        -> expectationFailure "expected sealed preview calculation" >> error "unreachable"
    staffMappings <- query @XeroStaffMapping |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
    earningsMappings <- query @XeroEarningsRateMapping |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
    payItemRequirements <- query @XeroPayItemRequirementRecord |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
    staffPayVersions <- query @StaffPayVersion |> filterWhereIn (#id, mapMaybe (fmap Id . (.staffPayVersionId)) fixture.entries) |> fetch
    shiftTypePayVersions <- query @ShiftTypePayVersion |> filterWhereIn (#id, mapMaybe (fmap Id . (.shiftTypePayVersionId)) fixture.entries) |> fetch
    importedPayItems <- query @XeroImportedPayItem |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
    payCalculations <- query @TimesheetPayCalculation |> filterWhereIn (#id, mapMaybe (.activePayCalculationId) fixture.entries) |> fetch
    awardLevels <- query @AwardLevel |> fetch
    let input =
            XeroTimesheetPreviewInput
                { previewVenueId = fixture.venue.id
                , previewPeriodStart = fixture.periodStart
                , previewPeriodEnd = fixture.periodEnd
                , previewTimesheetEntries = fixture.entries
                , previewStaff = [fixture.staffA, fixture.staffB]
                , previewStaffMappings = staffMappings
                , previewStaffPayVersions = staffPayVersions
                , previewShiftTypePayVersions = shiftTypePayVersions
                , previewImportedPayItems = importedPayItems
                , previewEarningsMappings = earningsMappings
                , previewPayItemRequirements = payItemRequirements
                , previewCalculationsByEntryId = calculations
                , previewPayCalculationsByEntryId = Map.fromList [(calculation.timesheetEntryId, calculation) | calculation <- payCalculations]
                , previewAwardLevels = awardLevels
                , previewRemoteTimesheets = remoteTimesheets
                }
    case buildXeroTimesheetPreviewRun input of
        Left err         -> expectationFailure (cs err) >> error "unreachable"
        Right previewRun -> pure previewRun

remoteTimesheetRef :: Text -> Text -> Day -> Day -> Maybe Text -> XeroTimesheetRef
remoteTimesheetRef timesheetId employeeId start end status =
    XeroTimesheetRef
        { xeroTimesheetId = Just timesheetId
        , xeroTimesheetEmployeeId = employeeId
        , xeroTimesheetStartDate = start
        , xeroTimesheetEndDate = end
        , xeroTimesheetStatus = status
        , xeroTimesheetHours = Nothing
        , xeroTimesheetLines = []
        , xeroTimesheetRaw = Aeson.object []
        }

overwritePreviewEmployeeRawCalendar :: (?modelContext :: ModelContext) => PreviewFixture -> Text -> Text -> IO ()
overwritePreviewEmployeeRawCalendar fixture employeeId payrollCalendarId = do
    employees <-
        query @XeroEmployee
            |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id)
            |> filterWhere (#xeroEmployeeId, employeeId)
            |> fetch
    forM_ employees \employee ->
        employee
            |> set #rawPayload (Aeson.object ["EmployeeID" Aeson..= employeeId, "PayrollCalendarID" Aeson..= payrollCalendarId])
            |> updateRecord
            >>= const (pure ())

onlyPreview :: XeroTimesheetPreviewRun -> XeroTimesheetPreview
onlyPreview previewRun =
    case previewRun.previewRunTimesheets of
        [preview] -> preview
        previews  -> error ("expected one preview, got " <> show (length previews))

onlyPreviewLine :: XeroTimesheetPreviewRun -> XeroTimesheetPreviewLine
onlyPreviewLine previewRun =
    case (onlyPreview previewRun).previewLines of
        [line] -> line
        lines  -> error ("expected one preview line, got " <> show (length lines))

isArrayOfLength :: Int -> Aeson.Value -> Bool
isArrayOfLength expectedLength (Aeson.Array values) = length values == expectedLength
isArrayOfLength _ _ = False

jsonContainsKey :: Text -> Aeson.Value -> Bool
jsonContainsKey key = \case
    Aeson.Object object -> KeyMap.member (fromString (cs key)) object || any (jsonContainsKey key) object
    Aeson.Array values  -> any (jsonContainsKey key) values
    _                   -> False
