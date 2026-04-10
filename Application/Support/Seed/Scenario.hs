module Application.Support.Seed.Scenario where

import qualified Data.Text as Text
import IHP.Prelude

data SeedScenarioName
    = RealisticDemo
    | BusyRoster
    | ConflictHeavy
    | PayrollHeavy
    deriving (Eq, Show)

data SeedScenario = SeedScenario
    { scenarioName         :: !SeedScenarioName
    , scenarioLabel        :: !Text
    , staffCount           :: !Int
    , managerCount         :: !Int
    , supportAdminCount    :: !Int
    , trialStaffCount      :: !Int
    , rosterFillPercent    :: !Int
    , leaveRequestCount    :: !Int
    , pendingLeaveCount    :: !Int
    , deniedLeaveCount     :: !Int
    , approvedTimesheets   :: !Int
    , pendingTimesheets    :: !Int
    , scenarioSeed         :: !Int
    }
    deriving (Eq, Show)

data SeedScenarioOverrides = SeedScenarioOverrides
    { overrideStaffCount      :: !(Maybe Int)
    , overrideManagerCount    :: !(Maybe Int)
    , overrideRosterFill      :: !(Maybe Int)
    , overrideScenarioSeed    :: !(Maybe Int)
    }
    deriving (Eq, Show)

defaultScenarioOverrides :: SeedScenarioOverrides
defaultScenarioOverrides =
    SeedScenarioOverrides
        { overrideStaffCount = Nothing
        , overrideManagerCount = Nothing
        , overrideRosterFill = Nothing
        , overrideScenarioSeed = Nothing
        }

parseScenarioName :: Text -> Maybe SeedScenarioName
parseScenarioName raw =
    case Text.toLower raw of
        "realistic-demo" -> Just RealisticDemo
        "busy-roster" -> Just BusyRoster
        "conflict-heavy" -> Just ConflictHeavy
        "payroll-heavy" -> Just PayrollHeavy
        _ -> Nothing

defaultScenario :: SeedScenario
defaultScenario = scenarioByName RealisticDemo

scenarioByName :: SeedScenarioName -> SeedScenario
scenarioByName = \case
    RealisticDemo ->
        SeedScenario
            { scenarioName = RealisticDemo
            , scenarioLabel = "realistic-demo"
            , staffCount = 16
            , managerCount = 2
            , supportAdminCount = 1
            , trialStaffCount = 1
            , rosterFillPercent = 78
            , leaveRequestCount = 4
            , pendingLeaveCount = 1
            , deniedLeaveCount = 1
            , approvedTimesheets = 27
            , pendingTimesheets = 12
            , scenarioSeed = 20260410
            }
    BusyRoster ->
        SeedScenario
            { scenarioName = BusyRoster
            , scenarioLabel = "busy-roster"
            , staffCount = 20
            , managerCount = 3
            , supportAdminCount = 1
            , trialStaffCount = 1
            , rosterFillPercent = 88
            , leaveRequestCount = 3
            , pendingLeaveCount = 1
            , deniedLeaveCount = 0
            , approvedTimesheets = 36
            , pendingTimesheets = 15
            , scenarioSeed = 20260412
            }
    ConflictHeavy ->
        SeedScenario
            { scenarioName = ConflictHeavy
            , scenarioLabel = "conflict-heavy"
            , staffCount = 14
            , managerCount = 2
            , supportAdminCount = 1
            , trialStaffCount = 1
            , rosterFillPercent = 62
            , leaveRequestCount = 6
            , pendingLeaveCount = 2
            , deniedLeaveCount = 1
            , approvedTimesheets = 21
            , pendingTimesheets = 15
            , scenarioSeed = 20260413
            }
    PayrollHeavy ->
        SeedScenario
            { scenarioName = PayrollHeavy
            , scenarioLabel = "payroll-heavy"
            , staffCount = 18
            , managerCount = 2
            , supportAdminCount = 1
            , trialStaffCount = 1
            , rosterFillPercent = 84
            , leaveRequestCount = 3
            , pendingLeaveCount = 1
            , deniedLeaveCount = 0
            , approvedTimesheets = 45
            , pendingTimesheets = 9
            , scenarioSeed = 20260411
            }

applyOverrides :: SeedScenarioOverrides -> SeedScenario -> SeedScenario
applyOverrides SeedScenarioOverrides { .. } scenario =
    scenario
        { staffCount = max 1 (fromMaybe scenario.staffCount overrideStaffCount)
        , managerCount = max 1 (fromMaybe scenario.managerCount overrideManagerCount)
        , rosterFillPercent = clampPercent (fromMaybe scenario.rosterFillPercent overrideRosterFill)
        , scenarioSeed = fromMaybe scenario.scenarioSeed overrideScenarioSeed
        }

clampPercent :: Int -> Int
clampPercent = max 0 . min 100

scenarioLabels :: [Text]
scenarioLabels =
    [ "realistic-demo"
    , "busy-roster"
    , "conflict-heavy"
    , "payroll-heavy"
    ]
