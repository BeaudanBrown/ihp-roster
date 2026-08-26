module Application.Script.SeedDev where

import Application.Fixture.DevFixtures (DevSeedFixture (..),
                                        seedDevelopmentFixtureAfterResetWithScenarioForWeekAndLeaveMonth,
                                        seedDevelopmentFixtureWithScenarioForWeekAndLeaveMonth)
import Application.Fixture.Reset (resetDatabase)
import Application.Fixture.Seed.Scenario
import Application.Helper.ShiftTypeColours (ShiftTypeColourKeyEnum,
                                            blankShiftTypeColourKey,
                                            shiftTypeColourKeyCssValue)
import Application.Helper.TimesheetPayLedger (backfillApprovedTimesheetPayCalculations)
import Application.Helper.WeekBoundaries (defaultRosterWeekStartsOn,
                                          startOfWeekFor)
import Application.Operator.Error
import Application.Script.Prelude
import Control.Monad (foldM)
import qualified Data.List as List
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day, addDays)
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
        , currentWindowStart = currentWindowStart
        , scenario = scenario
        } <- case resetMode of
            ResetBeforeSeed -> seedDevelopmentFixtureWithScenarioForWeekAndLeaveMonth scenario fixtureWeekStart (utctDay now)
            DatabaseAlreadyReset -> seedDevelopmentFixtureAfterResetWithScenarioForWeekAndLeaveMonth scenario fixtureWeekStart (utctDay now)

    backfillResult <- backfillApprovedTimesheetPayCalculations
    case backfillResult of
        Left failures -> liftIO (exitWithScriptError (ScriptOperationFailed ("dev seed pay-ledger backfill failed: " <> tshow failures)))
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
    rosterDays <-
        query @RosterDay
            |> filterWhere (#venueId, unpackId (get #id sandboxVenue))
            |> filterWhereGreaterThanOrEqualTo (#operationalDate, currentWindowStart)
            |> filterWhereLessThan (#operationalDate, addDays 7 currentWindowStart)
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
    deriving (Eq, Show)

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
    requireScriptResult (parseSeedDevArgs args)

parseSeedDevArgs :: [String] -> Either ScriptError SeedDevOptions
parseSeedDevArgs = foldM parseSeedDevArg defaultSeedDevOptions

parseSeedDevArg :: SeedDevOptions -> String -> Either ScriptError SeedDevOptions
parseSeedDevArg options arg
    | "--scenario=" `List.isPrefixOf` arg =
        case List.stripPrefix "--scenario=" arg >>= (parseScenarioName . cs) of
            Just name -> Right options { selectedScenario = name }
            Nothing   -> Left (InvalidScriptArgument ("unknown seed scenario: " <> cs arg))
    | "--seed=" `List.isPrefixOf` arg = do
        value <- readIntFlag "--seed=" arg
        Right options { scenarioOverrides = options.scenarioOverrides { overrideScenarioSeed = Just value } }
    | "--staff-count=" `List.isPrefixOf` arg = do
        value <- readPositiveIntFlag "--staff-count=" arg
        Right options { scenarioOverrides = options.scenarioOverrides { overrideStaffCount = Just value } }
    | "--users=" `List.isPrefixOf` arg = do
        value <- readPositiveIntFlag "--users=" arg
        Right options { scenarioOverrides = options.scenarioOverrides { overrideStaffCount = Just value } }
    | "--manager-count=" `List.isPrefixOf` arg = do
        value <- readPositiveIntFlag "--manager-count=" arg
        Right options { scenarioOverrides = options.scenarioOverrides { overrideManagerCount = Just value } }
    | "--roster-fill=" `List.isPrefixOf` arg = do
        value <- readIntFlag "--roster-fill=" arg
        if value >= 0 && value <= 100
            then Right options { scenarioOverrides = options.scenarioOverrides { overrideRosterFill = Just value } }
            else Left (InvalidScriptArgument "--roster-fill must be between 0 and 100")
    | otherwise = Left (InvalidScriptArgument ("unsupported seed-dev option: " <> cs arg))

readPositiveIntFlag :: String -> String -> Either ScriptError Int
readPositiveIntFlag prefix arg = do
    value <- readIntFlag prefix arg
    if value > 0
        then Right value
        else Left (InvalidScriptArgument (cs prefix <> " value must be greater than zero"))

readIntFlag :: String -> String -> Either ScriptError Int
readIntFlag prefix arg =
    case TextRead.readMaybe (drop (length prefix) arg) of
        Just value -> Right value
        Nothing    -> Left (InvalidScriptArgument ("expected integer for flag: " <> cs arg))

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
currentFixtureWeekStart = startOfWeekFor defaultRosterWeekStartsOn
