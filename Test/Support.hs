module Test.Support where

import Application.Helper.Controller (PlatformRole (..), currentVenueSessionKey,
                                      formatPasskeyVerifiedAt,
                                      passkeyVerifiedAtSessionKey,
                                      passkeyVerifiedUserSessionKey,
                                      platformRoleToEnum, unsafeEnumFromText)
import Application.Helper.ControllerContext (initCurrentVenueContext)
import Application.Helper.Pay (ensurePayVersionsForTimesheetApproval,
                               lockPayVersionsForApproval)
import Application.Helper.RosterGroups (ensureVenueDefaultRosterGroup,
                                        ensureVenueRosterDefaults)
import Application.Helper.TimeRules (rosterShiftStartDate)
import qualified Application.Support.PayrollFixtures as Payroll
import Application.VenueTime (RepeatedTimeOccurrence (FirstOccurrence),
                              melbourneTimeZoneName)
import Application.VenueTime.Model
import Config
import Control.Applicative ((<|>))
import Control.Exception (bracket)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as ByteString
import qualified Data.Char as Char
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
import IHP.ModelSupport (sqlExecDiscardResult)
import IHP.Prelude
import qualified IHP.Prelude as Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Header (RequestHeaders)
import qualified Network.Wai as Wai
import qualified Network.Wai.Session.Maybe as WaiSession
import System.Environment (lookupEnv, setEnv, unsetEnv)
import qualified System.IO as IO
import System.IO.Unsafe (unsafePerformIO)
import Web.FrontController ()
import Web.Types

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
        let startDay = case slot.endsAt of
                Just endInstant ->
                    let endLocal = storedInstantLocalTime (testFixtureTimezone slot.timezone) endInstant
                     in addDays (if endLocal.localTimeOfDay <= startTime then (-1) else 0) endLocal.localDay
                Nothing -> rosterSlotFixtureDay slot
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
    withMockContext WebApplication config action

withPrivilegedStrongAuthentication :: Bool -> IO value -> IO value
withPrivilegedStrongAuthentication enabled action =
    bracket
        (lookupEnv variableName)
        restore
        (\_ -> setEnv variableName (if enabled then "true" else "false") >> action)
  where
    variableName = "IHP_ROSTER_REQUIRE_PRIVILEGED_STRONG_AUTH"
    restore = maybe (unsetEnv variableName) (setEnv variableName)

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
    action

resetDatabase :: (?modelContext :: ModelContext) => IO ()
resetDatabase = do
    sqlExecDiscardResult
        "TRUNCATE TABLE app_jobs, award_time_penalty_allowances, award_level_penalty_rates, award_level_base_rates, award_levels, fwc_mapd_wage_allowances, fwc_mapd_penalty_rates, fwc_mapd_pay_rates, fwc_mapd_classifications, fwc_mapd_awards, fwc_mapd_sync_runs, public_holidays, xero_timesheet_submission_entries, xero_timesheet_submissions, xero_timesheet_preparation_decisions, xero_timesheet_preparation_runs, xero_submission_runs, xero_earnings_rate_mappings, xero_staff_mappings, xero_pay_runs, xero_payroll_calendars, xero_earnings_rates, xero_employees, xero_sync_runs, xero_oauth_states, xero_connections, venue_billing_controls, billing_events, billing_checkout_attempts, venue_subscriptions, venue_billing_customers, export_jobs, user_feedback_items, audit_events, venue_membership_role_events, timesheet_entry_versions, timesheet_entries, leave_request_events, leave_requests, staff_shift_preferences, roster_slots, roster_week_slot_definitions, roster_days, roster_weeks, export_job_entries, shift_type_pay_versions, staff_pay_versions, venue_config, day_names, slot_names, staff_roster_groups, roster_groups, shift_types, staff_documents, staff, user_preferences, passkey_setup_tokens, passkey_recovery_codes, passkeys, email_verification_tokens, venue_invitations, venue_onboarding_invitations, venue_memberships, users, venues RESTART IDENTITY CASCADE"
        ()
    pure ()

createVenueWithConfig :: (?modelContext :: ModelContext) => Text -> IO Venue
createVenueWithConfig name =
    withTransaction do
        venue <- newRecord @Venue
            |> set #name name
            |> createRecord
        _ <- ensureVenueRosterDefaults venue
        pure venue

createUserRecord :: (?modelContext :: ModelContext) => Text -> Text -> Bool -> IO User
createUserRecord emailAddress globalRole isProfileCompleted =
    createUserRecordWithPlatformRole emailAddress globalRole Nothing isProfileCompleted

createUserRecordWithPlatformRole :: (?modelContext :: ModelContext) => Text -> Text -> Maybe PlatformRole -> Bool -> IO User
createUserRecordWithPlatformRole emailAddress globalRole platformRole isProfileCompleted =
    newRecord @User
        |> set #email emailAddress
        |> set #passwordHash testPasswordHash
        |> set #userRole globalRole
        |> set #platformRole (platformRoleToEnum <$> platformRole)
        |> set #isProfileCompleted isProfileCompleted
        |> set #emailVerifiedAt (Just def)
        |> createRecord

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

createVenueMembershipRecord :: (?modelContext :: ModelContext) => Venue -> User -> Text -> IO VenueMembership
createVenueMembershipRecord venue user venueRole = do
    membership <- newRecord @VenueMembership
        |> set #venueId (unpackId (get #id venue))
        |> set #userId (unpackId (get #id user))
        |> set #venueRole (unsafeEnumFromText @VenueRoleEnum venueRole)
        |> set #isActive True
        |> createRecord
    when user.isProfileCompleted do
        void (ensureProfileCompleteStaffRecord venue user)
    pure membership

createVenueInvitationRecord :: (?modelContext :: ModelContext) => Venue -> Maybe User -> Text -> Text -> IO VenueInvitation
createVenueInvitationRecord venue maybeInviter emailAddress inviteRole =
    newRecord @VenueInvitation
        |> set #venueId (unpackId (get #id venue))
        |> set #invitedByUserId (fmap (unpackId . get #id) maybeInviter)
        |> set #email emailAddress
        |> set #inviteRole (unsafeEnumFromText @VenueRoleEnum inviteRole)
        |> set #status (unsafeEnumFromText @InvitationStatusEnum "pending")
        |> createRecord

createVenueOnboardingInvitationRecord :: (?modelContext :: ModelContext) => Maybe User -> Text -> IO VenueOnboardingInvitation
createVenueOnboardingInvitationRecord maybeInviter emailAddress =
    newRecord @VenueOnboardingInvitation
        |> set #invitedByUserId (fmap (unpackId . get #id) maybeInviter)
        |> set #email emailAddress
        |> set #status (unsafeEnumFromText @InvitationStatusEnum "pending")
        |> createRecord

createStaffRecord :: (?modelContext :: ModelContext) => Venue -> Maybe User -> Text -> Text -> IO Staff
createStaffRecord venue maybeUser firstName lastName = do
    staff <- case maybeUser of
        Just user -> do
            existingStaff <- query @Staff
                |> filterWhere (#venueId, unpackId (get #id venue))
                |> filterWhere (#userId, Just (unpackId (get #id user)))
                |> fetchOneOrNothing
            case existingStaff of
                Just existingStaff ->
                    existingStaff
                        |> set #firstName firstName
                        |> set #lastName lastName
                        |> set #preferredName Nothing
                        |> set #phone "0400000000"
                        |> set #emergencyContactName "Emergency Contact"
                        |> set #emergencyContactPhone "0411111111"
                        |> set #idealShiftsPerWeek 0
                        |> set #isActive True
                        |> updateRecord
                Nothing ->
                    createLinkedStaffRecord venue user firstName lastName
        Nothing ->
            newRecord @Staff
                |> set #venueId (unpackId (get #id venue))
                |> set #userId Nothing
                |> set #firstName firstName
                |> set #lastName lastName
                |> set #preferredName Nothing
                |> set #phone "0400000000"
                |> set #emergencyContactName "Emergency Contact"
                |> set #emergencyContactPhone "0411111111"
                |> set #idealShiftsPerWeek 0
                |> set #isActive True
                |> createRecord
    _ <- ensureStaffDefaultRosterGroup venue staff
    pure staff

createStaffRosterGroupRecord :: (?modelContext :: ModelContext) => Staff -> RosterGroup -> IO StaffRosterGroup
createStaffRosterGroupRecord staff rosterGroup =
    newRecord @StaffRosterGroup
        |> set #staffId (unpackId (get #id staff))
        |> set #rosterGroupId (unpackId (get #id rosterGroup))
        |> createRecord

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

createRosterWeekRecord :: (?modelContext :: ModelContext) => Venue -> Int -> Bool -> IO RosterWeek
createRosterWeekRecord venue weekOffset isLive = do
    rosterGroup <- ensureVenueDefaultRosterGroup venue
    createRosterWeekRecordForRosterGroup venue rosterGroup weekOffset isLive

createRosterWeekRecordForRosterGroup :: (?modelContext :: ModelContext) => Venue -> RosterGroup -> Int -> Bool -> IO RosterWeek
createRosterWeekRecordForRosterGroup venue rosterGroup weekOffset isLive =
    newRecord @RosterWeek
        |> set #venueId (unpackId (get #id venue))
        |> set #rosterGroupId (unpackId rosterGroup.id)
        |> set #weekOffset weekOffset
        |> set #isLive isLive
        |> createRecord

createRosterDayRecord :: (?modelContext :: ModelContext) => RosterWeek -> Int -> IO RosterDay
createRosterDayRecord rosterWeek dayOffset =
    newRecord @RosterDay
        |> set #rosterWeekId (unpackId (get #id rosterWeek))
        |> set #dayOffset dayOffset
        |> set #isClosed False
        |> createRecord

createRosterSlotRecord :: (?modelContext :: ModelContext) => RosterDay -> SlotName -> Maybe Staff -> Int -> IO RosterSlot
createRosterSlotRecord rosterDay slotName maybeStaff rowIndex = do
    slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay slotName
    newRecord @RosterSlot
        |> set #rosterDayId (unpackId (get #id rosterDay))
        |> set #rosterWeekSlotDefinitionId (unpackId (get #id slotDefinition))
        |> set #slotSortOrder slotDefinition.sortOrder
        |> set #staffId (fmap (unpackId . get #id) maybeStaff)
        |> set #rowIndex rowIndex
        |> set #timezone melbourneTimeZoneName
        |> createRecord

ensureRosterWeekSlotDefinitionForSlotName :: (?modelContext :: ModelContext) => RosterDay -> SlotName -> IO RosterWeekSlotDefinition
ensureRosterWeekSlotDefinitionForSlotName rosterDay slotName = do
    existing <- query @RosterWeekSlotDefinition
        |> filterWhere (#rosterWeekId, rosterDay.rosterWeekId)
        |> filterWhere (#name, slotName.name)
        |> filterWhere (#deletedAt, Nothing)
        |> fetchOneOrNothing
    case existing of
        Just slotDefinition -> pure slotDefinition
        Nothing ->
            newRecord @RosterWeekSlotDefinition
                |> set #rosterWeekId rosterDay.rosterWeekId
                |> set #name slotName.name
                |> set #sortOrder slotName.sortOrder
                |> createRecord

createTimesheetEntryRecord :: (?modelContext :: ModelContext) => Venue -> Staff -> Day -> IO TimesheetEntry
createTimesheetEntryRecord venue staff workedOn = do
    shiftType <- ensureVenueDefaultShiftType venue
    let boundaries =
            either (error . ("Invalid test support timesheet boundaries: " <>) . show) Prelude.id $
                resolveShiftBoundaries melbourneTimeZoneName ShiftBoundaryInput
                    { shiftBoundaryDate = workedOn
                    , shiftBoundaryStartTime = TimeOfDay 9 0 0
                    , shiftBoundaryStartOccurrence = Nothing
                    , shiftBoundaryEndTime = TimeOfDay 17 0 0
                    , shiftBoundaryEndOccurrence = Nothing
                    , shiftBoundaryBreak = Nothing
                    }
    newRecord @TimesheetEntry
        |> set #venueId (unpackId (get #id venue))
        |> set #staffId (unpackId (get #id staff))
        |> set #shiftTypeId (unpackId (get #id shiftType))
        |> applyTimesheetEntryBoundaries boundaries
        |> createRecord

createApprovedTimesheetEntryRecord :: (?modelContext :: ModelContext) => Venue -> Staff -> User -> Day -> IO TimesheetEntry
createApprovedTimesheetEntryRecord venue staff approver workedOn = do
    approvedAt <- getCurrentTime
    createApprovedTimesheetEntryRecordAt venue staff approver workedOn approvedAt

createApprovedTimesheetEntryRecordAt :: (?modelContext :: ModelContext) => Venue -> Staff -> User -> Day -> UTCTime -> IO TimesheetEntry
createApprovedTimesheetEntryRecordAt venue staff approver workedOn approvedAt = do
    entry <- createTimesheetEntryRecord venue staff workedOn
    (staffPayVersion, shiftTypePayVersion) <- ensurePayVersionsForTimesheetApproval approver.id entry
    lockPayVersionsForApproval approver.id approvedAt staffPayVersion shiftTypePayVersion
    entry
        |> set #isApproved True
        |> set #staffPayVersionId (Just (unpackId staffPayVersion.id))
        |> set #shiftTypePayVersionId (Just (unpackId shiftTypePayVersion.id))
        |> set #approvedAt (Just approvedAt)
        |> set #approvedByUserId (Just (unpackId approver.id))
        |> updateRecord

createLeaveRequestRecord :: (?modelContext :: ModelContext) => Venue -> Staff -> Day -> Day -> Text -> IO LeaveRequest
createLeaveRequestRecord venue staff startDate endDate leaveStatus =
    createLeaveRequestRecordWithNotes venue staff startDate endDate leaveStatus Nothing

createLeaveRequestRecordWithNotes :: (?modelContext :: ModelContext) => Venue -> Staff -> Day -> Day -> Text -> Maybe Text -> IO LeaveRequest
createLeaveRequestRecordWithNotes venue staff startDate endDate leaveStatus notes =
    newRecord @LeaveRequest
        |> set #venueId (unpackId (get #id venue))
        |> set #staffId (unpackId (get #id staff))
        |> set #startDate startDate
        |> set #endDate endDate
        |> set #status (unsafeEnumFromText @LeaveRequestStatusEnum leaveStatus)
        |> set #notes notes
        |> createRecord

createPayLevelRecord :: (?modelContext :: ModelContext) => Venue -> Text -> IO AwardLevel
createPayLevelRecord venue levelName =
    createPayLevelRecordWithRates venue levelName 0 0 0 1 1 1

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
createPayLevelRecordWithRates venue levelName baseRate eveningPenalty after12Penalty weekdayMultiplier saturdayMultiplier sundayMultiplier =
    createAwardLevelRecordWithRates levelName baseRate eveningPenalty after12Penalty saturdayMultiplier sundayMultiplier

createAwardLevelRecordWithRates :: (?modelContext :: ModelContext) => Text -> Scientific -> Scientific -> Scientific -> Scientific -> Scientific -> IO AwardLevel
createAwardLevelRecordWithRates levelName baseRate eveningPenalty after12Penalty saturdayMultiplier sundayMultiplier = do
    let classificationFixedId = awardLevelClassificationFixedId levelName
    awardLevel <-
        newRecord @AwardLevel
            |> set #awardFixedId 9
            |> set #classificationFixedId classificationFixedId
            |> set #classification levelName
            |> set #isActive True
            |> createRecord
    payRate <-
        newRecord @FwcMapdPayRate
            |> set #awardFixedId 9
            |> set #classificationFixedId (Just awardLevel.classificationFixedId)
            |> set #classification levelName
            |> set #employeeRateTypeCode (Just "AD")
            |> set #calculatedRate (Just baseRate)
            |> set #calculatedRateType (Just "Hourly")
            |> createRecord
    void
        ( newRecord @AwardLevelBaseRate
            |> set #awardLevelId (unpackId awardLevel.id)
            |> set #employmentBasis Permanent
            |> set #fwcMapdPayRateId (unpackId payRate.id)
            |> set #hourlyRate baseRate
            |> set #rateLabel ("Hourly" :: Text)
            |> createRecord
        )
    createSyntheticPenalty awardLevel SaturdayPenalty payRate (baseRate * saturdayMultiplier)
    createSyntheticPenalty awardLevel SundayPenalty payRate (baseRate * sundayMultiplier)
    createSyntheticPenalty awardLevel EveningAfter7Pm payRate (baseRate + eveningPenalty)
    createSyntheticPenalty awardLevel LateNightAfterMidnight payRate (baseRate + after12Penalty)
    createSyntheticTimeAllowanceIfMissing awardLevel EveningAfter7Pm eveningPenalty
    createSyntheticTimeAllowanceIfMissing awardLevel LateNightAfterMidnight after12Penalty
    pure awardLevel

awardLevelClassificationFixedId :: Text -> Int
awardLevelClassificationFixedId levelName =
    abs (Text.foldl' (\acc ch -> acc * 31 + Char.ord ch) 7 levelName)

createSyntheticPenalty :: (?modelContext :: ModelContext) => AwardLevel -> AwardPenaltyKindEnum -> FwcMapdPayRate -> Scientific -> IO ()
createSyntheticPenalty awardLevel penaltyKind payRate hourlyRate = do
    penaltyRate <-
        newRecord @FwcMapdPenaltyRate
            |> set #awardFixedId awardLevel.awardFixedId
            |> set #classificationFixedId (Just awardLevel.classificationFixedId)
            |> set #classification awardLevel.classification
            |> set #employeeRateTypeCode (Just "AD")
            |> set #basePayRateId payRate.basePayRateId
            |> set #penaltyDescription (Just (inputValue penaltyKind))
            |> set #penaltyCalculatedValue (Just hourlyRate)
            |> createRecord
    void
        ( newRecord @AwardLevelPenaltyRate
            |> set #awardLevelId (unpackId awardLevel.id)
            |> set #employmentBasis Permanent
            |> set #penaltyKind penaltyKind
            |> set #fwcMapdPenaltyRateId (unpackId penaltyRate.id)
            |> set #hourlyRate hourlyRate
            |> createRecord
        )

createSyntheticTimeAllowanceIfMissing :: (?modelContext :: ModelContext) => AwardLevel -> AwardPenaltyKindEnum -> Scientific -> IO ()
createSyntheticTimeAllowanceIfMissing awardLevel penaltyKind hourlyAmount =
    when (hourlyAmount > 0) do
        existingAllowance <- query @AwardTimePenaltyAllowance
            |> filterWhere (#awardFixedId, awardLevel.awardFixedId)
            |> filterWhere (#penaltyKind, penaltyKind)
            |> fetchOneOrNothing
        case existingAllowance of
            Just _ -> pure ()
            Nothing -> do
                wageAllowance <-
                    newRecord @FwcMapdWageAllowance
                        |> set #awardFixedId awardLevel.awardFixedId
                        |> set #allowance (Just (inputValue penaltyKind))
                        |> set #allowanceAmount (Just hourlyAmount)
                        |> createRecord
                void
                    ( newRecord @AwardTimePenaltyAllowance
                        |> set #awardFixedId awardLevel.awardFixedId
                        |> set #penaltyKind penaltyKind
                        |> set #fwcMapdWageAllowanceId (unpackId wageAllowance.id)
                        |> set #hourlyAmount hourlyAmount
                        |> createRecord
                    )

createShiftTypeRecord :: (?modelContext :: ModelContext) => Venue -> AwardLevel -> Text -> IO ShiftType
createShiftTypeRecord venue awardLevel shiftTypeName =
    newRecord @ShiftType
        |> set #venueId (unpackId (get #id venue))
        |> set #name shiftTypeName
        |> set #sortOrder 0
        |> set #overrideAwardLevelId (Just awardLevel.id)
        |> set #isActive True
        |> createRecord

createDayNameRecord :: (?modelContext :: ModelContext) => Venue -> Int -> Text -> IO DayName
createDayNameRecord venue weekdayIndex dayName =
    newRecord @DayName
        |> set #venueId (unpackId (get #id venue))
        |> set #weekdayIndex weekdayIndex
        |> set #name dayName
        |> set #isActive True
        |> createRecord

fetchDayNameRecord :: (?modelContext :: ModelContext) => Venue -> Int -> IO DayName
fetchDayNameRecord venue weekdayIndex =
    query @DayName
        |> filterWhere (#venueId, unpackId (get #id venue))
        |> filterWhere (#weekdayIndex, weekdayIndex)
        |> fetchOne

createPayLevelDayRuleRecord :: (?modelContext :: ModelContext) => ShiftType -> DayName -> AwardLevel -> IO ShiftType
createPayLevelDayRuleRecord shiftType _dayName awardLevel =
    shiftType
        |> set #overrideAwardLevelId (Just awardLevel.id)
        |> updateRecord

ensureVenueDefaultShiftType :: (?modelContext :: ModelContext) => Venue -> IO ShiftType
ensureVenueDefaultShiftType venue = do
    query @ShiftType
        |> filterWhere (#venueId, unpackId (get #id venue))
        |> orderByAsc #createdAt
        |> fetchOneOrNothing
        >>= \case
            Just shiftType -> pure shiftType
            Nothing -> do
                payLevel <- createPayLevelRecord venue ("Default Level " <> tshow venue.id)
                createShiftTypeRecord venue payLevel "Default Shift"

ensureProfileCompleteStaffRecord :: (?modelContext :: ModelContext) => Venue -> User -> IO Staff
ensureProfileCompleteStaffRecord venue user =
    createStaffRecord venue (Just user) "Profile" "Complete"

createLinkedStaffRecord :: (?modelContext :: ModelContext) => Venue -> User -> Text -> Text -> IO Staff
createLinkedStaffRecord venue user firstName lastName =
    newRecord @Staff
        |> set #venueId (unpackId (get #id venue))
        |> set #userId (Just (unpackId (get #id user)))
        |> set #firstName firstName
        |> set #lastName lastName
        |> set #preferredName Nothing
        |> set #phone "0400000000"
        |> set #emergencyContactName "Emergency Contact"
        |> set #emergencyContactPhone "0411111111"
        |> set #idealShiftsPerWeek 0
        |> set #isActive True
        |> createRecord

ensureStaffDefaultRosterGroup :: (?modelContext :: ModelContext) => Venue -> Staff -> IO StaffRosterGroup
ensureStaffDefaultRosterGroup venue staff = do
    defaultRosterGroup <- ensureVenueDefaultRosterGroup venue
    existingAssignment <- query @StaffRosterGroup
        |> filterWhere (#staffId, unpackId (get #id staff))
        |> filterWhere (#rosterGroupId, unpackId (get #id defaultRosterGroup))
        |> fetchOneOrNothing
    case existingAssignment of
        Just assignment -> pure assignment
        Nothing         -> createStaffRosterGroupRecord staff defaultRosterGroup

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
defaultWeekEpoch = fromGregorian 2025 1 6

testPassword :: Text
testPassword = "test-password-123"

-- Precomputed exclusively for test fixture construction. Authentication tests
-- still exercise IHP's real password verifier against this valid hash, while
-- user creation controller tests retain coverage of runtime password hashing.
testPasswordHash :: Text
testPasswordHash = "sha256|17|/WmoffT24t1UB8XPcp6HHQ==|iAsujD+YRqOaJWub+pGioz5nT9r6wglmf0wiNmlD5vY="
