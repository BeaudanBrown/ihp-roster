module Application.Fixture.PayrollFixtures where

import Application.Fixture
import Application.Fixture.Error
import Application.Fixture.WageSourceFixtures (ensureFreshWageSourceFacts,
                                               sealApprovedFixtureCalculation)
import Application.Helper.Pay (ensurePayVersionsForTimesheetApproval,
                               lockPayVersionsForApproval)
import Application.Helper.RosterGroups (ensureVenueRosterDefaults,
                                        fetchVenueDayNames)
import Application.Helper.VenueBootstrap (provisionVenueUser)
import Application.VenueTime (melbourneTimeZoneName)
import Application.VenueTime.Model
import Config
import Control.Exception (bracket)
import Data.Time.Calendar (Day, DayOfWeek (..), addDays, dayOfWeek,
                           fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlExecDiscardResult)
import IHP.Prelude

data CanonicalPayrollFixture = CanonicalPayrollFixture
    { venue        :: !Venue
    , admin        :: !User
    , levelOne     :: !AwardLevel
    , barShift     :: !ShiftType
    , floorShift   :: !ShiftType
    , kitchenShift :: !ShiftType
    , avaStaff     :: !Staff
    , kaiStaff     :: !Staff
    , trialStaff   :: !Staff
    , approvedAt   :: !UTCTime
    }

data ExplorationPayrollFixture = ExplorationPayrollFixture
    { explorationVenue           :: !Venue
    , explorationAdmin           :: !User
    , explorationApprovedEntries :: ![TimesheetEntry]
    , explorationPendingEntries  :: ![TimesheetEntry]
    }

data TimesheetFixtureValues = TimesheetFixtureValues
    { shiftTypeId       :: !UUID
    , startTime         :: !TimeOfDay
    , endTime           :: !TimeOfDay
    , hadBreak          :: !Bool
    , breakStartTime    :: !(Maybe TimeOfDay)
    , breakEndTime      :: !(Maybe TimeOfDay)
    , breakMinutes      :: !Int
    , calendarDayOffset :: !Int
    }

instance SetField "shiftTypeId" TimesheetFixtureValues UUID where
    setField value fixture = fixture { Application.Fixture.PayrollFixtures.shiftTypeId = value }

instance SetField "startTime" TimesheetFixtureValues TimeOfDay where
    setField value fixture = fixture { Application.Fixture.PayrollFixtures.startTime = value }

instance SetField "endTime" TimesheetFixtureValues TimeOfDay where
    setField value fixture = fixture { Application.Fixture.PayrollFixtures.endTime = value }

instance SetField "hadBreak" TimesheetFixtureValues Bool where
    setField value fixture = fixture { Application.Fixture.PayrollFixtures.hadBreak = value }

instance SetField "breakStartTime" TimesheetFixtureValues (Maybe TimeOfDay) where
    setField value fixture = fixture { Application.Fixture.PayrollFixtures.breakStartTime = value }

instance SetField "breakEndTime" TimesheetFixtureValues (Maybe TimeOfDay) where
    setField value fixture = fixture { Application.Fixture.PayrollFixtures.breakEndTime = value }

instance SetField "breakMinutes" TimesheetFixtureValues Int where
    setField value fixture = fixture { Application.Fixture.PayrollFixtures.breakMinutes = value }

instance SetField "calendarDayOffset" TimesheetFixtureValues Int where
    setField value fixture = fixture { Application.Fixture.PayrollFixtures.calendarDayOffset = value }

seedWeekDayNames :: (?modelContext :: ModelContext) => Venue -> IO [DayName]
seedWeekDayNames venue = do
    _ <- ensureVenueRosterDefaults venue
    fetchVenueDayNames venue

dayNameForWeekday :: [DayName] -> Int -> Either FixtureError DayName
dayNameForWeekday dayNames weekdayIndex =
    fixtureRequired
        (MissingFixtureReference ("day name for weekday index " <> tshow weekdayIndex))
        (find (\dayName -> dayName.weekdayIndex == weekdayIndex) dayNames)

-- | Build and lock real staff/shift versions through the production approval
-- builders, then seal the calculation. No separate snapshot setup is required.
createAndApproveEntry ::
    (?modelContext :: ModelContext) =>
    Venue ->
    Staff ->
    Day ->
    User ->
    UTCTime ->
    [TimesheetFixtureValues -> TimesheetFixtureValues] ->
    IO TimesheetEntry
createAndApproveEntry venue staff workedOn admin approvedAt transforms = do
    ensureFreshWageSourceFacts workedOn
    entry <- createTimesheetEntryRecord venue staff workedOn
    transformedEntry <- requireFixtureResult (applyTimesheetFixtureTransforms workedOn transforms entry)
    updatedEntry <- updateRecord transformedEntry
    timing <- requireFixtureResult (either (Left . InvalidFixtureBoundary . tshow) Right (decodeTimesheetTiming updatedEntry))
    (staffPayVersion, shiftTypePayVersion) <- ensurePayVersionsForTimesheetApproval admin.id timing updatedEntry
    lockPayVersionsForApproval admin.id approvedAt staffPayVersion shiftTypePayVersion
    approvedEntry <- withLegacyPayBackfillFixture do
        updatedEntry
            |> approveEntryWithVersions staffPayVersion shiftTypePayVersion admin approvedAt
            |> updateRecord
    sealApprovedFixtureCalculation approvedEntry

-- Compatibility fixtures intentionally model pre-ledger approved exports with
-- legacy unsupported pay-level IDs. Production and dev seed approvals never use
-- this test-only migration exemption.
withLegacyPayBackfillFixture :: (?modelContext :: ModelContext) => IO value -> IO value
withLegacyPayBackfillFixture action =
    bracket
        (sqlExecDiscardResult "ALTER TABLE timesheet_entries DISABLE TRIGGER prevent_legacy_pay_backfill_grant" ())
        (const (sqlExecDiscardResult "ALTER TABLE timesheet_entries ENABLE TRIGGER prevent_legacy_pay_backfill_grant" ()))
        (const action)

approveEntryWithVersions :: StaffPayVersion -> ShiftTypePayVersion -> User -> UTCTime -> TimesheetEntry -> TimesheetEntry
approveEntryWithVersions staffPayVersion shiftTypePayVersion admin approvedAt =
    set #staffPayVersionId (Just (unpackId staffPayVersion.id))
        . set #shiftTypePayVersionId (Just (unpackId shiftTypePayVersion.id))
        . set #isApproved True
        . set #legacyPayBackfillPending True
        . set #approvedAt (Just approvedAt)
        . set #approvedByUserId (Just (unpackId admin.id))

applyTransforms :: [record -> record] -> record -> record
applyTransforms transforms record = foldl' (\current transform -> transform current) record transforms

applyTimesheetFixtureTransforms :: Day -> [TimesheetFixtureValues -> TimesheetFixtureValues] -> TimesheetEntry -> Either FixtureError TimesheetEntry
applyTimesheetFixtureTransforms workedOn transforms entry = do
    let values = applyTransforms transforms TimesheetFixtureValues
            { shiftTypeId = entry.shiftTypeId
            , startTime = TimeOfDay 9 0 0
            , endTime = TimeOfDay 17 0 0
            , hadBreak = False
            , breakStartTime = Nothing
            , breakEndTime = Nothing
            , breakMinutes = 0
            , calendarDayOffset = 0
            }
    breakInput <-
        if values.hadBreak
            then do
                breakStart <- fixtureRequired (MissingFixtureValue "payroll fixture break start") values.breakStartTime
                breakEnd <- fixtureRequired (MissingFixtureValue "payroll fixture break end") values.breakEndTime
                Right (Just BreakBoundaryInput
                    { breakBoundaryStartTime = breakStart
                    , breakBoundaryStartOccurrence = Nothing
                    , breakBoundaryEndTime = breakEnd
                    , breakBoundaryEndOccurrence = Nothing
                    })
            else Right Nothing
    boundaries <-
        either (Left . InvalidFixtureBoundary . tshow) Right $
            resolveShiftBoundaries melbourneTimeZoneName ShiftBoundaryInput
                { shiftBoundaryDate = addDays (toInteger values.calendarDayOffset) workedOn
                , shiftBoundaryStartTime = values.startTime
                , shiftBoundaryStartOccurrence = Nothing
                , shiftBoundaryEndTime = values.endTime
                , shiftBoundaryEndOccurrence = Nothing
                , shiftBoundaryBreak = breakInput
                }
    Right
        ( entry
            |> set #shiftTypeId values.shiftTypeId
            |> applyTimesheetEntryBoundaries boundaries
        )

fixtureWeekdayIndex :: Day -> Int
fixtureWeekdayIndex day = case dayOfWeek day of
    Sunday    -> 0
    Monday    -> 1
    Tuesday   -> 2
    Wednesday -> 3
    Thursday  -> 4
    Friday    -> 5
    Saturday  -> 6


seedCanonicalPayrollFixtureForWeek :: (?modelContext :: ModelContext) => Day -> IO CanonicalPayrollFixture
seedCanonicalPayrollFixtureForWeek fixtureWeekStart = do
    let dayAtOffset offset = addDays offset fixtureWeekStart
    venue <- createVenueWithConfig "Payroll Parity Venue"
    venueConfig <- query @VenueConfig |> filterWhere (#venueId, unpackId venue.id) |> fetchOne
    _ <- venueConfig
        |> set #rosterWeekStartsOn (fixtureWeekdayIndex fixtureWeekStart)
        |> updateRecord
    admin <- createUserRecord "payroll-parity-admin@example.com" "staff" True
    _ <- provisionVenueUser venue admin VenueAdmin "Payroll" "Admin"
    dayNames <- seedWeekDayNames venue
    levelOne <- createPayLevelRecordWithRates venue "LVL 1" 30 0 0 1.25 1.5 1.75
    levelTwo <- createPayLevelRecordWithRates venue "LVL 2" 36 0 0 1.25 1.5 1.75
    barShift <- createShiftTypeRecord venue levelOne "Bar" >>= updateRecord . set #sortOrder 10
    floorShift <- createShiftTypeRecord venue levelOne "Floor" >>= updateRecord . set #sortOrder 20
    kitchenShift <- createShiftTypeRecord venue levelOne "Kitchen" >>= updateRecord . set #sortOrder 30
    friday <- requireFixtureResult (dayNameForWeekday dayNames 5)
    _ <- createPayLevelDayRuleRecord barShift friday levelTwo
    avaUser <- createUserRecord "payroll-parity-ava@example.com" "staff" True
    kaiUser <- createUserRecord "payroll-parity-kai@example.com" "staff" True
    avaStaff <- createPlaceholderStaffRecord venue (Just avaUser) "Ava" "Worker"
    kaiStaff <- createPlaceholderStaffRecord venue (Just kaiUser) "Kai" "Cook"
    trialStaff <- createPlaceholderStaffRecord venue Nothing "Trial" "Worker"
    let approvedAt = UTCTime (dayAtOffset 6) (secondsToDiffTime 3600)

    _ <- createAndApproveEntry venue avaStaff fixtureWeekStart admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , set #startTime (TimeOfDay 8 0 0)
        , set #endTime (TimeOfDay 10 30 0)
        ]
    _ <- createAndApproveEntry venue avaStaff fixtureWeekStart admin approvedAt
        [ set #shiftTypeId (unpackId floorShift.id)
        , set #startTime (TimeOfDay 9 0 0)
        , set #endTime (TimeOfDay 11 0 0)
        ]
    _ <- createAndApproveEntry venue kaiStaff (dayAtOffset 1) admin approvedAt
        [ set #shiftTypeId (unpackId kitchenShift.id)
        , set #startTime (TimeOfDay 10 0 0)
        , set #endTime (TimeOfDay 14 0 0)
        ]
    _ <- createAndApproveEntry venue avaStaff (dayAtOffset 4) admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , set #startTime (TimeOfDay 19 0 0)
        , set #endTime (TimeOfDay 1 0 0)
        ]
    _ <- createAndApproveEntry venue avaStaff (dayAtOffset 5) admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , set #startTime (TimeOfDay 9 0 0)
        , set #endTime (TimeOfDay 13 0 0)
        , set #hadBreak True
        , set #breakMinutes 30
        , set #breakStartTime (Just (TimeOfDay 11 0 0))
        , set #breakEndTime (Just (TimeOfDay 11 30 0))
        ]
    _ <- createAndApproveEntry venue trialStaff fixtureWeekStart admin approvedAt
        [ set #shiftTypeId (unpackId barShift.id)
        , set #startTime (TimeOfDay 10 0 0)
        , set #endTime (TimeOfDay 12 0 0)
        ]
    pendingEntry <- createTimesheetEntryRecord venue avaStaff (dayAtOffset 2)
    transformedPendingEntry <- requireFixtureResult $
        applyTimesheetFixtureTransforms (dayAtOffset 2)
            [ set #shiftTypeId (unpackId barShift.id)
            , set #startTime (TimeOfDay 12 0 0)
            , set #endTime (TimeOfDay 14 0 0)
            ]
            pendingEntry
    _ <- updateRecord transformedPendingEntry

    pure
        CanonicalPayrollFixture
            { venue
            , admin
            , levelOne
            , barShift
            , floorShift
            , kitchenShift
            , avaStaff
            , kaiStaff
            , trialStaff
            , approvedAt
            }
