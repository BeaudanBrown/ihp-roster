module Application.Script.ProfileLiveInvalidation where

import qualified Application.Helper.FrontendContract.Surface.Admin.Live as AdminLive
import Application.Helper.FrontendContract.Surface.Admin.Resource (adminInvitesResource,
                                                                   xeroConnectionResource)
import qualified Application.Helper.FrontendContract.Surface.Billing.Live as BillingLive
import Application.Helper.FrontendContract.Surface.Billing.Resource (billingResource)
import qualified Application.Helper.FrontendContract.Surface.Roster.Live as RosterLive
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterWeekResource)
import qualified Application.Helper.FrontendContract.Surface.Support.Live as SupportLive
import Application.Helper.FrontendContract.Surface.Support.Resource (supportAwardRatesResource)
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Live as TimesheetsLive
import Application.Helper.FrontendContract.Surface.Timesheets.Resource (timesheetWeekResource)
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.SurfaceResource
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LByteString
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.UUID (UUID, fromWords)
import GHC.Clock (getMonotonicTimeNSec)
import IHP.Prelude
import System.Directory (createDirectoryIfMissing)
import qualified System.Environment as Environment
import System.Exit (exitSuccess)
import System.FilePath ((</>))
import qualified Text.Read as TextRead
import Web.SurfaceInvalidation (SurfaceInvalidationTarget (..),
                                expandSurfaceResourcesWithoutContext,
                                performSurfaceInvalidationTargetWithoutContext,
                                planSurfaceInvalidationsWithoutContext)

run :: IO ()
run = do
    options <- parseOptions
    createDirectoryIfMissing True options.outputDir
    results <- concat <$> mapM (runScenario options) options.scenarios
    writeSummary options results
    printSummary results

data ProfileLiveInvalidationOptions = ProfileLiveInvalidationOptions
    { outputDir   :: !FilePath
    , scopeCounts :: ![Int]
    , iterations  :: !Int
    , scenarios   :: ![LiveInvalidationBenchmarkScenario]
    }
    deriving (Eq, Show)

defaultOptions :: ProfileLiveInvalidationOptions
defaultOptions =
    ProfileLiveInvalidationOptions
        { outputDir = "output/profile-live-invalidation/latest"
        , scopeCounts = [0, 10, 100, 500, 1000]
        , iterations = 50
        , scenarios = allScenarios
        }

data LiveInvalidationBenchmarkScenario
    = BillingDirectScenario
    | TimesheetWeekScenario
    | XeroConnectionScenario
    | RosterWeekFanoutScenario
    | MixedContextFreeScenario
    deriving (Eq, Ord, Show)

allScenarios :: [LiveInvalidationBenchmarkScenario]
allScenarios =
    [ BillingDirectScenario
    , TimesheetWeekScenario
    , XeroConnectionScenario
    , RosterWeekFanoutScenario
    , MixedContextFreeScenario
    ]

data BenchmarkPlan = BenchmarkPlan
    { planResources           :: !(Set.Set SurfaceResourceValue)
    , planActiveSubscriptions :: ![SurfaceSubscription]
    , planActiveRosterScopes  :: ![(UUID, UUID, Int)]
    }

scenarioName :: LiveInvalidationBenchmarkScenario -> Text
scenarioName = \case
    BillingDirectScenario -> "billing-direct"
    TimesheetWeekScenario -> "timesheet-week"
    XeroConnectionScenario -> "xero-connection"
    RosterWeekFanoutScenario -> "roster-week-fanout"
    MixedContextFreeScenario -> "mixed-context-free"

scenarioDescription :: LiveInvalidationBenchmarkScenario -> Text
scenarioDescription = \case
    BillingDirectScenario -> "One billing resource planned against many billing scopes."
    TimesheetWeekScenario -> "One timesheet week resource planned against many timesheet week scopes."
    XeroConnectionScenario -> "One Xero connection resource planned against many Xero admin scopes."
    RosterWeekFanoutScenario -> "Concrete roster week resources planned across active roster week scopes."
    MixedContextFreeScenario -> "Mixed support, billing, invites, timesheet, and Xero resources/scopes."

data BenchmarkResult = BenchmarkResult
    { resultScenario              :: !LiveInvalidationBenchmarkScenario
    , resultScopeCount            :: !Int
    , resultIterations            :: !Int
    , resultTouchedResourceCount  :: !Int
    , resultActiveScopeCount      :: !Int
    , resultExpandedResourceCount :: !Int
    , resultTargetCount           :: !Int
    , resultTargetFragmentCount   :: !Int
    , resultBroadcastCount        :: !Int
    , resultSubscriberCount       :: !Int
    , resultExpandMs              :: !Double
    , resultPlanMs                :: !Double
    , resultBroadcastMs           :: !Double
    , resultTotalMs               :: !Double
    }
    deriving (Eq, Show)

runScenario :: ProfileLiveInvalidationOptions -> LiveInvalidationBenchmarkScenario -> IO [BenchmarkResult]
runScenario options scenario =
    forM options.scopeCounts \requestedScopeCount -> do
        samples <- mapM (const (runOne scenario requestedScopeCount)) [1 .. options.iterations]
        pure (combineSamples scenario requestedScopeCount options.iterations samples)

runOne :: LiveInvalidationBenchmarkScenario -> Int -> IO BenchmarkResult
runOne scenario requestedScopeCount = do
    let benchmarkPlan = buildBenchmarkPlan scenario requestedScopeCount
    startedAtNs <- getMonotonicTimeNSec
    (expandedResources, expandMs) <- measureDuration do
        pure (expandSurfaceResourcesWithoutContext benchmarkPlan.planActiveRosterScopes benchmarkPlan.planResources)
    let activeSubscriptions = benchmarkPlan.planActiveSubscriptions
    (targets, planMs) <- measureDuration do
        pure (planSurfaceInvalidationsWithoutContext expandedResources activeSubscriptions)
    (broadcastResults, broadcastMs) <- measureDuration do
        mapM performSurfaceInvalidationTargetWithoutContext targets
    completedAtNs <- getMonotonicTimeNSec
    pure
        BenchmarkResult
            { resultScenario = scenario
            , resultScopeCount = requestedScopeCount
            , resultIterations = 1
            , resultTouchedResourceCount = Set.size benchmarkPlan.planResources
            , resultActiveScopeCount = length benchmarkPlan.planActiveSubscriptions
            , resultExpandedResourceCount = Set.size expandedResources
            , resultTargetCount = length targets
            , resultTargetFragmentCount = sum (map (length . targetFragments) targets)
            , resultBroadcastCount = length broadcastResults
            , resultSubscriberCount = sum (map broadcastSubscriberCount broadcastResults)
            , resultExpandMs = expandMs
            , resultPlanMs = planMs
            , resultBroadcastMs = broadcastMs
            , resultTotalMs = durationBetweenMs startedAtNs completedAtNs
            }

combineSamples :: LiveInvalidationBenchmarkScenario -> Int -> Int -> [BenchmarkResult] -> BenchmarkResult
combineSamples scenario requestedScopeCount iterations samples =
    BenchmarkResult
        { resultScenario = scenario
        , resultScopeCount = requestedScopeCount
        , resultIterations = iterations
        , resultTouchedResourceCount = stable resultTouchedResourceCount
        , resultActiveScopeCount = stable resultActiveScopeCount
        , resultExpandedResourceCount = stable resultExpandedResourceCount
        , resultTargetCount = stable resultTargetCount
        , resultTargetFragmentCount = stable resultTargetFragmentCount
        , resultBroadcastCount = stable resultBroadcastCount
        , resultSubscriberCount = stable resultSubscriberCount
        , resultExpandMs = average resultExpandMs
        , resultPlanMs = average resultPlanMs
        , resultBroadcastMs = average resultBroadcastMs
        , resultTotalMs = average resultTotalMs
        }
    where
        stable accessor = maybe 0 accessor (listToMaybe samples)
        average accessor =
            case samples of
                [] -> 0
                _  -> sum (map accessor samples) / fromIntegral (length samples)

buildBenchmarkPlan :: LiveInvalidationBenchmarkScenario -> Int -> BenchmarkPlan
buildBenchmarkPlan scenario requestedScopeCount =
    case scenario of
        BillingDirectScenario ->
            BenchmarkPlan
                { planResources = Set.singleton (billingResource targetVenueId)
                , planActiveSubscriptions =
                    [ benchmarkSubscription
                        (BillingLive.billingLiveScope (venueIdFor index))
                        [BillingLive.billingStatusLiveFragment]
                    | index <- [0 .. requestedScopeCount - 1]
                    ]
                , planActiveRosterScopes = []
                }
        TimesheetWeekScenario ->
            BenchmarkPlan
                { planResources = Set.singleton (timesheetWeekResource targetVenueId targetWeekOffset)
                , planActiveSubscriptions =
                    [ benchmarkSubscription
                        (TimesheetsLive.timesheetWeekLiveScope (venueIdFor index) (index `mod` 52))
                        [TimesheetsLive.timesheetToolbarLiveFragment]
                    | index <- [0 .. requestedScopeCount - 1]
                    ]
                , planActiveRosterScopes = []
                }
        XeroConnectionScenario ->
            BenchmarkPlan
                { planResources = Set.singleton (xeroConnectionResource targetVenueId)
                , planActiveSubscriptions =
                    [ benchmarkSubscription
                        (AdminLive.adminXeroLiveScope (venueIdFor index))
                        [AdminLive.adminXeroShellLiveFragment]
                    | index <- [0 .. requestedScopeCount - 1]
                    ]
                , planActiveRosterScopes = []
                }
        RosterWeekFanoutScenario ->
            BenchmarkPlan
                { planResources = Set.fromList [rosterWeekResource (rosterGroupIdFor index) targetWeekOffset | index <- [0 .. requestedScopeCount - 1]]
                , planActiveSubscriptions =
                    [ benchmarkSubscription
                        (RosterLive.rosterWeekLiveScope targetVenueId (rosterGroupIdFor index) targetWeekOffset)
                        [RosterLive.rosterContentLiveFragment]
                    | index <- [0 .. requestedScopeCount - 1]
                    ]
                , planActiveRosterScopes = [(targetVenueId, rosterGroupIdFor index, targetWeekOffset) | index <- [0 .. requestedScopeCount - 1]]
                }
        MixedContextFreeScenario ->
            BenchmarkPlan
                { planResources =
                    Set.fromList
                        [ supportAwardRatesResource
                        , billingResource targetVenueId
                        , adminInvitesResource targetVenueId
                        , timesheetWeekResource targetVenueId targetWeekOffset
                        , xeroConnectionResource targetVenueId
                        ]
                , planActiveSubscriptions = take requestedScopeCount (cycle mixedSubscriptions)
                , planActiveRosterScopes = []
                }
    where
        targetVenueId = venueIdFor 0
        targetWeekOffset = 0
        mixedSubscriptions =
            [ benchmarkSubscription SupportLive.supportPlatformLiveScope [SupportLive.supportAwardRatesSectionLiveFragment]
            , benchmarkSubscription (BillingLive.billingLiveScope targetVenueId) [BillingLive.billingStatusLiveFragment]
            , benchmarkSubscription (AdminLive.adminInvitesLiveScope targetVenueId) [AdminLive.adminInvitesLiveFragment]
            , benchmarkSubscription (TimesheetsLive.timesheetWeekLiveScope targetVenueId targetWeekOffset) [TimesheetsLive.timesheetToolbarLiveFragment]
            , benchmarkSubscription (AdminLive.adminXeroLiveScope targetVenueId) [AdminLive.adminXeroShellLiveFragment]
            ]

benchmarkSubscription :: SurfaceScope -> [SurfaceFragmentKey] -> SurfaceSubscription
benchmarkSubscription scope fragmentKeys =
    SurfaceSubscription
        { subscriptionScope = scope
        , subscriptionScopeKey = surfaceScopeKey scope
        , subscriptionFragmentKeys = fragmentKeys
        }

venueIdFor :: Int -> UUID
venueIdFor index =
    fromWords 0x10000000 0 0 (fromIntegral (index + 1))

rosterGroupIdFor :: Int -> UUID
rosterGroupIdFor index =
    fromWords 0x20000000 0 0 (fromIntegral (index + 1))

measureDuration :: IO a -> IO (a, Double)
measureDuration action = do
    startedAtNs <- getMonotonicTimeNSec
    result <- action
    completedAtNs <- getMonotonicTimeNSec
    pure (result, durationBetweenMs startedAtNs completedAtNs)

durationBetweenMs :: Word64 -> Word64 -> Double
durationBetweenMs startedAtNs completedAtNs =
    fromIntegral (completedAtNs - startedAtNs) / 1000000

parseOptions :: IO ProfileLiveInvalidationOptions
parseOptions = do
    args <- map cs <$> Environment.getArgs
    go defaultOptions args
    where
        go options [] = pure options
        go options (arg : rest)
            | Just value <- Text.stripPrefix "--output-dir=" arg =
                go options { outputDir = cs value } rest
            | Just value <- Text.stripPrefix "--scopes=" arg =
                go options { scopeCounts = parseIntList "--scopes" value } rest
            | Just value <- Text.stripPrefix "--iterations=" arg =
                go options { iterations = parsePositiveInt "--iterations" value } rest
            | Just value <- Text.stripPrefix "--scenario=" arg =
                go options { scenarios = parseScenarioList value } rest
            | arg `elem` ["--help", "-h"] = do
                TextIO.putStrLn usageText
                exitSuccess
            | otherwise =
                error ("Unknown profile-live-invalidation argument: " <> cs arg)

usageText :: Text
usageText =
    Text.unlines
        [ "Usage: profile-live-invalidation [options]"
        , ""
        , "Options:"
        , "  --output-dir=path                 Artifact directory"
        , "  --scopes=0,10,100,500,1000       Active scope counts"
        , "  --iterations=N                   Samples per scenario/count"
        , "  --scenario=name[,name...]        billing-direct|timesheet-week|xero-connection|roster-week-fanout|mixed-context-free"
        ]

parseIntList :: Text -> Text -> [Int]
parseIntList optionName value =
    case map (parseNonNegativeInt optionName) (Text.splitOn "," value) of
        []     -> error (cs optionName <> " requires at least one value")
        values -> values

parseScenarioList :: Text -> [LiveInvalidationBenchmarkScenario]
parseScenarioList value =
    case map parseScenario (Text.splitOn "," value) of
        []     -> error "--scenario requires at least one value"
        values -> values

parseScenario :: Text -> LiveInvalidationBenchmarkScenario
parseScenario value =
    case value of
        "billing-direct" -> BillingDirectScenario
        "timesheet-week" -> TimesheetWeekScenario
        "xero-connection" -> XeroConnectionScenario
        "roster-week-fanout" -> RosterWeekFanoutScenario
        "mixed-context-free" -> MixedContextFreeScenario
        _ -> error ("Unsupported live invalidation profile scenario: " <> cs value)

parsePositiveInt :: Text -> Text -> Int
parsePositiveInt optionName value =
    let parsed = parseNonNegativeInt optionName value
     in if parsed > 0
            then parsed
            else error (cs optionName <> " must be greater than zero")

parseNonNegativeInt :: Text -> Text -> Int
parseNonNegativeInt optionName value =
    case TextRead.readMaybe (cs value) of
        Just parsed | parsed >= 0 -> parsed
        _ -> error (cs optionName <> " expects a non-negative integer: " <> cs value)

writeSummary :: ProfileLiveInvalidationOptions -> [BenchmarkResult] -> IO ()
writeSummary options results = do
    LByteString.writeFile (options.outputDir </> "profile-live-invalidation.json") (Aeson.encode (jsonSummary options results))
    TextIO.writeFile (options.outputDir </> "profile-live-invalidation.md") (markdownSummary options results)

jsonSummary :: ProfileLiveInvalidationOptions -> [BenchmarkResult] -> Aeson.Value
jsonSummary options results =
    Aeson.object
        [ "options" Aeson..= Aeson.object
            [ "scopeCounts" Aeson..= options.scopeCounts
            , "iterations" Aeson..= options.iterations
            , "scenarios" Aeson..= map scenarioName options.scenarios
            ]
        , "results" Aeson..= map resultJson results
        ]

resultJson :: BenchmarkResult -> Aeson.Value
resultJson result =
    Aeson.object
        [ "scenario" Aeson..= scenarioName result.resultScenario
        , "description" Aeson..= scenarioDescription result.resultScenario
        , "scopeCount" Aeson..= result.resultScopeCount
        , "iterations" Aeson..= result.resultIterations
        , "touchedResourceCount" Aeson..= result.resultTouchedResourceCount
        , "activeScopeCount" Aeson..= result.resultActiveScopeCount
        , "expandedResourceCount" Aeson..= result.resultExpandedResourceCount
        , "targetCount" Aeson..= result.resultTargetCount
        , "targetFragmentCount" Aeson..= result.resultTargetFragmentCount
        , "broadcastCount" Aeson..= result.resultBroadcastCount
        , "subscriberCount" Aeson..= result.resultSubscriberCount
        , "avgExpandMs" Aeson..= result.resultExpandMs
        , "avgPlanMs" Aeson..= result.resultPlanMs
        , "avgBroadcastMs" Aeson..= result.resultBroadcastMs
        , "avgTotalMs" Aeson..= result.resultTotalMs
        ]

markdownSummary :: ProfileLiveInvalidationOptions -> [BenchmarkResult] -> Text
markdownSummary options results =
    Text.unlines $
        [ "# Live Invalidation Profile"
        , ""
        , "Iterations per row: `" <> tshow options.iterations <> "`"
        , "Scope counts: `" <> Text.intercalate ", " (map tshow options.scopeCounts) <> "`"
        , ""
        , "| Scenario | Scopes | Touched | Expanded | Targets | Fragments | Broadcasts | Subscribers | Expand ms | Plan ms | Broadcast ms | Total ms |"
        , "| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |"
        ]
            <> map resultRow results

resultRow :: BenchmarkResult -> Text
resultRow result =
    Text.intercalate
        " | "
        [ "| `" <> scenarioName result.resultScenario <> "`"
        , tshow result.resultScopeCount
        , tshow result.resultTouchedResourceCount
        , tshow result.resultExpandedResourceCount
        , tshow result.resultTargetCount
        , tshow result.resultTargetFragmentCount
        , tshow result.resultBroadcastCount
        , tshow result.resultSubscriberCount
        , renderDuration result.resultExpandMs
        , renderDuration result.resultPlanMs
        , renderDuration result.resultBroadcastMs
        , renderDuration result.resultTotalMs <> " |"
        ]

printSummary :: [BenchmarkResult] -> IO ()
printSummary results = do
    TextIO.putStrLn "Live invalidation profile completed."
    forM_ results \result ->
        TextIO.putStrLn $
            scenarioName result.resultScenario
                <> " scopes=" <> tshow result.resultScopeCount
                <> " total_ms=" <> renderDuration result.resultTotalMs
                <> " plan_ms=" <> renderDuration result.resultPlanMs
                <> " targets=" <> tshow result.resultTargetCount
                <> " fragments=" <> tshow result.resultTargetFragmentCount

renderDuration :: Double -> Text
renderDuration durationMs =
    tshow (fromIntegral (round (durationMs * 1000)) / 1000 :: Double)
