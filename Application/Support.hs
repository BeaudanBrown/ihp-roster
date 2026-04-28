module Application.Support where

import Application.Helper.Controller (PlatformRole (..),
                                      defaultWeekOffsetEpochForStartDay,
                                      platformRoleToEnum, unsafeEnumFromText)
import Application.Helper.RosterGroups (ensureVenueDefaultRosterGroup,
                                        ensureVenueRosterDefaults)
import Control.Monad (void)
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
        "TRUNCATE TABLE app_jobs, award_time_penalty_allowances, award_level_penalty_rates, award_level_base_rates, award_levels, fwc_mapd_wage_allowances, fwc_mapd_penalty_rates, fwc_mapd_pay_rates, fwc_mapd_classifications, fwc_mapd_awards, fwc_mapd_sync_runs, public_holidays, xero_payroll_calendars, xero_earnings_rates, xero_employees, xero_sync_runs, xero_oauth_states, xero_connections, export_jobs, audit_events, venue_membership_role_events, timesheet_entry_versions, timesheet_entries, leave_request_events, leave_requests, staff_shift_preferences, staff_availability, roster_slots, roster_days, roster_weeks, pay_config_snapshots, venue_config, report_definition_shift_type_filters, report_definitions, day_names, slot_names, staff_roster_groups, roster_groups, shift_types, staff, email_verification_tokens, venue_invitations, venue_onboarding_invitations, venue_memberships, users, venues RESTART IDENTITY CASCADE"
        ()
    pure ()

createVenueWithConfig :: (?modelContext :: ModelContext) => Text -> IO Venue
createVenueWithConfig name =
    fst <$> createVenueWithBootstrapConfig name defaultVenueBootstrapTimezone 1

defaultVenueBootstrapTimezone :: Text
defaultVenueBootstrapTimezone = "Australia/Melbourne"

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
    createUserRecordWithPasswordAndPlatformRoleAndId emailAddress password globalRole platformRole isProfileCompleted Nothing

createUserRecordWithPasswordAndPlatformRoleAndId :: (?modelContext :: ModelContext) => Text -> Text -> Text -> Maybe PlatformRole -> Bool -> Maybe (Id User) -> IO User
createUserRecordWithPasswordAndPlatformRoleAndId emailAddress password globalRole platformRole isProfileCompleted maybeUserId = do
    passwordHash <- hashPassword password
    let user =
            newRecord @User
                |> set #email emailAddress
                |> set #passwordHash passwordHash
                |> set #userRole globalRole
                |> set #platformRole (platformRoleToEnum <$> platformRole)
                |> set #isProfileCompleted isProfileCompleted
                |> set #emailVerifiedAt (Just def)
    maybe user (\userId -> user |> set #id userId) maybeUserId
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

createStaffRecord :: (?modelContext :: ModelContext) => Venue -> Maybe User -> Text -> Text -> Maybe Text -> Text -> Text -> Text -> Int -> Bool -> IO Staff
createStaffRecord venue maybeUser firstName lastName preferredName phone emergencyContactName emergencyContactPhone idealShiftsPerWeek isActive = do
    staff <- newRecord @Staff
        |> set #venueId (unpackId (get #id venue))
        |> set #userId (fmap (unpackId . get #id) maybeUser)
        |> set #firstName firstName
        |> set #lastName lastName
        |> set #preferredName preferredName
        |> set #phone phone
        |> set #emergencyContactName emergencyContactName
        |> set #emergencyContactPhone emergencyContactPhone
        |> set #idealShiftsPerWeek idealShiftsPerWeek
        |> set #isActive isActive
        |> createRecord
    _ <- createStaffRosterGroupRecord staff =<< ensureVenueDefaultRosterGroup venue
    pure staff

createPlaceholderStaffRecord :: (?modelContext :: ModelContext) => Venue -> Maybe User -> Text -> Text -> IO Staff
createPlaceholderStaffRecord venue maybeUser firstName lastName =
    createStaffRecord venue maybeUser firstName lastName Nothing "0400000000" "Emergency Contact" "0411111111" 0 True

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
                createPlaceholderStaffRecord venue (Just user) firstName lastName

provisionVenueMembership :: (?modelContext :: ModelContext) => Venue -> User -> Text -> IO VenueMembership
provisionVenueMembership venue user venueRole =
    ensureVenueMembershipRecord venue user venueRole

provisionVenueUser :: (?modelContext :: ModelContext) => Venue -> User -> Text -> Text -> Text -> IO (VenueMembership, Staff)
provisionVenueUser venue user venueRole firstName lastName = do
    membership <- provisionVenueMembership venue user venueRole
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
    awardLevel <-
        newRecord @AwardLevel
            |> set #awardFixedId 9
            |> set #classificationFixedId (abs (Text.foldl' (\acc ch -> acc * 31 + Char.ord ch) 7 levelName))
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
