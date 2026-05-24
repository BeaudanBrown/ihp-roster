module Application.Support.DevFixtures where

import Application.Helper.Controller (PlatformRole (..))
import Application.Helper.Pay (ensurePayVersionsForTimesheetApproval,
                               ensureShiftTypePayVersionForShiftType,
                               lockPayVersionsForApproval)
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        ensureVenueDefaultRosterGroup,
                                        fetchActiveRosterGroupSlotNames,
                                        syncStaffRosterGroupAssignments)
import Application.Helper.ShiftTypeColours (blankShiftTypeColourKey)
import Application.Helper.StaffShiftPreferences (ShiftPreferenceSelection (..))
import Application.Helper.VenueBootstrap (provisionVenueUser)
import Application.Support
import Application.Support.Seed.Scenario
import Control.Monad (replicateM, void)
import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, dayOfWeek, diffDays, fromGregorian)
import Data.Time.Clock (UTCTime (..), getCurrentTime, secondsToDiffTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlExecDiscardResult)
import IHP.ModelSupport.Types (CanCreate (createMany))
import IHP.Prelude

data DevRosterSlotSeed = DevRosterSlotSeed
    { slotStaff       :: !(Maybe Staff)
    , slotStartTime   :: !(Maybe TimeOfDay)
    , slotShiftTypeId :: !(Maybe UUID)
    }

data DevSeedFixture = DevSeedFixture
    { sandboxVenue      :: !Venue
    , sandboxAdmin      :: !User
    , sandboxManager    :: !User
    , sandboxManagers   :: ![User]
    , sandboxWorker     :: !User
    , supportAdmin      :: !User
    , sandboxInvitation :: !VenueInvitation
    , frontOfHouseGroup :: !RosterGroup
    , backOfHouseGroup  :: !RosterGroup
    , currentWeekOffset :: !Int
    , scenario          :: !SeedScenario
    }

seedDevelopmentFixtureForWeek :: (?modelContext :: ModelContext) => Day -> IO DevSeedFixture
seedDevelopmentFixtureForWeek =
    seedDevelopmentFixtureWithScenarioForWeek defaultScenario

seedDevelopmentFixtureWithScenarioForWeek :: (?modelContext :: ModelContext) => SeedScenario -> Day -> IO DevSeedFixture
seedDevelopmentFixtureWithScenarioForWeek scenario fixtureWeekStart =
    seedDevelopmentFixtureWithScenarioForWeekAndLeaveMonth scenario fixtureWeekStart fixtureWeekStart

seedDevelopmentFixtureWithScenarioForWeekAndLeaveMonth :: (?modelContext :: ModelContext) => SeedScenario -> Day -> Day -> IO DevSeedFixture
seedDevelopmentFixtureWithScenarioForWeekAndLeaveMonth scenario fixtureWeekStart leaveMonthAnchor = do
    -- `seed-dev app` rebuilds the dev DB from schema + bootstrap fixtures first.
    -- Wipe those bootstrap rows here so the scripted demo surface is the only
    -- seeded venue set that remains afterwards.
    resetDevFixtureData
    ensureSeedShiftTypeAwardLevels
    venue <- createVenueWithConfig "Development Sandbox Venue"
    admin <- createSeededUserRecordWithPassword "venue2@bepis.lol" "venue2" "admin" True
    _ <- provisionVenueUser venue admin "venue_admin" "venue2" "bepis"
    supportAdmin <- createSeededUserRecordWithPasswordAndPlatformRole "admin@bepis.lol" "admin" "admin" (Just SuperAdminRole) True
    managerUsers <- createManagerUsers venue scenario.managerCount
    let managerUser = fromMaybe (error "Expected at least one seeded manager user") (listToMaybe managerUsers)
    workerUser <- createUserRecord "dev-worker@example.com" "staff" True
    (_, seededWorkerStaff) <- provisionVenueUser venue workerUser "worker" "Willa" "Worker"
    seedSandboxRoleAliasAccounts venue
    invitation <- createVenueInvitationRecord venue (Just admin) "pending-invite@example.com" "worker"

    frontGroup <-
        ensureVenueDefaultRosterGroup venue
            >>= updateRecord . set #name "Front of House"
    backGroup <- createVenueRosterGroupWithDefaults venue "Back of House" 20 True

    frontSlots <- fetchActiveRosterGroupSlotNames (get #id frontGroup)
    backSlots <- fetchActiveRosterGroupSlotNames (get #id backGroup)

    floorShift <- createSeedShiftTypeRecord venue admin fixtureWeekStart "Floor" 10 "palette-1" seededFloorAwardLevelId
    kitchenShift <- createSeedShiftTypeRecord venue admin fixtureWeekStart "Kitchen" 20 "palette-2" seededKitchenAwardLevelId
    extraShiftTypes <- forM seedExtraShiftTypeSpecs \(shiftTypeName, sortOrder, colourKey, awardLevelId) ->
        createSeedShiftTypeRecord venue admin fixtureWeekStart shiftTypeName sortOrder colourKey awardLevelId
    let seedShiftTypes = [floorShift, kitchenShift] <> extraShiftTypes
    managerStaffs <- mapM (createManagerStaff venue) (zip [0 ..] managerUsers)
    workerStaff <- seededWorkerStaff |> set #idealShiftsPerWeek 3 |> updateRecord
    seededStaff <- createGeneratedStaff venue scenario.scenarioSeed scenario.staffCount
    let frontOnlyStaff = takeFrontOnly seededStaff
    let backOnlyStaff = takeBackOnly seededStaff
    let crossGroupStaff = takeCrossGroup seededStaff
    trialStaffs <- createTrialStaff venue scenario.trialStaffCount

    mapM_ (\staff -> syncStaffRosterGroupAssignments staff [get #id frontGroup, get #id backGroup]) managerStaffs
    syncStaffRosterGroupAssignments workerStaff [get #id frontGroup]
    mapM_ (\staff -> syncStaffRosterGroupAssignments staff [get #id frontGroup]) frontOnlyStaff
    mapM_ (\staff -> syncStaffRosterGroupAssignments staff [get #id backGroup]) backOnlyStaff
    mapM_ (\staff -> syncStaffRosterGroupAssignments staff [get #id frontGroup, get #id backGroup]) crossGroupStaff
    mapM_ (\staff -> syncStaffRosterGroupAssignments staff [get #id frontGroup]) trialStaffs

    seedStaffPreferences
        scenario.scenarioSeed
        frontGroup
        backGroup
        frontSlots
        backSlots
        managerStaffs
        workerStaff
        frontOnlyStaff
        backOnlyStaff
        crossGroupStaff
        trialStaffs

    let allFrontCandidates = managerStaffs <> [workerStaff] <> frontOnlyStaff <> crossGroupStaff <> trialStaffs
    let allBackCandidates = managerStaffs <> backOnlyStaff <> crossGroupStaff

    let weekOffset = weekOffsetFor fixtureWeekStart
    seedRosterWindow
        scenario
        fixtureWeekStart
        venue
        frontGroup
        backGroup
        frontSlots
        backSlots
        allFrontCandidates
        allBackCandidates
        seedShiftTypes

    let allOperationalStaff = managerStaffs <> [workerStaff] <> seededStaff <> trialStaffs

    seedLeaveRequests fixtureWeekStart leaveMonthAnchor venue scenario allOperationalStaff

    let approvedAt = UTCTime (dayAtOffset fixtureWeekStart 6) (secondsToDiffTime 3600)
    seedTimesheets fixtureWeekStart venue admin scenario floorShift kitchenShift allOperationalStaff approvedAt

    pure
        DevSeedFixture
            { sandboxVenue = venue
            , sandboxAdmin = admin
            , sandboxManager = managerUser
            , sandboxManagers = managerUsers
            , sandboxWorker = workerUser
            , supportAdmin = supportAdmin
            , sandboxInvitation = invitation
            , frontOfHouseGroup = frontGroup
            , backOfHouseGroup = backGroup
            , currentWeekOffset = weekOffset
            , scenario = scenario
            }

createSeedShiftTypeRecord :: (?modelContext :: ModelContext) => Venue -> User -> Day -> Text -> Int -> Text -> Id AwardLevel -> IO ShiftType
createSeedShiftTypeRecord venue actorUser effectiveFrom shiftTypeName sortOrder colourKey awardLevelId = do
    shiftType <-
        newRecord @ShiftType
            |> set #venueId (unpackId (get #id venue))
            |> set #name shiftTypeName
            |> set #sortOrder sortOrder
            |> set #colourKey colourKey
            |> set #overrideAwardLevelId (Just awardLevelId)
            |> set #isActive True
            |> createRecord
    _ <- ensureShiftTypePayVersionForShiftType actorUser.id shiftType effectiveFrom
    pure shiftType

seedExtraShiftTypeSpecs :: [(Text, Int, Text, Id AwardLevel)]
seedExtraShiftTypeSpecs =
    [ ("Bar", 30, blankShiftTypeColourKey, seededFloorAwardLevelId)
    , ("Gaming", 40, blankShiftTypeColourKey, seededFloorAwardLevelId)
    , ("Glassy", 50, blankShiftTypeColourKey, seededFloorAwardLevelId)
    , ("Cellar", 60, blankShiftTypeColourKey, seededFloorAwardLevelId)
    , ("Functions", 70, blankShiftTypeColourKey, seededFloorAwardLevelId)
    , ("Runner", 80, blankShiftTypeColourKey, seededFloorAwardLevelId)
    , ("Door", 90, blankShiftTypeColourKey, seededKitchenAwardLevelId)
    , ("Supervisor", 100, blankShiftTypeColourKey, seededKitchenAwardLevelId)
    ]

seededFloorAwardLevelId :: Id AwardLevel
seededFloorAwardLevelId =
    seededHospitalityAwardLevelId "2cba4998-4691-4eeb-9bd3-e79263c54769"

seededKitchenAwardLevelId :: Id AwardLevel
seededKitchenAwardLevelId =
    seededHospitalityAwardLevelId "8a53b7c8-574c-49f8-abd4-0caf3b46a22f"

seededHospitalityAwardLevelId :: Text -> Id AwardLevel
seededHospitalityAwardLevelId value =
    Id (fromMaybe (error ("Invalid dev award level id: " <> cs value)) (UUID.fromText value))

resetDevFixtureData :: (?modelContext :: ModelContext) => IO ()
resetDevFixtureData = do
    sqlExecDiscardResult
        "TRUNCATE TABLE app_jobs, xero_timesheet_submission_entries, xero_timesheet_submissions, xero_submission_runs, xero_payroll_calendar_selections, xero_earnings_rate_mappings, xero_staff_mappings, xero_payroll_calendars, xero_earnings_rates, xero_employees, xero_sync_runs, xero_oauth_states, xero_connections, export_jobs, audit_events, venue_membership_role_events, timesheet_entry_versions, timesheet_entries, leave_request_events, leave_requests, staff_shift_preferences, roster_slots, roster_week_slot_definitions, roster_days, roster_weeks, export_job_entries, shift_type_pay_versions, staff_pay_versions, venue_config, report_definition_shift_type_filters, report_definitions, day_names, slot_names, staff_roster_groups, roster_groups, shift_types, staff_documents, staff, user_preferences, email_verification_tokens, venue_invitations, venue_onboarding_invitations, venue_memberships, users, venues RESTART IDENTITY CASCADE"
        ()
    pure ()

ensureSeedShiftTypeAwardLevels :: (?modelContext :: ModelContext) => IO ()
ensureSeedShiftTypeAwardLevels = do
    sqlExecDiscardResult
        "INSERT INTO award_levels (id, award_fixed_id, classification_fixed_id, classification, classification_level, parent_classification_name, clause_description, operative_from, operative_to, published_year, is_active, raw_json) VALUES ('2cba4998-4691-4eeb-9bd3-e79263c54769', 9, 243, 'Level 1', '2.0', 'Food and beverage attendant grade 1; Guest service grade 1; Kitchen attendant grade 1', 'Hospitality Employees', '2025-07-01', NULL, 2025, TRUE, '{}'::jsonb), ('8a53b7c8-574c-49f8-abd4-0caf3b46a22f', 9, 268, 'Level 4', '5.0', 'Clerical grade 3; Cook (tradesperson) grade 3; Food and beverage attendant (tradesperson) grade 4; Front office grade 3; Gardener grade 3 (tradesperson); Guest service grade 4; Leisure attendant grade 3; Storeperson grade 3', 'Hospitality Employees', '2025-07-01', NULL, 2025, TRUE, '{}'::jsonb) ON CONFLICT (id) DO NOTHING"
        ()
    pure ()

seedSandboxRoleAliasAccounts :: (?modelContext :: ModelContext) => Venue -> IO ()
seedSandboxRoleAliasAccounts venue = do
    staffUser <- createSeededUserRecordWithPassword "staff@bepis.lol" "staff" "staff" True
    _ <- provisionVenueUser venue staffUser "worker" "staff" "bepis"

    managerUser <- createSeededUserRecordWithPassword "manager@bepis.lol" "manager" "manager" True
    _ <- provisionVenueUser venue managerUser "manager" "manager" "bepis"

    venueAdminUser <- createSeededUserRecordWithPassword "venue@bepis.lol" "venue" "admin" True
    _ <- provisionVenueUser venue venueAdminUser "venue_admin" "venue" "bepis"

    venueOwnerUser <- createSeededUserRecordWithPassword "owner@bepis.lol" "owner" "admin" True
    _ <- provisionVenueUser venue venueOwnerUser "venue_owner" "owner" "bepis"

    pure ()

createSeededUserRecordWithPassword :: (?modelContext :: ModelContext) => Text -> Text -> Text -> Bool -> IO User
createSeededUserRecordWithPassword emailAddress password globalRole isProfileCompleted =
    createSeededUserRecordWithPasswordAndPlatformRole emailAddress password globalRole Nothing isProfileCompleted

createSeededUserRecordWithPasswordAndPlatformRole :: (?modelContext :: ModelContext) => Text -> Text -> Text -> Maybe PlatformRole -> Bool -> IO User
createSeededUserRecordWithPasswordAndPlatformRole emailAddress password globalRole platformRole isProfileCompleted =
    createUserRecordWithPasswordAndPlatformRoleAndId emailAddress password globalRole platformRole isProfileCompleted (seededUserIdForPasskeyEmail emailAddress)

seededUserIdForPasskeyEmail :: Text -> Maybe (Id User)
seededUserIdForPasskeyEmail emailAddress =
    Id <$> (Map.lookup emailAddress seededUserIdsForPasskeys >>= UUID.fromText)

seededUserIdsForPasskeys :: Map.Map Text Text
seededUserIdsForPasskeys =
    Map.fromList
        [ ("admin@bepis.lol", "a1642410-7297-46fd-916f-9d1ce464c388")
        , ("manager@bepis.lol", "71ced305-dc24-414c-9471-e891468e0120")
        , ("owner@bepis.lol", "7fe0607d-32aa-4a63-8a02-147b44987b43")
        , ("staff@bepis.lol", "0342d268-4d58-4c11-b925-124db23b4758")
        , ("venue@bepis.lol", "c3b1be9d-12de-49d1-9f21-e507af4c14ab")
        , ("venue2@bepis.lol", "4c83e177-4d6e-4ef2-abf3-92e9781cfc90")
        ]

createManagerUsers :: (?modelContext :: ModelContext) => Venue -> Int -> IO [User]
createManagerUsers venue count =
    forM [0 .. max 0 (count - 1)] \index -> do
        let emailAddress =
                if index == 0
                    then "dev-manager@example.com"
                    else "dev-manager-" <> tshow (index + 1) <> "@example.com"
        user <- createUserRecord emailAddress "manager" True
        _ <- createVenueMembershipRecord venue user "manager"
        pure user

createManagerStaff :: (?modelContext :: ModelContext) => Venue -> (Int, User) -> IO Staff
createManagerStaff venue (index, user) =
    createPlaceholderStaffRecord venue (Just user) firstName lastName
        >>= updateRecord . set #idealShiftsPerWeek (4 + (index `mod` 2))
    where
        (firstName, lastName) =
            fromMaybe ("Morgan", "Manager") (safeIndex managerNames index)

createGeneratedStaff :: (?modelContext :: ModelContext) => Venue -> Int -> Int -> IO [Staff]
createGeneratedStaff venue seedValue requestedCount =
    forM (take (max 0 requestedCount) generatedStaffCatalog) \(index, firstName, lastName, preferredName) -> do
        user <- createUserRecord ("dev-" <> Text.toLower firstName <> "-" <> tshow (index + 1) <> "@example.com") "staff" True
        createPlaceholderStaffRecord venue (Just user) firstName lastName
            >>= updateRecord . set #preferredName (preferredNameFor seedValue index firstName preferredName)
            >>= updateRecord . set #idealShiftsPerWeek (1 + ((index + 2) `mod` 5))

createTrialStaff :: (?modelContext :: ModelContext) => Venue -> Int -> IO [Staff]
createTrialStaff venue requestedCount =
    forM [0 .. max 0 (requestedCount - 1)] \index ->
        createPlaceholderStaffRecord venue Nothing "Taylor" ("Trial " <> tshow (index + 1))
            >>= updateRecord . set #idealShiftsPerWeek 1

takeFrontOnly :: [Staff] -> [Staff]
takeFrontOnly staff =
    map snd (filter (\(index, _) -> assignmentBucket index == FrontOnly) (zip [0 :: Int ..] staff))

takeBackOnly :: [Staff] -> [Staff]
takeBackOnly staff =
    map snd (filter (\(index, _) -> assignmentBucket index == BackOnly) (zip [0 :: Int ..] staff))

takeCrossGroup :: [Staff] -> [Staff]
takeCrossGroup staff =
    map snd (filter (\(index, _) -> assignmentBucket index == CrossGroup) (zip [0 :: Int ..] staff))

seedStaffPreferences ::
    (?modelContext :: ModelContext) =>
    Int ->
    RosterGroup ->
    RosterGroup ->
    [SlotName] ->
    [SlotName] ->
    [Staff] ->
    Staff ->
    [Staff] ->
    [Staff] ->
    [Staff] ->
    [Staff] ->
    IO ()
seedStaffPreferences seedValue frontGroup backGroup frontSlots backSlots managerStaffs workerStaff frontOnlyStaff backOnlyStaff crossGroupStaff trialStaffs = do
    forM_ (zip [0 :: Int ..] managerStaffs) \(index, staff) ->
        seedStaffRecurringPreferences
            seedValue
            (index + 1)
            staff
            [(frontGroup, frontSlots), (backGroup, backSlots)]
    seedStaffRecurringPreferences
        seedValue
        21
        workerStaff
        [(frontGroup, frontSlots)]
    forM_ (zip [0 :: Int ..] frontOnlyStaff) \(index, staff) ->
        seedStaffRecurringPreferences
            seedValue
            (40 + index)
            staff
            [(frontGroup, frontSlots)]
    forM_ (zip [0 :: Int ..] backOnlyStaff) \(index, staff) ->
        seedStaffRecurringPreferences
            seedValue
            (80 + index)
            staff
            [(backGroup, backSlots)]
    forM_ (zip [0 :: Int ..] crossGroupStaff) \(index, staff) ->
        seedStaffRecurringPreferences
            seedValue
            (120 + index)
            staff
            [(frontGroup, frontSlots), (backGroup, backSlots)]
    forM_ (zip [0 :: Int ..] trialStaffs) \(index, staff) ->
        seedStaffRecurringPreferences
            seedValue
            (160 + index)
            staff
            [(frontGroup, frontSlots)]

seedStaffRecurringPreferences ::
    (?modelContext :: ModelContext) =>
    Int ->
    Int ->
    Staff ->
    [(RosterGroup, [SlotName])] ->
    IO ()
seedStaffRecurringPreferences seedValue staffIndex staff groupSlots =
    seedStaffShiftPreferenceRecords seedValue staffIndex staff groupSlots

seedStaffShiftPreferenceRecords ::
    (?modelContext :: ModelContext) =>
    Int ->
    Int ->
    Staff ->
    [(RosterGroup, [SlotName])] ->
    IO ()
seedStaffShiftPreferenceRecords _ _ _ [] = pure ()
seedStaffShiftPreferenceRecords seedValue staffIndex staff groupSlots = do
    let desiredPreferenceCount = 1 + deterministicIndex seedValue [staffIndex, 401] 5
    let preferenceSelections =
            take desiredPreferenceCount
                (buildShiftPreferenceSelections seedValue staffIndex groupSlots)
    createStaffShiftPreferenceRecords staff (nub preferenceSelections)

createStaffShiftPreferenceRecords :: (?modelContext :: ModelContext) => Staff -> [ShiftPreferenceSelection] -> IO ()
createStaffShiftPreferenceRecords _ [] = pure ()
createStaffShiftPreferenceRecords staff selections = do
    preferenceIds <- map Id <$> freshUUIDs (length selections)
    now <- getCurrentTime
    void (createMany (zipWith (staffShiftPreferenceRecord now staff) preferenceIds selections))

staffShiftPreferenceRecord :: UTCTime -> Staff -> Id StaffShiftPreference -> ShiftPreferenceSelection -> StaffShiftPreference
staffShiftPreferenceRecord now staff preferenceId selection =
    newRecord @StaffShiftPreference
        |> set #id preferenceId
        |> set #venueId staff.venueId
        |> set #staffId (unpackId staff.id)
        |> set #weekdayIndex selection.weekdayIndex
        |> set #preferredStartHour selection.startHour
        |> set #preferredEndHour selection.endHour
        |> set #createdAt now
        |> set #updatedAt now

buildShiftPreferenceSelections ::
    Int ->
    Int ->
    [(RosterGroup, [SlotName])] ->
    [ShiftPreferenceSelection]
buildShiftPreferenceSelections seedValue staffIndex groupSlots =
    nub
        [ ShiftPreferenceSelection
            { weekdayIndex = weekdayIndex
            , startHour = 5
            , endHour = 23
            }
        | offset <- [0 :: Int .. 9]
        , let groupIndex = deterministicIndex seedValue [staffIndex, 410, offset] (length groupSlots)
        , let (_rosterGroup, slotNames) = groupSlots !! groupIndex
        , not (null slotNames)
        , let weekdayIndex = uniqueWeekdaySequence seedValue [staffIndex, 412] !! (offset `mod` 7)
        ]

seedRosterGroup ::
    (?modelContext :: ModelContext) =>
    Int ->
    Int ->
    Day ->
    RosterGroup ->
    [RosterDay] ->
    [SlotName] ->
    [Staff] ->
    [ShiftType] ->
    IO ()
seedRosterGroup seedValue fillPercent fixtureWeekStart rosterGroup rosterDays slotNames staffPool shiftTypes = do
    forM_ (zip [0 :: Int ..] rosterDays) \(dayIndex, rosterDay) -> do
        let rowCount = 2
        _ <- rosterDay
            |> set #rowCount rowCount
            |> updateRecord
        let seedRows _ [] = pure ()
            seedRows usedStaffIds (rowIndex:remainingRowIndexes) = do
                let (assignments, nextUsedStaffIds) =
                        buildRowAssignments seedValue fillPercent dayIndex rowIndex slotNames staffPool shiftTypes usedStaffIds
                createRosterRow rosterDay slotNames rowIndex assignments
                seedRows nextUsedStaffIds remainingRowIndexes
        seedRows [] [0 .. rowCount - 1]
    ensureAssignedShiftPreferenceCoverage fixtureWeekStart rosterGroup rosterDays

seedRosterWindow ::
    (?modelContext :: ModelContext) =>
    SeedScenario ->
    Day ->
    Venue ->
    RosterGroup ->
    RosterGroup ->
    [SlotName] ->
    [SlotName] ->
    [Staff] ->
    [Staff] ->
    [ShiftType] ->
    IO ()
seedRosterWindow scenario currentWeekStart venue frontGroup backGroup frontSlots backSlots frontCandidates backCandidates shiftTypes =
    forM_ devSeedWeekStarts \(weekIndex, weekStart) -> do
        let weekOffset = weekOffsetFor weekStart
        frontWeek <- createRosterWeekRecordForRosterGroup venue frontGroup weekOffset (weekIndex == 0)
        backWeek <- createRosterWeekRecordForRosterGroup venue backGroup weekOffset False
        frontDays <- createRosterDayRecords frontWeek [0 .. 6]
        backDays <- createRosterDayRecords backWeek [0 .. 6]
        let weekSeed = scenario.scenarioSeed + (weekIndex * 1009)
        seedRosterGroup weekSeed (rosterFillForWeek scenario.rosterFillPercent weekIndex) weekStart frontGroup frontDays frontSlots frontCandidates shiftTypes
        seedRosterGroup (weekSeed + 97) (max 40 (rosterFillForWeek scenario.rosterFillPercent weekIndex - 8)) weekStart backGroup backDays backSlots backCandidates shiftTypes
    where
        devSeedWeekStarts =
            [ (-1, addDays (-7) currentWeekStart)
            , (0, currentWeekStart)
            , (1, addDays 7 currentWeekStart)
            ]

rosterFillForWeek :: Int -> Int -> Int
rosterFillForWeek fillPercent weekIndex =
    clampRosterFill (fillPercent - abs weekIndex * 6)

clampRosterFill :: Int -> Int
clampRosterFill = max 35 . min 100

buildRowAssignments ::
    Int ->
    Int ->
    Int ->
    Int ->
    [SlotName] ->
    [Staff] ->
    [ShiftType] ->
    [UUID] ->
    ([(Text, DevRosterSlotSeed)], [UUID])
buildRowAssignments seedValue fillPercent dayIndex rowIndex slotNames staffPool shiftTypes initialUsedStaffIds =
    ensureMinimumStaffedRow (rowAssignments, rowUsedStaffIds)
    where
        (rowAssignments, rowUsedStaffIds) =
            foldl'
                (\(assignments, usedStaffIds) (slotIndex, slotName) ->
                    case seedAssignment seedValue fillPercent dayIndex rowIndex slotIndex slotName staffPool shiftTypes usedStaffIds of
                        Just (assignment, selectedStaffId) -> (assignments <> [assignment], usedStaffIds <> [selectedStaffId])
                        Nothing -> (assignments, usedStaffIds)
                )
                ([], initialUsedStaffIds)
                (zip [0 :: Int ..] slotNames)

        ensureMinimumStaffedRow result@(assignments, usedStaffIds)
            | null slotNames = result
            | any (isJust . (.slotStaff) . snd) assignments = result
            | otherwise =
                case forceAssignmentForRow seedValue dayIndex rowIndex slotNames staffPool shiftTypes usedStaffIds of
                    Just (assignment, selectedStaffId) -> ([assignment], usedStaffIds <> [selectedStaffId])
                    Nothing -> result

forceAssignmentForRow ::
    Int ->
    Int ->
    Int ->
    [SlotName] ->
    [Staff] ->
    [ShiftType] ->
    [UUID] ->
    Maybe ((Text, DevRosterSlotSeed), UUID)
forceAssignmentForRow seedValue dayIndex rowIndex slotNames staffPool shiftTypes usedStaffIds = do
    let slotIndex = deterministicIndex seedValue [dayIndex, rowIndex, 991] (length slotNames)
    let slotName = slotNames !! slotIndex
    staff <- chooseAvailableStaff seedValue [dayIndex, rowIndex, slotIndex, 992, textHash (get #name slotName)] staffPool usedStaffIds
    pure
        ( ( get #name slotName
          , seededRosterSlot
                (Just staff)
                (slotStartTimeFor slotIndex dayIndex)
                (slotShiftTypeIdFor seedValue [dayIndex, rowIndex, slotIndex, 993] shiftTypes)
          )
        , unpackId (get #id staff)
        )

seedAssignment :: Int -> Int -> Int -> Int -> Int -> SlotName -> [Staff] -> [ShiftType] -> [UUID] -> Maybe ((Text, DevRosterSlotSeed), UUID)
seedAssignment _ _ _ _ _ _ [] _ _ = Nothing
seedAssignment seedValue fillPercent dayIndex rowIndex slotIndex slotName staffPool shiftTypes usedStaffIds
    | deterministicPercent seedValue [dayIndex, rowIndex, slotIndex] >= fillPercent = Nothing
    | otherwise =
        selectedStaff >>= \staff ->
            Just
                ( ( get #name slotName
                  , seededRosterSlot
                        (Just staff)
                        (slotStartTimeFor slotIndex dayIndex)
                        (slotShiftTypeIdFor seedValue [dayIndex, rowIndex, slotIndex, textHash (get #name slotName)] shiftTypes)
                  )
                , unpackId (get #id staff)
                )
    where
        selectedStaff = chooseAvailableStaff seedValue [dayIndex, rowIndex, slotIndex, textHash (get #name slotName)] staffPool usedStaffIds

chooseAvailableStaff :: Int -> [Int] -> [Staff] -> [UUID] -> Maybe Staff
chooseAvailableStaff _ _ [] _ = Nothing
chooseAvailableStaff seedValue keys staffPool usedStaffIds =
    listToMaybe preferredPool <|> listToMaybe staffPool
    where
        rotatedPool = rotateList (deterministicIndex seedValue keys (length staffPool)) staffPool
        preferredPool =
            filter (\staff -> unpackId (get #id staff) `notElem` usedStaffIds) rotatedPool

data StaffPreferenceTarget = StaffPreferenceTarget
    { targetStaffId   :: !UUID
    , targetSelection :: !ShiftPreferenceSelection
    }
    deriving (Eq, Show)

ensureAssignedShiftPreferenceCoverage ::
    (?modelContext :: ModelContext) =>
    Day ->
    RosterGroup ->
    [RosterDay] ->
    IO ()
ensureAssignedShiftPreferenceCoverage fixtureWeekStart rosterGroup rosterDays = do
    let rosterDayIds = map (unpackId . get #id) rosterDays
    let dayOffsetsById = Map.fromList (map (\rosterDay -> (unpackId (get #id rosterDay), rosterDay.dayOffset)) rosterDays)

    assignedSlots <-
        query @RosterSlot
            |> filterWhereIn (#rosterDayId, rosterDayIds)
            |> orderByAsc #rosterDayId
            |> orderByAsc #rowIndex
            |> orderByAsc #slotSortOrder
            |> fetch
    let assignedSlotsWithStaff = filter (isJust . (.staffId)) assignedSlots

    let assignedStaffIds = nub (mapMaybe (.staffId) assignedSlotsWithStaff)
    unless (null assignedStaffIds) do
        existingPreferences <-
            query @StaffShiftPreference
                |> filterWhereIn (#staffId, assignedStaffIds)
                |> fetch

        let existingTargets = map staffShiftPreferenceToTarget existingPreferences
        let missingTargets = mapMaybe (missingPreferenceTarget fixtureWeekStart dayOffsetsById rosterGroup existingTargets) assignedSlotsWithStaff
        let requiredPreferredCount = minimumPreferredSlotCount (length assignedSlotsWithStaff)
        let existingPreferredCount = length assignedSlotsWithStaff - length missingTargets
        let missingPreferredCount = max 0 (requiredPreferredCount - existingPreferredCount)

        backfillAssignedShiftPreferences rosterGroup existingTargets missingTargets missingPreferredCount

backfillAssignedShiftPreferences ::
    (?modelContext :: ModelContext) =>
    RosterGroup ->
    [StaffPreferenceTarget] ->
    [StaffPreferenceTarget] ->
    Int ->
    IO ()
backfillAssignedShiftPreferences _ _ _ remainingNeeded | remainingNeeded <= 0 = pure ()
backfillAssignedShiftPreferences rosterGroup existingTargets missingTargets remainingNeeded =
    go existingTargets missingTargets remainingNeeded
    where
        venueId = rosterGroup.venueId

        go _ _ needed | needed <= 0 = pure ()
        go _ [] _ = pure ()
        go coveredTargets (target:remainingTargets) needed
            | target `elem` coveredTargets =
                go coveredTargets remainingTargets (needed - 1)
            | otherwise = do
                createStaffShiftPreferenceRecords
                    (preferenceTargetStaff venueId target)
                    [target.targetSelection]
                go (target : coveredTargets) remainingTargets (needed - 1)

preferenceTargetStaff :: UUID -> StaffPreferenceTarget -> Staff
preferenceTargetStaff venueId target =
    newRecord @Staff
        |> set #venueId venueId
        |> set #id (Id target.targetStaffId)

missingPreferenceTarget ::
    Day ->
    Map.Map UUID Int ->
    RosterGroup ->
    [StaffPreferenceTarget] ->
    RosterSlot ->
    Maybe StaffPreferenceTarget
missingPreferenceTarget fixtureWeekStart dayOffsetsById rosterGroup existingTargets rosterSlot = do
    staffId <- rosterSlot.staffId
    dayOffset <- Map.lookup rosterSlot.rosterDayId dayOffsetsById
    let target =
            StaffPreferenceTarget
                { targetStaffId = staffId
                , targetSelection =
                    ShiftPreferenceSelection
                        { weekdayIndex = weekdayIndexForFixtureDay fixtureWeekStart dayOffset
                        , startHour = 5
                        , endHour = 23
                        }
                }
    if target `elem` existingTargets
        then Nothing
        else Just target

staffShiftPreferenceToTarget :: StaffShiftPreference -> StaffPreferenceTarget
staffShiftPreferenceToTarget preference =
    StaffPreferenceTarget
        { targetStaffId = preference.staffId
        , targetSelection =
            ShiftPreferenceSelection
                { weekdayIndex = preference.weekdayIndex
                , startHour = preference.preferredStartHour
                , endHour = preference.preferredEndHour
                }
        }

minimumPreferredSlotCount :: Int -> Int
minimumPreferredSlotCount assignedSlotCount =
    ceiling ((fromIntegral assignedSlotCount :: Double) * 0.8)

weekdayIndexForFixtureDay :: Day -> Int -> Int
weekdayIndexForFixtureDay fixtureWeekStart dayOffset =
    case fromEnum (dayOfWeek (addDays (toInteger dayOffset) fixtureWeekStart)) of
        7     -> 0
        index -> index

rotateList :: Int -> [a] -> [a]
rotateList _ [] = []
rotateList offset values =
    drop clampedOffset values <> take clampedOffset values
    where
        clampedOffset = offset `mod` length values

seedLeaveRequests :: (?modelContext :: ModelContext) => Day -> Day -> Venue -> SeedScenario -> [Staff] -> IO ()
seedLeaveRequests fixtureWeekStart _leaveMonthAnchor venue scenario staffPool = do
    let approvedCount = max 0 (scenario.leaveRequestCount - scenario.pendingLeaveCount - scenario.deniedLeaveCount)
        leaveDates = spreadLeaveDatesAcrossSeedWindow fixtureWeekStart scenario.leaveRequestCount
    createLeaveBatch venue staffPool leaveDates 0 approvedCount "approved"
    createLeaveBatch venue staffPool leaveDates approvedCount scenario.pendingLeaveCount "pending"
    createLeaveBatch venue staffPool leaveDates (approvedCount + scenario.pendingLeaveCount) scenario.deniedLeaveCount "denied"

createLeaveBatch :: (?modelContext :: ModelContext) => Venue -> [Staff] -> [(Day, Day)] -> Int -> Int -> Text -> IO ()
createLeaveBatch venue staffPool leaveDates startIndex count status =
    forM_ (zip [startIndex ..] (zip (drop startIndex (cycle staffPool)) (take count (drop startIndex leaveDates)))) \(index, (staff, (startDate, endDate))) -> do
        _ <- createLeaveRequestRecordWithNotes venue staff startDate endDate status (Just (leaveNoteFor status index))
        pure ()

spreadLeaveDatesAcrossSeedWindow :: Day -> Int -> [(Day, Day)]
spreadLeaveDatesAcrossSeedWindow fixtureWeekStart count
    | count <= 0 = []
    | otherwise = map leaveWindowForIndex [0 .. count - 1]
    where
        windowStart = addDays (-7) fixtureWeekStart
        windowEnd = addDays 12 fixtureWeekStart
        windowSpanDays = max 0 (diffDays windowEnd windowStart)
        divisor = max 1 (count - 1)

        leaveWindowForIndex index =
            let startOffset = (toInteger index * windowSpanDays) `div` toInteger divisor
                durationDays = toInteger (1 + (index `mod` 2))
                startDate = addDays startOffset windowStart
                endDate = addDays durationDays startDate
             in (startDate, endDate)

leaveNoteFor :: Text -> Int -> Text
leaveNoteFor status index =
    noteBank !! deterministicIndex (textHash status + 7001) [index, Text.length status] (length noteBank)
    where
        noteBank =
            [ "Family event"
            , "Medical appointment"
            , "Interstate travel"
            , "Study leave"
            , "School holiday care"
            , "Personal day"
            , "Wedding weekend"
            , "Carer responsibilities"
            ]

seedTimesheets ::
    (?modelContext :: ModelContext) =>
    Day ->
    Venue ->
    User ->
    SeedScenario ->
    ShiftType ->
    ShiftType ->
    [Staff] ->
    UTCTime ->
    IO ()
seedTimesheets fixtureWeekStart venue admin scenario floorShift kitchenShift staffPool approvedAt = do
    seededXeroCaseCount <-
        seedXeroPayCalendarTimesheets
            venue
            admin
            floorShift
            kitchenShift
            staffPool
            approvedAt
    let remainingApprovedCount = max 0 (scenario.approvedTimesheets - seededXeroCaseCount)
    let approvedStaffPool = concat (replicate 3 (seededXeroMatchedStaffPool staffPool)) <> staffPool
    forM_ (zip [0 ..] (take remainingApprovedCount (cycle approvedStaffPool))) \(index, staff) -> do
        let globalIndex = index + seededXeroCaseCount
        let shiftTypeId =
                if globalIndex `mod` 4 == 0
                    then unpackId (get #id kitchenShift)
                    else unpackId (get #id floorShift)
        let (hadBreak, breakStartTime, breakEndTime, breakMinutes) =
                seededBreakFields scenario.scenarioSeed globalIndex
        entry <-
            createTimesheetEntryRecord venue staff (seededTimesheetWorkedOn fixtureWeekStart globalIndex)
                >>= updateRecord
                    . set #shiftTypeId shiftTypeId
                    . set #startTime (TimeOfDay (6 + ((globalIndex * 2) `mod` 8)) 0 0)
                    . set #endTime (TimeOfDay (12 + ((globalIndex * 2) `mod` 8)) 0 0)
                    . set #hadBreak hadBreak
                    . set #breakStartTime breakStartTime
                    . set #breakEndTime breakEndTime
                    . set #breakMinutes breakMinutes
        (staffPayVersion, shiftTypePayVersion) <- ensurePayVersionsForTimesheetApproval admin.id entry
        lockPayVersionsForApproval admin.id approvedAt staffPayVersion shiftTypePayVersion
        _ <- entry
            |> set #isApproved True
            |> set #staffPayVersionId (Just (unpackId staffPayVersion.id))
            |> set #shiftTypePayVersionId (Just (unpackId shiftTypePayVersion.id))
            |> set #approvedAt (Just approvedAt)
            |> set #approvedByUserId (Just (unpackId admin.id))
            |> updateRecord
        pure ()
    let pendingStaffPool = nonXeroMatchedStaffPool staffPool <> staffPool
    forM_ (zip [0 ..] (take scenario.pendingTimesheets (drop scenario.approvedTimesheets (cycle pendingStaffPool)))) \(index, staff) -> do
        let globalIndex = scenario.approvedTimesheets + index
        let (hadBreak, breakStartTime, breakEndTime, breakMinutes) =
                seededBreakFields scenario.scenarioSeed globalIndex
        _ <-
            createTimesheetEntryRecord venue staff (seededTimesheetWorkedOn fixtureWeekStart (globalIndex + 2))
                >>= updateRecord
                    . set #shiftTypeId (unpackId (get #id floorShift))
                    . set #startTime (TimeOfDay (9 + (index `mod` 3)) 0 0)
                    . set #endTime (TimeOfDay (15 + (index `mod` 3)) 0 0)
                    . set #hadBreak hadBreak
                    . set #breakStartTime breakStartTime
                    . set #breakEndTime breakEndTime
                    . set #breakMinutes breakMinutes
        pure ()

data SeededXeroTimesheetCase = SeededXeroTimesheetCase
    { caseFirstName :: !Text
    , caseLastName  :: !Text
    , caseWorkedOn  :: !Day
    , caseShiftType :: !SeededTimesheetShiftType
    , caseStartTime :: !TimeOfDay
    , caseEndTime   :: !TimeOfDay
    , caseBreak     :: !SeededTimesheetBreak
    }

data SeededTimesheetShiftType
    = SeededFloorShift
    | SeededKitchenShift

data SeededTimesheetBreak
    = SeededNoBreak
    | SeededBreak !TimeOfDay !TimeOfDay !Int

seedXeroPayCalendarTimesheets ::
    (?modelContext :: ModelContext) =>
    Venue ->
    User ->
    ShiftType ->
    ShiftType ->
    [Staff] ->
    UTCTime ->
    IO Int
seedXeroPayCalendarTimesheets venue admin floorShift kitchenShift staffPool approvedAt = do
    entries <-
        forM seededXeroPayCalendarCases \seedCase ->
            case findStaffByName seedCase.caseFirstName seedCase.caseLastName staffPool of
                Nothing -> pure Nothing
                Just staff -> do
                    Just <$> createApprovedSeededTimesheetCase venue admin floorShift kitchenShift staff approvedAt seedCase
    pure (length (catMaybes entries))

createApprovedSeededTimesheetCase ::
    (?modelContext :: ModelContext) =>
    Venue ->
    User ->
    ShiftType ->
    ShiftType ->
    Staff ->
    UTCTime ->
    SeededXeroTimesheetCase ->
    IO TimesheetEntry
createApprovedSeededTimesheetCase venue admin floorShift kitchenShift staff approvedAt seedCase = do
    entry <-
        createTimesheetEntryRecord venue staff seedCase.caseWorkedOn
            >>= updateRecord
                . set #shiftTypeId (seededCaseShiftTypeId seedCase.caseShiftType floorShift kitchenShift)
                . set #startTime seedCase.caseStartTime
                . set #endTime seedCase.caseEndTime
                . applySeededBreak seedCase.caseBreak
    approveSeededTimesheetEntry admin approvedAt entry

approveSeededTimesheetEntry ::
    (?modelContext :: ModelContext) =>
    User ->
    UTCTime ->
    TimesheetEntry ->
    IO TimesheetEntry
approveSeededTimesheetEntry admin approvedAt entry = do
    (staffPayVersion, shiftTypePayVersion) <- ensurePayVersionsForTimesheetApproval admin.id entry
    lockPayVersionsForApproval admin.id approvedAt staffPayVersion shiftTypePayVersion
    entry
        |> set #isApproved True
        |> set #staffPayVersionId (Just (unpackId staffPayVersion.id))
        |> set #shiftTypePayVersionId (Just (unpackId shiftTypePayVersion.id))
        |> set #approvedAt (Just approvedAt)
        |> set #approvedByUserId (Just (unpackId admin.id))
        |> updateRecord

seededCaseShiftTypeId :: SeededTimesheetShiftType -> ShiftType -> ShiftType -> UUID
seededCaseShiftTypeId SeededFloorShift floorShift _ = unpackId (get #id floorShift)
seededCaseShiftTypeId SeededKitchenShift _ kitchenShift = unpackId (get #id kitchenShift)

applySeededBreak :: SeededTimesheetBreak -> TimesheetEntry -> TimesheetEntry
applySeededBreak SeededNoBreak =
    set #hadBreak False
        . set #breakStartTime Nothing
        . set #breakEndTime Nothing
        . set #breakMinutes 0
applySeededBreak (SeededBreak startTime endTime minutes) =
    set #hadBreak True
        . set #breakStartTime (Just startTime)
        . set #breakEndTime (Just endTime)
        . set #breakMinutes minutes

findStaffByName :: Text -> Text -> [Staff] -> Maybe Staff
findStaffByName firstName lastName =
    find (\staff -> staff.firstName == firstName && staff.lastName == lastName)

seededXeroPayCalendarCases :: [SeededXeroTimesheetCase]
seededXeroPayCalendarCases =
    -- Fortnightly Calendar current period ending 26 May 2026.
    seededXeroCalendarWindowCases
        (fromGregorian 2026 5 13)
        (fromGregorian 2026 5 26)
        [ ("James", "Lebron")
        , ("Oliver", "Grey")
        , ("Sally", "Martin")
        ]
        <>
    -- Weekly Calendar current period ending 5 May 2026.
    seededXeroCalendarWindowCases
        (fromGregorian 2026 4 29)
        (fromGregorian 2026 5 5)
        [ ("Odette", "Garrison")
        , ("Tracy", "Green")
        ]

seededXeroCalendarWindowCases :: Day -> Day -> [(Text, Text)] -> [SeededXeroTimesheetCase]
seededXeroCalendarWindowCases startDate endDate staffNames =
    concat
        [ map (seededXeroCaseForDay staffIndex firstName lastName) (zip [0 ..] (dateRange startDate endDate))
        | (staffIndex, (firstName, lastName)) <- zip [0 ..] staffNames
        ]

seededXeroCaseForDay :: Int -> Text -> Text -> (Int, Day) -> SeededXeroTimesheetCase
seededXeroCaseForDay staffIndex firstName lastName (dayIndex, workedOn) =
    let template = seededXeroTimesheetTemplates !! ((staffIndex * 3 + dayIndex) `mod` length seededXeroTimesheetTemplates)
     in xeroCase firstName lastName workedOn template.templateShiftType template.templateStartTime template.templateEndTime template.templateBreak

dateRange :: Day -> Day -> [Day]
dateRange startDate endDate =
    takeWhile (<= endDate) (iterate (addDays 1) startDate)

data SeededXeroTimesheetTemplate = SeededXeroTimesheetTemplate
    { templateShiftType :: !SeededTimesheetShiftType
    , templateStartTime :: !TimeOfDay
    , templateEndTime   :: !TimeOfDay
    , templateBreak     :: !SeededTimesheetBreak
    }

seededXeroTimesheetTemplates :: [SeededXeroTimesheetTemplate]
seededXeroTimesheetTemplates =
    [ xeroTemplate SeededFloorShift (TimeOfDay 9 0 0) (TimeOfDay 17 0 0) (SeededBreak (TimeOfDay 15 30 0) (TimeOfDay 16 0 0) 30)
    , xeroTemplate SeededFloorShift (TimeOfDay 18 0 0) (TimeOfDay 1 0 0) (SeededBreak (TimeOfDay 21 30 0) (TimeOfDay 22 0 0) 30)
    , xeroTemplate SeededKitchenShift (TimeOfDay 10 0 0) (TimeOfDay 16 0 0) (SeededBreak (TimeOfDay 12 30 0) (TimeOfDay 13 0 0) 30)
    , xeroTemplate SeededFloorShift (TimeOfDay 22 0 0) (TimeOfDay 2 0 0) (SeededBreak (TimeOfDay 23 30 0) (TimeOfDay 0 0 0) 30)
    , xeroTemplate SeededKitchenShift (TimeOfDay 8 0 0) (TimeOfDay 14 0 0) SeededNoBreak
    , xeroTemplate SeededFloorShift (TimeOfDay 12 0 0) (TimeOfDay 20 0 0) SeededNoBreak
    , xeroTemplate SeededKitchenShift (TimeOfDay 6 0 0) (TimeOfDay 14 0 0) (SeededBreak (TimeOfDay 10 0 0) (TimeOfDay 10 30 0) 30)
    ]

xeroTemplate ::
    SeededTimesheetShiftType ->
    TimeOfDay ->
    TimeOfDay ->
    SeededTimesheetBreak ->
    SeededXeroTimesheetTemplate
xeroTemplate shiftType startTime endTime timesheetBreak =
    SeededXeroTimesheetTemplate
        { templateShiftType = shiftType
        , templateStartTime = startTime
        , templateEndTime = endTime
        , templateBreak = timesheetBreak
        }

xeroCase ::
    Text ->
    Text ->
    Day ->
    SeededTimesheetShiftType ->
    TimeOfDay ->
    TimeOfDay ->
    SeededTimesheetBreak ->
    SeededXeroTimesheetCase
xeroCase firstName lastName workedOn shiftType startTime endTime timesheetBreak =
    SeededXeroTimesheetCase
        { caseFirstName = firstName
        , caseLastName = lastName
        , caseWorkedOn = workedOn
        , caseShiftType = shiftType
        , caseStartTime = startTime
        , caseEndTime = endTime
        , caseBreak = timesheetBreak
        }

seededTimesheetWorkedOn :: Day -> Int -> Day
seededTimesheetWorkedOn fixtureWeekStart index =
    addDays (toInteger weekStartOffset + toInteger (index `mod` 7)) fixtureWeekStart
    where
        weekStartOffset =
            case index `mod` 3 of
                0 -> -7
                1 -> 0
                _ -> 7

seededXeroMatchedStaffPool :: [Staff] -> [Staff]
seededXeroMatchedStaffPool staffPool =
    filter seededStaffHasXeroEmployeeMatch staffPool

nonXeroMatchedStaffPool :: [Staff] -> [Staff]
nonXeroMatchedStaffPool staffPool =
    filter (not . seededStaffHasXeroEmployeeMatch) staffPool

seededStaffHasXeroEmployeeMatch :: Staff -> Bool
seededStaffHasXeroEmployeeMatch staff =
    (staff.firstName, staff.lastName)
        `elem`
            [ ("Alice", "Front")
            , ("Bob", "Both")
            , ("James", "Lebron")
            , ("Oliver", "Grey")
            , ("Odette", "Garrison")
            , ("Sally", "Martin")
            , ("Tracy", "Green")
            ]

seededBreakFields :: Int -> Int -> (Bool, Maybe TimeOfDay, Maybe TimeOfDay, Int)
seededBreakFields seedValue index
    | deterministicPercent seedValue [index, 901] < 80 =
        let breakStartHour = 10 + (index `mod` 4)
            breakStartMinute = if deterministicPercent seedValue [index, 902] < 50 then 0 else 15
            breakLengthMinutes = if deterministicPercent seedValue [index, 903] < 55 then 30 else 45
            breakStartTime = TimeOfDay breakStartHour breakStartMinute 0
            breakEndTime = addBreakMinutes breakStartTime breakLengthMinutes
         in (True, Just breakStartTime, Just breakEndTime, breakLengthMinutes)
    | otherwise = (False, Nothing, Nothing, 0)

addBreakMinutes :: TimeOfDay -> Int -> TimeOfDay
addBreakMinutes startTime minutes =
    let totalMinutes = todHour startTime * 60 + todMin startTime + minutes
     in TimeOfDay (totalMinutes `div` 60) (totalMinutes `mod` 60) 0

createRosterDayRecords :: (?modelContext :: ModelContext) => RosterWeek -> [Int] -> IO [RosterDay]
createRosterDayRecords _ [] = pure []
createRosterDayRecords rosterWeek dayOffsets = do
    rosterDayIds <- map Id <$> freshUUIDs (length dayOffsets)
    now <- getCurrentTime
    createMany (zipWith (rosterDayRecord now rosterWeek) rosterDayIds dayOffsets)

rosterDayRecord :: UTCTime -> RosterWeek -> Id RosterDay -> Int -> RosterDay
rosterDayRecord now rosterWeek rosterDayId dayOffset =
    newRecord @RosterDay
        |> set #id rosterDayId
        |> set #rosterWeekId (unpackId (get #id rosterWeek))
        |> set #dayOffset dayOffset
        |> set #isClosed False
        |> set #createdAt now
        |> set #updatedAt now

createRosterRow ::
    (?modelContext :: ModelContext) =>
    RosterDay ->
    [SlotName] ->
    Int ->
    [(Text, DevRosterSlotSeed)] ->
    IO ()
createRosterRow rosterDay slotNames rowIndex assignments = do
    slotDefinitions <- forM slotNames (ensureRosterWeekSlotDefinitionForSlotName rosterDay)
    let assignedSlotDefinitions =
            [ (slotDefinition, slotSeed)
            | slotDefinition <- slotDefinitions
            , Just slotSeed <- [lookup (get #name slotDefinition) assignments]
            ]
    rosterSlotIds <- map Id <$> freshUUIDs (length assignedSlotDefinitions)
    now <- getCurrentTime
    void (createMany (zipWith (rosterSlotRecord now rosterDay rowIndex) rosterSlotIds assignedSlotDefinitions))
    where
        rosterSlotRecord now rosterDay rowIndex rosterSlotId (slotDefinition, slotSeed) =
            newRecord @RosterSlot
                    |> set #id rosterSlotId
                    |> set #rosterDayId (unpackId (get #id rosterDay))
                    |> set #rosterWeekSlotDefinitionId (unpackId (get #id slotDefinition))
                    |> set #slotSortOrder slotDefinition.sortOrder
                    |> set #staffId (fmap (unpackId . get #id) slotSeed.slotStaff)
                    |> set #shiftTypeId slotSeed.slotShiftTypeId
                    |> set #rowIndex rowIndex
                    |> set #startTime slotSeed.slotStartTime
                    |> set #createdAt now
                    |> set #updatedAt now

seededRosterSlot :: Maybe Staff -> TimeOfDay -> Maybe UUID -> DevRosterSlotSeed
seededRosterSlot maybeStaff startTime maybeShiftTypeId =
    DevRosterSlotSeed
        { slotStaff = maybeStaff
        , slotStartTime = Just startTime
        , slotShiftTypeId = maybeShiftTypeId
        }

slotShiftTypeIdFor :: Int -> [Int] -> [ShiftType] -> Maybe UUID
slotShiftTypeIdFor _ _ [] = Nothing
slotShiftTypeIdFor seedValue keys shiftTypes =
    Just (unpackId (get #id (shiftTypes !! deterministicIndex seedValue keys (length shiftTypes))))

slotStartTimeFor :: Int -> Int -> TimeOfDay
slotStartTimeFor slotIndex dayIndex =
    case slotIndex of
        0 -> TimeOfDay (6 + (dayIndex `mod` 2)) 30 0
        1 -> TimeOfDay (11 + (dayIndex `mod` 2)) 0 0
        _ -> TimeOfDay (16 + (dayIndex `mod` 2)) 30 0

deterministicPercent :: Int -> [Int] -> Int
deterministicPercent seedValue keys = deterministicIndex seedValue keys 100

deterministicIndex :: Int -> [Int] -> Int -> Int
deterministicIndex _ _ 0 = 0
deterministicIndex seedValue keys modulus =
    abs (foldl' (\acc value -> (acc * 1103515245) + value + 12345) (seedValue + 17) keys) `mod` modulus

textHash :: Text -> Int
textHash = Text.foldl' (\acc ch -> (acc * 33) + fromEnum ch) 7

uniqueWeekdaySequence :: Int -> [Int] -> [Int]
uniqueWeekdaySequence seedValue keys =
    nub (map (\offset -> deterministicIndex seedValue (keys <> [offset]) 7) [0 :: Int .. 20])

preferredNameFor :: Int -> Int -> Text -> Maybe Text -> Maybe Text
preferredNameFor _ _ _ (Just preferredName) = Just preferredName
preferredNameFor seedValue index firstName Nothing
    | deterministicPercent seedValue [index, 601] < 32 =
        generatedNickname firstName
    | otherwise = Nothing

generatedNickname :: Text -> Maybe Text
generatedNickname firstName =
    case Text.toLower firstName of
        "alice" -> Just "Ali"
        "cara"  -> Just "C"
        "dylan" -> Just "Dyl"
        "frank" -> Just "Frankie"
        "jules" -> Just "J"
        "talia" -> Just "T"
        _       -> Nothing

managerNames :: [(Text, Text)]
managerNames =
    [ ("Morgan", "Manager")
    , ("Harper", "Lead")
    , ("Casey", "Shiftlead")
    , ("Jordan", "Supervisor")
    ]

generatedStaffCatalog :: [(Int, Text, Text, Maybe Text)]
generatedStaffCatalog =
    zipWith (\index (firstName, lastName, preferredName) -> (index, firstName, lastName, preferredName)) [0 ..] $
        [ ("Alice", "Front", Nothing)
        , ("Bob", "Both", Nothing)
        , ("James", "Lebron", Just "JL")
        , ("Oliver", "Grey", Nothing)
        , ("Odette", "Garrison", Nothing)
        , ("Sally", "Martin", Nothing)
        , ("Sonia", "Michaels", Nothing)
        , ("Tracy", "Green", Nothing)
        , ("Alice", "Host", Just "Ali")
        , ("Jules", "Cook", Nothing)
        , ("Kira", "Cafe", Nothing)
        , ("Luca", "Pass", Nothing)
        , ("Mia", "Morning", Nothing)
        , ("Noah", "Dish", Nothing)
        , ("Omar", "Floor", Nothing)
        , ("Piper", "Expo", Nothing)
        , ("Quinn", "Late", Nothing)
        , ("Rosa", "Morning", Just "Rosie")
        , ("Seth", "Grill", Nothing)
        , ("Talia", "Barista", Just "T")
        ]

data StaffAssignmentBucket
    = FrontOnly
    | BackOnly
    | CrossGroup
    deriving (Eq)

assignmentBucket :: Int -> StaffAssignmentBucket
assignmentBucket index =
    case index `mod` 6 of
        1 -> CrossGroup
        2 -> BackOnly
        5 -> BackOnly
        _ -> FrontOnly

safeIndex :: [a] -> Int -> Maybe a
safeIndex values index
    | index < 0 = Nothing
    | otherwise = listToMaybe (drop index values)

freshUUIDs :: Int -> IO [UUID]
freshUUIDs count =
    replicateM count UUIDv4.nextRandom

dayAtOffset :: Day -> Integer -> Day
dayAtOffset weekStart offset = addDays offset weekStart

weekOffsetFor :: Day -> Int
weekOffsetFor day = fromInteger (diffDays day defaultWeekEpoch `div` 7)
