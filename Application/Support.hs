module Application.Support where

import Application.Helper.Controller (PlatformRole (..),
                                      defaultWeekOffsetEpochForStartDay,
                                      platformRoleToEnum, unsafeEnumFromText)
import Application.Helper.RosterGroups (ensureVenueDefaultRosterGroup,
                                        ensureVenueRosterDefaults)
import qualified Data.Aeson as Aeson
import qualified Data.Char as Char
import qualified Data.Text as Text
import Data.Scientific (Scientific)
import Data.Time.Calendar (Day, fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlExecDiscardResult)
import IHP.Prelude

resetDatabase :: (?modelContext :: ModelContext) => IO ()
resetDatabase = do
    sqlExecDiscardResult
        "TRUNCATE TABLE export_jobs, audit_events, venue_membership_role_events, timesheet_entry_versions, timesheet_entries, leave_request_events, leave_requests, staff_shift_preferences, staff_availability, roster_slots, roster_days, roster_weeks, pay_config_snapshots, venue_config, report_definition_shift_type_filters, report_definitions, day_names, slot_names, staff_roster_groups, roster_groups, shift_types, pay_levels, staff, email_verification_tokens, venue_invitations, venue_onboarding_invitations, venue_memberships, users, venues RESTART IDENTITY CASCADE"
        ()
    pure ()

createVenueWithConfig :: (?modelContext :: ModelContext) => Text -> IO Venue
createVenueWithConfig name =
    fst <$> createVenueWithBootstrapConfig name "Australia/Melbourne" 1

createVenueWithBootstrapConfig :: (?modelContext :: ModelContext) => Text -> Text -> Int -> IO (Venue, VenueConfig)
createVenueWithBootstrapConfig name timezone rosterWeekStartsOn =
    withTransaction do
        createVenueWithBootstrapConfigInCurrentTransaction name timezone rosterWeekStartsOn

createVenueWithBootstrapConfigInCurrentTransaction :: (?modelContext :: ModelContext) => Text -> Text -> Int -> IO (Venue, VenueConfig)
createVenueWithBootstrapConfigInCurrentTransaction name timezone rosterWeekStartsOn = do
    venue <-
        newRecord @Venue
            |> set #name name
            |> set #status (unsafeEnumFromText @VenueStatusEnum "active")
            |> createRecord
    venueConfig <-
        newRecord @VenueConfig
            |> set #venueId (unpackId venue.id)
            |> set #timezone timezone
            |> set #rosterWeekStartsOn rosterWeekStartsOn
            |> set #weekOffsetEpoch (defaultWeekOffsetEpochForStartDay rosterWeekStartsOn)
            |> set #lateToEarlyMinStartGapMinutes 600
            |> set #staffTimesheetEditWindowDays 7
            |> createRecord
    _ <- ensureVenueRosterDefaults venue
    pure (venue, venueConfig)

createUserRecord :: (?modelContext :: ModelContext) => Text -> Text -> Bool -> IO User
createUserRecord emailAddress globalRole isProfileCompleted =
    createUserRecordWithPlatformRole emailAddress globalRole Nothing isProfileCompleted

createUserRecordWithPassword :: (?modelContext :: ModelContext) => Text -> Text -> Text -> Bool -> IO User
createUserRecordWithPassword emailAddress password globalRole isProfileCompleted =
    createUserRecordWithPasswordAndPlatformRole emailAddress password globalRole Nothing isProfileCompleted

createUserRecordWithPlatformRole :: (?modelContext :: ModelContext) => Text -> Text -> Maybe PlatformRole -> Bool -> IO User
createUserRecordWithPlatformRole emailAddress globalRole platformRole isProfileCompleted = do
    createUserRecordWithPasswordAndPlatformRole emailAddress testPassword globalRole platformRole isProfileCompleted

createUserRecordWithPasswordAndPlatformRole :: (?modelContext :: ModelContext) => Text -> Text -> Text -> Maybe PlatformRole -> Bool -> IO User
createUserRecordWithPasswordAndPlatformRole emailAddress password globalRole platformRole isProfileCompleted = do
    passwordHash <- hashPassword password
    newRecord @User
        |> set #email emailAddress
        |> set #passwordHash passwordHash
        |> set #userRole globalRole
        |> set #platformRole (platformRoleToEnum <$> platformRole)
        |> set #isProfileCompleted isProfileCompleted
        |> set #emailVerifiedAt (Just def)
        |> createRecord

createVenueMembershipRecord :: (?modelContext :: ModelContext) => Venue -> User -> Text -> IO VenueMembership
createVenueMembershipRecord venue user venueRole =
    newRecord @VenueMembership
        |> set #venueId (unpackId (get #id venue))
        |> set #userId (unpackId (get #id user))
        |> set #venueRole (unsafeEnumFromText @VenueRoleEnum venueRole)
        |> set #isActive True
        |> createRecord

ensureVenueMembershipRecord :: (?modelContext :: ModelContext) => Venue -> User -> Text -> IO VenueMembership
ensureVenueMembershipRecord venue user venueRole =
    query @VenueMembership
        |> filterWhere (#venueId, unpackId (get #id venue))
        |> filterWhere (#userId, unpackId (get #id user))
        |> fetchOneOrNothing
        >>= \case
            Just membership ->
                membership
                    |> set #venueRole (unsafeEnumFromText @VenueRoleEnum venueRole)
                    |> set #isActive True
                    |> updateRecord
            Nothing ->
                createVenueMembershipRecord venue user venueRole

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

ensureLinkedStaffRecord :: (?modelContext :: ModelContext) => Venue -> User -> Text -> Text -> IO Staff
ensureLinkedStaffRecord venue user firstName lastName =
    query @Staff
        |> filterWhere (#venueId, unpackId (get #id venue))
        |> filterWhere (#userId, Just (unpackId (get #id user)))
        |> fetchOneOrNothing
        >>= \case
            Just staff ->
                if staff.isActive
                    then pure staff
                    else staff
                        |> set #isActive True
                        |> updateRecord
            Nothing ->
                createStaffRecord venue (Just user) firstName lastName

provisionVenueUser :: (?modelContext :: ModelContext) => Venue -> User -> Text -> Text -> Text -> IO (VenueMembership, Staff)
provisionVenueUser venue user venueRole firstName lastName =
    do
        membership <- ensureVenueMembershipRecord venue user venueRole
        staff <- ensureLinkedStaffRecord venue user firstName lastName
        pure (membership, staff)

defaultStaffNameFromEmail :: Text -> (Text, Text)
defaultStaffNameFromEmail emailAddress =
    case filter (not . Text.null) (Text.split (not . Char.isAlphaNum) localPart) of
        [] -> ("Invited", "User")
        [firstName] -> (toTitleCase firstName, "User")
        firstName:lastName:_ -> (toTitleCase firstName, toTitleCase lastName)
    where
        localPart = Text.takeWhile (/= '@') emailAddress
        toTitleCase token =
            case Text.uncons token of
                Nothing -> "User"
                Just (firstCharacter, remainingCharacters) ->
                    Text.cons (Char.toUpper firstCharacter) (Text.toLower remainingCharacters)

createStaffRosterGroupRecord :: (?modelContext :: ModelContext) => Staff -> RosterGroup -> IO StaffRosterGroup
createStaffRosterGroupRecord staff rosterGroup =
    newRecord @StaffRosterGroup
        |> set #staffId (unpackId (get #id staff))
        |> set #rosterGroupId (unpackId (get #id rosterGroup))
        |> createRecord

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
        |> set #slotSortOrder slotName.sortOrder
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

defaultWeekEpoch :: Day
defaultWeekEpoch = fromGregorian 2025 1 6

testPassword :: Text
testPassword = "password123"
