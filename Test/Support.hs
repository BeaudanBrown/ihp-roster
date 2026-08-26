module Test.Support where

import qualified Application.Fixture as ApplicationFixture
import qualified Application.Fixture.PayrollFixtures as Payroll
import qualified Application.Fixture.Reset as FixtureReset
import Application.Fixture.WageSourceFixtures (ensureFreshWageSourceFacts,
                                               sealApprovedFixtureCalculation)
import Application.Helper.Controller (currentVenueSessionKey,
                                      formatPasskeyVerifiedAt,
                                      initImpersonationContext,
                                      passkeyVerifiedAtSessionKey,
                                      passkeyVerifiedUserSessionKey)
import Application.Helper.ControllerContext (initCurrentVenueContext)
import Application.Helper.Pay (ensurePayVersionsForTimesheetApproval,
                               lockPayVersionsForApproval)
import Application.Helper.RosterGroups (ensureVenueDefaultRosterGroup)
import Application.Helper.TimeRules (rosterShiftStartDate)
import Application.RosterShiftAssignment (RosterShiftAssignment (..))
import Application.VenueTime (RepeatedTimeOccurrence (FirstOccurrence),
                              melbourneTimeZoneName)
import Application.VenueTime.Model
import Config
import Control.Applicative ((<|>))
import Control.Exception (bracket)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as ByteString
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Serialize as Serialize
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, diffDays, fromGregorian)
import Data.Time.Clock (UTCTime, addUTCTime, diffUTCTime, getCurrentTime)
import Data.Time.LocalTime (TimeOfDay (..))
import qualified Data.Vault.Lazy as Vault
import Database.PostgreSQL.Simple.Types (Binary (Binary))
import Generated.Types
import GHC.Clock (getMonotonicTimeNSec)
import IHP.Controller.Context (ControllerContext, newControllerContext)
import IHP.Controller.Session (sessionVaultKey)
import IHP.ControllerPrelude
import IHP.ControllerSupport (Respond)
import IHP.FrameworkConfig
import IHP.HaskellSupport
import qualified IHP.LoginSupport.Helper.Controller as LoginSupport
import IHP.LoginSupport.Middleware (initAuthentication)
import qualified IHP.Log as Log
import IHP.ModelSupport (sqlExecDiscardResult)
import IHP.Prelude
import qualified IHP.Prelude as Prelude
import IHP.Test.Mocking
import Network.HTTP.Types (Status)
import Network.HTTP.Types.Header (RequestHeaders)
import qualified Network.Wai as Wai
import qualified Network.Wai.Session.Maybe as WaiSession
import System.Environment (lookupEnv, setEnv, unsetEnv)
import qualified System.IO as IO
import System.IO.Unsafe (unsafePerformIO)
import Test.Hspec (Expectation, shouldBe)
import Web.FrontController ()
import Web.Types

actionResponsesShouldHaveStatus :: Status -> [(Text, IO Wai.Response)] -> Expectation
actionResponsesShouldHaveStatus expectedStatus actions = do
    actualStatuses <-
        mapM
            (\(label, request) -> do
                response <- request
                pure (label, Wai.responseStatus response)
            )
            actions
    actualStatuses `shouldBe` map (\(label, _) -> (label, expectedStatus)) actions

class TestLocalTimeRecord record localTime | record -> localTime where
    testStartTime :: record -> localTime
    testEndTime :: record -> localTime
    setTestStartTime :: localTime -> record -> record
    setTestEndTime :: localTime -> record -> record

instance TestLocalTimeRecord TimesheetEntry TimeOfDay where
    testStartTime = timesheetEntryStartTime
    testEndTime = timesheetEntryEndTime
    setTestStartTime startTime entry =
        entry |> set #startsAt (resolveTestFixtureInstant entry.timezone (timesheetEntryWorkedOn entry) startTime)
    setTestEndTime endTime entry =
        let startLocal = storedInstantLocalTime entry.timezone entry.startsAt
            endDay = addDays (if endTime <= startLocal.localTimeOfDay then 1 else 0) startLocal.localDay
         in entry |> set #endsAt (resolveTestFixtureInstant entry.timezone endDay endTime)

instance TestLocalTimeRecord Payroll.TimesheetFixtureValues TimeOfDay where
    testStartTime = (.startTime)
    testEndTime = (.endTime)
    setTestStartTime = set #startTime
    setTestEndTime = set #endTime

instance TestLocalTimeRecord RosterSlot (Maybe TimeOfDay) where
    testStartTime = rosterSlotStartTime
    testEndTime = rosterSlotEndTime
    setTestStartTime Nothing slot = slot |> set #startsAt Nothing
    setTestStartTime (Just startTime) slot =
        let startDay = rosterSlotFixtureDay slot
         in slot
                |> set #startsAt (Just (resolveTestFixtureInstant (testFixtureTimezone slot.timezone) startDay startTime))
                |> set #timezone (testFixtureTimezone slot.timezone)
    setTestEndTime Nothing slot = slot |> set #endsAt Nothing
    setTestEndTime (Just endTime) slot =
        let startDay = rosterSlotFixtureDay slot
            startTime = fromMaybe endTime (rosterSlotStartTime slot)
            endDay = addDays (if endTime <= startTime then 1 else 0) startDay
         in slot
                |> set #endsAt (Just (resolveTestFixtureInstant (testFixtureTimezone slot.timezone) endDay endTime))
                |> set #timezone (testFixtureTimezone slot.timezone)

resolveTestFixtureInstant :: Text -> Day -> TimeOfDay -> UTCTime
resolveTestFixtureInstant rawTimezone day timeOfDay =
    let timezone = testFixtureTimezone rawTimezone
        occurrence = if civilBoundaryIsRepeated day timeOfDay then Just FirstOccurrence else Nothing
     in either (error . ("Invalid test fixture boundary: " <>) . show) Prelude.id $
            resolveBoundaryInstant timezone day timeOfDay occurrence

testFixtureTimezone :: Text -> Text
testFixtureTimezone timezone
    | Text.null timezone = melbourneTimeZoneName
    | otherwise = timezone

rosterSlotFixtureDay :: RosterSlot -> Day
rosterSlotFixtureDay slot =
    case slot.startsAt <|> slot.endsAt of
        Just instant -> (storedInstantLocalTime (testFixtureTimezone slot.timezone) instant).localDay
        Nothing -> defaultWeekEpoch

testWorkedOn :: TimesheetEntry -> Day
testWorkedOn = timesheetEntryWorkedOn

setTestWorkedOn :: Day -> TimesheetEntry -> TimesheetEntry
setTestWorkedOn targetDay entry
    | Text.null entry.timezone =
        let boundaries =
                either (error . ("Invalid blank test timesheet boundaries: " <>) . show) Prelude.id $
                    resolveShiftBoundaries melbourneTimeZoneName ShiftBoundaryInput
                        { shiftBoundaryDate = targetDay
                        , shiftBoundaryStartTime = TimeOfDay 9 0 0
                        , shiftBoundaryStartOccurrence = Nothing
                        , shiftBoundaryEndTime = TimeOfDay 17 0 0
                        , shiftBoundaryEndOccurrence = Nothing
                        , shiftBoundaryBreak = Nothing
                        }
         in applyTimesheetEntryBoundaries boundaries entry
    | otherwise =
        let timezone = entry.timezone
            sourceDay = timesheetEntryWorkedOn entry
            moveBoundary instant =
                let local = storedInstantLocalTime timezone instant
                    movedDay = addDays (diffDays local.localDay sourceDay) targetDay
                 in resolveTestFixtureInstant timezone movedDay local.localTimeOfDay
         in entry
                |> set #startsAt (moveBoundary entry.startsAt)
                |> set #endsAt (moveBoundary entry.endsAt)
                |> set #breakStartsAt (moveBoundary <$> entry.breakStartsAt)
                |> set #breakEndsAt (moveBoundary <$> entry.breakEndsAt)

setTestTimesheetBoundaries :: Day -> TimeOfDay -> TimeOfDay -> TimesheetEntry -> TimesheetEntry
setTestTimesheetBoundaries workedOn startTime endTime entry =
    let boundaries =
            either (error . ("Invalid test timesheet boundaries: " <>) . show) Prelude.id $
                resolveShiftBoundaries (testFixtureTimezone entry.timezone) ShiftBoundaryInput
                    { shiftBoundaryDate = workedOn
                    , shiftBoundaryStartTime = startTime
                    , shiftBoundaryStartOccurrence = Nothing
                    , shiftBoundaryEndTime = endTime
                    , shiftBoundaryEndOccurrence = Nothing
                    , shiftBoundaryBreak = Nothing
                    }
     in applyTimesheetEntryBoundaries boundaries entry

class TestBreakRecord record where
    testHadBreak :: record -> Bool
    setTestHadBreak :: Bool -> record -> record
    testBreakStartTime :: record -> Maybe TimeOfDay
    setTestBreakStartTime :: Maybe TimeOfDay -> record -> record
    testBreakEndTime :: record -> Maybe TimeOfDay
    setTestBreakEndTime :: Maybe TimeOfDay -> record -> record
    testBreakMinutes :: record -> Int
    setTestBreakMinutes :: Int -> record -> record

instance TestBreakRecord TimesheetEntry where
    testHadBreak = timesheetEntryHadBreak
    setTestHadBreak False entry = entry |> set #breakStartsAt Nothing |> set #breakEndsAt Nothing
    setTestHadBreak True entry
        | isJust entry.breakStartsAt && isJust entry.breakEndsAt = entry
        | otherwise =
            let duration = diffUTCTime entry.endsAt entry.startsAt
                breakStart = addUTCTime (duration / 2) entry.startsAt
             in entry
                    |> set #breakStartsAt (Just breakStart)
                    |> set #breakEndsAt (Just (addUTCTime 1800 breakStart))
    testBreakStartTime = timesheetEntryBreakStartTime
    setTestBreakStartTime Nothing entry = entry |> set #breakStartsAt Nothing
    setTestBreakStartTime (Just breakTime) entry =
        let startLocal = storedInstantLocalTime entry.timezone entry.startsAt
            breakDay = addDays (if breakTime < startLocal.localTimeOfDay then 1 else 0) startLocal.localDay
         in entry |> set #breakStartsAt (Just (resolveTestFixtureInstant entry.timezone breakDay breakTime))
    testBreakEndTime = timesheetEntryBreakEndTime
    setTestBreakEndTime Nothing entry = entry |> set #breakEndsAt Nothing
    setTestBreakEndTime (Just breakTime) entry =
        let startLocal = storedInstantLocalTime entry.timezone entry.startsAt
            breakDay = addDays (if breakTime < startLocal.localTimeOfDay then 1 else 0) startLocal.localDay
         in entry |> set #breakEndsAt (Just (resolveTestFixtureInstant entry.timezone breakDay breakTime))
    testBreakMinutes = floor . (/ 60) . timesheetEntryBreakElapsedSeconds
    setTestBreakMinutes minutes entry =
        case entry.breakStartsAt of
            Nothing -> entry
            Just breakStart -> entry |> set #breakEndsAt (Just (addUTCTime (fromIntegral (minutes * 60)) breakStart))

instance TestBreakRecord Payroll.TimesheetFixtureValues where
    testHadBreak = (.hadBreak)
    setTestHadBreak = set #hadBreak
    testBreakStartTime = (.breakStartTime)
    setTestBreakStartTime = set #breakStartTime
    testBreakEndTime = (.breakEndTime)
    setTestBreakEndTime = set #breakEndTime
    testBreakMinutes = (.breakMinutes)
    setTestBreakMinutes = set #breakMinutes

setTestRosterSlotBoundaries :: Day -> TimeOfDay -> TimeOfDay -> RosterSlot -> RosterSlot
setTestRosterSlotBoundaries rosterDate startTime endTime slot =
    let boundaries =
            either (error . ("Invalid test roster boundaries: " <>) . show) Prelude.id $
                resolveShiftBoundaries (testFixtureTimezone slot.timezone) ShiftBoundaryInput
                    { shiftBoundaryDate = rosterShiftStartDate rosterDate startTime
                    , shiftBoundaryStartTime = startTime
                    , shiftBoundaryStartOccurrence = Nothing
                    , shiftBoundaryEndTime = endTime
                    , shiftBoundaryEndOccurrence = Nothing
                    , shiftBoundaryBreak = Nothing
                    }
     in applyRosterSlotBoundaries boundaries slot

testDurationMinutes :: RosterSlot -> Maybe Int
testDurationMinutes = fmap (floor . (/ 60)) . rosterSlotElapsedSeconds

setTestDurationMinutes :: Maybe Int -> RosterSlot -> RosterSlot
setTestDurationMinutes Nothing slot = slot |> set #endsAt Nothing
setTestDurationMinutes (Just minutes) slot =
    case slot.startsAt of
        Nothing -> slot
        Just start -> slot |> set #endsAt (Just (addUTCTime (fromIntegral (minutes * 60)) start))

withDatabaseTestContext :: (MockContext WebApplication -> IO a) -> IO a
withDatabaseTestContext action = do
    setEnv "IHP_ROSTER_REQUIRE_PRIVILEGED_STRONG_AUTH" "true"
    withMockContext WebApplication databaseTestConfig action

-- Routine database suites suppress per-query Debug output. Focused diagnosis can
-- restore the normal Development logger without replacing explicit test-local
-- capture loggers installed on a ModelContext.
databaseTestConfig :: ConfigBuilder
databaseTestConfig = do
    detailedSql <- configIO ((== Just "1") <$> lookupEnv "HSPEC_SQL_LOG")
    logger <- configIO do
        let Log.LoggerSettings
                { Log.formatter = defaultFormatter
                , Log.destination = defaultDestination
                , Log.timeFormat = defaultTimeFormat
                } = def
        Log.newLogger Log.LoggerSettings
            { Log.level = if detailedSql then Log.Debug else Log.Warn
            , Log.formatter = defaultFormatter
            , Log.destination = defaultDestination
            , Log.timeFormat = defaultTimeFormat
            }
    option logger
    config

withPrivilegedStrongAuthentication :: Bool -> IO value -> IO value
withPrivilegedStrongAuthentication enabled action =
    bracket
        (lookupEnv variableName)
        restore
        (\_ -> setEnv variableName (if enabled then "true" else "false") >> action)
  where
    variableName = "IHP_ROSTER_REQUIRE_PRIVILEGED_STRONG_AUTH"
    restore = maybe (unsetEnv variableName) (setEnv variableName)

resetDatabase :: (?modelContext :: ModelContext) => IO ()
resetDatabase = FixtureReset.resetDatabase

withCleanDb :: (?modelContext :: ModelContext) => IO a -> IO a
withCleanDb action = do
    case hspecResetMetricsFile of
        Nothing -> resetDatabase
        Just metricsFile -> do
            startedAt <- getMonotonicTimeNSec
            resetDatabase
            finishedAt <- getMonotonicTimeNSec
            IO.appendFile metricsFile (Text.unpack (tshow (finishedAt - startedAt)) <> "\n")
    action

-- Optional, process-local measurement only. The canonical test path performs
-- the same reset without filesystem writes when the variable is unset.
{-# NOINLINE hspecResetMetricsFile #-}
hspecResetMetricsFile :: Maybe FilePath
hspecResetMetricsFile = unsafePerformIO (lookupEnv "HSPEC_RESET_METRICS_FILE")

withControllerTestContext ::
    (?mocking :: MockContext WebApplication, ?request :: Wai.Request, ?respond :: Respond) =>
    ((?context :: ControllerContext) => IO a) ->
    IO a
withControllerTestContext action =
    withSessionValues [] do
        controllerContext <- newControllerContext
        let ?context = controllerContext
        action

withCurrentControllerContext ::
    (?mocking :: MockContext WebApplication, ?request :: Wai.Request, ?modelContext :: ModelContext) =>
    ((?context :: ControllerContext) => IO a) ->
    IO a
withCurrentControllerContext action = do
    let ?frameworkConfig = config
    controllerContext <- newControllerContext
    let ?context = controllerContext
    initAuthentication @User
    initCurrentVenueContext
    initImpersonationContext
    action

createVenueWithConfig :: (?modelContext :: ModelContext) => Text -> IO Venue
createVenueWithConfig name =
    withTransaction do
        venue <- ApplicationFixture.createVenueRecordWithRosterDefaults name
        venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
        _ <- venueConfig |> set #rosterLayoutMode DayRows |> updateRecord
        pure venue

createUserRecord :: (?modelContext :: ModelContext) => Text -> Text -> Bool -> IO User
createUserRecord emailAddress globalRole isProfileCompleted =
    createUserRecordWithPlatformRole emailAddress globalRole Nothing isProfileCompleted

createUserRecordWithPlatformRole :: (?modelContext :: ModelContext) => Text -> Text -> Maybe PlatformRoleEnum -> Bool -> IO User
createUserRecordWithPlatformRole emailAddress globalRole platformRole isProfileCompleted =
    ApplicationFixture.createUserRecordWithPasswordInputAndPlatformRoleAndId
        emailAddress
        (ApplicationFixture.UseFixturePasswordHash testPasswordHash)
        globalRole
        platformRole
        isProfileCompleted
        Nothing

createTestPasskeyRecord :: (?modelContext :: ModelContext) => User -> Text -> IO Passkey
createTestPasskeyRecord user passkeyName =
    newRecord @Passkey
        |> set #userId (unpackId user.id)
        |> set #credentialId (Binary (cs ("test-credential-id-" <> inputValue user.id <> "-" <> passkeyName) :: ByteString.ByteString))
        |> set #publicKey (Binary "test-public-key")
        |> set #name passkeyName
        |> createRecord

createImportedXeroPayItemRecord :: (?modelContext :: ModelContext) => Venue -> User -> Text -> Text -> Scientific -> IO XeroImportedPayItem
createImportedXeroPayItemRecord venue importedBy name earningsRateId rate = do
    connection <- createXeroConnectionRecord venue importedBy ("tenant-" <> earningsRateId)
    newRecord @XeroImportedPayItem
        |> set #venueId (unpackId venue.id)
        |> set #xeroConnectionId (unpackId connection.id)
        |> set #xeroEarningsRateId earningsRateId
        |> set #name name
        |> set #accountCode (Just ("477" :: Text))
        |> set #earningsType ("ORDINARYTIMEEARNINGS" :: Text)
        |> set #rateType ("RATEPERUNIT" :: Text)
        |> set #typeOfUnits ("Hours" :: Text)
        |> set #ratePerUnit rate
        |> set #rawPayload (Aeson.object [])
        |> set #importedByUserId (unpackId importedBy.id)
        |> createRecord

createXeroConnectionRecord :: (?modelContext :: ModelContext) => Venue -> User -> Text -> IO XeroConnection
createXeroConnectionRecord venue connectedBy tenantId =
    newRecord @XeroConnection
        |> set #venueId (unpackId venue.id)
        |> set #tenantId tenantId
        |> set #tenantName (Just ("Test Tenant" :: Text))
        |> set #connectionStatus ("active" :: Text)
        |> set #scopes ("payroll.employees payroll.payitems" :: Text)
        |> set #encryptedRefreshToken ("encrypted-refresh-token" :: Text)
        |> set #connectedByUserId (Just (unpackId connectedBy.id))
        |> createRecord

createVenueMembershipRecord :: (?modelContext :: ModelContext) => Venue -> User -> VenueRoleEnum -> IO VenueMembership
createVenueMembershipRecord venue user venueRole =
    ApplicationFixture.createVenueMembershipRecordWithStaffFixture
        ApplicationFixture.EnsureProfileStaffForCompletedUser
        venue
        user
        venueRole

containsTextInOrder :: Text -> [Text] -> Bool
containsTextInOrder _ [] = True
containsTextInOrder haystack (needle : remaining) =
    case Text.breakOn needle haystack of
        (_, suffix)
            | Text.null suffix -> False
            | otherwise -> containsTextInOrder (Text.drop (Text.length needle) suffix) remaining

createVenueInvitationRecord :: (?modelContext :: ModelContext) => Venue -> Maybe User -> Text -> VenueRoleEnum -> IO VenueInvitation
createVenueInvitationRecord = ApplicationFixture.createVenueInvitationRecord

createVenueOnboardingInvitationRecord :: (?modelContext :: ModelContext) => Maybe User -> Text -> IO VenueOnboardingInvitation
createVenueOnboardingInvitationRecord = ApplicationFixture.createVenueOnboardingInvitationRecord

createStaffRecord :: (?modelContext :: ModelContext) => Venue -> Maybe User -> Text -> Text -> IO Staff
createStaffRecord = ApplicationFixture.createIdempotentStaffRecordWithDefaults

createStaffRosterGroupRecord :: (?modelContext :: ModelContext) => Staff -> RosterGroup -> IO StaffRosterGroup
createStaffRosterGroupRecord = ApplicationFixture.createStaffRosterGroupRecord

createSlotNameRecord :: (?modelContext :: ModelContext) => Venue -> Text -> IO SlotName
createSlotNameRecord venue slotName = do
    rosterGroup <- ensureVenueDefaultRosterGroup venue
    createSlotNameRecordForRosterGroup venue rosterGroup slotName

createSlotNameRecordForRosterGroup :: (?modelContext :: ModelContext) => Venue -> RosterGroup -> Text -> IO SlotName
createSlotNameRecordForRosterGroup venue rosterGroup slotName = do
    nextSortOrder <-
        query @SlotName
            |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
            |> orderByDesc #sortOrder
            |> fetchOneOrNothing
            >>= pure . maybe 0 ((+ 1) . get #sortOrder)

    newRecord @SlotName
        |> set #venueId (unpackId (get #id venue))
        |> set #rosterGroupId (unpackId rosterGroup.id)
        |> set #name slotName
        |> set #sortOrder nextSortOrder
        |> set #isActive True
        |> createRecord

fetchSlotNameRecord :: (?modelContext :: ModelContext) => Venue -> Text -> IO SlotName
fetchSlotNameRecord venue slotName =
    query @SlotName
        |> filterWhere (#venueId, unpackId (get #id venue))
        |> filterWhere (#name, slotName)
        |> fetchOne

fetchSlotNameRecordForRosterGroup :: (?modelContext :: ModelContext) => RosterGroup -> Text -> IO SlotName
fetchSlotNameRecordForRosterGroup rosterGroup slotName =
    query @SlotName
        |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
        |> filterWhere (#name, slotName)
        |> fetchOne

data TestRosterWindow = TestRosterWindow
    { fixtureVenueId           :: !UUID
    , fixtureRosterGroupId     :: !UUID
    , fixtureWindowStart       :: !Day
    , fixtureWindowIsPublished :: !Bool
    }
    deriving (Eq, Show)

fromApplicationRosterWindow :: ApplicationFixture.FixtureRosterWindow -> TestRosterWindow
fromApplicationRosterWindow rosterWindow = TestRosterWindow
    { fixtureVenueId = rosterWindow.fixtureVenueId
    , fixtureRosterGroupId = rosterWindow.fixtureRosterGroupId
    , fixtureWindowStart = rosterWindow.fixtureWindowStart
    , fixtureWindowIsPublished = rosterWindow.fixtureWindowIsPublished
    }

toApplicationRosterWindow :: TestRosterWindow -> ApplicationFixture.FixtureRosterWindow
toApplicationRosterWindow rosterWindow = ApplicationFixture.FixtureRosterWindow
    { fixtureVenueId = rosterWindow.fixtureVenueId
    , fixtureRosterGroupId = rosterWindow.fixtureRosterGroupId
    , fixtureWindowStart = rosterWindow.fixtureWindowStart
    , fixtureWindowIsPublished = rosterWindow.fixtureWindowIsPublished
    }

createRosterWeekRecord :: (?modelContext :: ModelContext) => Venue -> Int -> Bool -> IO TestRosterWindow
createRosterWeekRecord venue windowIndex isPublished = do
    rosterWeek <- fromApplicationRosterWindow <$> ApplicationFixture.createRosterWeekRecord venue (testAnchorForOffset windowIndex) isPublished
    when isPublished (void (mapM (ApplicationFixture.createRosterDayRecord (toApplicationRosterWindow rosterWeek)) [0 .. 6]))
    pure rosterWeek

createRosterWeekRecordForRosterGroup :: (?modelContext :: ModelContext) => Venue -> RosterGroup -> Int -> Bool -> IO TestRosterWindow
createRosterWeekRecordForRosterGroup venue rosterGroup windowIndex isPublished =
    createRosterWindowRecordForRosterGroupAt venue rosterGroup (testAnchorForOffset windowIndex) isPublished

createRosterWindowRecordForRosterGroupAt :: (?modelContext :: ModelContext) => Venue -> RosterGroup -> Day -> Bool -> IO TestRosterWindow
createRosterWindowRecordForRosterGroupAt venue rosterGroup windowStart isPublished = do
    rosterWindow <- fromApplicationRosterWindow <$> ApplicationFixture.createRosterWeekRecordForRosterGroup venue rosterGroup windowStart isPublished
    when isPublished (void (mapM (ApplicationFixture.createRosterDayRecord (toApplicationRosterWindow rosterWindow)) [0 .. 6]))
    pure rosterWindow

fetchTestRosterWindowDays :: (?modelContext :: ModelContext) => TestRosterWindow -> IO [RosterDay]
fetchTestRosterWindowDays rosterWindow =
    query @RosterDay
        |> filterWhere (#venueId, rosterWindow.fixtureVenueId)
        |> filterWhere (#rosterGroupId, rosterWindow.fixtureRosterGroupId)
        |> filterWhereGreaterThanOrEqualTo (#operationalDate, rosterWindow.fixtureWindowStart)
        |> filterWhereLessThan (#operationalDate, addDays 7 rosterWindow.fixtureWindowStart)
        |> orderByAsc #operationalDate
        |> fetch

createRosterDayRecord :: (?modelContext :: ModelContext) => TestRosterWindow -> Int -> IO RosterDay
createRosterDayRecord rosterWindow dayIndex = do
    let operationalDate = addDays (toInteger dayIndex) rosterWindow.fixtureWindowStart
    existing <- query @RosterDay
        |> filterWhere (#venueId, rosterWindow.fixtureVenueId)
        |> filterWhere (#rosterGroupId, rosterWindow.fixtureRosterGroupId)
        |> filterWhere (#operationalDate, operationalDate)
        |> fetchOneOrNothing
    maybe (ApplicationFixture.createRosterDayRecord (toApplicationRosterWindow rosterWindow) dayIndex) pure existing

createNativeRosterDayRecord :: (?modelContext :: ModelContext) => Venue -> RosterGroup -> Day -> Int -> IO RosterDay
createNativeRosterDayRecord venue rosterGroup operationalDate _dayIndex =
    newRecord @RosterDay
        |> set #venueId (unpackId venue.id)
        |> set #rosterGroupId (unpackId rosterGroup.id)
        |> set #operationalDate operationalDate
        |> set #publicationState Draft
        |> createRecord

createRosterSlotRecord :: (?modelContext :: ModelContext) => RosterDay -> SlotName -> Maybe Staff -> Int -> IO RosterSlot
createRosterSlotRecord rosterDay slotName maybeStaff rowIndex =
    ApplicationFixture.createRosterSlotRecord rosterDay slotName assignment rowIndex
  where
    assignment = maybe OpenAssignment (StaffAssignment . (.id)) maybeStaff

fetchRosterLaneForDefinition :: (?modelContext :: ModelContext) => RosterDay -> RosterLane -> IO RosterLane
fetchRosterLaneForDefinition rosterDay rosterLane =
    query @RosterLane
        |> filterWhere (#rosterDayId, unpackId rosterDay.id)
        |> filterWhere (#name, rosterLane.name)
        |> filterWhere (#deletedAt, Nothing)
        |> fetchOne

createCompleteRosterSlotRecord :: (?modelContext :: ModelContext) => RosterDay -> SlotName -> Staff -> Int -> IO RosterSlot
createCompleteRosterSlotRecord rosterDay slotName staff rowIndex = do
    venue <- fetch (Id rosterDay.venueId :: Id Venue)
    shiftType <- ensureVenueDefaultShiftType venue
    createRosterSlotRecord rosterDay slotName (Just staff) rowIndex
        >>= updateRecord
            . set #shiftTypeId (Just (unpackId shiftType.id))
            . setTestRosterSlotBoundaries (fromGregorian 2025 1 6) (TimeOfDay 9 0 0) (TimeOfDay 17 0 0)

ensureRosterWeekSlotDefinitionForSlotName :: (?modelContext :: ModelContext) => RosterDay -> SlotName -> IO RosterLane
ensureRosterWeekSlotDefinitionForSlotName = ApplicationFixture.ensureRosterLaneForSlotName

createTimesheetEntryRecord :: (?modelContext :: ModelContext) => Venue -> Staff -> Day -> IO TimesheetEntry
createTimesheetEntryRecord venue staff workedOn =
    ApplicationFixture.createTimesheetEntryRecordWithDefaultLevelName
        venue
        staff
        workedOn
        ("Default Level " <> tshow venue.id)

createApprovedTimesheetEntryRecord :: (?modelContext :: ModelContext) => Venue -> Staff -> User -> Day -> IO TimesheetEntry
createApprovedTimesheetEntryRecord venue staff approver workedOn = do
    approvedAt <- getCurrentTime
    createApprovedTimesheetEntryRecordAt venue staff approver workedOn approvedAt

createApprovedTimesheetEntryRecordAt :: (?modelContext :: ModelContext) => Venue -> Staff -> User -> Day -> UTCTime -> IO TimesheetEntry
withLegacyPayBackfillFixture :: (?modelContext :: ModelContext) => IO value -> IO value
withLegacyPayBackfillFixture action =
    bracket
        (sqlExecDiscardResult "ALTER TABLE timesheet_entries DISABLE TRIGGER prevent_legacy_pay_backfill_grant" ())
        (const (sqlExecDiscardResult "ALTER TABLE timesheet_entries ENABLE TRIGGER prevent_legacy_pay_backfill_grant" ()))
        (const action)

createApprovedTimesheetEntryRecordAt venue staff approver workedOn approvedAt = do
    shiftType <- ensureVenueDefaultShiftType venue
    createApprovedTimesheetEntryRecordAtWithShiftTimes
        venue
        staff
        approver
        shiftType
        workedOn
        approvedAt
        (TimeOfDay 9 0 0)
        (TimeOfDay 17 0 0)

createApprovedTimesheetEntryRecordAtWithShiftTimes ::
    (?modelContext :: ModelContext) =>
    Venue ->
    Staff ->
    User ->
    ShiftType ->
    Day ->
    UTCTime ->
    TimeOfDay ->
    TimeOfDay ->
    IO TimesheetEntry
createApprovedTimesheetEntryRecordAtWithShiftTimes venue staff approver shiftType workedOn approvedAt startTime endTime = do
    ensureFreshWageSourceFacts workedOn
    let boundaries =
            either (error . ("Invalid approved test support timesheet boundaries: " <>) . show) Prelude.id $
                resolveShiftBoundaries melbourneTimeZoneName ShiftBoundaryInput
                    { shiftBoundaryDate = workedOn
                    , shiftBoundaryStartTime = startTime
                    , shiftBoundaryStartOccurrence = Nothing
                    , shiftBoundaryEndTime = endTime
                    , shiftBoundaryEndOccurrence = Nothing
                    , shiftBoundaryBreak = Nothing
                    }
    entry <- newRecord @TimesheetEntry
        |> set #venueId (unpackId venue.id)
        |> set #staffId (unpackId staff.id)
        |> set #shiftTypeId (unpackId shiftType.id)
        |> set #operationalDate workedOn
        |> applyTimesheetEntryBoundaries boundaries
        |> createRecord
    (staffPayVersion, shiftTypePayVersion) <- ensurePayVersionsForTimesheetApproval approver.id entry
    lockPayVersionsForApproval approver.id approvedAt staffPayVersion shiftTypePayVersion
    approvedEntry <- withLegacyPayBackfillFixture do
        entry
            |> set #isApproved True
            |> set #legacyPayBackfillPending True
            |> set #staffPayVersionId (Just (unpackId staffPayVersion.id))
            |> set #shiftTypePayVersionId (Just (unpackId shiftTypePayVersion.id))
            |> set #approvedAt (Just approvedAt)
            |> set #approvedByUserId (Just (unpackId approver.id))
            |> updateRecord
    sealApprovedFixtureCalculation approvedEntry

createLeaveRequestRecord :: (?modelContext :: ModelContext) => Venue -> Staff -> Day -> Day -> LeaveRequestStatusEnum -> IO LeaveRequest
createLeaveRequestRecord = ApplicationFixture.createLeaveRequestRecord


createPayLevelRecord :: (?modelContext :: ModelContext) => Venue -> Text -> IO AwardLevel
createPayLevelRecord = ApplicationFixture.createPayLevelRecord

createPayLevelRecordWithRates ::
    (?modelContext :: ModelContext) =>
    Venue ->
    Text ->
    Scientific ->
    Scientific ->
    Scientific ->
    Scientific ->
    Scientific ->
    Scientific ->
    IO AwardLevel
createPayLevelRecordWithRates = ApplicationFixture.createPayLevelRecordWithRates

createShiftTypeRecord :: (?modelContext :: ModelContext) => Venue -> AwardLevel -> Text -> IO ShiftType
createShiftTypeRecord = ApplicationFixture.createShiftTypeRecord



createPayLevelDayRuleRecord :: (?modelContext :: ModelContext) => ShiftType -> DayName -> AwardLevel -> IO ShiftType
createPayLevelDayRuleRecord = ApplicationFixture.createPayLevelDayRuleRecord

ensureVenueDefaultShiftType :: (?modelContext :: ModelContext) => Venue -> IO ShiftType
ensureVenueDefaultShiftType venue =
    ApplicationFixture.ensureVenueDefaultShiftTypeWithLevelName venue ("Default Level " <> tshow venue.id)

ensureProfileCompleteStaffRecord :: (?modelContext :: ModelContext) => Venue -> User -> IO Staff
ensureProfileCompleteStaffRecord = ApplicationFixture.ensureProfileCompleteStaffRecord

withUserAndCurrentVenue ::
    forall result.
    (?mocking :: MockContext WebApplication, ?request :: Wai.Request) =>
    User ->
    Id Venue ->
    ((?request :: Wai.Request) => IO result) ->
    IO result
withUserAndCurrentVenue user venueId callback =
    withSessionValues
        [ (cs (LoginSupport.sessionKey @User), Serialize.encode user.id)
        , (currentVenueSessionKey, Serialize.encode venueId)
        ]
        callback

withPasskeyVerifiedUser ::
    forall result.
    (?mocking :: MockContext WebApplication, ?modelContext :: ModelContext, ?request :: Wai.Request) =>
    User ->
    ((?request :: Wai.Request) => IO result) ->
    IO result
withPasskeyVerifiedUser user callback = do
    ensureTestUserHasPasskey user
    now <- getCurrentTime
    withSessionValues
        [ (cs (LoginSupport.sessionKey @User), Serialize.encode user.id)
        , (passkeyVerifiedUserSessionKey, Serialize.encode (inputValue user.id :: Text))
        , (passkeyVerifiedAtSessionKey, Serialize.encode (formatPasskeyVerifiedAt now))
        ]
        callback

withPasskeyVerifiedUserAndCurrentVenue ::
    forall result.
    (?mocking :: MockContext WebApplication, ?modelContext :: ModelContext, ?request :: Wai.Request) =>
    User ->
    Id Venue ->
    ((?request :: Wai.Request) => IO result) ->
    IO result
withPasskeyVerifiedUserAndCurrentVenue user venueId callback = do
    ensureTestUserHasPasskey user
    now <- getCurrentTime
    withSessionValues
        [ (cs (LoginSupport.sessionKey @User), Serialize.encode user.id)
        , (currentVenueSessionKey, Serialize.encode venueId)
        , (passkeyVerifiedUserSessionKey, Serialize.encode (inputValue user.id :: Text))
        , (passkeyVerifiedAtSessionKey, Serialize.encode (formatPasskeyVerifiedAt now))
        ]
        callback

ensureTestUserHasPasskey :: (?modelContext :: ModelContext) => User -> IO ()
ensureTestUserHasPasskey user = do
    hasPasskey <-
        query @Passkey
            |> filterWhere (#userId, unpackId user.id)
            |> fetchExists
    unless hasPasskey do
        void (createTestPasskeyRecord user "Test passkey")

withSessionValues ::
    forall result.
    (?mocking :: MockContext WebApplication, ?request :: Wai.Request) =>
    [(ByteString.ByteString, ByteString.ByteString)] ->
    ((?request :: Wai.Request) => IO result) ->
    IO result
withSessionValues initialValues callback = do
    store <- newIORef (Map.fromList initialValues)
    let ?request = requestWithSession store
    callback
    where
        requestWithSession store =
            ?request { Wai.vault = Vault.insert sessionVaultKey (newSession store) (Wai.vault ?request) }

        newSession :: IORef (Map.Map ByteString.ByteString ByteString.ByteString) -> WaiSession.Session IO ByteString.ByteString ByteString.ByteString
        newSession store = (lookupSession store, insertSession store)

        lookupSession store key = Map.lookup key <$> readIORef store

        insertSession store key value = modifyIORef' store (Map.insert key value)

withRequestHeaders ::
    forall result.
    (?request :: Wai.Request) =>
    RequestHeaders ->
    ((?request :: Wai.Request) => IO result) ->
    IO result
withRequestHeaders headers callback = do
    let request' =
            ?request
                { Wai.requestHeaders = headers <> Wai.requestHeaders ?request
                }
    let ?request = request'
    callback

defaultWeekEpoch :: Day
defaultWeekEpoch = ApplicationFixture.defaultWeekEpoch

testAnchorForOffset :: Int -> Day
testAnchorForOffset windowIndex = addDays (toInteger (windowIndex * 7)) defaultWeekEpoch

testWindowIndexForDay :: Day -> Int
testWindowIndexForDay day = fromInteger (diffDays day defaultWeekEpoch `div` 7)

rosterCopyParams :: Int -> Int -> [(ByteString.ByteString, ByteString.ByteString)]
rosterCopyParams sourceOffset targetOffset =
    [ ("sourceAnchorDate", cs (show (testAnchorForOffset sourceOffset)))
    , ("targetAnchorDate", cs (show (testAnchorForOffset targetOffset)))
    , ("rosterCalendarRevision", "1")
    ]

rosterNotificationParams :: TestRosterWindow -> [(ByteString.ByteString, ByteString.ByteString)]
rosterNotificationParams rosterWeek =
    [ ("rosterGroupId", cs (show rosterWeek.fixtureRosterGroupId))
    , ("windowStartDate", cs (show windowStart))
    , ("windowEndDate", cs (show (addDays 7 windowStart)))
    , ("rosterCalendarRevision", "1")
    ]
  where
    windowStart = rosterWeek.fixtureWindowStart

rosterMutationParams :: Int -> [(ByteString.ByteString, ByteString.ByteString)]
rosterMutationParams weekOffset =
    [ ("anchorDate", cs (show (testAnchorForOffset weekOffset)))
    , ("rosterCalendarRevision", "1")
    ]

testPassword :: Text
testPassword = "test-password-123"

-- Precomputed exclusively for test fixture construction. Authentication tests
-- still exercise IHP's real password verifier against this valid hash, while
-- user creation controller tests retain coverage of runtime password hashing.
testPasswordHash :: Text
testPasswordHash = "sha256|17|/WmoffT24t1UB8XPcp6HHQ==|iAsujD+YRqOaJWub+pGioz5nT9r6wglmf0wiNmlD5vY="
