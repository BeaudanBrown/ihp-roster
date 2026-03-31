module Application.Script.SeedDev where

import Application.Script.Prelude
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (getCurrentTime, utctDay)
import System.Exit (exitFailure)
import Test.Support (defaultWeekEpoch, testPassword)
import Test.Support.DevFixtures (DevSeedFixture (..),
                                 seedDevelopmentFixtureForWeek)
import Test.Support.PayrollFixtures (ExplorationPayrollFixture (..))

run :: Script
run = do
    now <- getCurrentTime
    let fixtureWeekStart = currentFixtureWeekStart (utctDay now)
    existingVenues <-
        query @Venue
            |> filterWhereIn (#name, fixtureVenueNames)
            |> fetch

    unless (null existingVenues) do
        TextIO.putStrLn "Seed-dev fixture venues already exist in the target database:"
        forM_ existingVenues \venue -> TextIO.putStrLn ("- " <> get #name venue)
        TextIO.putStrLn "Refusing to seed duplicate dev fixture data."
        TextIO.putStrLn "Reset the target database first, or remove the existing dev fixture rows."
        liftIO exitFailure

    DevSeedFixture
        { sandboxVenue = sandboxVenue
        , sandboxAdmin = sandboxAdmin
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
    TextIO.putStrLn ("Sandbox admin password: " <> testPassword)
    TextIO.putStrLn ("Current week start: " <> tshow fixtureWeekStart)
    TextIO.putStrLn ("Roster groups: " <> get #name frontOfHouseGroup <> ", " <> get #name backOfHouseGroup)
    TextIO.putStrLn ("Seeded payroll venue: " <> get #name payrollVenue)
    TextIO.putStrLn ("Payroll admin login: " <> get #email payrollAdmin)
    TextIO.putStrLn ("Approved payroll entries: " <> tshow (length approvedEntries))
    TextIO.putStrLn ("Pending payroll entries: " <> tshow (length pendingEntries))
    TextIO.putStrLn "Manual testing surface now includes multi-group roster data, leave conflicts, and payroll export data."
  where
    fixtureVenueNames = ["Development Sandbox Venue", "Payroll Parity Venue"]

currentFixtureWeekStart :: Day -> Day
currentFixtureWeekStart today =
    addDays (toInteger (currentWeekOffsetForDay today * 7)) defaultWeekEpoch

currentWeekOffsetForDay :: Day -> Int
currentWeekOffsetForDay today = fromInteger (diffDays today defaultWeekEpoch `div` 7)
