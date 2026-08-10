module Application.Fixture.DevFixtures
    ( DevSeedFixture (..)
    , seedDevelopmentFixtureAfterResetWithScenarioForWeekAndLeaveMonth
    , seedDevelopmentFixtureForWeek
    , seedDevelopmentFixtureWithScenarioForWeek
    , seedDevelopmentFixtureWithScenarioForWeekAndLeaveMonth
    ) where

import Application.Fixture (createVenueWithConfig)
import Application.Fixture.DevFixtures.Deterministic (dayAtOffset)
import Application.Fixture.DevFixtures.Leave (seedLeaveProjection)
import Application.Fixture.DevFixtures.Payroll
import Application.Fixture.DevFixtures.Roster
import Application.Fixture.DevFixtures.Staff
import Application.Fixture.Reset (resetDatabase)
import Application.Fixture.Seed.Calendar (weekOffsetForDay)
import Application.Fixture.Seed.Scenario
import Data.Time.Calendar (Day)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude

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
    resetDatabase
    seedDevelopmentFixtureAfterResetWithScenarioForWeekAndLeaveMonth scenario fixtureWeekStart leaveMonthAnchor

-- | Interpret one stable scenario through the ordered domain projections.
-- The caller may preload reference rows between the canonical reset and this
-- operation; every domain module receives only the context it needs.
seedDevelopmentFixtureAfterResetWithScenarioForWeekAndLeaveMonth :: (?modelContext :: ModelContext) => SeedScenario -> Day -> Day -> IO DevSeedFixture
seedDevelopmentFixtureAfterResetWithScenarioForWeekAndLeaveMonth scenario fixtureWeekStart leaveMonthAnchor = do
    ensurePayReferenceData
    venue <- createVenueWithConfig "Development Sandbox Venue"
    accounts <- seedAccounts venue scenario
    roster <- seedRosterFoundation venue
    pay <- seedShiftTypes venue accounts.admin fixtureWeekStart
    baseStaff <- seedStaff venue scenario accounts
    staff <- applySeededPayAssignments pay.floorAwardLevel pay.importedPayItem.id accounts.aliasStaff baseStaff
    seedRosterProjection scenario fixtureWeekStart venue roster staff pay.allShiftTypes
    seedLeaveProjection fixtureWeekStart leaveMonthAnchor venue scenario staff.allOperationalStaff
    now <- getCurrentTime
    let scheduledApprovalAt = UTCTime (dayAtOffset fixtureWeekStart 6) (secondsToDiffTime 3600)
        approvedAt = min now scheduledApprovalAt
    seedTimesheetProjection fixtureWeekStart venue accounts.admin scenario pay staff.allOperationalStaff approvedAt
    pure
        DevSeedFixture
            { sandboxVenue = venue
            , sandboxAdmin = accounts.admin
            , sandboxManager = accounts.managerUser
            , sandboxManagers = accounts.managerUsers
            , sandboxWorker = accounts.workerUser
            , supportAdmin = accounts.supportAdmin
            , sandboxInvitation = accounts.invitation
            , frontOfHouseGroup = roster.frontOfHouseGroup
            , backOfHouseGroup = roster.backOfHouseGroup
            , currentWeekOffset = weekOffsetForDay fixtureWeekStart
            , scenario = scenario
            }
