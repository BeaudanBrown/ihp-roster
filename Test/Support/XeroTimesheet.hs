module Test.Support.XeroTimesheet where

import Application.Fixture.PayrollFixtures (TimesheetFixtureValues,
                                            createAndApproveEntry)
import Application.Helper.Pay
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroPayItems
import Application.Helper.XeroTimesheetReadiness
import Application.Xero.Timesheets.Preview
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.KeyMap as KeyMap
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, diffDays, fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import Test.Hspec (expectationFailure)
import Test.Support

data FixtureStaff = FixtureStaffA | FixtureStaffB
    deriving (Eq, Show)

fixtureStaffA, fixtureStaffB :: FixtureStaff
fixtureStaffA = FixtureStaffA
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

data FixtureApprovalTiming = ApproveBeforeXero | ApproveAfterXero
    deriving (Eq, Show)

data PreviewPayFacts = PreviewPayFacts
    { payLevelName         :: !Text
    , baseHourlyRate       :: !Scientific
    , eveningPenalty       :: !Scientific
    , afterMidnightPenalty :: !Scientific
    , weekdayMultiplier    :: !Scientific
    , saturdayMultiplier   :: !Scientific
    , sundayMultiplier     :: !Scientific
    , shiftTypeName        :: !Text
    }

data PreviewFixturePlan = PreviewFixturePlan
    { fixtureRosterWeekStartsOn :: !Int
    , fixtureApprovalTiming     :: !FixtureApprovalTiming
    , fixtureCalendarType       :: !Text
    , fixturePeriodStart        :: !Day
    , fixtureStaffFacts         :: ![FixtureStaff]
    , fixturePayFacts           :: !PreviewPayFacts
    , fixtureEntrySpecs         :: ![EntrySpec]
    }

data PreviewFixture = PreviewFixture
    { venue       :: !Venue
    , owner       :: !User
    , connection  :: !XeroConnection
    , request     :: !XeroTimesheetReadinessRequest
    , periodStart :: !Day
    , periodEnd   :: !Day
    , staffA      :: !Staff
    , staffB      :: !(Maybe Staff)
    , entries     :: ![TimesheetEntry]
    }

createPreviewFixture :: (?modelContext :: ModelContext) => Text -> [EntrySpec] -> IO PreviewFixture
createPreviewFixture = createPreviewFixtureWithRosterStart 1

createPreviewFixtureWithStaffFacts :: (?modelContext :: ModelContext) => [FixtureStaff] -> Text -> [EntrySpec] -> IO PreviewFixture
createPreviewFixtureWithStaffFacts staffFacts calendarType entrySpecs =
    createCurrentPreviewFixture (standardPreviewFixturePlan 1 ApproveAfterXero staffFacts calendarType fixtureAnchorStart entrySpecs)

createPreviewFixtureWithRosterStart :: (?modelContext :: ModelContext) => Int -> Text -> [EntrySpec] -> IO PreviewFixture
createPreviewFixtureWithRosterStart rosterWeekStartsOn calendarType entrySpecs =
    createCurrentPreviewFixture (standardPreviewFixturePlan rosterWeekStartsOn ApproveAfterXero (fixtureStaffFactsFromEntries entrySpecs) calendarType fixtureAnchorStart entrySpecs)

createLateBindingPreviewFixture :: (?modelContext :: ModelContext) => Text -> [EntrySpec] -> IO PreviewFixture
createLateBindingPreviewFixture calendarType entrySpecs =
    createCurrentPreviewFixture (standardPreviewFixturePlan 1 ApproveBeforeXero (fixtureStaffFactsFromEntries entrySpecs) calendarType fixtureAnchorStart entrySpecs)

createCurrentPreviewFixture :: (?modelContext :: ModelContext) => PreviewFixturePlan -> IO PreviewFixture
createCurrentPreviewFixture plan = do
    today <- utctDay <$> getCurrentTime
    let periodLength = fixturePeriodLength plan.fixtureCalendarType
        periodsElapsed = diffDays today fixtureAnchorStart `div` periodLength
        currentPeriodStart = addDays (periodsElapsed * periodLength) fixtureAnchorStart
    fixture <- createPreviewFixtureFromPlan plan { fixturePeriodStart = currentPeriodStart }
    _ <- createPreviewPayRun fixture "DRAFT"
    pure fixture

createPreviewFixtureAtPeriod :: (?modelContext :: ModelContext) => Text -> Day -> [EntrySpec] -> IO PreviewFixture
createPreviewFixtureAtPeriod = createPreviewFixtureAtPeriodWithRosterStart 1

createPreviewFixtureAtPeriodWithRosterStart :: (?modelContext :: ModelContext) => Int -> Text -> Day -> [EntrySpec] -> IO PreviewFixture
createPreviewFixtureAtPeriodWithRosterStart rosterWeekStartsOn calendarType periodStart entrySpecs =
    createPreviewFixtureFromPlan (standardPreviewFixturePlan rosterWeekStartsOn ApproveAfterXero (fixtureStaffFactsFromEntries entrySpecs) calendarType periodStart entrySpecs)

standardPreviewFixturePlan :: Int -> FixtureApprovalTiming -> [FixtureStaff] -> Text -> Day -> [EntrySpec] -> PreviewFixturePlan
standardPreviewFixturePlan fixtureRosterWeekStartsOn fixtureApprovalTiming fixtureStaffFacts fixtureCalendarType fixturePeriodStart fixtureEntrySpecs =
    PreviewFixturePlan { fixturePayFacts = standardPreviewPayFacts, .. }

standardPreviewPayFacts :: PreviewPayFacts
standardPreviewPayFacts = PreviewPayFacts
    { payLevelName = "Level 2"
    , baseHourlyRate = 25
    , eveningPenalty = 2
    , afterMidnightPenalty = 3
    , weekdayMultiplier = 1
    , saturdayMultiplier = 1.25
    , sundayMultiplier = 1.5
    , shiftTypeName = "Preview Shift"
    }

fixtureStaffFactsFromEntries :: [EntrySpec] -> [FixtureStaff]
fixtureStaffFactsFromEntries entrySpecs = nub (FixtureStaffA : map (.entryStaff) entrySpecs)

fixtureAnchorStart :: Day
fixtureAnchorStart = fromGregorian 2026 5 4

fixturePeriodLength :: Text -> Integer
fixturePeriodLength calendarType = if calendarType == "fortnightly" then 14 else 7

createPreviewFixtureFromPlan :: (?modelContext :: ModelContext) => PreviewFixturePlan -> IO PreviewFixture
createPreviewFixtureFromPlan plan = do
    let periodStart = plan.fixturePeriodStart
        periodEnd = addDays (fixturePeriodLength plan.fixtureCalendarType - 1) periodStart
    venue <- createVenueWithConfig "Xero Preview Venue"
    venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
    _ <- venueConfig |> set #rosterWeekStartsOn plan.fixtureRosterWeekStartsOn |> updateRecord
    owner <- createUserRecord "preview-owner@example.com" "admin" True
    _ <- createVenueMembershipRecord venue owner VenueOwner
    let payFacts = plan.fixturePayFacts
    awardLevel <- createPayLevelRecordWithRates venue payFacts.payLevelName payFacts.baseHourlyRate payFacts.eveningPenalty payFacts.afterMidnightPenalty payFacts.weekdayMultiplier payFacts.saturdayMultiplier payFacts.sundayMultiplier
    staffA <- createMappedStaff venue awardLevel "Ada" "Lovelace"
    staffB <-
        if FixtureStaffB `elem` plan.fixtureStaffFacts
            then Just <$> createMappedStaff venue awardLevel "Grace" "Hopper"
            else pure Nothing
    let fixtureStaff = resolveFixtureStaff staffA staffB
    shiftType <- createShiftTypeRecord venue awardLevel payFacts.shiftTypeName
    entriesBeforeXero <-
        case plan.fixtureApprovalTiming of
            ApproveBeforeXero -> mapM (createFixtureEntry venue owner fixtureStaff shiftType periodStart) plan.fixtureEntrySpecs
            ApproveAfterXero  -> pure []
    connection <- createPreviewXeroConnection venue owner
    _ <- createPreviewSyncRun venue connection
    _ <- createPreviewPayrollCalendar venue connection plan.fixtureCalendarType periodStart
    buckets <- currentVenueBuckets venue periodStart
    createPreviewMappings venue connection periodStart ([staffA] <> maybeToList staffB) buckets
    entries <-
        case plan.fixtureApprovalTiming of
            ApproveBeforeXero -> pure entriesBeforeXero
            ApproveAfterXero  -> mapM (createFixtureEntry venue owner fixtureStaff shiftType periodStart) plan.fixtureEntrySpecs
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

requiredFixtureStaff :: PreviewFixture -> FixtureStaff -> Staff
requiredFixtureStaff fixture = resolveFixtureStaff fixture.staffA fixture.staffB

resolveFixtureStaff :: Staff -> Maybe Staff -> FixtureStaff -> Staff
resolveFixtureStaff staffA _ FixtureStaffA = staffA
resolveFixtureStaff _ (Just staffB) FixtureStaffB = staffB
resolveFixtureStaff _ Nothing FixtureStaffB = error "FixtureStaffB was not requested by the fixture plan"

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

createFixtureEntry :: (?modelContext :: ModelContext) => Venue -> User -> (FixtureStaff -> Staff) -> ShiftType -> Day -> EntrySpec -> IO TimesheetEntry
createFixtureEntry venue owner resolveStaff shiftType periodStart spec = do
    approvedAt <- getCurrentTime
    createAndApproveEntry venue (resolveStaff spec.entryStaff) (addDays spec.entryDayOffset periodStart) () owner approvedAt (entryTransforms shiftType spec)

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
createPreviewXeroConnection venue owner = do
    connection <- createXeroConnectionRecord venue owner "tenant-preview"
    connection
        |> set #tenantName (Just "Demo Company")
        |> set #scopes requiredXeroScopesText
        |> updateRecord

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

createPreviewMappings :: (?modelContext :: ModelContext) => Venue -> XeroConnection -> Day -> [Staff] -> [XeroLocalEarningsBucket] -> IO ()
createPreviewMappings venue connection periodStart staffMembersToMap buckets = do
    forM_ (zip staffMembersToMap ["employee-a", "employee-b"]) \(staff, employeeId) -> do
        createStaffMapping staff employeeId
        createXeroEmployee staff employeeId
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
    loadedInput <- fetchPreviewInput fixture.request fixture.connection
    let input = loadedInput { previewRemoteTimesheets = remoteTimesheets }
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
