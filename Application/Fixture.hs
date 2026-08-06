module Application.Fixture where

import Application.Fixture.Reset (resetDatabase)
import Application.Helper.Pay (ensurePayVersionsForTimesheetApproval,
                               lockPayVersionsForApproval)
import Application.Helper.RosterGroups (ensureVenueDefaultRosterGroup,
                                        ensureVenueRosterDefaults)
import Application.Helper.VenueBootstrap
import Application.RosterShiftAssignment (RosterShiftAssignment,
                                          applyRosterShiftAssignment)
import Application.VenueTime (melbourneTimeZoneName)
import Application.VenueTime.Model
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Char as Char
import Data.Scientific (Scientific)
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude
import qualified IHP.Prelude as Prelude

createVenueWithConfig :: (?modelContext :: ModelContext) => Text -> IO Venue
createVenueWithConfig name =
    fst <$> createVenueWithBootstrapConfig (defaultVenueBootstrapConfig name)

createVenueRecordWithRosterDefaults :: (?modelContext :: ModelContext) => Text -> IO Venue
createVenueRecordWithRosterDefaults name = do
    venue <- newRecord @Venue
        |> set #name name
        |> createRecord
    void (ensureVenueRosterDefaults venue)
    pure venue

data FixturePasswordInput
    = HashFixturePassword !Text
    | UseFixturePasswordHash !Text

createUserRecord :: (?modelContext :: ModelContext) => Text -> Text -> Bool -> IO User
createUserRecord emailAddress globalRole isProfileCompleted =
    createUserRecordWithPlatformRole emailAddress globalRole Nothing isProfileCompleted


createUserRecordWithPlatformRole :: (?modelContext :: ModelContext) => Text -> Text -> Maybe PlatformRoleEnum -> Bool -> IO User
createUserRecordWithPlatformRole emailAddress globalRole platformRole isProfileCompleted = do
    createUserRecordWithPasswordAndPlatformRole emailAddress testPassword globalRole platformRole isProfileCompleted

createUserRecordWithPasswordAndPlatformRole :: (?modelContext :: ModelContext) => Text -> Text -> Text -> Maybe PlatformRoleEnum -> Bool -> IO User
createUserRecordWithPasswordAndPlatformRole emailAddress password globalRole platformRole isProfileCompleted = do
    createUserRecordWithPasswordAndPlatformRoleAndId emailAddress password globalRole platformRole isProfileCompleted Nothing

createUserRecordWithPasswordAndPlatformRoleAndId :: (?modelContext :: ModelContext) => Text -> Text -> Text -> Maybe PlatformRoleEnum -> Bool -> Maybe (Id User) -> IO User
createUserRecordWithPasswordAndPlatformRoleAndId emailAddress password globalRole platformRole isProfileCompleted maybeUserId =
    createUserRecordWithPasswordInputAndPlatformRoleAndId
        emailAddress
        (HashFixturePassword password)
        globalRole
        platformRole
        isProfileCompleted
        maybeUserId

createUserRecordWithPasswordInputAndPlatformRoleAndId :: (?modelContext :: ModelContext) => Text -> FixturePasswordInput -> Text -> Maybe PlatformRoleEnum -> Bool -> Maybe (Id User) -> IO User
createUserRecordWithPasswordInputAndPlatformRoleAndId emailAddress passwordInput globalRole platformRole isProfileCompleted maybeUserId = do
    passwordHash <- case passwordInput of
        HashFixturePassword password        -> hashPassword password
        UseFixturePasswordHash existingHash -> pure existingHash
    let user =
            newRecord @User
                |> set #email emailAddress
                |> set #passwordHash passwordHash
                |> set #userRole globalRole
                |> set #platformRole platformRole
                |> set #isProfileCompleted isProfileCompleted
                |> set #emailVerifiedAt (Just def)
    maybe user (\userId -> user |> set #id userId) maybeUserId
        |> createRecord

data MembershipStaffFixture
    = MembershipOnly
    | EnsureProfileStaffForCompletedUser
    deriving (Eq)

createVenueMembershipRecord :: (?modelContext :: ModelContext) => Venue -> User -> VenueRoleEnum -> IO VenueMembership
createVenueMembershipRecord venue user venueRole =
    createVenueMembershipRecordWithStaffFixture MembershipOnly venue user venueRole

createVenueMembershipRecordWithStaffFixture :: (?modelContext :: ModelContext) => MembershipStaffFixture -> Venue -> User -> VenueRoleEnum -> IO VenueMembership
createVenueMembershipRecordWithStaffFixture staffFixture venue user venueRole = do
    membership <- newRecord @VenueMembership
        |> set #venueId (unpackId (get #id venue))
        |> set #userId (unpackId (get #id user))
        |> set #venueRole venueRole
        |> set #isActive True
        |> createRecord
    when (staffFixture == EnsureProfileStaffForCompletedUser && user.isProfileCompleted) do
        void (createIdempotentStaffRecordWithDefaults venue (Just user) "Profile" "Complete")
    pure membership


createVenueInvitationRecord :: (?modelContext :: ModelContext) => Venue -> Maybe User -> Text -> VenueRoleEnum -> IO VenueInvitation
createVenueInvitationRecord venue maybeInviter emailAddress inviteRole =
    newRecord @VenueInvitation
        |> set #venueId (unpackId (get #id venue))
        |> set #invitedByUserId (fmap (unpackId . get #id) maybeInviter)
        |> set #email emailAddress
        |> set #inviteRole inviteRole
        |> set #status (InvitationStatusEnumPending)
        |> createRecord

createVenueOnboardingInvitationRecord :: (?modelContext :: ModelContext) => Maybe User -> Text -> IO VenueOnboardingInvitation
createVenueOnboardingInvitationRecord maybeInviter emailAddress =
    newRecord @VenueOnboardingInvitation
        |> set #invitedByUserId (fmap (unpackId . get #id) maybeInviter)
        |> set #email emailAddress
        |> set #status (InvitationStatusEnumPending)
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

createIdempotentStaffRecordWithDefaults :: (?modelContext :: ModelContext) => Venue -> Maybe User -> Text -> Text -> IO Staff
createIdempotentStaffRecordWithDefaults venue maybeUser firstName lastName = do
    staff <- case maybeUser of
        Just user -> do
            existingStaff <- query @Staff
                |> filterWhere (#venueId, unpackId venue.id)
                |> filterWhere (#userId, Just (unpackId user.id))
                |> fetchOneOrNothing
            case existingStaff of
                Just record -> applyDefaults record |> updateRecord
                Nothing     -> applyDefaults (newRecord @Staff |> set #venueId (unpackId venue.id) |> set #userId (Just (unpackId user.id))) |> createRecord
        Nothing ->
            applyDefaults (newRecord @Staff |> set #venueId (unpackId venue.id) |> set #userId Nothing)
                |> createRecord
    defaultRosterGroup <- ensureVenueDefaultRosterGroup venue
    existingAssignment <- query @StaffRosterGroup
        |> filterWhere (#staffId, unpackId staff.id)
        |> filterWhere (#rosterGroupId, unpackId defaultRosterGroup.id)
        |> fetchOneOrNothing
    when (isNothing existingAssignment) do
        void (createStaffRosterGroupRecord staff defaultRosterGroup)
    pure staff
  where
    applyDefaults staff =
        staff
            |> set #firstName firstName
            |> set #lastName lastName
            |> set #preferredName Nothing
            |> set #phone "0400000000"
            |> set #emergencyContactName "Emergency Contact"
            |> set #emergencyContactPhone "0411111111"
            |> set #idealShiftsPerWeek 0
            |> set #isActive True

ensureProfileCompleteStaffRecord :: (?modelContext :: ModelContext) => Venue -> User -> IO Staff
ensureProfileCompleteStaffRecord venue user =
    createIdempotentStaffRecordWithDefaults venue (Just user) "Profile" "Complete"

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

createRosterSlotRecord :: (?modelContext :: ModelContext) => RosterDay -> SlotName -> RosterShiftAssignment -> Int -> IO RosterSlot
createRosterSlotRecord rosterDay slotName assignment rowIndex = do
    slotDefinition <- ensureRosterWeekSlotDefinitionForSlotName rosterDay slotName
    rosterWeek <- fetch (Id rosterDay.rosterWeekId :: Id RosterWeek)
    venue <- fetch (Id rosterWeek.venueId :: Id Venue)
    shiftType <- ensureVenueDefaultShiftType venue
    let rosterDate = addDays (toInteger rosterDay.dayOffset) (fromGregorian 2025 1 6)
        boundaries =
            either (error . ("Invalid roster shift fixture: " <>) . show) Prelude.id $
                resolveShiftBoundaries melbourneTimeZoneName ShiftBoundaryInput
                    { shiftBoundaryDate = rosterDate
                    , shiftBoundaryStartTime = TimeOfDay 9 0 0
                    , shiftBoundaryStartOccurrence = Nothing
                    , shiftBoundaryEndTime = TimeOfDay 17 0 0
                    , shiftBoundaryEndOccurrence = Nothing
                    , shiftBoundaryBreak = Nothing
                    }
    newRecord @RosterSlot
        |> set #rosterDayId (unpackId (get #id rosterDay))
        |> set #rosterWeekSlotDefinitionId (unpackId (get #id slotDefinition))
        |> set #slotSortOrder slotDefinition.sortOrder
        |> set #rowIndex rowIndex
        |> set #shiftTypeId (Just (unpackId shiftType.id))
        |> applyRosterShiftAssignment assignment
        |> applyRosterSlotBoundaries boundaries
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
createTimesheetEntryRecord venue staff workedOn =
    createTimesheetEntryRecordWithDefaultLevelName venue staff workedOn "Default Level"

createTimesheetEntryRecordWithDefaultLevelName :: (?modelContext :: ModelContext) => Venue -> Staff -> Day -> Text -> IO TimesheetEntry
createTimesheetEntryRecordWithDefaultLevelName venue staff workedOn defaultLevelName = do
    shiftType <- ensureVenueDefaultShiftTypeWithLevelName venue defaultLevelName
    let boundaries =
            either (error . ("Invalid support timesheet fixture: " <>) . show) Prelude.id $
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

createLeaveRequestRecord :: (?modelContext :: ModelContext) => Venue -> Staff -> Day -> Day -> LeaveRequestStatusEnum -> IO LeaveRequest
createLeaveRequestRecord venue staff startDate endDate leaveStatus =
    createLeaveRequestRecordWithNotes venue staff startDate endDate leaveStatus Nothing

createLeaveRequestRecordWithNotes :: (?modelContext :: ModelContext) => Venue -> Staff -> Day -> Day -> LeaveRequestStatusEnum -> Maybe Text -> IO LeaveRequest
createLeaveRequestRecordWithNotes venue staff startDate endDate leaveStatus notes =
    newRecord @LeaveRequest
        |> set #venueId (unpackId (get #id venue))
        |> set #staffId (unpackId (get #id staff))
        |> set #startDate startDate
        |> set #endDate endDate
        |> set #status leaveStatus
        |> set #notes notes
        |> createRecord

createPayLevelRecord :: (?modelContext :: ModelContext) => Venue -> Text -> IO AwardLevel
createPayLevelRecord venue levelName =
    createPayLevelRecordWithRates venue levelName 30 0 0 1 1.25 1.5

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
    existingLevels <- query @AwardLevel |> filterWhere (#awardFixedId, 9 :: Int) |> fetch
    let preferredClassificationId = awardLevelClassificationFixedId levelName
    case find ((== preferredClassificationId) . (.classificationFixedId)) existingLevels of
        Just existingLevel
            | "Fixture Level " `Text.isPrefixOf` existingLevel.classification ->
                existingLevel
                    |> set #classification levelName
                    |> updateRecord
            | otherwise -> pure existingLevel
        Nothing -> do
            let usedClassificationIds = map (.classificationFixedId) existingLevels
                classificationFixedId =
                    fromMaybe
                        (error "synthetic wage fixture exhausted supported MA000009 classifications")
                        (find (`notElem` usedClassificationIds) (preferredClassificationId : filter (/= preferredClassificationId) supportedFixtureClassificationIds))
            requestedLevel <- createFixtureLevel classificationFixedId levelName
            let remainingClassificationIds =
                    supportedFixtureClassificationIds
                        \\ (classificationFixedId : usedClassificationIds)
            forM_ remainingClassificationIds \fixedId ->
                void (createFixtureLevel fixedId ("Fixture Level " <> tshow fixedId))
            pure requestedLevel
  where
    createFixtureLevel classificationFixedId classificationName = do
        awardLevel <-
            newRecord @AwardLevel
                |> set #awardFixedId 9
                |> set #classificationFixedId classificationFixedId
                |> set #classification classificationName
                |> set #operativeFrom (Just (fromGregorian 2020 1 1))
                |> set #isActive True
                |> createRecord
        payRate <-
            newRecord @FwcMapdPayRate
                |> set #awardFixedId 9
                |> set #classificationFixedId (Just awardLevel.classificationFixedId)
                |> set #classification classificationName
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
                |> set #operativeFrom (Just (fromGregorian 2020 1 1))
                |> createRecord
            )
        createSyntheticPenaltyFor Permanent awardLevel SaturdayPenalty payRate (baseRate * saturdayMultiplier)
        createSyntheticPenaltyFor Permanent awardLevel SundayPenalty payRate (baseRate * sundayMultiplier)
        createSyntheticPenaltyFor Permanent awardLevel PublicHolidayPenalty payRate (baseRate * 2.25)
        casualPayRate <-
            newRecord @FwcMapdPayRate
                |> set #awardFixedId 9
                |> set #classificationFixedId (Just awardLevel.classificationFixedId)
                |> set #classification classificationName
                |> set #employeeRateTypeCode (Just "AD")
                |> set #calculatedRate (Just (baseRate * 1.25))
                |> set #calculatedRateType (Just "Casual Hourly")
                |> createRecord
        void
            ( newRecord @AwardLevelBaseRate
                |> set #awardLevelId (unpackId awardLevel.id)
                |> set #employmentBasis Casual
                |> set #fwcMapdPayRateId (unpackId casualPayRate.id)
                |> set #hourlyRate (baseRate * 1.25)
                |> set #rateLabel ("Casual Hourly" :: Text)
                |> set #operativeFrom (Just (fromGregorian 2020 1 1))
                |> createRecord
            )
        createSyntheticPenaltyFor Casual awardLevel SaturdayPenalty casualPayRate (baseRate * 1.5)
        createSyntheticPenaltyFor Casual awardLevel SundayPenalty casualPayRate (baseRate * 1.75)
        createSyntheticPenaltyFor Casual awardLevel PublicHolidayPenalty casualPayRate (baseRate * 2.5)
        createSyntheticTimeAllowanceIfMissing awardLevel EveningAfter7Pm (max 0.01 eveningPenalty)
        createSyntheticTimeAllowanceIfMissing awardLevel LateNightAfterMidnight (max 0.01 after12Penalty)
        pure awardLevel

supportedFixtureClassificationIds :: [Int]
supportedFixtureClassificationIds = [242, 243, 246, 257, 268, 276, 282]

awardLevelClassificationFixedId :: Text -> Int
awardLevelClassificationFixedId levelName
    | "intro" `Text.isInfixOf` normalized = 242
    | "level 6" `Text.isInfixOf` normalized || "lvl 6" `Text.isInfixOf` normalized = 282
    | "level 5" `Text.isInfixOf` normalized || "lvl 5" `Text.isInfixOf` normalized = 276
    | "level 4" `Text.isInfixOf` normalized || "lvl 4" `Text.isInfixOf` normalized = 268
    | "level 3" `Text.isInfixOf` normalized || "lvl 3" `Text.isInfixOf` normalized = 257
    | "level 2" `Text.isInfixOf` normalized || "lvl 2" `Text.isInfixOf` normalized = 246
    | "level 1" `Text.isInfixOf` normalized || "lvl 1" `Text.isInfixOf` normalized = 243
    | otherwise = supportedFixtureClassificationIds !! (awardLevelNameHash `mod` length supportedFixtureClassificationIds)
  where
    normalized = Text.toCaseFold levelName
    awardLevelNameHash = abs (Text.foldl' (\acc ch -> acc * 31 + Char.ord ch) 7 normalized)


createSyntheticPenaltyFor :: (?modelContext :: ModelContext) => StaffEmploymentBasisEnum -> AwardLevel -> AwardPenaltyKindEnum -> FwcMapdPayRate -> Scientific -> IO ()
createSyntheticPenaltyFor employmentBasis awardLevel penaltyKind payRate hourlyRate = do
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
            |> set #employmentBasis employmentBasis
            |> set #penaltyKind penaltyKind
            |> set #fwcMapdPenaltyRateId (unpackId penaltyRate.id)
            |> set #hourlyRate hourlyRate
            |> set #operativeFrom (Just (fromGregorian 2020 1 1))
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
                        |> set #operativeFrom (Just (fromGregorian 2020 1 1))
                        |> createRecord
                    )

createShiftTypeRecord :: (?modelContext :: ModelContext) => Venue -> AwardLevel -> Text -> IO ShiftType
createShiftTypeRecord venue awardLevel shiftTypeName =
    newRecord @ShiftType
        |> set #venueId (unpackId (get #id venue))
        |> set #name shiftTypeName
        |> set #sortOrder 0
        |> set #payAssignmentMode AwardRate
        |> set #overrideAwardLevelId (Just awardLevel.id)
        |> set #isActive True
        |> createRecord

createPayLevelDayRuleRecord :: (?modelContext :: ModelContext) => ShiftType -> DayName -> AwardLevel -> IO ShiftType
createPayLevelDayRuleRecord shiftType _dayName awardLevel =
    shiftType
        |> set #payAssignmentMode AwardRate
        |> set #overrideAwardLevelId (Just awardLevel.id)
        |> updateRecord

ensureVenueDefaultShiftType :: (?modelContext :: ModelContext) => Venue -> IO ShiftType
ensureVenueDefaultShiftType venue =
    ensureVenueDefaultShiftTypeWithLevelName venue "Default Level"

ensureVenueDefaultShiftTypeWithLevelName :: (?modelContext :: ModelContext) => Venue -> Text -> IO ShiftType
ensureVenueDefaultShiftTypeWithLevelName venue defaultLevelName = do
    query @ShiftType
        |> filterWhere (#venueId, unpackId (get #id venue))
        |> orderByAsc #createdAt
        |> fetchOneOrNothing
        >>= \case
            Just shiftType -> pure shiftType
            Nothing -> do
                payLevel <- createPayLevelRecord venue defaultLevelName
                createShiftTypeRecord venue payLevel "Default Shift"

defaultWeekEpoch :: Day
defaultWeekEpoch = fromGregorian 2025 1 6

testPassword :: Text
testPassword = "password123"
