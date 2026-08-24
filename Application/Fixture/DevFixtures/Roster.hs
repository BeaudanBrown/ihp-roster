module Application.Fixture.DevFixtures.Roster
    ( RosterFixture (..)
    , seedRosterFoundation
    , seedRosterProjection
    ) where

import Application.Fixture
import Application.Fixture.DevFixtures.Deterministic
import Application.Fixture.DevFixtures.Staff (SeededStaff (..))
import Application.Fixture.Seed.Scenario
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        ensureVenueDefaultRosterGroup,
                                        fetchActiveRosterGroupSlotNames,
                                        syncStaffRosterGroupAssignments)
import Application.Helper.StaffShiftPreferences (ShiftPreferenceSelection (..))
import Application.Helper.TimeRules (rosterShiftStartDate)
import Application.RosterShiftAssignment (RosterShiftAssignment (..),
                                          applyRosterShiftAssignment)
import Application.VenueTime.Model
import Control.Monad (void)
import qualified Data.Map.Strict as Map
import Data.Time.Calendar (Day, addDays, dayOfWeek, fromGregorian)
import Data.Time.Clock (UTCTime, getCurrentTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Data.UUID (UUID)
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport.Types (CanCreate (createMany))
import IHP.Prelude
import qualified IHP.Prelude as Prelude

data DevRosterSlotSeed = DevRosterSlotSeed
    { slotStaff       :: !(Maybe Staff)
    , slotStartTime   :: !(Maybe TimeOfDay)
    , slotEndTime     :: !(Maybe TimeOfDay)
    , slotShiftTypeId :: !(Maybe UUID)
    }

data RosterFixture = RosterFixture
    { frontOfHouseGroup :: !RosterGroup
    , backOfHouseGroup  :: !RosterGroup
    , frontSlotNames    :: ![SlotName]
    , backSlotNames     :: ![SlotName]
    }

seedRosterFoundation :: (?modelContext :: ModelContext) => Venue -> IO RosterFixture
seedRosterFoundation venue = do
    frontOfHouseGroup <- ensureVenueDefaultRosterGroup venue >>= updateRecord . set #name "Front of House"
    backOfHouseGroup <- createVenueRosterGroupWithDefaults venue "Back of House" 20 True
    frontSlotNames <- fetchActiveRosterGroupSlotNames frontOfHouseGroup.id
    backSlotNames <- fetchActiveRosterGroupSlotNames backOfHouseGroup.id
    pure RosterFixture { .. }

seedRosterProjection ::
    (?modelContext :: ModelContext) =>
    SeedScenario ->
    Day ->
    Venue ->
    RosterFixture ->
    SeededStaff ->
    [ShiftType] ->
    IO ()
seedRosterProjection scenario fixtureWeekStart venue rosterFixture staffFixture shiftTypes = do
    let frontGroup = rosterFixture.frontOfHouseGroup
    let backGroup = rosterFixture.backOfHouseGroup
    let frontSlots = rosterFixture.frontSlotNames
    let backSlots = rosterFixture.backSlotNames
    mapM_ (\staff -> syncStaffRosterGroupAssignments staff [frontGroup.id, backGroup.id]) staffFixture.managerStaffs
    syncStaffRosterGroupAssignments staffFixture.workerStaff [frontGroup.id]
    mapM_ (\staff -> syncStaffRosterGroupAssignments staff [frontGroup.id]) staffFixture.frontOnlyStaff
    mapM_ (\staff -> syncStaffRosterGroupAssignments staff [backGroup.id]) staffFixture.backOnlyStaff
    mapM_ (\staff -> syncStaffRosterGroupAssignments staff [frontGroup.id, backGroup.id]) staffFixture.crossGroupStaff
    mapM_ (\staff -> syncStaffRosterGroupAssignments staff [frontGroup.id]) staffFixture.trialStaffs
    syncStaffRosterGroupAssignments staffFixture.rosterOnlyStaff [frontGroup.id, backGroup.id]
    seedStaffPreferences scenario.scenarioSeed frontGroup backGroup frontSlots backSlots
        staffFixture.managerStaffs staffFixture.workerStaff staffFixture.frontOnlyStaff
        staffFixture.backOnlyStaff staffFixture.crossGroupStaff staffFixture.trialStaffs
    let allFrontCandidates = staffFixture.managerStaffs <> [staffFixture.xeroStaff] <> staffFixture.frontOnlyStaff <> staffFixture.crossGroupStaff <> staffFixture.trialStaffs
    let allBackCandidates = staffFixture.managerStaffs <> staffFixture.backOnlyStaff <> staffFixture.crossGroupStaff
    venueConfig <- query @VenueConfig
        |> filterWhere (#venueId, unpackId venue.id)
        |> fetchOne
    seedRosterWindow scenario fixtureWeekStart venue venueConfig frontGroup backGroup frontSlots backSlots allFrontCandidates allBackCandidates shiftTypes
    seedPayAssignmentMatrix
        frontGroup
        fixtureWeekStart
        [staffFixture.awardStaff, staffFixture.xeroStaff, staffFixture.rosterOnlyStaff]
        (take 4 shiftTypes)

seedPayAssignmentMatrix :: (?modelContext :: ModelContext) => RosterGroup -> Day -> [Staff] -> [ShiftType] -> IO ()
seedPayAssignmentMatrix rosterGroup windowStart staffModes shiftModes = do
    when (length staffModes /= 3 || length shiftModes /= 4) $
        fail "Dev pay matrix requires three staff modes and four shift modes"
    rosterDays <-
        query @RosterDay
            |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
            |> filterWhereGreaterThanOrEqualTo (#operationalDate, windowStart)
            |> filterWhereLessThan (#operationalDate, addDays 7 windowStart)
            |> orderByAsc #operationalDate
            |> fetch
    when (length rosterDays < length shiftModes) $
        fail "Dev pay matrix requires four roster days"
    forM_ (zip (take 4 rosterDays) shiftModes) \(rosterDay, shiftType) -> do
        slots <-
            query @RosterSlot
                |> filterWhere (#rosterDayId, unpackId rosterDay.id)
                |> orderByAsc #rowIndex
                |> orderByAsc #slotSortOrder
                |> fetch
        when (length slots < length staffModes) $
            fail "Dev pay matrix requires three persisted slots on each matrix day"
        forM_ (zip (take 3 slots) staffModes) \(slot, staff) -> do
            slot
                |> set #staffId (Just (unpackId staff.id))
                |> set #shiftTypeId (Just (unpackId shiftType.id))
                |> updateRecord
                |> void
            ensureSeedMatrixDayPreference staff rosterDay.operationalDate

ensureSeedMatrixDayPreference :: (?modelContext :: ModelContext) => Staff -> Day -> IO ()
ensureSeedMatrixDayPreference staff operationalDate = do
    let weekdayIndex = weekdayIndexForFixtureDate operationalDate
    existing <-
        query @StaffShiftPreference
            |> filterWhere (#staffId, unpackId staff.id)
            |> filterWhere (#weekdayIndex, weekdayIndex)
            |> fetchOneOrNothing
    case existing of
        Just _ -> pure ()
        Nothing ->
            newRecord @StaffShiftPreference
                |> set #venueId staff.venueId
                |> set #staffId (unpackId staff.id)
                |> set #weekdayIndex weekdayIndex
                |> set #preferredStartHour 5
                |> set #preferredEndHour 23
                |> createRecord
                |> void

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
    VenueConfig ->
    RosterGroup ->
    [RosterDay] ->
    [SlotName] ->
    [Staff] ->
    [ShiftType] ->
    IO ()
seedRosterGroup seedValue fillPercent fixtureWeekStart venueConfig rosterGroup rosterDays slotNames staffPool shiftTypes = do
    forM_ (zip [0 :: Int ..] rosterDays) \(dayIndex, rosterDay) -> do
        let rowCount = 2
        _ <- rosterDay
            |> set #rowCount rowCount
            |> updateRecord
        rosterLanes <- mapM (ensureRosterLaneForSlotName rosterDay) slotNames
        let seedRows _ [] = pure ()
            seedRows usedStaffIds (rowIndex:remainingRowIndexes) = do
                let (assignments, nextUsedStaffIds) =
                        buildRowAssignments seedValue fillPercent dayIndex rowIndex slotNames staffPool shiftTypes usedStaffIds
                createRosterRow venueConfig rosterDay rosterLanes rowIndex assignments
                seedRows nextUsedStaffIds remainingRowIndexes
        seedRows [] [0 .. rowCount - 1]
    ensureAssignedShiftPreferenceCoverage rosterGroup rosterDays

seedRosterWindow ::
    (?modelContext :: ModelContext) =>
    SeedScenario ->
    Day ->
    Venue ->
    VenueConfig ->
    RosterGroup ->
    RosterGroup ->
    [SlotName] ->
    [SlotName] ->
    [Staff] ->
    [Staff] ->
    [ShiftType] ->
    IO ()
seedRosterWindow scenario currentWeekStart venue venueConfig frontGroup backGroup frontSlots backSlots frontCandidates backCandidates shiftTypes =
    forM_ devSeedWeekStarts \(weekIndex, weekStart) -> do
        frontWeek <- createRosterWeekRecordForWindow venue frontGroup weekStart (weekIndex == 0)
        backWeek <- createRosterWeekRecordForWindow venue backGroup weekStart False
        let operationalDates = map (`addDays` weekStart) [0 .. 6]
        frontDays <- createRosterDayRecords frontWeek weekStart operationalDates
        backDays <- createRosterDayRecords backWeek weekStart operationalDates
        let weekSeed = scenario.scenarioSeed + (weekIndex * 1009)
        seedRosterGroup weekSeed (rosterFillForWeek scenario.rosterFillPercent weekIndex) weekStart venueConfig frontGroup frontDays frontSlots frontCandidates shiftTypes
        seedRosterGroup (weekSeed + 97) (max 40 (rosterFillForWeek scenario.rosterFillPercent weekIndex - 8)) weekStart venueConfig backGroup backDays backSlots backCandidates shiftTypes
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
    RosterGroup ->
    [RosterDay] ->
    IO ()
ensureAssignedShiftPreferenceCoverage rosterGroup rosterDays = do
    let rosterDayIds = map (unpackId . get #id) rosterDays
    let dayDatesById = Map.fromList (map (\rosterDay -> (unpackId (get #id rosterDay), rosterDay.operationalDate)) rosterDays)

    fetchedAssignedSlots <-
        query @RosterSlot
            |> filterWhereIn (#rosterDayId, rosterDayIds)
            |> fetch
    let assignedSlots =
            sortOn
                (\slot ->
                    ( Map.findWithDefault (fromGregorian 9999 12 31) slot.rosterDayId dayDatesById
                    , slot.rowIndex
                    , slot.slotSortOrder
                    )
                )
                fetchedAssignedSlots
    let assignedSlotsWithStaff = filter (isJust . (.staffId)) assignedSlots

    let assignedStaffIds = nub (mapMaybe (.staffId) assignedSlotsWithStaff)
    unless (null assignedStaffIds) do
        existingPreferences <-
            query @StaffShiftPreference
                |> filterWhereIn (#staffId, assignedStaffIds)
                |> fetch

        let existingTargets = map staffShiftPreferenceToTarget existingPreferences
        let missingTargets = mapMaybe (missingPreferenceTarget dayDatesById rosterGroup existingTargets) assignedSlotsWithStaff
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
    Map.Map UUID Day ->
    RosterGroup ->
    [StaffPreferenceTarget] ->
    RosterSlot ->
    Maybe StaffPreferenceTarget
missingPreferenceTarget dayDatesById rosterGroup existingTargets rosterSlot = do
    staffId <- rosterSlot.staffId
    operationalDate <- Map.lookup rosterSlot.rosterDayId dayDatesById
    let target =
            StaffPreferenceTarget
                { targetStaffId = staffId
                , targetSelection =
                    ShiftPreferenceSelection
                        { weekdayIndex = weekdayIndexForFixtureDate operationalDate
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

weekdayIndexForFixtureDate :: Day -> Int
weekdayIndexForFixtureDate operationalDate =
    case fromEnum (dayOfWeek operationalDate) of
        7     -> 0
        index -> index

rotateList :: Int -> [a] -> [a]
rotateList _ [] = []
rotateList offset values =
    drop clampedOffset values <> take clampedOffset values
    where
        clampedOffset = offset `mod` length values


createRosterDayRecords :: (?modelContext :: ModelContext) => FixtureRosterWindow -> Day -> [Day] -> IO [RosterDay]
createRosterDayRecords _ _ [] = pure []
createRosterDayRecords rosterWeek windowStart operationalDates = do
    rosterDayIds <- map Id <$> freshUUIDs (length operationalDates)
    now <- getCurrentTime
    createMany (zipWith (rosterDayRecord now rosterWeek windowStart) rosterDayIds operationalDates)

rosterDayRecord :: UTCTime -> FixtureRosterWindow -> Day -> Id RosterDay -> Day -> RosterDay
rosterDayRecord now rosterWindow _windowStart rosterDayId operationalDate =
    newRecord @RosterDay
        |> set #id rosterDayId
        |> set #venueId rosterWindow.fixtureVenueId
        |> set #rosterGroupId rosterWindow.fixtureRosterGroupId
        |> set #operationalDate operationalDate
        |> set #publicationState (if rosterWindow.fixtureWindowIsPublished then Published else Draft)
        |> set #isClosed False
        |> set #createdAt now
        |> set #updatedAt now

createRosterRow ::
    (?modelContext :: ModelContext) =>
    VenueConfig ->
    RosterDay ->
    [RosterLane] ->
    Int ->
    [(Text, DevRosterSlotSeed)] ->
    IO ()
createRosterRow venueConfig rosterDay rosterLanes rowIndex assignments = do
    let rosterDate = rosterDay.operationalDate
    let assignedRosterLanes =
            [ (rosterLane, slotSeed)
            | rosterLane <- rosterLanes
            , Just slotSeed <- [lookup (get #name rosterLane) assignments]
            ]
    rosterSlotIds <- map Id <$> freshUUIDs (length assignedRosterLanes)
    now <- getCurrentTime
    void (createMany (zipWith (rosterSlotRecord now rosterDate venueConfig.timezone rosterDay rowIndex) rosterSlotIds assignedRosterLanes))
    where
        rosterSlotRecord now rosterDate timezone rosterDay rowIndex rosterSlotId (rosterLane, slotSeed) =
            let baseSlot =
                    newRecord @RosterSlot
                        |> set #id rosterSlotId
                        |> set #rosterDayId (unpackId (get #id rosterDay))
                        |> set #rosterLaneId (unpackId (get #id rosterLane))
                        |> set #slotSortOrder rosterLane.sortOrder
                        |> applyRosterShiftAssignment (maybe OpenAssignment (StaffAssignment . (.id)) slotSeed.slotStaff)
                        |> set #shiftTypeId slotSeed.slotShiftTypeId
                        |> set #rowIndex rowIndex
                        |> set #timezone timezone
                        |> set #createdAt now
                        |> set #updatedAt now
             in case (slotSeed.slotStartTime, slotSeed.slotEndTime) of
                    (Just startTime, Just endTime) ->
                        let boundaries =
                                either (error . ("Invalid seeded roster boundaries: " <>) . show) Prelude.id $
                                    resolveShiftBoundaries timezone ShiftBoundaryInput
                                        { shiftBoundaryDate = rosterShiftStartDate rosterDate startTime
                                        , shiftBoundaryStartTime = startTime
                                        , shiftBoundaryStartOccurrence = Nothing
                                        , shiftBoundaryEndTime = endTime
                                        , shiftBoundaryEndOccurrence = Nothing
                                        , shiftBoundaryBreak = Nothing
                                        }
                         in applyRosterSlotBoundaries boundaries baseSlot
                    _ -> baseSlot

seededRosterSlot :: Maybe Staff -> TimeOfDay -> Maybe UUID -> DevRosterSlotSeed
seededRosterSlot maybeStaff startTime maybeShiftTypeId =
    DevRosterSlotSeed
        { slotStaff = maybeStaff
        , slotStartTime = Just startTime
        , slotEndTime = Just (slotEndTimeFor startTime)
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

slotEndTimeFor :: TimeOfDay -> TimeOfDay
slotEndTimeFor startTime =
    minutesToTimeOfDay (timeOfDayToMinutes startTime + 330)
