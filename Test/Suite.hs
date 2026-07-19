module Test.Suite
    ( ShardSelection (..)
    , SuiteKind (..)
    , TestLane (..)
    , TestSuite (..)
    , renderShardSelection
    , shardSelectionFromEnv
    )
where

import Data.List (minimumBy, sortOn)
import Data.Ord (Down (..), comparing)
import qualified Data.Text as Text
import IHP.Prelude
import System.Environment (lookupEnv)
import Test.Hspec (Spec)
import Text.Read (readMaybe)

import qualified Test.AsyncQueueSpec
import qualified Test.BillingPersistenceSpec
import qualified Test.BillingReadOnlySpec
import qualified Test.BillingWebhookSpec
import qualified Test.ConflictSpec
import qualified Test.Controller.Admin.AccessSpec
import qualified Test.Controller.Admin.ConfigSpec
import qualified Test.Controller.Admin.XeroSpec
import qualified Test.Controller.BillingSpec
import qualified Test.Controller.E2ETestSpec
import qualified Test.Controller.ExportsSpec
import qualified Test.Controller.FeedbackSpec
import qualified Test.Controller.FixedExportGoldenSpec
import qualified Test.Controller.HelpSpec
import qualified Test.Controller.LeaveRequestsSpec
import qualified Test.Controller.PasskeysSpec
import qualified Test.Controller.ProfilesSpec
import qualified Test.Controller.RosterWeeks.BaselineSpec
import qualified Test.Controller.RosterWeeks.DirectReadModelSpec
import qualified Test.Controller.RosterWeeks.FragmentsSpec
import qualified Test.Controller.RosterWeeks.NavigationSpec
import qualified Test.Controller.RosterWeeks.WorkflowSpec
import qualified Test.Controller.SessionsSpec
import qualified Test.Controller.StaffDocumentsSpec
import qualified Test.Controller.StaffSpec
import qualified Test.Controller.StaticSpec
import qualified Test.Controller.SupportSpec
import qualified Test.Controller.TimesheetsSpec
import qualified Test.Controller.UsersSpec
import qualified Test.Controller.VenueAccessSpec
import qualified Test.DatabaseProtectionSpec
import qualified Test.DevSeedSpec
import qualified Test.FrontendContractSpec
import qualified Test.FrontendContractsSpec
import qualified Test.FrontendSurfaceAdapterGeneratorSpec
import qualified Test.FrontendSurfaceDslSpec
import qualified Test.FrontendSurfaceNamingSpec
import qualified Test.FrontendSurfaceRequestAdapterSpec
import qualified Test.FwcMapdSyncSpec
import qualified Test.HorizontalScrollSpec
import qualified Test.LiveUpdateSpec
import qualified Test.MailSpec
import qualified Test.MutationBoundarySpec
import qualified Test.OrderedRangeSpec
import qualified Test.OverlaySpec
import qualified Test.PageHelpSpec
import qualified Test.PaySpec
import qualified Test.ProfilingSpec
import qualified Test.PublicHolidaySyncSpec
import qualified Test.PwaInstallSpec
import qualified Test.RosterGridSpec
import qualified Test.SchemaSpec
import qualified Test.StaffDocumentsRsaSpec
import qualified Test.StripeBillingSpec
import qualified Test.StripeContractSpec
import qualified Test.SurfaceDependencySpec
import qualified Test.SurfaceGuardSpec
import qualified Test.SurfaceInvalidationSpec
import qualified Test.SurfaceResourceSpec
import qualified Test.TimePickerSpec
import qualified Test.ToggleButtonSpec
import qualified Test.VenueInvitationSpec
import qualified Test.VenueOnboardingInvitationSpec
import qualified Test.XeroCandidateFilterSpec
import qualified Test.XeroContractSpec
import qualified Test.XeroImportedPayItemsSpec
import qualified Test.XeroKeepaliveSpec
import qualified Test.XeroTimesheetPreviewSpec
import qualified Test.XeroTimesheetReadinessSpec
import qualified Test.XeroTimesheetSubmissionSpec

data SuiteKind = PureSuite | DatabaseSuite
    deriving (Eq, Show)

data TestLane = AllTests | PureTests | DatabaseTests
    deriving (Eq, Show)

data TestSuite = TestSuite
    { suiteLabel  :: String
    , suiteWeight :: Int
    , suiteKind   :: SuiteKind
    , suiteSpec   :: Spec
    }

data ShardSelection = ShardSelection
    { shardIndex :: Int
    , shardTotal :: Int
    , testLane   :: TestLane
    , suites     :: [TestSuite]
    }

shardSelectionFromEnv :: IO ShardSelection
shardSelectionFromEnv = do
    total <- readShardEnv "TEST_SHARD_TOTAL" 1
    index <- readShardEnv "TEST_SHARD_INDEX" 1
    lane <- readTestLane

    when (index < 1 || index > total) do
        error $
            "Invalid test shard selection: TEST_SHARD_INDEX="
                <> show index
                <> ", TEST_SHARD_TOTAL="
                <> show total

    pure
        ShardSelection
            { shardIndex = index
            , shardTotal = total
            , testLane = lane
            , suites = selectShardSuites lane total index
            }

readTestLane :: IO TestLane
readTestLane = do
    value <- lookupEnv "TEST_LANE"
    case value of
        Nothing -> pure AllTests
        Just "" -> pure AllTests
        Just "all" -> pure AllTests
        Just "pure" -> pure PureTests
        Just "db" -> pure DatabaseTests
        Just raw -> error ("TEST_LANE must be one of all, pure, or db; got: " <> cs raw)

renderShardSelection :: ShardSelection -> String
renderShardSelection selection =
    let
        selectedLabels = map (cs . suiteLabel) selection.suites
        summaryTail =
            if null selectedLabels
                then " (no suites assigned)"
                else " weight=" <> tshow (sum (map suiteWeight selection.suites)) <> " [" <> Text.intercalate ", " selectedLabels <> "]"
     in
        cs $
            "Hspec "
                <> renderTestLane selection.testLane
                <> " shard "
                <> tshow selection.shardIndex
                <> "/"
                <> tshow selection.shardTotal
                <> summaryTail

renderTestLane :: TestLane -> Text
renderTestLane = \case
    AllTests -> "all"
    PureTests -> "pure"
    DatabaseTests -> "db"

readShardEnv :: String -> Int -> IO Int
readShardEnv varName fallback = do
    value <- lookupEnv varName
    case value of
        Nothing -> pure fallback
        Just "" -> pure fallback
        Just raw ->
            case readMaybe raw of
                Just parsed | parsed >= 1 -> pure parsed
                _ ->
                    let
                        message :: Text
                        message =
                            "Expected "
                                <> cs varName
                                <> " to be a positive integer, got: "
                                <> cs raw
                     in
                        error (cs message)

selectShardSuites :: TestLane -> Int -> Int -> [TestSuite]
selectShardSuites lane total index
    | total <= 1 = laneSuites lane
    | otherwise = balancedShardSuites (laneSuites lane) total !! (index - 1)

laneSuites :: TestLane -> [TestSuite]
laneSuites = \case
    AllTests -> allSuites
    PureTests -> filter ((== PureSuite) . suiteKind) allSuites
    DatabaseTests -> filter ((== DatabaseSuite) . suiteKind) allSuites

balancedShardSuites :: [TestSuite] -> Int -> [[TestSuite]]
balancedShardSuites selectedSuites total =
    selectedSuites
        |> sortOn (Down . suiteWeight)
        |> foldl' assignToLightest initialBuckets
        |> sortOn bucketIndex
        |> map (reverse . bucketSuites)
  where
    initialBuckets =
        [ ShardBucket bucketIndex 0 []
        | bucketIndex <- [0 .. total - 1]
        ]

    assignToLightest buckets suite =
        let
            target = minimumBy (comparing bucketWeight <> comparing bucketIndex) buckets
         in
            buckets
                |> map
                    ( \bucket ->
                        if bucketIndex bucket == bucketIndex target
                            then bucket{bucketWeight = bucketWeight bucket + suiteWeight suite, bucketSuites = suite : bucketSuites bucket}
                            else bucket
                    )

data ShardBucket = ShardBucket
    { bucketIndex  :: Int
    , bucketWeight :: Int
    , bucketSuites :: [TestSuite]
    }

pureSuite :: String -> Int -> Spec -> TestSuite
pureSuite label weight = TestSuite label weight PureSuite

databaseSuite :: String -> Int -> Spec -> TestSuite
databaseSuite label weight = TestSuite label weight DatabaseSuite

allSuites :: [TestSuite]
allSuites =
    [ databaseSuite "StaticController" 10 Test.Controller.StaticSpec.tests
    , databaseSuite "AsyncQueue" 10 Test.AsyncQueueSpec.tests
    , databaseSuite "Billing" 10 Test.BillingPersistenceSpec.tests
    , databaseSuite "BillingReadOnly" 20 Test.BillingReadOnlySpec.tests
    , databaseSuite "BillingController" 15 Test.Controller.BillingSpec.tests
    , databaseSuite "BillingWebhook" 35 Test.BillingWebhookSpec.tests
    , databaseSuite "E2ETestController" 5 Test.Controller.E2ETestSpec.tests
    , pureSuite "StripeBilling" 10 Test.StripeBillingSpec.tests
    , pureSuite "StripeContract" 10 Test.StripeContractSpec.tests
    , databaseSuite "AdminController.Access" 20 Test.Controller.Admin.AccessSpec.tests
    , databaseSuite "AdminController.Xero" 180 Test.Controller.Admin.XeroSpec.tests
    , databaseSuite "AdminController.Config" 90 Test.Controller.Admin.ConfigSpec.tests
    , databaseSuite "ProfilesController" 35 Test.Controller.ProfilesSpec.tests
    , databaseSuite "PasskeysController" 25 Test.Controller.PasskeysSpec.tests
    , pureSuite "Schema" 10 Test.SchemaSpec.tests
    , databaseSuite "DatabaseProtection" 10 Test.DatabaseProtectionSpec.tests
    , databaseSuite "SessionsController" 25 Test.Controller.SessionsSpec.tests
    , databaseSuite "RosterWeeksController.Navigation" 15 Test.Controller.RosterWeeks.NavigationSpec.tests
    , databaseSuite "RosterWeeksController.Workflow" 50 Test.Controller.RosterWeeks.WorkflowSpec.tests
    , databaseSuite "RosterWeeksController.Fragments" 40 Test.Controller.RosterWeeks.FragmentsSpec.tests
    , databaseSuite "RosterWeeksController.Baseline" 5 Test.Controller.RosterWeeks.BaselineSpec.tests
    , databaseSuite "RosterWeeksController.DirectReadModel" 10 Test.Controller.RosterWeeks.DirectReadModelSpec.tests
    , databaseSuite "LeaveRequestsController" 20 Test.Controller.LeaveRequestsSpec.tests
    , databaseSuite "FeedbackController" 10 Test.Controller.FeedbackSpec.tests
    , databaseSuite "HelpController" 10 Test.Controller.HelpSpec.tests
    , databaseSuite "SupportController" 20 Test.Controller.SupportSpec.tests
    , pureSuite "RosterGrid" 10 Test.RosterGridSpec.tests
    , databaseSuite "UsersController" 10 Test.Controller.UsersSpec.tests
    , databaseSuite "ExportsController" 10 Test.Controller.ExportsSpec.tests
    , databaseSuite "TimesheetsController" 40 Test.Controller.TimesheetsSpec.tests
    , databaseSuite "Pay" 20 Test.PaySpec.tests
    , pureSuite "PageHelp" 5 Test.PageHelpSpec.tests
    , pureSuite "Profiling" 5 Test.ProfilingSpec.tests
    , databaseSuite "PublicHolidaySync" 15 Test.PublicHolidaySyncSpec.tests
    , databaseSuite "FwcMapdSync" 20 Test.FwcMapdSyncSpec.tests
    , databaseSuite "VenueAccess" 35 Test.Controller.VenueAccessSpec.tests
    , databaseSuite "FixedExportGolden" 30 Test.Controller.FixedExportGoldenSpec.tests
    , databaseSuite "StaffController" 35 Test.Controller.StaffSpec.tests
    , databaseSuite "StaffDocumentsController" 20 Test.Controller.StaffDocumentsSpec.tests
    , databaseSuite "StaffDocumentsRSA" 20 Test.StaffDocumentsRsaSpec.tests
    , databaseSuite "VenueInvitation" 10 Test.VenueInvitationSpec.tests
    , databaseSuite "VenueOnboardingInvitation" 5 Test.VenueOnboardingInvitationSpec.tests
    , databaseSuite "DevSeed" 180 Test.DevSeedSpec.tests
    , pureSuite "Conflict" 5 Test.ConflictSpec.tests
    , pureSuite "FrontendContract" 5 Test.FrontendContractSpec.tests
    , pureSuite "FrontendContracts" 15 Test.FrontendContractsSpec.tests
    , pureSuite "FrontendSurfaceAdapterGenerator" 5 Test.FrontendSurfaceAdapterGeneratorSpec.tests
    , pureSuite "FrontendSurfaceRequestAdapter" 5 Test.FrontendSurfaceRequestAdapterSpec.tests
    , pureSuite "FrontendSurfaceNaming" 5 Test.FrontendSurfaceNamingSpec.tests
    , pureSuite "FrontendSurfaceDSL" 15 Test.FrontendSurfaceDslSpec.tests
    , pureSuite "LiveUpdate" 20 Test.LiveUpdateSpec.tests
    , pureSuite "SurfaceResource" 5 Test.SurfaceResourceSpec.tests
    , pureSuite "SurfaceInvalidation" 5 Test.SurfaceInvalidationSpec.tests
    , pureSuite "SurfaceDependency" 10 Test.SurfaceDependencySpec.tests
    , pureSuite "SurfaceGuard" 5 Test.SurfaceGuardSpec.tests
    , databaseSuite "ToggleButton" 5 Test.ToggleButtonSpec.tests
    , pureSuite "HorizontalScroll" 5 Test.HorizontalScrollSpec.tests
    , pureSuite "PwaInstall" 5 Test.PwaInstallSpec.tests
    , databaseSuite "OrderedRange" 5 Test.OrderedRangeSpec.tests
    , databaseSuite "Overlay" 5 Test.OverlaySpec.tests
    , databaseSuite "TimePicker" 5 Test.TimePickerSpec.tests
    , databaseSuite "Mail" 10 Test.MailSpec.tests
    , pureSuite "MutationBoundary" 5 Test.MutationBoundarySpec.tests
    , databaseSuite "XeroCandidateFilter" 5 Test.XeroCandidateFilterSpec.tests
    , pureSuite "XeroContract" 20 Test.XeroContractSpec.tests
    , pureSuite "XeroImportedPayItems" 10 Test.XeroImportedPayItemsSpec.tests
    , databaseSuite "XeroKeepalive" 10 Test.XeroKeepaliveSpec.tests
    , databaseSuite "XeroTimesheetPreview" 50 Test.XeroTimesheetPreviewSpec.tests
    , databaseSuite "XeroTimesheetReadiness" 35 Test.XeroTimesheetReadinessSpec.tests
    , databaseSuite "XeroTimesheetSubmission" 35 Test.XeroTimesheetSubmissionSpec.tests
    ]
