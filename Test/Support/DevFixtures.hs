module Test.Support.DevFixtures where

import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        ensureVenueDefaultRosterGroup,
                                        fetchActiveRosterGroupSlotNames,
                                        fetchVenueDayNames,
                                        syncStaffRosterGroupAssignments)
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude
import Test.Support
import Test.Support.PayrollFixtures (ExplorationPayrollFixture (..),
                                     approveEntryWithSnapshot,
                                     createPayrollSnapshot, dayNameForWeekday,
                                     seedExplorationPayrollFixtureForWeek)

data DevSeedFixture = DevSeedFixture
    { sandboxVenue      :: !Venue
    , sandboxAdmin      :: !User
    , frontOfHouseGroup :: !RosterGroup
    , backOfHouseGroup  :: !RosterGroup
    , currentWeekOffset :: !Int
    , payrollFixture    :: !ExplorationPayrollFixture
    }

seedDevelopmentFixtureForWeek :: (?modelContext :: ModelContext) => Day -> IO DevSeedFixture
seedDevelopmentFixtureForWeek fixtureWeekStart = do
    venue <- createVenueWithConfig "Development Sandbox Venue"
    admin <- createUserRecord "dev-admin@example.com" "admin" True
    _ <- createVenueMembershipRecord venue admin "venue_admin"

    frontGroup <-
        ensureVenueDefaultRosterGroup venue
            >>= updateRecord . set #name "Front of House"
    backGroup <- createVenueRosterGroupWithDefaults venue "Back of House" 20 True

    frontSlots <- fetchActiveRosterGroupSlotNames (get #id frontGroup)
    backSlots <- fetchActiveRosterGroupSlotNames (get #id backGroup)
    dayNames <- fetchVenueDayNames venue

    frontLevel <- createPayLevelRecordWithRates venue "FOH Level" 31 0 0 1.25 1.5 1.75
    backLevel <- createPayLevelRecordWithRates venue "BOH Level" 34 1 2 1.25 1.5 1.75
    floorShift <- createShiftTypeRecord venue frontLevel "Floor" >>= updateRecord . set #sortOrder 10
    kitchenShift <- createShiftTypeRecord venue backLevel "Kitchen" >>= updateRecord . set #sortOrder 20
    let saturday = dayNameForWeekday dayNames 6
    _ <- createPayLevelDayRuleRecord kitchenShift saturday backLevel
    snapshot <- createPayrollSnapshot venue admin [frontLevel, backLevel] [floorShift, kitchenShift] dayNames []

    aliceUser <- createUserRecord "dev-alice@example.com" "staff" True
    bobUser <- createUserRecord "dev-bob@example.com" "staff" True
    caraUser <- createUserRecord "dev-cara@example.com" "staff" True
    dylanUser <- createUserRecord "dev-dylan@example.com" "staff" True
    eveUser <- createUserRecord "dev-eve@example.com" "staff" True
    frankUser <- createUserRecord "dev-frank@example.com" "staff" True

    alice <- createStaffRecord venue (Just aliceUser) "Alice" "Front"
    bob <- createStaffRecord venue (Just bobUser) "Bob" "Both"
    cara <- createStaffRecord venue (Just caraUser) "Cara" "Kitchen"
    dylan <- createStaffRecord venue (Just dylanUser) "Dylan" "Leave"
    eve <- createStaffRecord venue (Just eveUser) "Eve" "Closer"
    frank <- createStaffRecord venue (Just frankUser) "Frank" "Prep"
    trialStaff <- createStaffRecord venue Nothing "Taylor" "Trial"

    syncStaffRosterGroupAssignments alice [get #id frontGroup]
    syncStaffRosterGroupAssignments bob [get #id frontGroup, get #id backGroup]
    syncStaffRosterGroupAssignments cara [get #id backGroup]
    syncStaffRosterGroupAssignments dylan [get #id frontGroup]
    syncStaffRosterGroupAssignments eve [get #id frontGroup]
    syncStaffRosterGroupAssignments frank [get #id backGroup]
    syncStaffRosterGroupAssignments trialStaff [get #id frontGroup]

    let weekOffset = weekOffsetFor fixtureWeekStart
    frontWeek <- createRosterWeekRecordForRosterGroup venue frontGroup weekOffset True
    backWeek <- createRosterWeekRecordForRosterGroup venue backGroup weekOffset False

    frontDays <- mapM (createRosterDayRecord frontWeek) [0 .. 6]
    backDays <- mapM (createRosterDayRecord backWeek) [0 .. 6]
    let [frontMonday, frontTuesday, frontWednesday, frontThursday, frontFriday, frontSaturday, frontSunday] = frontDays
    let [backMonday, backTuesday, backWednesday, _, backFriday, backSaturday, _] = backDays

    createRosterRow frontMonday frontSlots 0
        [ ("Early", Just alice)
        , ("Mid", Just bob)
        , ("Late", Just dylan)
        ]
    createRosterRow frontMonday frontSlots 1
        [ ("Mid", Just eve)
        ]
    createRosterRow frontTuesday frontSlots 0
        [ ("Early", Just dylan)
        , ("Mid", Just alice)
        , ("Late", Just eve)
        ]
    createRosterRow frontWednesday frontSlots 0
        [ ("Early", Just trialStaff)
        , ("Mid", Just bob)
        ]
    createRosterRow frontThursday frontSlots 0
        [ ("Early", Just alice)
        , ("Late", Just eve)
        ]
    createRosterRow frontFriday frontSlots 0
        [ ("Mid", Just bob)
        , ("Late", Just eve)
        ]
    createRosterRow frontSaturday frontSlots 0
        [ ("Early", Just eve)
        , ("Mid", Just alice)
        ]
    createRosterRow frontSunday frontSlots 0
        [ ("Mid", Just trialStaff)
        ]

    createRosterRow backMonday backSlots 0
        [ ("Early", Just cara)
        , ("Mid", Just bob)
        , ("Late", Just frank)
        ]
    createRosterRow backTuesday backSlots 0
        [ ("Early", Just cara)
        , ("Mid", Just frank)
        ]
    createRosterRow backWednesday backSlots 0
        [ ("Mid", Just bob)
        , ("Late", Just cara)
        ]
    createRosterRow backFriday backSlots 0
        [ ("Early", Just frank)
        , ("Mid", Just cara)
        ]
    createRosterRow backSaturday backSlots 0
        [ ("Early", Just bob)
        , ("Late", Just cara)
        ]

    _ <- createLeaveRequestRecord venue dylan (dayAtOffset fixtureWeekStart 1) (dayAtOffset fixtureWeekStart 4) "approved"
    _ <- createLeaveRequestRecord venue alice (dayAtOffset fixtureWeekStart 5) (dayAtOffset fixtureWeekStart 6) "pending"

    let approvedAt = UTCTime (dayAtOffset fixtureWeekStart 6) (secondsToDiffTime 3600)
    _ <-
        createTimesheetEntryRecord venue alice (dayAtOffset fixtureWeekStart 0)
            >>= updateRecord
                . set #shiftTypeId (unpackId (get #id floorShift))
                . set #startTime (TimeOfDay 8 0 0)
                . set #endTime (TimeOfDay 16 0 0)
                . approveEntryWithSnapshot snapshot admin approvedAt
    _ <-
        createTimesheetEntryRecord venue cara (dayAtOffset fixtureWeekStart 1)
            >>= updateRecord
                . set #shiftTypeId (unpackId (get #id kitchenShift))
                . set #startTime (TimeOfDay 6 0 0)
                . set #endTime (TimeOfDay 14 0 0)
                . approveEntryWithSnapshot snapshot admin approvedAt
    _ <-
        createTimesheetEntryRecord venue bob (dayAtOffset fixtureWeekStart 2)
            >>= updateRecord
                . set #shiftTypeId (unpackId (get #id floorShift))
                . set #startTime (TimeOfDay 12 0 0)
                . set #endTime (TimeOfDay 18 0 0)

    seededPayrollFixture <- seedExplorationPayrollFixtureForWeek fixtureWeekStart

    pure
        DevSeedFixture
            { sandboxVenue = venue
            , sandboxAdmin = admin
            , frontOfHouseGroup = frontGroup
            , backOfHouseGroup = backGroup
            , currentWeekOffset = weekOffset
            , payrollFixture = seededPayrollFixture
            }

createRosterRow ::
    (?modelContext :: ModelContext) =>
    RosterDay ->
    [SlotName] ->
    Int ->
    [(Text, Maybe Staff)] ->
    IO ()
createRosterRow rosterDay slotNames rowIndex assignments =
    forM_ slotNames \slotName -> do
        let assignedStaff = lookup (get #name slotName) assignments |> join
        _ <- createRosterSlotRecord rosterDay slotName assignedStaff rowIndex
        pure ()

dayAtOffset :: Day -> Integer -> Day
dayAtOffset weekStart offset = addDays offset weekStart

weekOffsetFor :: Day -> Int
weekOffsetFor day = fromInteger (diffDays day defaultWeekEpoch `div` 7)
