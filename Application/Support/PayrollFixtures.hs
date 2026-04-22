module Application.Support.PayrollFixtures where

import Application.Helper.RosterGroups (ensureVenueRosterDefaults,
                                        fetchVenueDayNames)
import Application.Support
import Config
import qualified Data.Aeson as Aeson
import Data.Time.Calendar (Day, addDays, fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude

data CanonicalPayrollFixture = CanonicalPayrollFixture
    { venue        :: !Venue
    , admin        :: !User
    , dayNames     :: ![DayName]
    , levelOne     :: !PayLevel
    , levelTwo     :: !PayLevel
    , barShift     :: !ShiftType
    , floorShift   :: !ShiftType
    , kitchenShift :: !ShiftType
    , avaStaff     :: !Staff
    , kaiStaff     :: !Staff
    , trialStaff   :: !Staff
    , snapshot     :: !PayConfigSnapshot
    , approvedAt   :: !UTCTime
    }

data ExplorationPayrollFixture = ExplorationPayrollFixture
    { explorationVenue           :: !Venue
    , explorationAdmin           :: !User
    , explorationApprovedEntries :: ![TimesheetEntry]
    , explorationPendingEntries  :: ![TimesheetEntry]
    }

seedWeekDayNames :: (?modelContext :: ModelContext) => Venue -> IO [DayName]
seedWeekDayNames venue = do
    _ <- ensureVenueRosterDefaults venue
    fetchVenueDayNames venue

dayNameForWeekday :: HasCallStack => [DayName] -> Int -> DayName
dayNameForWeekday dayNames weekdayIndex =
    dayNames
        |> find (\dayName -> dayName.weekdayIndex == weekdayIndex)
        |> fromMaybe (error ("Missing day name for weekday index " <> tshow weekdayIndex))

createAndApproveEntry ::
    (?modelContext :: ModelContext) =>
    Venue ->
    Staff ->
    Day ->
    PayConfigSnapshot ->
    User ->
    UTCTime ->
    [TimesheetEntry -> TimesheetEntry] ->
    IO TimesheetEntry
createAndApproveEntry venue staff workedOn snapshot admin approvedAt transforms = do
    entry <- createTimesheetEntryRecord venue staff workedOn
    entry
        |> applyTransforms transforms
        |> approveEntryWithSnapshot snapshot admin approvedAt
        |> updateRecord

approveEntryWithSnapshot :: PayConfigSnapshot -> User -> UTCTime -> TimesheetEntry -> TimesheetEntry
approveEntryWithSnapshot snapshot admin approvedAt =
    set #payConfigSnapshotId (Just (unpackId snapshot.id))
        . set #isApproved True
        . set #approvedAt (Just approvedAt)
        . set #approvedByUserId (Just (unpackId admin.id))

applyTransforms :: [record -> record] -> record -> record
applyTransforms transforms record = foldl' (\current transform -> transform current) record transforms

createPayrollSnapshot ::
    (?modelContext :: ModelContext) =>
    Venue ->
    User ->
    [PayLevel] ->
    [ShiftType] ->
    [DayName] ->
    [PayLevelDayRule] ->
    IO PayConfigSnapshot
createPayrollSnapshot venue admin payLevels shiftTypes dayNames rules =
    createPayrollSnapshotWithVersion venue admin 1 payLevels shiftTypes dayNames rules

createPayrollSnapshotWithVersion ::
    (?modelContext :: ModelContext) =>
    Venue ->
    User ->
    Int ->
    [PayLevel] ->
    [ShiftType] ->
    [DayName] ->
    [PayLevelDayRule] ->
    IO PayConfigSnapshot
createPayrollSnapshotWithVersion venue admin versionNumber payLevels shiftTypes dayNames rules = do
    venueConfig <- query @VenueConfig
        |> filterWhere (#venueId, unpackId venue.id)
        |> fetchOne
    createPayConfigSnapshotRecord venue admin versionNumber $
        Aeson.object
            [ "venueConfig" Aeson..= Aeson.object
                [ "id" Aeson..= unpackId venueConfig.id
                , "timezone" Aeson..= venueConfig.timezone
                , "rosterWeekStartsOn" Aeson..= venueConfig.rosterWeekStartsOn
                , "weekOffsetEpoch" Aeson..= venueConfig.weekOffsetEpoch
                , "lateToEarlyMinStartGapMinutes" Aeson..= venueConfig.lateToEarlyMinStartGapMinutes
                , "staffTimesheetEditWindowDays" Aeson..= venueConfig.staffTimesheetEditWindowDays
                ]
            , "payLevels" Aeson..= map serializePayLevel payLevels
            , "shiftTypes" Aeson..= map serializeShiftType shiftTypes
            , "payLevelDayRules" Aeson..= map (serializePayLevelDayRule dayNames) rules
            ]
    where
        serializePayLevel payLevel =
            Aeson.object
                [ "id" Aeson..= unpackId payLevel.id
                , "name" Aeson..= payLevel.name
                , "baseRate" Aeson..= payLevel.baseRate
                , "eveningPenalty" Aeson..= payLevel.eveningPenalty
                , "after12Penalty" Aeson..= payLevel.after12Penalty
                , "weekdayMultiplier" Aeson..= payLevel.weekdayMultiplier
                , "saturdayMultiplier" Aeson..= payLevel.saturdayMultiplier
                , "sundayMultiplier" Aeson..= payLevel.sundayMultiplier
                , "isActive" Aeson..= payLevel.isActive
                ]

        serializeShiftType shiftType =
            Aeson.object
                [ "id" Aeson..= unpackId shiftType.id
                , "name" Aeson..= shiftType.name
                , "sortOrder" Aeson..= shiftType.sortOrder
                , "defaultPayLevelId" Aeson..= shiftType.defaultPayLevelId
                , "isActive" Aeson..= shiftType.isActive
                ]

        serializePayLevelDayRule currentDayNames rule =
            Aeson.object
                [ "id" Aeson..= unpackId rule.id
                , "shiftTypeId" Aeson..= rule.shiftTypeId
                , "payLevelId" Aeson..= rule.payLevelId
                , "dayNameId" Aeson..= rule.dayNameId
                , "weekdayIndex" Aeson..= fmap (.weekdayIndex) (find (\dayName -> unpackId dayName.id == rule.dayNameId) currentDayNames)
                ]

seedCanonicalPayrollFixture :: (?modelContext :: ModelContext) => IO CanonicalPayrollFixture
seedCanonicalPayrollFixture = seedCanonicalPayrollFixtureForWeek defaultWeekEpoch

seedCanonicalPayrollFixtureForWeek :: (?modelContext :: ModelContext) => Day -> IO CanonicalPayrollFixture
seedCanonicalPayrollFixtureForWeek fixtureWeekStart = do
    let dayAtOffset offset = addDays offset fixtureWeekStart
    venue <- createVenueWithConfig "Payroll Parity Venue"
    admin <- createUserRecord "payroll-parity-admin@example.com" "staff" True
    _ <- provisionVenueUser venue admin "venue_admin" "Payroll" "Admin"
    dayNames <- seedWeekDayNames venue
    levelOne <- createPayLevelRecordWithRates venue "LVL 1" 30 0 0 1.25 1.5 1.75
    levelTwo <- createPayLevelRecordWithRates venue "LVL 2" 36 0 0 1.25 1.5 1.75
    barShift <- createShiftTypeRecord venue levelOne "Bar" >>= updateRecord . set #sortOrder 10
    floorShift <- createShiftTypeRecord venue levelOne "Floor" >>= updateRecord . set #sortOrder 20
    kitchenShift <- createShiftTypeRecord venue levelOne "Kitchen" >>= updateRecord . set #sortOrder 30
    let friday = dayNameForWeekday dayNames 5
    overrideRule <- createPayLevelDayRuleRecord barShift friday levelTwo
    avaUser <- createUserRecord "payroll-parity-ava@example.com" "staff" True
    kaiUser <- createUserRecord "payroll-parity-kai@example.com" "staff" True
    avaStaff <- createStaffRecord venue (Just avaUser) "Ava" "Worker"
    kaiStaff <- createStaffRecord venue (Just kaiUser) "Kai" "Cook"
    trialStaff <- createStaffRecord venue Nothing "Trial" "Worker"
    snapshot <- createPayrollSnapshot venue admin [levelOne, levelTwo] [barShift, floorShift, kitchenShift] dayNames [overrideRule]
    let approvedAt = UTCTime (dayAtOffset 6) (secondsToDiffTime 3600)

    _ <- createAndApproveEntry venue avaStaff fixtureWeekStart snapshot admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , set #startTime (TimeOfDay 8 0 0)
        , set #endTime (TimeOfDay 10 30 0)
        ]
    _ <- createAndApproveEntry venue avaStaff fixtureWeekStart snapshot admin approvedAt
        [ set #shiftTypeId (unpackId floorShift.id)
        , set #startTime (TimeOfDay 9 0 0)
        , set #endTime (TimeOfDay 11 0 0)
        ]
    _ <- createAndApproveEntry venue kaiStaff (dayAtOffset 1) snapshot admin approvedAt
        [ set #shiftTypeId (unpackId kitchenShift.id)
        , set #startTime (TimeOfDay 10 0 0)
        , set #endTime (TimeOfDay 14 0 0)
        ]
    _ <- createAndApproveEntry venue avaStaff (dayAtOffset 4) snapshot admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , set #startTime (TimeOfDay 19 0 0)
        , set #endTime (TimeOfDay 1 0 0)
        ]
    _ <- createAndApproveEntry venue avaStaff (dayAtOffset 5) snapshot admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , set #startTime (TimeOfDay 9 0 0)
        , set #endTime (TimeOfDay 13 0 0)
        , set #hadBreak True
        , set #breakMinutes 30
        , set #breakStartTime (Just (TimeOfDay 11 0 0))
        , set #breakEndTime (Just (TimeOfDay 11 30 0))
        ]
    _ <- createAndApproveEntry venue trialStaff fixtureWeekStart snapshot admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , set #startTime (TimeOfDay 10 0 0)
        , set #endTime (TimeOfDay 12 0 0)
        ]
    _ <- createTimesheetEntryRecord venue avaStaff (dayAtOffset 2)
        >>= updateRecord
            . set #shiftTypeId (unpackId barShift.id)
            . set #startTime (TimeOfDay 12 0 0)
            . set #endTime (TimeOfDay 14 0 0)

    pure
        CanonicalPayrollFixture
            { venue
            , admin
            , dayNames
            , levelOne
            , levelTwo
            , barShift
            , floorShift
            , kitchenShift
            , avaStaff
            , kaiStaff
            , trialStaff
            , snapshot
            , approvedAt
            }

seedExplorationPayrollFixtureForWeek :: (?modelContext :: ModelContext) => Day -> IO ExplorationPayrollFixture
seedExplorationPayrollFixtureForWeek fixtureWeekStart = do
    let dayAtOffset offset = addDays offset fixtureWeekStart
    venue <- createVenueWithConfig "Payroll Parity Venue"
    admin <- createUserRecord "payroll-parity-admin@example.com" "staff" True
    _ <- provisionVenueUser venue admin "venue_admin" "Payroll" "Admin"
    dayNames <- seedWeekDayNames venue
    levelOne <- createPayLevelRecordWithRates venue "LVL 1" 30 0 0 1.25 1.5 1.75
    levelTwo <- createPayLevelRecordWithRates venue "LVL 2" 36 0 0 1.25 1.5 1.75
    levelThree <- createPayLevelRecordWithRates venue "LVL 3" 42 2 4 1.3 1.6 1.85
    barShift <- createShiftTypeRecord venue levelOne "Bar" >>= updateRecord . set #sortOrder 10
    floorShift <- createShiftTypeRecord venue levelTwo "Floor" >>= updateRecord . set #sortOrder 20
    kitchenShift <- createShiftTypeRecord venue levelThree "Kitchen" >>= updateRecord . set #sortOrder 30
    let friday = dayNameForWeekday dayNames 5
    let saturday = dayNameForWeekday dayNames 6
    fridayOverride <- createPayLevelDayRuleRecord barShift friday levelTwo
    saturdayOverride <- createPayLevelDayRuleRecord kitchenShift saturday levelThree

    avaUser <- createUserRecord "payroll-parity-ava@example.com" "staff" True
    kaiUser <- createUserRecord "payroll-parity-kai@example.com" "staff" True
    miaUser <- createUserRecord "payroll-parity-mia@example.com" "staff" True
    noorUser <- createUserRecord "payroll-parity-noor@example.com" "staff" True
    benUser <- createUserRecord "payroll-parity-ben@example.com" "staff" True

    avaStaff <- createStaffRecord venue (Just avaUser) "Ava" "Worker"
    kaiStaff <- createStaffRecord venue (Just kaiUser) "Kai" "Cook"
    miaStaff <- createStaffRecord venue (Just miaUser) "Mia" "Closer"
    noorStaff <- createStaffRecord venue (Just noorUser) "Noor" "Late"
    benStaff <- createStaffRecord venue (Just benUser) "Ben" "Split"
    trialStaff <- createStaffRecord venue Nothing "Trial" "Worker"

    snapshot <- createPayrollSnapshot venue admin [levelOne, levelTwo, levelThree] [barShift, floorShift, kitchenShift] dayNames [fridayOverride, saturdayOverride]
    let approvedAt = UTCTime (dayAtOffset 6) (secondsToDiffTime 3600)

    approvedEntries <-
        sequence
            [ createAndApproveEntry venue avaStaff (dayAtOffset 0) snapshot admin approvedAt
                [ set #shiftTypeId (unpackId barShift.id)
                , set #startTime (TimeOfDay 8 0 0)
                , set #endTime (TimeOfDay 12 30 0)
                ]
            , createAndApproveEntry venue avaStaff (dayAtOffset 0) snapshot admin approvedAt
                [ set #shiftTypeId (unpackId floorShift.id)
                , set #startTime (TimeOfDay 18 0 0)
                , set #endTime (TimeOfDay 22 0 0)
                , set #hadBreak True
                , set #breakMinutes 15
                , set #breakStartTime (Just (TimeOfDay 20 0 0))
                , set #breakEndTime (Just (TimeOfDay 20 15 0))
                ]
            , createAndApproveEntry venue kaiStaff (dayAtOffset 1) snapshot admin approvedAt
                [ set #shiftTypeId (unpackId kitchenShift.id)
                , set #startTime (TimeOfDay 6 0 0)
                , set #endTime (TimeOfDay 14 0 0)
                , set #hadBreak True
                , set #breakMinutes 30
                , set #breakStartTime (Just (TimeOfDay 10 0 0))
                , set #breakEndTime (Just (TimeOfDay 10 30 0))
                ]
            , createAndApproveEntry venue miaStaff (dayAtOffset 2) snapshot admin approvedAt
                [ set #shiftTypeId (unpackId floorShift.id)
                , set #startTime (TimeOfDay 11 0 0)
                , set #endTime (TimeOfDay 19 0 0)
                , set #hadBreak True
                , set #breakMinutes 30
                , set #breakStartTime (Just (TimeOfDay 15 0 0))
                , set #breakEndTime (Just (TimeOfDay 15 30 0))
                ]
            , createAndApproveEntry venue benStaff (dayAtOffset 3) snapshot admin approvedAt
                [ set #shiftTypeId (unpackId floorShift.id)
                , set #startTime (TimeOfDay 7 0 0)
                , set #endTime (TimeOfDay 12 0 0)
                ]
            , createAndApproveEntry venue kaiStaff (dayAtOffset 3) snapshot admin approvedAt
                [ set #shiftTypeId (unpackId kitchenShift.id)
                , set #startTime (TimeOfDay 14 0 0)
                , set #endTime (TimeOfDay 22 0 0)
                , set #hadBreak True
                , set #breakMinutes 45
                , set #breakStartTime (Just (TimeOfDay 18 0 0))
                , set #breakEndTime (Just (TimeOfDay 18 45 0))
                ]
            , createAndApproveEntry venue avaStaff (dayAtOffset 4) snapshot admin approvedAt
                [ set #shiftTypeId (unpackId barShift.id)
                , set #startTime (TimeOfDay 19 0 0)
                , set #endTime (TimeOfDay 2 0 0)
                , set #hadBreak True
                , set #breakMinutes 30
                , set #breakStartTime (Just (TimeOfDay 22 0 0))
                , set #breakEndTime (Just (TimeOfDay 22 30 0))
                ]
            , createAndApproveEntry venue benStaff (dayAtOffset 4) snapshot admin approvedAt
                [ set #shiftTypeId (unpackId barShift.id)
                , set #startTime (TimeOfDay 12 0 0)
                , set #endTime (TimeOfDay 18 0 0)
                ]
            , createAndApproveEntry venue miaStaff (dayAtOffset 5) snapshot admin approvedAt
                [ set #shiftTypeId (unpackId floorShift.id)
                , set #startTime (TimeOfDay 17 0 0)
                , set #endTime (TimeOfDay 1 0 0)
                , set #hadBreak True
                , set #breakMinutes 45
                , set #breakStartTime (Just (TimeOfDay 21 0 0))
                , set #breakEndTime (Just (TimeOfDay 21 45 0))
                ]
            , createAndApproveEntry venue noorStaff (dayAtOffset 5) snapshot admin approvedAt
                [ set #shiftTypeId (unpackId barShift.id)
                , set #startTime (TimeOfDay 9 0 0)
                , set #endTime (TimeOfDay 15 0 0)
                , set #hadBreak True
                , set #breakMinutes 30
                , set #breakStartTime (Just (TimeOfDay 12 0 0))
                , set #breakEndTime (Just (TimeOfDay 12 30 0))
                ]
            , createAndApproveEntry venue noorStaff (dayAtOffset 6) snapshot admin approvedAt
                [ set #shiftTypeId (unpackId barShift.id)
                , set #startTime (TimeOfDay 10 0 0)
                , set #endTime (TimeOfDay 16 0 0)
                ]
            , createAndApproveEntry venue benStaff (dayAtOffset 6) snapshot admin approvedAt
                [ set #shiftTypeId (unpackId kitchenShift.id)
                , set #startTime (TimeOfDay 11 0 0)
                , set #endTime (TimeOfDay 17 0 0)
                , set #hadBreak True
                , set #breakMinutes 20
                , set #breakStartTime (Just (TimeOfDay 13 30 0))
                , set #breakEndTime (Just (TimeOfDay 13 50 0))
                ]
            , createAndApproveEntry venue trialStaff (dayAtOffset 1) snapshot admin approvedAt
                [ set #shiftTypeId (unpackId barShift.id)
                , set #startTime (TimeOfDay 10 0 0)
                , set #endTime (TimeOfDay 12 0 0)
                ]
            ]

    pendingEntries <-
        sequence
            [ createTimesheetEntryRecord venue avaStaff (dayAtOffset 2)
                >>= updateRecord
                    . set #shiftTypeId (unpackId barShift.id)
                    . set #startTime (TimeOfDay 12 0 0)
                    . set #endTime (TimeOfDay 14 0 0)
            , createTimesheetEntryRecord venue noorStaff (dayAtOffset 4)
                >>= updateRecord
                    . set #shiftTypeId (unpackId floorShift.id)
                    . set #startTime (TimeOfDay 7 30 0)
                    . set #endTime (TimeOfDay 11 30 0)
            ]

    pure
        ExplorationPayrollFixture
            { explorationVenue = venue
            , explorationAdmin = admin
            , explorationApprovedEntries = approvedEntries
            , explorationPendingEntries = pendingEntries
            }
