module Application.Support.DevFixtures where

import Application.Helper.Controller (PlatformRole (..))
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        ensureVenueDefaultRosterGroup,
                                        fetchActiveRosterGroupSlotNames,
                                        syncStaffRosterGroupAssignments)
import Application.Helper.StaffShiftPreferences (ShiftPreferenceSelection (..))
import Application.Support
import Application.Support.Seed.Scenario
import Control.Monad (replicateM, void)
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays, dayOfWeek, diffDays, fromGregorian,
                           toGregorian)
import Data.Time.Clock (UTCTime (..), getCurrentTime, secondsToDiffTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Data.UUID (UUID)
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport.Types (CanCreate (createMany))
import IHP.Prelude

data DevRosterSlotSeed = DevRosterSlotSeed
    { slotStaff     :: !(Maybe Staff)
    , slotStartTime :: !(Maybe TimeOfDay)
    , slotNote      :: !(Maybe Text)
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
    resetDatabase
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

    floorShift <- createSeedShiftTypeRecord venue "Floor" 10
    kitchenShift <- createSeedShiftTypeRecord venue "Kitchen" 20
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

    seedStaffPreferencesAndAvailability
        scenario.scenarioSeed
        fixtureWeekStart
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
    frontWeek <- createRosterWeekRecordForRosterGroup venue frontGroup weekOffset True
    backWeek <- createRosterWeekRecordForRosterGroup venue backGroup weekOffset False

    frontDays <- createRosterDayRecords frontWeek [0 .. 6]
    backDays <- createRosterDayRecords backWeek [0 .. 6]
    seedRosterGroup scenario.scenarioSeed scenario.rosterFillPercent fixtureWeekStart frontGroup frontDays frontSlots allFrontCandidates
    seedRosterGroup (scenario.scenarioSeed + 97) (max 40 (scenario.rosterFillPercent - 8)) fixtureWeekStart backGroup backDays backSlots allBackCandidates

    let allOperationalStaff = managerStaffs <> [workerStaff] <> seededStaff <> trialStaffs

    seedLeaveRequests leaveMonthAnchor venue scenario allOperationalStaff

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

createSeedShiftTypeRecord :: (?modelContext :: ModelContext) => Venue -> Text -> Int -> IO ShiftType
createSeedShiftTypeRecord venue shiftTypeName sortOrder =
    newRecord @ShiftType
        |> set #venueId (unpackId (get #id venue))
        |> set #name shiftTypeName
        |> set #sortOrder sortOrder
        |> set #overrideAwardLevelId Nothing
        |> set #isActive True
        |> createRecord

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

seedStaffPreferencesAndAvailability ::
    (?modelContext :: ModelContext) =>
    Int ->
    Day ->
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
seedStaffPreferencesAndAvailability seedValue fixtureWeekStart frontGroup backGroup frontSlots backSlots managerStaffs workerStaff frontOnlyStaff backOnlyStaff crossGroupStaff trialStaffs = do
    forM_ (zip [0 :: Int ..] managerStaffs) \(index, staff) ->
        seedStaffRecurringPreferencesAndAvailability
            seedValue
            fixtureWeekStart
            (index + 1)
            staff
            [(frontGroup, frontSlots), (backGroup, backSlots)]
    seedStaffRecurringPreferencesAndAvailability
        seedValue
        fixtureWeekStart
        21
        workerStaff
        [(frontGroup, frontSlots)]
    forM_ (zip [0 :: Int ..] frontOnlyStaff) \(index, staff) ->
        seedStaffRecurringPreferencesAndAvailability
            seedValue
            fixtureWeekStart
            (40 + index)
            staff
            [(frontGroup, frontSlots)]
    forM_ (zip [0 :: Int ..] backOnlyStaff) \(index, staff) ->
        seedStaffRecurringPreferencesAndAvailability
            seedValue
            fixtureWeekStart
            (80 + index)
            staff
            [(backGroup, backSlots)]
    forM_ (zip [0 :: Int ..] crossGroupStaff) \(index, staff) ->
        seedStaffRecurringPreferencesAndAvailability
            seedValue
            fixtureWeekStart
            (120 + index)
            staff
            [(frontGroup, frontSlots), (backGroup, backSlots)]
    forM_ (zip [0 :: Int ..] trialStaffs) \(index, staff) ->
        seedStaffRecurringPreferencesAndAvailability
            seedValue
            fixtureWeekStart
            (160 + index)
            staff
            [(frontGroup, frontSlots)]

seedStaffRecurringPreferencesAndAvailability ::
    (?modelContext :: ModelContext) =>
    Int ->
    Day ->
    Int ->
    Staff ->
    [(RosterGroup, [SlotName])] ->
    IO ()
seedStaffRecurringPreferencesAndAvailability seedValue fixtureWeekStart staffIndex staff groupSlots = do
    seedStaffAvailabilityRecords seedValue fixtureWeekStart staffIndex staff
    seedStaffShiftPreferenceRecords seedValue staffIndex staff groupSlots

seedStaffAvailabilityRecords ::
    (?modelContext :: ModelContext) =>
    Int ->
    Day ->
    Int ->
    Staff ->
    IO ()
seedStaffAvailabilityRecords seedValue fixtureWeekStart staffIndex staff = do
    let venueId = staff.venueId
    let recurringUnavailabilityCount = deterministicIndex seedValue [staffIndex, 301] 3
    let recurringAvailableCount = deterministicIndex seedValue [staffIndex, 302] 2
    let recurringUnavailableWeekdays =
            take recurringUnavailabilityCount
                (uniqueWeekdaySequence seedValue [staffIndex, 303])
    let recurringAvailableWeekdays =
            take recurringAvailableCount
                (filter (`notElem` recurringUnavailableWeekdays) (uniqueWeekdaySequence seedValue [staffIndex, 304]))
    let recurringUnavailableSeeds =
            [ (Just weekdayIndex, Nothing, False, Just (availabilityNoteFor seedValue staffIndex noteIndex))
            | (noteIndex, weekdayIndex) <- zip [0 :: Int ..] recurringUnavailableWeekdays
            ]
    let recurringAvailableSeeds =
            [ (Just weekdayIndex, Nothing, True, Nothing)
            | weekdayIndex <- recurringAvailableWeekdays
            ]
    let specificDateSeeds =
            if deterministicPercent seedValue [staffIndex, 305] < 45
                then
                    let dateOffset = toInteger (deterministicIndex seedValue [staffIndex, 306] 7)
                        specificDate = dayAtOffset fixtureWeekStart dateOffset
                        isAvailable = deterministicPercent seedValue [staffIndex, 307] < 35
                     in [(Nothing, Just specificDate, isAvailable, Just (if isAvailable then "Requested swap" else "Study / childcare"))]
                else []
    let availabilitySeeds = recurringUnavailableSeeds <> recurringAvailableSeeds <> specificDateSeeds
    availabilityIds <- map Id <$> freshUUIDs (length availabilitySeeds)
    now <- getCurrentTime
    void (createMany (zipWith (availabilityRecord now venueId (unpackId staff.id)) availabilityIds availabilitySeeds))

availabilityRecord :: UTCTime -> UUID -> UUID -> Id StaffAvailability -> (Maybe Int, Maybe Day, Bool, Maybe Text) -> StaffAvailability
availabilityRecord now venueId staffId availabilityId (weekdayIndex, specificDate, isAvailable, note) =
    newRecord @StaffAvailability
        |> set #id availabilityId
        |> set #venueId venueId
        |> set #staffId staffId
        |> set #weekdayIndex weekdayIndex
        |> set #specificDate specificDate
        |> set #isAvailable isAvailable
        |> set #note note
        |> set #createdAt now
        |> set #updatedAt now

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
        |> set #rosterGroupId (unpackId selection.rosterGroupId)
        |> set #slotNameId (unpackId selection.slotNameId)
        |> set #weekdayIndex selection.weekdayIndex
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
            { rosterGroupId = get #id rosterGroup
            , weekdayIndex = weekdayIndex
            , slotNameId = get #id slotName
            }
        | offset <- [0 :: Int .. 9]
        , let groupIndex = deterministicIndex seedValue [staffIndex, 410, offset] (length groupSlots)
        , let (rosterGroup, slotNames) = groupSlots !! groupIndex
        , not (null slotNames)
        , let slotName = slotNames !! deterministicIndex seedValue [staffIndex, 411, offset] (length slotNames)
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
    IO ()
seedRosterGroup seedValue fillPercent fixtureWeekStart rosterGroup rosterDays slotNames staffPool = do
    forM_ (zip [0 :: Int ..] rosterDays) \(dayIndex, rosterDay) -> do
        let rowCount = 2
        let seedRows _ [] = pure ()
            seedRows usedStaffIds (rowIndex:remainingRowIndexes) = do
                let (assignments, nextUsedStaffIds) =
                        buildRowAssignments seedValue fillPercent dayIndex rowIndex slotNames staffPool usedStaffIds
                createRosterRow rosterDay slotNames rowIndex assignments
                seedRows nextUsedStaffIds remainingRowIndexes
        seedRows [] [0 .. rowCount - 1]
    ensureAssignedShiftPreferenceCoverage fixtureWeekStart rosterGroup rosterDays

buildRowAssignments ::
    Int ->
    Int ->
    Int ->
    Int ->
    [SlotName] ->
    [Staff] ->
    [UUID] ->
    ([(Text, DevRosterSlotSeed)], [UUID])
buildRowAssignments seedValue fillPercent dayIndex rowIndex slotNames staffPool initialUsedStaffIds =
    ensureMinimumStaffedRow (rowAssignments, rowUsedStaffIds)
    where
        (rowAssignments, rowUsedStaffIds) =
            foldl'
                (\(assignments, usedStaffIds) (slotIndex, slotName) ->
                    case seedAssignment seedValue fillPercent dayIndex rowIndex slotIndex slotName staffPool usedStaffIds of
                        Just (assignment, selectedStaffId) -> (assignments <> [assignment], usedStaffIds <> [selectedStaffId])
                        Nothing -> (assignments, usedStaffIds)
                )
                ([], initialUsedStaffIds)
                (zip [0 :: Int ..] slotNames)

        ensureMinimumStaffedRow result@(assignments, usedStaffIds)
            | null slotNames = result
            | any (isJust . (.slotStaff) . snd) assignments = result
            | otherwise =
                case forceAssignmentForRow seedValue dayIndex rowIndex slotNames staffPool usedStaffIds of
                    Just (assignment, selectedStaffId) -> ([assignment], usedStaffIds <> [selectedStaffId])
                    Nothing -> result

forceAssignmentForRow ::
    Int ->
    Int ->
    Int ->
    [SlotName] ->
    [Staff] ->
    [UUID] ->
    Maybe ((Text, DevRosterSlotSeed), UUID)
forceAssignmentForRow seedValue dayIndex rowIndex slotNames staffPool usedStaffIds = do
    let slotIndex = deterministicIndex seedValue [dayIndex, rowIndex, 991] (length slotNames)
    let slotName = slotNames !! slotIndex
    staff <- chooseAvailableStaff seedValue [dayIndex, rowIndex, slotIndex, 992, textHash (get #name slotName)] staffPool usedStaffIds
    pure
        ( ( get #name slotName
          , seededRosterSlot
                (Just staff)
                (slotStartTimeFor slotIndex dayIndex)
                (slotNoteFor seedValue dayIndex rowIndex slotIndex)
          )
        , unpackId (get #id staff)
        )

seedAssignment :: Int -> Int -> Int -> Int -> Int -> SlotName -> [Staff] -> [UUID] -> Maybe ((Text, DevRosterSlotSeed), UUID)
seedAssignment _ _ _ _ _ _ [] _ = Nothing
seedAssignment seedValue fillPercent dayIndex rowIndex slotIndex slotName staffPool usedStaffIds
    | deterministicPercent seedValue [dayIndex, rowIndex, slotIndex] >= fillPercent = Nothing
    | otherwise =
        selectedStaff >>= \staff ->
            Just
                ( ( get #name slotName
                  , seededRosterSlot
                        (Just staff)
                        (slotStartTimeFor slotIndex dayIndex)
                        (slotNoteFor seedValue dayIndex rowIndex slotIndex)
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
                |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
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
                        { rosterGroupId = rosterGroup.id
                        , weekdayIndex = weekdayIndexForFixtureDay fixtureWeekStart dayOffset
                        , slotNameId = Id rosterSlot.slotNameId
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
                { rosterGroupId = Id preference.rosterGroupId
                , weekdayIndex = preference.weekdayIndex
                , slotNameId = Id preference.slotNameId
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

seedLeaveRequests :: (?modelContext :: ModelContext) => Day -> Venue -> SeedScenario -> [Staff] -> IO ()
seedLeaveRequests leaveMonthAnchor venue scenario staffPool = do
    let approvedCount = max 0 (scenario.leaveRequestCount - scenario.pendingLeaveCount - scenario.deniedLeaveCount)
        leaveDates = spreadLeaveDatesAcrossMonth leaveMonthAnchor scenario.leaveRequestCount
    createLeaveBatch venue staffPool leaveDates 0 approvedCount "approved"
    createLeaveBatch venue staffPool leaveDates approvedCount scenario.pendingLeaveCount "pending"
    createLeaveBatch venue staffPool leaveDates (approvedCount + scenario.pendingLeaveCount) scenario.deniedLeaveCount "denied"

createLeaveBatch :: (?modelContext :: ModelContext) => Venue -> [Staff] -> [(Day, Day)] -> Int -> Int -> Text -> IO ()
createLeaveBatch venue staffPool leaveDates startIndex count status =
    forM_ (zip [startIndex ..] (zip (drop startIndex (cycle staffPool)) (take count (drop startIndex leaveDates)))) \(index, (staff, (startDate, endDate))) -> do
        _ <- createLeaveRequestRecordWithNotes venue staff startDate endDate status (Just (leaveNoteFor status index))
        pure ()

spreadLeaveDatesAcrossMonth :: Day -> Int -> [(Day, Day)]
spreadLeaveDatesAcrossMonth anchorDay count
    | count <= 0 = []
    | otherwise = map leaveWindowForIndex [0 .. count - 1]
    where
        monthStart = firstDayOfMonth anchorDay
        monthEnd = lastDayOfMonth anchorDay
        monthSpanDays = max 0 (diffDays monthEnd monthStart)
        divisor = max 1 (count - 1)

        leaveWindowForIndex index =
            let startOffset = (toInteger index * monthSpanDays) `div` toInteger divisor
                durationDays = toInteger (1 + (index `mod` 2))
                startDate = addDays startOffset monthStart
                endDate = min monthEnd (addDays durationDays startDate)
             in (startDate, endDate)

firstDayOfMonth :: Day -> Day
firstDayOfMonth day =
    let (year, month, _) = toGregorian day
     in fromGregorian year month 1

lastDayOfMonth :: Day -> Day
lastDayOfMonth day =
    let (year, month, _) = toGregorian day
        nextMonthStart =
            if month == 12
                then fromGregorian (year + 1) 1 1
                else fromGregorian year (month + 1) 1
     in addDays (-1) nextMonthStart

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
    forM_ (zip [0 ..] (take scenario.approvedTimesheets (cycle staffPool))) \(index, staff) -> do
        let shiftTypeId =
                if index `mod` 4 == 0
                    then unpackId (get #id kitchenShift)
                    else unpackId (get #id floorShift)
        let (hadBreak, breakStartTime, breakEndTime, breakMinutes) =
                seededBreakFields scenario.scenarioSeed index
        _ <-
            createTimesheetEntryRecord venue staff (dayAtOffset fixtureWeekStart (toInteger (index `mod` 7)))
                >>= updateRecord
                    . set #shiftTypeId shiftTypeId
                    . set #startTime (TimeOfDay (6 + ((index * 2) `mod` 8)) 0 0)
                    . set #endTime (TimeOfDay (12 + ((index * 2) `mod` 8)) 0 0)
                    . set #hadBreak hadBreak
                    . set #breakStartTime breakStartTime
                    . set #breakEndTime breakEndTime
                    . set #breakMinutes breakMinutes
                    . set #isApproved True
                    . set #approvedAt (Just approvedAt)
                    . set #approvedByUserId (Just (unpackId admin.id))
        pure ()
    forM_ (zip [0 ..] (take scenario.pendingTimesheets (drop scenario.approvedTimesheets (cycle staffPool)))) \(index, staff) -> do
        let globalIndex = scenario.approvedTimesheets + index
        let (hadBreak, breakStartTime, breakEndTime, breakMinutes) =
                seededBreakFields scenario.scenarioSeed globalIndex
        _ <-
            createTimesheetEntryRecord venue staff (dayAtOffset fixtureWeekStart (toInteger ((index + 2) `mod` 7)))
                >>= updateRecord
                    . set #shiftTypeId (unpackId (get #id floorShift))
                    . set #startTime (TimeOfDay (9 + (index `mod` 3)) 0 0)
                    . set #endTime (TimeOfDay (15 + (index `mod` 3)) 0 0)
                    . set #hadBreak hadBreak
                    . set #breakStartTime breakStartTime
                    . set #breakEndTime breakEndTime
                    . set #breakMinutes breakMinutes
        pure ()

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
    rosterSlotIds <- map Id <$> freshUUIDs (length slotNames)
    now <- getCurrentTime
    void (createMany (zipWith (rosterSlotRecord now rosterDay rowIndex) rosterSlotIds slotNames))
    where
        emptySeed = DevRosterSlotSeed { slotStaff = Nothing, slotStartTime = Nothing, slotNote = Nothing }
        rosterSlotRecord now rosterDay rowIndex rosterSlotId slotName =
            let slotSeed = fromMaybe emptySeed (lookup (get #name slotName) assignments)
             in newRecord @RosterSlot
                    |> set #id rosterSlotId
                    |> set #rosterDayId (unpackId (get #id rosterDay))
                    |> set #slotNameId (unpackId (get #id slotName))
                    |> set #slotSortOrder slotName.sortOrder
                    |> set #staffId (fmap (unpackId . get #id) slotSeed.slotStaff)
                    |> set #rowIndex rowIndex
                    |> set #startTime slotSeed.slotStartTime
                    |> set #note slotSeed.slotNote
                    |> set #createdAt now
                    |> set #updatedAt now

seededRosterSlot :: Maybe Staff -> TimeOfDay -> Text -> DevRosterSlotSeed
seededRosterSlot maybeStaff startTime note =
    DevRosterSlotSeed
        { slotStaff = maybeStaff
        , slotStartTime = Just startTime
        , slotNote = Just note
        }

slotStartTimeFor :: Int -> Int -> TimeOfDay
slotStartTimeFor slotIndex dayIndex =
    case slotIndex of
        0 -> TimeOfDay (6 + (dayIndex `mod` 2)) 30 0
        1 -> TimeOfDay (11 + (dayIndex `mod` 2)) 0 0
        _ -> TimeOfDay (16 + (dayIndex `mod` 2)) 30 0

slotNoteFor :: Int -> Int -> Int -> Int -> Text
slotNoteFor seedValue dayIndex rowIndex slotIndex =
    noteBank !! deterministicIndex seedValue [dayIndex, rowIndex, slotIndex, 77] (length noteBank)

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

availabilityNoteFor :: Int -> Int -> Int -> Text
availabilityNoteFor seedValue staffIndex noteIndex =
    availabilityNotes !! deterministicIndex seedValue [staffIndex, noteIndex, 499] (length availabilityNotes)

preferredNameFor :: Int -> Int -> Text -> Maybe Text -> Maybe Text
preferredNameFor seedValue index firstName fallbackPreferredName
    | deterministicPercent seedValue [index, 601] < 32 =
        fallbackPreferredName <|> generatedNickname firstName
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
        , ("Cara", "Kitchen", Just "CJ")
        , ("Dylan", "Leave", Nothing)
        , ("Eve", "Closer", Nothing)
        , ("Frank", "Prep", Just "Frankie")
        , ("Gina", "Bar", Nothing)
        , ("Hugo", "Runner", Nothing)
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

noteBank :: [Text]
noteBank = ["OP", "LU", "CL", "EX", "TR", "EV", "ST", "FN", "WK", "BR", "PK", "CV"]

availabilityNotes :: [Text]
availabilityNotes = ["School", "Uni", "Childcare", "Second job", "Medical", "Family"]

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
