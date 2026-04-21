module Application.Script.SeedDev where

import Application.Helper.Controller (unsafeEnumFromText)
import Application.Script.Prelude
import Application.Support (defaultWeekEpoch, testPassword)
import Application.Support.DevFixtures (DevSeedFixture (..),
                                        seedDevelopmentFixtureWithScenarioForWeekAndLeaveMonth)
import Application.Support.PayrollFixtures (ExplorationPayrollFixture (..))
import Application.Support.Seed.Scenario
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified System.Environment as Environment
import System.Exit (exitSuccess)
import qualified Text.Read as TextRead

seededSupportAdminPassword :: Text
seededSupportAdminPassword = "admin"

run :: Script
run = do
    options <- liftIO parseSeedDevOptions
    now <- getCurrentTime
    let fixtureWeekStart = currentFixtureWeekStart (utctDay now)
    let scenario = resolveScenario options

    DevSeedFixture
        { sandboxVenue = sandboxVenue
        , sandboxAdmin = sandboxAdmin
        , sandboxManager = sandboxManager
        , sandboxManagers = sandboxManagers
        , sandboxWorker = sandboxWorker
        , supportAdmin = supportAdmin
        , sandboxInvitation = sandboxInvitation
        , frontOfHouseGroup = frontOfHouseGroup
        , backOfHouseGroup = backOfHouseGroup
        , currentWeekOffset = currentWeekOffset
        , scenario = scenario
        , payrollFixture =
            ExplorationPayrollFixture
                { explorationVenue = payrollVenue
                , explorationAdmin = payrollAdmin
                , explorationApprovedEntries = approvedEntries
                , explorationPendingEntries = pendingEntries
                }
        } <- seedDevelopmentFixtureWithScenarioForWeekAndLeaveMonth scenario fixtureWeekStart (utctDay now)

    actualStaffCount <-
        query @Staff
            |> filterWhere (#venueId, unpackId (get #id sandboxVenue))
            |> fetchCount
    actualManagerCount <-
        query @VenueMembership
            |> filterWhere (#venueId, unpackId (get #id sandboxVenue))
            |> filterWhere (#venueRole, unsafeEnumFromText @VenueRoleEnum "manager")
            |> fetchCount
    leaveRequests <-
        query @LeaveRequest
            |> filterWhere (#venueId, unpackId (get #id sandboxVenue))
            |> fetch
    timesheetEntries <-
        query @TimesheetEntry
            |> filterWhere (#venueId, unpackId (get #id sandboxVenue))
            |> fetch
    rosterWeeks <-
        query @RosterWeek
            |> filterWhere (#venueId, unpackId (get #id sandboxVenue))
            |> filterWhere (#weekOffset, currentWeekOffset)
            |> fetch
    rosterDays <-
        query @RosterDay
            |> filterWhereIn (#rosterWeekId, map (unpackId . (.id)) rosterWeeks)
            |> fetch
    rosterSlots <-
        query @RosterSlot
            |> filterWhereIn (#rosterDayId, map (unpackId . (.id)) rosterDays)
            |> fetch
    let filledRosterSlotCount = length (filter (isJust . (.staffId)) rosterSlots)
    let totalRosterSlotCount = length rosterSlots
    let approvedLeaveCount = length (filter (\leaveRequest -> get #status leaveRequest == unsafeEnumFromText @LeaveRequestStatusEnum "approved") leaveRequests)
    let pendingLeaveCount = length (filter (\leaveRequest -> get #status leaveRequest == unsafeEnumFromText @LeaveRequestStatusEnum "pending") leaveRequests)
    let deniedLeaveCount = length (filter (\leaveRequest -> get #status leaveRequest == unsafeEnumFromText @LeaveRequestStatusEnum "denied") leaveRequests)
    let approvedTimesheetCount = length (filter (.isApproved) timesheetEntries)
    let pendingTimesheetCount = length timesheetEntries - approvedTimesheetCount

    TextIO.putStrLn ("Scenario: " <> scenario.scenarioLabel)
    TextIO.putStrLn ("Deterministic seed: " <> tshow scenario.scenarioSeed)
    TextIO.putStrLn ("Seeded dev sandbox venue: " <> get #name sandboxVenue)
    TextIO.putStrLn ("Sandbox admin login: " <> get #email sandboxAdmin)
    TextIO.putStrLn ("Sandbox manager login: " <> get #email sandboxManager)
    when (length sandboxManagers > 1) $
        TextIO.putStrLn ("Additional manager logins: " <> intercalate ", " (map (get #email) (drop 1 sandboxManagers)))
    TextIO.putStrLn ("Sandbox worker login: " <> get #email sandboxWorker)
    TextIO.putStrLn ("Support admin login: " <> get #email supportAdmin)
    TextIO.putStrLn ("Sandbox admin password: " <> testPassword)
    TextIO.putStrLn ("Support admin password: " <> seededSupportAdminPassword)
    TextIO.putStrLn ("Pending invitation email: " <> get #email sandboxInvitation)
    TextIO.putStrLn ("Current week start: " <> tshow fixtureWeekStart)
    TextIO.putStrLn ("Roster groups: " <> get #name frontOfHouseGroup <> ", " <> get #name backOfHouseGroup)
    TextIO.putStrLn ("Seeded staff count: " <> tshow actualStaffCount)
    TextIO.putStrLn ("Seeded manager count: " <> tshow actualManagerCount)
    TextIO.putStrLn ("Target roster fill: " <> tshow scenario.rosterFillPercent <> "%")
    TextIO.putStrLn ("Current-week roster fill: " <> tshow filledRosterSlotCount <> "/" <> tshow totalRosterSlotCount)
    TextIO.putStrLn ("Leave requests: approved=" <> tshow approvedLeaveCount <> ", pending=" <> tshow pendingLeaveCount <> ", denied=" <> tshow deniedLeaveCount)
    TextIO.putStrLn ("Sandbox timesheets: approved=" <> tshow approvedTimesheetCount <> ", pending=" <> tshow pendingTimesheetCount)
    TextIO.putStrLn ("Seeded payroll venue: " <> get #name payrollVenue)
    TextIO.putStrLn ("Payroll admin login: " <> get #email payrollAdmin)
    TextIO.putStrLn ("Approved payroll entries: " <> tshow (length approvedEntries))
    TextIO.putStrLn ("Pending payroll entries: " <> tshow (length pendingEntries))
    TextIO.putStrLn "Manual testing surface now includes multi-group roster data, support switching, invitation/bootstrap state, leave/timesheet activity, and payroll export data."

data SeedDevOptions = SeedDevOptions
    { selectedScenario  :: !SeedScenarioName
    , scenarioOverrides :: !SeedScenarioOverrides
    }

defaultSeedDevOptions :: SeedDevOptions
defaultSeedDevOptions =
    SeedDevOptions
        { selectedScenario = scenarioName defaultScenario
        , scenarioOverrides = defaultScenarioOverrides
        }

resolveScenario :: SeedDevOptions -> SeedScenario
resolveScenario SeedDevOptions { selectedScenario, scenarioOverrides } =
    applyOverrides scenarioOverrides (scenarioByName selectedScenario)

parseSeedDevOptions :: IO SeedDevOptions
parseSeedDevOptions = do
    args <- Environment.getArgs
    when ("--help" `elem` args || "-h" `elem` args) do
        printSeedDevUsage
        exitSuccess
    parseArgs defaultSeedDevOptions args

parseArgs :: SeedDevOptions -> [String] -> IO SeedDevOptions
parseArgs options [] = pure options
parseArgs options (arg:remainingArgs) = do
    nextOptions <- parseArg options arg
    parseArgs nextOptions remainingArgs

parseArg :: SeedDevOptions -> String -> IO SeedDevOptions
parseArg options arg
    | "--scenario=" `List.isPrefixOf` arg =
        case List.stripPrefix "--scenario=" arg >>= (parseScenarioName . cs) of
            Just name -> pure options { selectedScenario = name }
            Nothing   -> error ("Unknown scenario: " <> cs arg)
    | "--seed=" `List.isPrefixOf` arg =
        pure options { scenarioOverrides = options.scenarioOverrides { overrideScenarioSeed = Just (readIntFlag "--seed=" arg) } }
    | "--staff-count=" `List.isPrefixOf` arg =
        pure options { scenarioOverrides = options.scenarioOverrides { overrideStaffCount = Just (readIntFlag "--staff-count=" arg) } }
    | "--users=" `List.isPrefixOf` arg =
        pure options { scenarioOverrides = options.scenarioOverrides { overrideStaffCount = Just (readIntFlag "--users=" arg) } }
    | "--manager-count=" `List.isPrefixOf` arg =
        pure options { scenarioOverrides = options.scenarioOverrides { overrideManagerCount = Just (readIntFlag "--manager-count=" arg) } }
    | "--roster-fill=" `List.isPrefixOf` arg =
        pure options { scenarioOverrides = options.scenarioOverrides { overrideRosterFill = Just (readIntFlag "--roster-fill=" arg) } }
    | otherwise = error ("Unsupported seed-dev option: " <> cs arg)

readIntFlag :: String -> String -> Int
readIntFlag prefix arg =
    case TextRead.readMaybe (drop (length prefix) arg) of
        Just value -> value
        _          -> error ("Expected integer for flag: " <> cs arg)

printSeedDevUsage :: IO ()
printSeedDevUsage = do
    TextIO.putStrLn "Usage: seed-dev [app|app_test] [--force] [seed-options...]"
    TextIO.putStrLn ("Available scenarios: " <> Text.intercalate ", " scenarioLabels)
    TextIO.putStrLn "Seed options:"
    TextIO.putStrLn "  --scenario=<name>"
    TextIO.putStrLn "  --seed=<int>"
    TextIO.putStrLn "  --staff-count=<int>"
    TextIO.putStrLn "  --users=<int>"
    TextIO.putStrLn "  --manager-count=<int>"
    TextIO.putStrLn "  --roster-fill=<0-100>"

currentFixtureWeekStart :: Day -> Day
currentFixtureWeekStart today =
    addDays (toInteger (currentWeekOffsetForDay today * 7)) defaultWeekEpoch

currentWeekOffsetForDay :: Day -> Int
currentWeekOffsetForDay today = fromInteger (diffDays today defaultWeekEpoch `div` 7)
