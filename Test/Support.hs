module Test.Support where

import Application.Helper.RosterGroups (ensureVenueDefaultRosterGroup,
                                        ensureVenueRosterDefaults)
import Application.Helper.Controller (PlatformRole (..),
                                      currentVenueSessionKey,
                                      platformRoleToEnum,
                                      unsafeEnumFromText)
import Config
import qualified Data.Aeson as Aeson
import qualified Data.ByteString as ByteString
import Data.IORef (IORef, modifyIORef', newIORef, readIORef)
import qualified Data.Map.Strict as Map
import Data.Scientific (Scientific)
import qualified Data.Serialize as Serialize
import Data.Time.Calendar (Day, fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))
import qualified Data.Vault.Lazy as Vault
import Generated.Types
import IHP.ApplicationContext (ApplicationContext)
import IHP.Controller.Context (ControllerContext, newControllerContext)
import IHP.Controller.RequestContext (RequestContext (..))
import IHP.Controller.Session (sessionVaultKey)
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import qualified IHP.LoginSupport.Helper.Controller as LoginSupport
import IHP.ModelSupport (sqlExec)
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Header (RequestHeaders)
import qualified Network.Wai as Wai
import qualified Network.Wai.Session
import Web.FrontController ()
import Web.Types

testContext :: IO (MockContext WebApplication)
testContext = mockContextNoDatabase WebApplication config

withCleanDb :: (?modelContext :: ModelContext) => IO a -> IO a
withCleanDb action = do
    resetDatabase
    action

withControllerTestContext ::
    (?mocking :: MockContext WebApplication) =>
    ((?context :: ControllerContext) => IO a) ->
    ((?context :: RequestContext) => IO a)
withControllerTestContext action =
    withSessionValues [] do
        let ?requestContext = ?context
        controllerContext <- newControllerContext
        let ?context = controllerContext
        action

resetDatabase :: (?modelContext :: ModelContext) => IO ()
resetDatabase = do
    sqlExec
        "TRUNCATE TABLE export_jobs, audit_events, venue_membership_role_events, timesheet_entry_versions, timesheet_entries, leave_request_events, leave_requests, staff_shift_preferences, staff_availability, roster_slots, roster_days, roster_weeks, pay_config_snapshots, venue_config, report_definition_shift_type_filters, report_definitions, day_names, slot_names, staff_roster_groups, roster_groups, shift_types, pay_levels, staff, venue_invitations, venue_memberships, users, venues RESTART IDENTITY CASCADE"
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
createUserRecordWithPlatformRole emailAddress globalRole platformRole isProfileCompleted = do
    passwordHash <- hashPassword testPassword
    newRecord @User
        |> set #email emailAddress
        |> set #passwordHash passwordHash
        |> set #userRole globalRole
        |> set #platformRole (platformRoleToEnum <$> platformRole)
        |> set #isProfileCompleted isProfileCompleted
        |> createRecord

createVenueMembershipRecord :: (?modelContext :: ModelContext) => Venue -> User -> Text -> IO VenueMembership
createVenueMembershipRecord venue user venueRole =
    newRecord @VenueMembership
        |> set #venueId (unpackId (get #id venue))
        |> set #userId (unpackId (get #id user))
        |> set #venueRole (unsafeEnumFromText @VenueRoleEnum venueRole)
        |> set #isActive True
        |> createRecord

createVenueInvitationRecord :: (?modelContext :: ModelContext) => Venue -> Maybe User -> Text -> Text -> IO VenueInvitation
createVenueInvitationRecord venue maybeInviter emailAddress inviteRole =
    newRecord @VenueInvitation
        |> set #venueId (unpackId (get #id venue))
        |> set #invitedByUserId (fmap (unpackId . get #id) maybeInviter)
        |> set #email emailAddress
        |> set #inviteRole (unsafeEnumFromText @VenueRoleEnum inviteRole)
        |> set #status (unsafeEnumFromText @InvitationStatusEnum "pending")
        |> createRecord

createStaffRecord :: (?modelContext :: ModelContext) => Venue -> Maybe User -> Text -> Text -> IO Staff
createStaffRecord venue maybeUser firstName lastName = do
    staff <- newRecord @Staff
        |> set #venueId (unpackId (get #id venue))
        |> set #userId (fmap (unpackId . get #id) maybeUser)
        |> set #firstName firstName
        |> set #lastName lastName
        |> set #preferredName Nothing
        |> set #phone "0400000000"
        |> set #emergencyContactName "Emergency Contact"
        |> set #emergencyContactPhone "0411111111"
        |> set #idealShiftsPerWeek 0
        |> set #isActive True
        |> createRecord
    _ <- createStaffRosterGroupRecord staff =<< ensureVenueDefaultRosterGroup venue
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
createSlotNameRecordForRosterGroup venue rosterGroup slotName =
    newRecord @SlotName
        |> set #venueId (unpackId (get #id venue))
        |> set #rosterGroupId (unpackId rosterGroup.id)
        |> set #name slotName
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
createRosterSlotRecord rosterDay slotName maybeStaff rowIndex =
    newRecord @RosterSlot
        |> set #rosterDayId (unpackId (get #id rosterDay))
        |> set #slotNameId (unpackId (get #id slotName))
        |> set #staffId (fmap (unpackId . get #id) maybeStaff)
        |> set #rowIndex rowIndex
        |> createRecord

createTimesheetEntryRecord :: (?modelContext :: ModelContext) => Venue -> Staff -> Day -> IO TimesheetEntry
createTimesheetEntryRecord venue staff workedOn = do
    shiftType <- ensureVenueDefaultShiftType venue
    newRecord @TimesheetEntry
        |> set #venueId (unpackId (get #id venue))
        |> set #staffId (unpackId (get #id staff))
        |> set #shiftTypeId (unpackId (get #id shiftType))
        |> set #workedOn workedOn
        |> set #startTime (TimeOfDay 9 0 0)
        |> set #endTime (TimeOfDay 17 0 0)
        |> set #hadBreak False
        |> set #breakStartTime Nothing
        |> set #breakEndTime Nothing
        |> set #breakMinutes 0
        |> createRecord

createLeaveRequestRecord :: (?modelContext :: ModelContext) => Venue -> Staff -> Day -> Day -> Text -> IO LeaveRequest
createLeaveRequestRecord venue staff startDate endDate leaveStatus =
    newRecord @LeaveRequest
        |> set #venueId (unpackId (get #id venue))
        |> set #staffId (unpackId (get #id staff))
        |> set #startDate startDate
        |> set #endDate endDate
        |> set #status (unsafeEnumFromText @LeaveRequestStatusEnum leaveStatus)
        |> createRecord

createPayLevelRecord :: (?modelContext :: ModelContext) => Venue -> Text -> IO PayLevel
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
    IO PayLevel
createPayLevelRecordWithRates venue levelName baseRate eveningPenalty after12Penalty weekdayMultiplier saturdayMultiplier sundayMultiplier =
    newRecord @PayLevel
        |> set #venueId (unpackId (get #id venue))
        |> set #name levelName
        |> set #baseRate baseRate
        |> set #eveningPenalty eveningPenalty
        |> set #after12Penalty after12Penalty
        |> set #weekdayMultiplier weekdayMultiplier
        |> set #saturdayMultiplier saturdayMultiplier
        |> set #sundayMultiplier sundayMultiplier
        |> set #isActive True
        |> createRecord

createShiftTypeRecord :: (?modelContext :: ModelContext) => Venue -> PayLevel -> Text -> IO ShiftType
createShiftTypeRecord venue payLevel shiftTypeName =
    newRecord @ShiftType
        |> set #venueId (unpackId (get #id venue))
        |> set #name shiftTypeName
        |> set #sortOrder 0
        |> set #defaultPayLevelId (unpackId (get #id payLevel))
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

createPayLevelDayRuleRecord :: (?modelContext :: ModelContext) => ShiftType -> DayName -> PayLevel -> IO PayLevelDayRule
createPayLevelDayRuleRecord shiftType dayName payLevel =
    newRecord @PayLevelDayRule
        |> set #shiftTypeId (unpackId (get #id shiftType))
        |> set #payLevelId (unpackId (get #id payLevel))
        |> set #dayNameId (unpackId (get #id dayName))
        |> createRecord

ensureVenueDefaultShiftType :: (?modelContext :: ModelContext) => Venue -> IO ShiftType
ensureVenueDefaultShiftType venue = do
    query @ShiftType
        |> filterWhere (#venueId, unpackId (get #id venue))
        |> orderByAsc #createdAt
        |> fetchOneOrNothing
        >>= \case
            Just shiftType -> pure shiftType
            Nothing -> do
                payLevel <- createPayLevelRecord venue "Default Level"
                createShiftTypeRecord venue payLevel "Default Shift"

createPayConfigSnapshotRecord :: (?modelContext :: ModelContext) => Venue -> User -> Int -> Aeson.Value -> IO PayConfigSnapshot
createPayConfigSnapshotRecord venue user versionNumber snapshot =
    newRecord @PayConfigSnapshot
        |> set #venueId (unpackId (get #id venue))
        |> set #versionNumber versionNumber
        |> set #versionLabel ("v" <> tshow versionNumber)
        |> set #createdByUserId (unpackId (get #id user))
        |> set #snapshot snapshot
        |> createRecord

withUserAndCurrentVenue ::
    forall result.
    (?mocking :: MockContext WebApplication, ?context :: RequestContext, ?applicationContext :: ApplicationContext) =>
    User ->
    Id Venue ->
    ((?context :: RequestContext) => IO result) ->
    IO result
withUserAndCurrentVenue user venueId callback =
    withSessionValues
        [ (cs (LoginSupport.sessionKey @User), Serialize.encode user.id)
        , (currentVenueSessionKey, Serialize.encode venueId)
        ]
        callback

withSessionValues ::
    forall result.
    (?mocking :: MockContext WebApplication, ?context :: RequestContext) =>
    [(ByteString.ByteString, ByteString.ByteString)] ->
    ((?context :: RequestContext) => IO result) ->
    IO result
withSessionValues initialValues callback = do
    store <- newIORef (Map.fromList initialValues)
    let ?context = (?context) { request = requestWithSession store }
    callback
    where
        RequestContext { request } = ?mocking.requestContext

        requestWithSession store =
            request { Wai.vault = Vault.insert sessionVaultKey (newSession store) (Wai.vault request) }

        newSession :: IORef (Map.Map ByteString.ByteString ByteString.ByteString) -> Network.Wai.Session.Session IO ByteString.ByteString ByteString.ByteString
        newSession store = (lookupSession store, insertSession store)

        lookupSession store key = Map.lookup key <$> readIORef store

        insertSession store key value = modifyIORef' store (Map.insert key value)

withRequestHeaders ::
    forall result.
    (?context :: RequestContext) =>
    RequestHeaders ->
    ((?context :: RequestContext) => IO result) ->
    IO result
withRequestHeaders headers callback = do
    let request' =
            ?context.request
                { Wai.requestHeaders = headers <> Wai.requestHeaders ?context.request
                }
    let ?context = (?context) { request = request' }
    callback

defaultWeekEpoch :: Day
defaultWeekEpoch = fromGregorian 2025 1 6

testPassword :: Text
testPassword = "test-password-123"
