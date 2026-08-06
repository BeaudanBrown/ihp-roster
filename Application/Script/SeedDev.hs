module Application.Script.SeedDev where

import Application.Fixture.DevFixtures (DevSeedFixture (..),
                                        seedDevelopmentFixtureAfterResetWithScenarioForWeekAndLeaveMonth,
                                        seedDevelopmentFixtureWithScenarioForWeekAndLeaveMonth)
import Application.Fixture.Reset (resetDatabase)
import Application.Fixture.Seed.Calendar (currentWeekOffsetForDay,
                                          weekStartForOffset)
import Application.Fixture.Seed.Scenario
import Application.Helper.ShiftTypeColours (ShiftTypeColourKeyEnum,
                                            blankShiftTypeColourKey,
                                            shiftTypeColourKeyCssValue)
import Application.Helper.TimesheetPayLedger (backfillApprovedTimesheetPayCalculations)
import Application.Script.Prelude
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day)
import Data.Time.Clock (getCurrentTime, utctDay)
import qualified System.Environment as Environment
import System.Exit (exitSuccess)
import qualified Text.Read as TextRead

seededSupportAdminPassword :: Text
seededSupportAdminPassword = "admin"

seededSandboxAdminPassword :: Text
seededSandboxAdminPassword = "venue2"

data SeedResetMode
    = ResetBeforeSeed
    | DatabaseAlreadyReset

resetOnly :: Script
resetOnly = resetDatabase

run :: Script
run = runWithResetMode ResetBeforeSeed

runAfterReset :: Script
runAfterReset = runWithResetMode DatabaseAlreadyReset

runWithResetMode :: SeedResetMode -> Script
runWithResetMode resetMode = do
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
        } <- case resetMode of
            ResetBeforeSeed -> seedDevelopmentFixtureWithScenarioForWeekAndLeaveMonth scenario fixtureWeekStart (utctDay now)
            DatabaseAlreadyReset -> seedDevelopmentFixtureAfterResetWithScenarioForWeekAndLeaveMonth scenario fixtureWeekStart (utctDay now)

    backfillResult <- backfillApprovedTimesheetPayCalculations
    case backfillResult of
        Left failures -> fail (Text.unpack ("Dev seed pay-ledger backfill failed: " <> tshow failures))
        Right _ -> pure ()

    actualStaffCount <-
        query @Staff
            |> filterWhere (#venueId, unpackId (get #id sandboxVenue))
            |> fetchCount
    actualManagerCount <-
        query @VenueMembership
            |> filterWhere (#venueId, unpackId (get #id sandboxVenue))
            |> filterWhere (#venueRole, Manager)
            |> fetchCount
    leaveRequests <-
        query @LeaveRequest
            |> filterWhere (#venueId, unpackId (get #id sandboxVenue))
            |> fetch
    shiftTypes <-
        query @ShiftType
            |> filterWhere (#venueId, unpackId (get #id sandboxVenue))
            |> filterWhere (#isActive, True)
            |> orderByAsc #sortOrder
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
    let approvedLeaveCount = length (filter (\leaveRequest -> get #status leaveRequest == LeaveRequestStatusEnumApproved) leaveRequests)
    let pendingLeaveCount = length (filter (\leaveRequest -> get #status leaveRequest == LeaveRequestStatusEnumPending) leaveRequests)
    let deniedLeaveCount = length (filter (\leaveRequest -> get #status leaveRequest == LeaveRequestStatusEnumDenied) leaveRequests)
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
    TextIO.putStrLn ("Sandbox admin password: " <> seededSandboxAdminPassword)
    TextIO.putStrLn ("Support admin password: " <> seededSupportAdminPassword)
    TextIO.putStrLn ("Pending invitation email: " <> get #email sandboxInvitation)
    TextIO.putStrLn ("Current week start: " <> tshow fixtureWeekStart)
    TextIO.putStrLn ("Roster groups: " <> get #name frontOfHouseGroup <> ", " <> get #name backOfHouseGroup)
    TextIO.putStrLn ("Shift types: " <> Text.intercalate ", " (map shiftTypeSummary shiftTypes))
    TextIO.putStrLn ("Seeded staff count: " <> tshow actualStaffCount)
    TextIO.putStrLn ("Seeded manager count: " <> tshow actualManagerCount)
    TextIO.putStrLn ("Target roster fill: " <> tshow scenario.rosterFillPercent <> "%")
    TextIO.putStrLn ("Current-week roster fill: " <> tshow filledRosterSlotCount <> "/" <> tshow totalRosterSlotCount)
    TextIO.putStrLn ("Leave requests: approved=" <> tshow approvedLeaveCount <> ", pending=" <> tshow pendingLeaveCount <> ", denied=" <> tshow deniedLeaveCount)
    TextIO.putStrLn ("Sandbox timesheets: approved=" <> tshow approvedTimesheetCount <> ", pending=" <> tshow pendingTimesheetCount)
    TextIO.putStrLn "Manual testing surface now includes multi-group roster data, support switching, invitation/bootstrap state, leave, and timesheet activity."

shiftTypeSummary :: ShiftType -> Text
shiftTypeSummary shiftType =
    shiftType.name <> " (" <> displayShiftTypeColourKey shiftType.colourKey <> ")"

displayShiftTypeColourKey :: ShiftTypeColourKeyEnum -> Text
displayShiftTypeColourKey colourKey
    | colourKey == blankShiftTypeColourKey = "no colour"
    | otherwise = shiftTypeColourKeyCssValue colourKey

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
currentFixtureWeekStart = weekStartForOffset . currentWeekOffsetForDay
