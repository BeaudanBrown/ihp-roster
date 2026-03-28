module Application.Script.SeedPayrollFixture where

import Application.Script.Prelude
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (getCurrentTime, utctDay)
import System.Exit (exitFailure)
import Test.Support (defaultWeekEpoch)
import Test.Support.PayrollFixtures (ExplorationPayrollFixture (..),
                                     seedExplorationPayrollFixtureForWeek)

run :: Script
run = do
    now <- getCurrentTime
    let fixtureWeekStart = currentFixtureWeekStart (utctDay now)
    existingVenue <- query @Venue
        |> filterWhere (#name, fixtureVenueName)
        |> fetchOneOrNothing

    when (isJust existingVenue) do
        TextIO.putStrLn ("Payroll fixture venue already exists: " <> fixtureVenueName)
        TextIO.putStrLn "Refusing to seed duplicate canonical payroll fixture data."
        TextIO.putStrLn "Reset the target database first, or remove the existing payroll fixture rows."
        liftIO exitFailure

    ExplorationPayrollFixture
        { explorationVenue = seededVenue
        , explorationAdmin = seededAdmin
        , explorationApprovedEntries = approvedEntries
        , explorationPendingEntries = pendingEntries
        } <- seedExplorationPayrollFixtureForWeek fixtureWeekStart

    TextIO.putStrLn ("Seeded payroll exploration fixture into venue: " <> get #name seededVenue)
    TextIO.putStrLn ("Admin login: " <> get #email seededAdmin)
    TextIO.putStrLn ("Week start: " <> tshow fixtureWeekStart)
    TextIO.putStrLn ("Approved timesheets: " <> tshow (length approvedEntries))
    TextIO.putStrLn ("Pending timesheets: " <> tshow (length pendingEntries))
    TextIO.putStrLn "Exports page will now generate the richer payroll fixture data for the current week."
  where
    fixtureVenueName = "Payroll Parity Venue"

currentFixtureWeekStart :: Day -> Day
currentFixtureWeekStart today =
    addDays (toInteger (currentWeekOffset today * 7)) defaultWeekEpoch

currentWeekOffset :: Day -> Int
currentWeekOffset today = fromInteger (diffDays today defaultWeekEpoch `div` 7)
