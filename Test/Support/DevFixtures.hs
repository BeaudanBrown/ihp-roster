module Test.Support.DevFixtures where

import Application.Helper.Controller (PlatformRole (..))
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

data DevRosterSlotSeed = DevRosterSlotSeed
    { slotStaff     :: !(Maybe Staff)
    , slotStartTime :: !(Maybe TimeOfDay)
    , slotNote      :: !(Maybe Text)
    }

data DevSeedFixture = DevSeedFixture
    { sandboxVenue      :: !Venue
    , sandboxAdmin      :: !User
    , sandboxManager    :: !User
    , sandboxWorker     :: !User
    , supportAdmin      :: !User
    , sandboxInvitation :: !VenueInvitation
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
    supportAdmin <- createUserRecordWithPlatformRole "support-admin@example.com" "admin" (Just SuperAdminRole) True
    managerUser <- createUserRecord "dev-manager@example.com" "manager" True
    workerUser <- createUserRecord "dev-worker@example.com" "staff" True
    _ <- createVenueMembershipRecord venue managerUser "manager"
    _ <- createVenueMembershipRecord venue workerUser "worker"
    invitation <- createVenueInvitationRecord venue (Just admin) "pending-invite@example.com" "worker"

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

    managerStaff <- createStaffRecord venue (Just managerUser) "Morgan" "Manager" >>= updateRecord . set #idealShiftsPerWeek 4
    workerStaff <- createStaffRecord venue (Just workerUser) "Willa" "Worker" >>= updateRecord . set #idealShiftsPerWeek 3
    alice <- createStaffRecord venue (Just aliceUser) "Alice" "Front" >>= updateRecord . set #idealShiftsPerWeek 5
    bob <- createStaffRecord venue (Just bobUser) "Bob" "Both" >>= updateRecord . set #idealShiftsPerWeek 4
    cara <- createStaffRecord venue (Just caraUser) "Cara" "Kitchen" >>= updateRecord . set #idealShiftsPerWeek 4
    dylan <- createStaffRecord venue (Just dylanUser) "Dylan" "Leave" >>= updateRecord . set #idealShiftsPerWeek 2
    eve <- createStaffRecord venue (Just eveUser) "Eve" "Closer" >>= updateRecord . set #idealShiftsPerWeek 5
    frank <- createStaffRecord venue (Just frankUser) "Frank" "Prep" >>= updateRecord . set #idealShiftsPerWeek 3
    trialStaff <- createStaffRecord venue Nothing "Taylor" "Trial" >>= updateRecord . set #idealShiftsPerWeek 1

    syncStaffRosterGroupAssignments managerStaff [get #id frontGroup, get #id backGroup]
    syncStaffRosterGroupAssignments workerStaff [get #id frontGroup]
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
        [ ("Early", seededRosterSlot (Just alice) (TimeOfDay 7 0 0) "OP")
        , ("Mid", seededRosterSlot (Just bob) (TimeOfDay 11 0 0) "LU")
        , ("Late", seededRosterSlot (Just dylan) (TimeOfDay 16 0 0) "CL")
        ]
    createRosterRow frontMonday frontSlots 1
        [ ("Mid", seededRosterSlot (Just eve) (TimeOfDay 12 0 0) "EX")
        ]
    createRosterRow frontTuesday frontSlots 0
        [ ("Early", seededRosterSlot (Just dylan) (TimeOfDay 7 30 0) "SR")
        , ("Mid", seededRosterSlot (Just alice) (TimeOfDay 11 30 0) "TR")
        , ("Late", seededRosterSlot (Just eve) (TimeOfDay 17 0 0) "EV")
        ]
    createRosterRow frontWednesday frontSlots 0
        [ ("Early", seededRosterSlot (Just trialStaff) (TimeOfDay 8 0 0) "SH")
        , ("Mid", seededRosterSlot (Just bob) (TimeOfDay 12 0 0) "CV")
        ]
    createRosterRow frontThursday frontSlots 0
        [ ("Early", seededRosterSlot (Just managerStaff) (TimeOfDay 6 30 0) "ST")
        , ("Late", seededRosterSlot (Just eve) (TimeOfDay 16 30 0) "FN")
        ]
    createRosterRow frontFriday frontSlots 0
        [ ("Early", seededRosterSlot (Just workerStaff) (TimeOfDay 7 0 0) "PP")
        , ("Mid", seededRosterSlot (Just bob) (TimeOfDay 11 0 0) "FP")
        , ("Late", seededRosterSlot (Just eve) (TimeOfDay 17 30 0) "LK")
        ]
    createRosterRow frontSaturday frontSlots 0
        [ ("Early", seededRosterSlot (Just eve) (TimeOfDay 8 0 0) "WE")
        , ("Mid", seededRosterSlot (Just alice) (TimeOfDay 12 30 0) "BR")
        ]
    createRosterRow frontSunday frontSlots 0
        [ ("Mid", seededRosterSlot (Just trialStaff) (TimeOfDay 11 0 0) "TS")
        ]

    createRosterRow backMonday backSlots 0
        [ ("Early", seededRosterSlot (Just cara) (TimeOfDay 6 0 0) "PR")
        , ("Mid", seededRosterSlot (Just bob) (TimeOfDay 11 0 0) "XO")
        , ("Late", seededRosterSlot (Just frank) (TimeOfDay 16 0 0) "KC")
        ]
    createRosterRow backTuesday backSlots 0
        [ ("Early", seededRosterSlot (Just cara) (TimeOfDay 6 30 0) "MP")
        , ("Mid", seededRosterSlot (Just frank) (TimeOfDay 12 0 0) "SV")
        ]
    createRosterRow backWednesday backSlots 0
        [ ("Mid", seededRosterSlot (Just bob) (TimeOfDay 11 30 0) "SC")
        , ("Late", seededRosterSlot (Just cara) (TimeOfDay 17 0 0) "CK")
        ]
    createRosterRow backFriday backSlots 0
        [ ("Early", seededRosterSlot (Just frank) (TimeOfDay 6 0 0) "GR")
        , ("Mid", seededRosterSlot (Just cara) (TimeOfDay 12 0 0) "FS")
        ]
    createRosterRow backSaturday backSlots 0
        [ ("Early", seededRosterSlot (Just bob) (TimeOfDay 7 30 0) "WC")
        , ("Late", seededRosterSlot (Just cara) (TimeOfDay 17 30 0) "SA")
        ]

    _ <- createLeaveRequestRecord venue dylan (dayAtOffset fixtureWeekStart 1) (dayAtOffset fixtureWeekStart 4) "approved"
    _ <- createLeaveRequestRecord venue alice (dayAtOffset fixtureWeekStart 5) (dayAtOffset fixtureWeekStart 6) "pending"
    _ <- createLeaveRequestRecord venue workerStaff (dayAtOffset fixtureWeekStart 3) (dayAtOffset fixtureWeekStart 5) "denied"

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
            , sandboxManager = managerUser
            , sandboxWorker = workerUser
            , supportAdmin = supportAdmin
            , sandboxInvitation = invitation
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
    [(Text, DevRosterSlotSeed)] ->
    IO ()
createRosterRow rosterDay slotNames rowIndex assignments =
    forM_ slotNames \slotName -> do
        let slotSeed = fromMaybe emptySeed (lookup (get #name slotName) assignments)
        _ <-
            createRosterSlotRecord rosterDay slotName slotSeed.slotStaff rowIndex
                >>= updateRecord
                    . set #startTime slotSeed.slotStartTime
                    . set #note slotSeed.slotNote
        pure ()
    where
        emptySeed = DevRosterSlotSeed { slotStaff = Nothing, slotStartTime = Nothing, slotNote = Nothing }

seededRosterSlot :: Maybe Staff -> TimeOfDay -> Text -> DevRosterSlotSeed
seededRosterSlot maybeStaff startTime note =
    DevRosterSlotSeed
        { slotStaff = maybeStaff
        , slotStartTime = Just startTime
        , slotNote = Just note
        }

dayAtOffset :: Day -> Integer -> Day
dayAtOffset weekStart offset = addDays offset weekStart

weekOffsetFor :: Day -> Int
weekOffsetFor day = fromInteger (diffDays day defaultWeekEpoch `div` 7)
