module Application.Script.SeedDev where

import Application.Script.Prelude
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (getCurrentTime, utctDay)
import Application.Support (defaultWeekEpoch, testPassword)
import Application.Support.DevFixtures (DevSeedFixture (..),
                                        seedDevelopmentFixtureForWeek)
import Application.Support.PayrollFixtures (ExplorationPayrollFixture (..))

run :: Script
run = do
    now <- getCurrentTime
    let fixtureWeekStart = currentFixtureWeekStart (utctDay now)

    DevSeedFixture
        { sandboxVenue = sandboxVenue
        , sandboxAdmin = sandboxAdmin
        , sandboxManager = sandboxManager
        , sandboxWorker = sandboxWorker
        , supportAdmin = supportAdmin
        , sandboxInvitation = sandboxInvitation
        , frontOfHouseGroup = frontOfHouseGroup
        , backOfHouseGroup = backOfHouseGroup
        , payrollFixture =
            ExplorationPayrollFixture
                { explorationVenue = payrollVenue
                , explorationAdmin = payrollAdmin
                , explorationApprovedEntries = approvedEntries
                , explorationPendingEntries = pendingEntries
                }
        } <- seedDevelopmentFixtureForWeek fixtureWeekStart

    TextIO.putStrLn ("Seeded dev sandbox venue: " <> get #name sandboxVenue)
    TextIO.putStrLn ("Sandbox admin login: " <> get #email sandboxAdmin)
    TextIO.putStrLn ("Sandbox manager login: " <> get #email sandboxManager)
    TextIO.putStrLn ("Sandbox worker login: " <> get #email sandboxWorker)
    TextIO.putStrLn ("Support admin login: " <> get #email supportAdmin)
    TextIO.putStrLn ("Sandbox admin password: " <> testPassword)
    TextIO.putStrLn ("Pending invitation email: " <> get #email sandboxInvitation)
    TextIO.putStrLn ("Current week start: " <> tshow fixtureWeekStart)
    TextIO.putStrLn ("Roster groups: " <> get #name frontOfHouseGroup <> ", " <> get #name backOfHouseGroup)
    TextIO.putStrLn ("Seeded payroll venue: " <> get #name payrollVenue)
    TextIO.putStrLn ("Payroll admin login: " <> get #email payrollAdmin)
    TextIO.putStrLn ("Approved payroll entries: " <> tshow (length approvedEntries))
    TextIO.putStrLn ("Pending payroll entries: " <> tshow (length pendingEntries))
    TextIO.putStrLn "Manual testing surface now includes multi-group roster data, support switching, invitation/bootstrap state, leave conflicts, and payroll export data."

currentFixtureWeekStart :: Day -> Day
currentFixtureWeekStart today =
    addDays (toInteger (currentWeekOffsetForDay today * 7)) defaultWeekEpoch

currentWeekOffsetForDay :: Day -> Int
currentWeekOffsetForDay today = fromInteger (diffDays today defaultWeekEpoch `div` 7)
