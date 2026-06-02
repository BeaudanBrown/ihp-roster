module Test.XeroTimesheetPreviewSpec where

import Application.Helper.Pay
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroPayItems
import Application.Helper.XeroTimesheetReadiness
import Application.Xero.Timesheets.Preview
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, diffDays, fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

tests :: Spec
tests =
    beforeAll testContext do
        describe "Xero timesheet preview payloads" do
            it "builds weekly daily units in period order and zero-fills missing days" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    previewRun <- buildFixturePreview fixture

                    let line = onlyPreviewLine previewRun
                    line.previewLineNumberOfUnits `shouldBe` [4, 0, 0, 0, 0, 0, 0]

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
                        mapping |> set #mappingStatus ("stale" :: Text) |> updateRecord >>= const (pure ())

                    previewRun <- buildFixturePreview fixture

                    (onlyPreviewLine previewRun).previewLineXeroEarningsRateId `shouldSatisfy` Text.isPrefixOf "earnings-"

            it "maps weekday delayed meal break segments to the managed pay item bucket" $ withContext do
                withCleanDb do
                    fixture <- createPreviewFixture "weekly" [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 17 0 0)]

                    previewRun <- buildFixturePreview fixture

                    let lines = (onlyPreview previewRun).previewLines
                    map (.previewLineLocalBucketKey) lines `shouldSatisfy` any (Text.isInfixOf "penalty:delayed_meal_break_weekday")
                    delayedLine <-
                        case find (Text.isInfixOf "penalty:delayed_meal_break_weekday" . (.previewLineLocalBucketKey)) lines of
                            Just line -> pure line
                            Nothing   -> expectationFailure "expected a delayed meal break preview line" >> error "unreachable"
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
                            run.status `shouldBe` "previewed"
                            run.readinessSnapshotJson `shouldSatisfy` jsonContainsKey "ready"
                            run.xeroDuplicateCheckJson `shouldBe` duplicateCheck
                            run.previewPayloadJson `shouldSatisfy` jsonContainsKey "requestPayload"
                            run.selectedPayrollCalendarId `shouldBe` Just "calendar-preview"
                            run.selectedPeriodKey `shouldBe` fixture.request.readinessSelectedPeriodKey

            it "previews a historical selected Xero period without a global calendar selection" $ withContext do
                withCleanDb do
                    let historicalStart = fromGregorian 2026 1 5
                    fixture <- createPreviewFixtureAtPeriod "weekly" historicalStart [EntrySpec 0 fixtureStaffA (TimeOfDay 9 0 0) (TimeOfDay 13 0 0)]
                    selectionCount <- query @XeroPayrollCalendarSelection |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetchCount
                    selectionCount `shouldBe` 0

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

data EntrySpec = EntrySpec
    { entryDayOffset :: !Integer
    , entryStaff     :: !FixtureStaff
    , entryStartTime :: !TimeOfDay
    , entryEndTime   :: !TimeOfDay
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
createPreviewFixture calendarType entrySpecs = do
    today <- utctDay <$> getCurrentTime
    let anchorStart = fromGregorian 2026 5 4
        periodLength = if calendarType == "fortnightly" then 14 else 7
        periodsElapsed = diffDays today anchorStart `div` periodLength
        periodStart = addDays (periodsElapsed * periodLength) anchorStart
    fixture <- createPreviewFixtureAtPeriod calendarType periodStart entrySpecs
    createPreviewPayrollCalendarSelection fixture.venue fixture.connection fixture.owner
    _ <- createPreviewPayRun fixture "DRAFT"
    pure fixture

createPreviewFixtureAtPeriod :: (?modelContext :: ModelContext) => Text -> Day -> [EntrySpec] -> IO PreviewFixture
createPreviewFixtureAtPeriod calendarType periodStart entrySpecs = do
    let periodLength = if calendarType == "fortnightly" then 14 else 7
        periodEnd = addDays (periodLength - 1) periodStart
    venue <- createVenueWithConfig "Xero Preview Venue"
    owner <- createUserRecord "preview-owner@example.com" "admin" True
    _ <- createVenueMembershipRecord venue owner "venue_owner"
    awardLevel <- createPayLevelRecordWithRates venue "Level 2" 25 2 3 1 1.25 1.5
    staffA <- createMappedStaff venue awardLevel "Ada" "Lovelace"
    staffB <- createMappedStaff venue awardLevel "Grace" "Hopper"
    entries <- mapM (createFixtureEntry venue owner staffA staffB periodStart) entrySpecs
    connection <- createPreviewXeroConnection venue owner
    _ <- createPreviewSyncRun venue connection
    _ <- createPreviewPayrollCalendar venue connection calendarType periodStart
    buckets <- currentVenueBuckets venue periodStart
    createPreviewMappings venue connection periodStart staffA staffB buckets
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
    staff <- createStaffRecord venue Nothing firstName lastName
    staff
        |> set #employmentBasis Permanent
        |> set #defaultAwardLevelId (Just awardLevel.id)
        |> updateRecord

createFixtureEntry :: (?modelContext :: ModelContext) => Venue -> User -> Staff -> Staff -> Day -> EntrySpec -> IO TimesheetEntry
createFixtureEntry venue owner staffA staffB periodStart spec = do
    let staff = if spec.entryStaff == FixtureStaffA then staffA else staffB
    entry <- createApprovedTimesheetEntryRecord venue staff owner (addDays spec.entryDayOffset periodStart)
    entry
        |> set #startTime spec.entryStartTime
        |> set #endTime spec.entryEndTime
        |> updateRecord

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
createPreviewSyncRun venue connection =
    newRecord @XeroSyncRun
        |> set #venueId (unpackId venue.id)
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #syncStatus ("succeeded" :: Text)
        |> set #syncKind ("payroll_reference_data" :: Text)
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

createPreviewPayrollCalendarSelection :: (?modelContext :: ModelContext) => Venue -> XeroConnection -> User -> IO XeroPayrollCalendarSelection
createPreviewPayrollCalendarSelection venue connection owner =
    newRecord @XeroPayrollCalendarSelection
        |> set #venueId (unpackId venue.id)
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #xeroPayrollCalendarId (Just ("calendar-preview" :: Text))
        |> set #xeroPayrollCalendarName (Just ("Preview Calendar" :: Text))
        |> set #calendarStatus ("verified" :: Text)
        |> set #createdByUserId (Just (unpackId owner.id))
        |> set #updatedByUserId (Just (unpackId owner.id))
        |> createRecord

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
                |> set #mappingStatus ("verified" :: Text)
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
            |> set #selectionStatus ("verified" :: Text)
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
                |> set #mappingStatus ("verified" :: Text)
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
    pure (deriveXeroLocalEarningsBuckets effectiveDay (deriveXeroUsedAwardPayScopes staffMembers shiftTypes) awardLevels baseRates penaltyRates timeAllowances)

buildFixturePreview :: (?modelContext :: ModelContext) => PreviewFixture -> IO XeroTimesheetPreviewRun
buildFixturePreview fixture = buildFixturePreviewWithRemotes fixture []

buildFixturePreviewWithRemotes :: (?modelContext :: ModelContext) => PreviewFixture -> [XeroTimesheetRef] -> IO XeroTimesheetPreviewRun
buildFixturePreviewWithRemotes fixture remoteTimesheets = do
    payResults <- fetchTimesheetPayResultsForEntries fixture.entries
    staffMappings <- query @XeroStaffMapping |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
    earningsMappings <- query @XeroEarningsRateMapping |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
    payItemRequirements <- query @XeroPayItemRequirementRecord |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
    staffPayVersions <- query @StaffPayVersion |> filterWhereIn (#id, mapMaybe (fmap Id . (.staffPayVersionId)) fixture.entries) |> fetch
    shiftTypePayVersions <- query @ShiftTypePayVersion |> filterWhereIn (#id, mapMaybe (fmap Id . (.shiftTypePayVersionId)) fixture.entries) |> fetch
    importedPayItems <- query @XeroImportedPayItem |> filterWhere (#xeroConnectionId, unpackId fixture.connection.id) |> fetch
    awardLevels <- query @AwardLevel |> fetch
    baseRates <- query @AwardLevelBaseRate |> fetch
    penaltyRates <- query @AwardLevelPenaltyRate |> fetch
    timeAllowances <- query @AwardTimePenaltyAllowance |> fetch
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
                , previewPayResultsByEntryId = payResults
                , previewAwardLevels = awardLevels
                , previewAwardLevelBaseRates = baseRates
                , previewAwardLevelPenalties = penaltyRates
                , previewTimePenaltyAllowances = timeAllowances
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
