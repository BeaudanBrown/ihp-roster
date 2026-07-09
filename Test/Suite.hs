module Test.Suite
    ( ShardSelection (..)
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
import qualified Test.Controller.AdminSpec
import qualified Test.Controller.BillingSpec
import qualified Test.Controller.E2ETestSpec
import qualified Test.Controller.ExportsSpec
import qualified Test.Controller.FeedbackSpec
import qualified Test.Controller.LeaveRequestsSpec
import qualified Test.Controller.PasskeysSpec
import qualified Test.Controller.PayrollExportParitySpec
import qualified Test.Controller.ProfilesSpec
import qualified Test.Controller.RosterWeeksSpec
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
import qualified Test.FrontendSurfaceDslSpec
import qualified Test.FrontendSurfaceGhcSpec
import qualified Test.FrontendSurfaceNamingSpec
import qualified Test.FwcMapdSyncSpec
import qualified Test.LiveUpdateSpec
import qualified Test.MailSpec
import qualified Test.MutationBoundarySpec
import qualified Test.PaySpec
import qualified Test.ProfilingSpec
import qualified Test.PublicHolidaySyncSpec
import qualified Test.RosterGridSpec
import qualified Test.RosterTimesheetsAutomationSpec
import qualified Test.SchemaSpec
import qualified Test.StaffDocumentsRsaSpec
import qualified Test.StripeBillingSpec
import qualified Test.StripeContractSpec
import qualified Test.SurfaceDependencySpec
import qualified Test.SurfaceGuardSpec
import qualified Test.SurfaceInvalidationSpec
import qualified Test.SurfaceResourceSpec
import qualified Test.VenueInvitationSpec
import qualified Test.VenueOnboardingInvitationSpec
import qualified Test.XeroContractSpec
import qualified Test.XeroImportedPayItemsSpec
import qualified Test.XeroKeepaliveSpec
import qualified Test.XeroTimesheetPreviewSpec
import qualified Test.XeroTimesheetReadinessSpec
import qualified Test.XeroTimesheetSubmissionSpec

data TestSuite = TestSuite
    { suiteLabel  :: String
    , suiteWeight :: Int
    , suiteSpec   :: Spec
    }

data ShardSelection = ShardSelection
    { shardIndex :: Int
    , shardTotal :: Int
    , suites     :: [TestSuite]
    }

shardSelectionFromEnv :: IO ShardSelection
shardSelectionFromEnv = do
    total <- readShardEnv "TEST_SHARD_TOTAL" 1
    index <- readShardEnv "TEST_SHARD_INDEX" 1

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
            , suites = selectShardSuites total index
            }

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
            "Hspec shard "
                <> tshow selection.shardIndex
                <> "/"
                <> tshow selection.shardTotal
                <> summaryTail

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

selectShardSuites :: Int -> Int -> [TestSuite]
selectShardSuites total index
    | total <= 1 = allSuites
    | otherwise = balancedShardSuites total !! (index - 1)

balancedShardSuites :: Int -> [[TestSuite]]
balancedShardSuites total =
    allSuites
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

allSuites :: [TestSuite]
allSuites =
    [ TestSuite "StaticController" 10 Test.Controller.StaticSpec.tests
    , TestSuite "AsyncQueue" 10 Test.AsyncQueueSpec.tests
    , TestSuite "Billing" 10 Test.BillingPersistenceSpec.tests
    , TestSuite "BillingReadOnly" 20 Test.BillingReadOnlySpec.tests
    , TestSuite "BillingController" 15 Test.Controller.BillingSpec.tests
    , TestSuite "BillingWebhook" 35 Test.BillingWebhookSpec.tests
    , TestSuite "E2ETestController" 5 Test.Controller.E2ETestSpec.tests
    , TestSuite "StripeBilling" 10 Test.StripeBillingSpec.tests
    , TestSuite "StripeContract" 10 Test.StripeContractSpec.tests
    , TestSuite "AdminController" 180 Test.Controller.AdminSpec.tests
    , TestSuite "ProfilesController" 35 Test.Controller.ProfilesSpec.tests
    , TestSuite "PasskeysController" 25 Test.Controller.PasskeysSpec.tests
    , TestSuite "Schema" 10 Test.SchemaSpec.tests
    , TestSuite "DatabaseProtection" 10 Test.DatabaseProtectionSpec.tests
    , TestSuite "SessionsController" 25 Test.Controller.SessionsSpec.tests
    , TestSuite "RosterWeeksController" 120 Test.Controller.RosterWeeksSpec.tests
    , TestSuite "LeaveRequestsController" 20 Test.Controller.LeaveRequestsSpec.tests
    , TestSuite "FeedbackController" 10 Test.Controller.FeedbackSpec.tests
    , TestSuite "SupportController" 20 Test.Controller.SupportSpec.tests
    , TestSuite "RosterGrid" 10 Test.RosterGridSpec.tests
    , TestSuite "UsersController" 10 Test.Controller.UsersSpec.tests
    , TestSuite "ExportsController" 10 Test.Controller.ExportsSpec.tests
    , TestSuite "TimesheetsController" 40 Test.Controller.TimesheetsSpec.tests
    , TestSuite "Pay" 20 Test.PaySpec.tests
    , TestSuite "Profiling" 5 Test.ProfilingSpec.tests
    , TestSuite "PublicHolidaySync" 15 Test.PublicHolidaySyncSpec.tests
    , TestSuite "FwcMapdSync" 20 Test.FwcMapdSyncSpec.tests
    , TestSuite "RosterTimesheetsAutomation" 20 Test.RosterTimesheetsAutomationSpec.tests
    , TestSuite "VenueAccess" 35 Test.Controller.VenueAccessSpec.tests
    , TestSuite "PayrollExportParity" 30 Test.Controller.PayrollExportParitySpec.tests
    , TestSuite "StaffController" 35 Test.Controller.StaffSpec.tests
    , TestSuite "StaffDocumentsController" 20 Test.Controller.StaffDocumentsSpec.tests
    , TestSuite "StaffDocumentsRSA" 20 Test.StaffDocumentsRsaSpec.tests
    , TestSuite "VenueInvitation" 10 Test.VenueInvitationSpec.tests
    , TestSuite "VenueOnboardingInvitation" 5 Test.VenueOnboardingInvitationSpec.tests
    , TestSuite "DevSeed" 180 Test.DevSeedSpec.tests
    , TestSuite "Conflict" 5 Test.ConflictSpec.tests
    , TestSuite "FrontendContract" 5 Test.FrontendContractSpec.tests
    , TestSuite "FrontendContracts" 15 Test.FrontendContractsSpec.tests
    , TestSuite "FrontendSurfaceNaming" 5 Test.FrontendSurfaceNamingSpec.tests
    , TestSuite "FrontendSurfaceDSL" 15 Test.FrontendSurfaceDslSpec.tests
    , TestSuite "FrontendSurfaceGHC" 25 Test.FrontendSurfaceGhcSpec.tests
    , TestSuite "LiveUpdate" 20 Test.LiveUpdateSpec.tests
    , TestSuite "SurfaceResource" 5 Test.SurfaceResourceSpec.tests
    , TestSuite "SurfaceInvalidation" 5 Test.SurfaceInvalidationSpec.tests
    , TestSuite "SurfaceDependency" 10 Test.SurfaceDependencySpec.tests
    , TestSuite "SurfaceGuard" 5 Test.SurfaceGuardSpec.tests
    , TestSuite "Mail" 10 Test.MailSpec.tests
    , TestSuite "MutationBoundary" 5 Test.MutationBoundarySpec.tests
    , TestSuite "XeroContract" 20 Test.XeroContractSpec.tests
    , TestSuite "XeroImportedPayItems" 10 Test.XeroImportedPayItemsSpec.tests
    , TestSuite "XeroKeepalive" 10 Test.XeroKeepaliveSpec.tests
    , TestSuite "XeroTimesheetPreview" 50 Test.XeroTimesheetPreviewSpec.tests
    , TestSuite "XeroTimesheetReadiness" 35 Test.XeroTimesheetReadinessSpec.tests
    , TestSuite "XeroTimesheetSubmission" 35 Test.XeroTimesheetSubmissionSpec.tests
    ]
