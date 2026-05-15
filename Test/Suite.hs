module Test.Suite
    ( ShardSelection (..)
    , TestSuite (..)
    , renderShardSelection
    , shardSelectionFromEnv
    )
where

import qualified Data.Text as Text
import IHP.Prelude
import System.Environment (lookupEnv)
import Test.Hspec (Spec)
import Text.Read (readMaybe)

import qualified Test.BillingPersistenceSpec
import qualified Test.BillingReadOnlySpec
import qualified Test.BillingWebhookSpec
import qualified Test.ConflictSpec
import qualified Test.Controller.AdminSpec
import qualified Test.Controller.BillingSpec
import qualified Test.Controller.ExportsSpec
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
import qualified Test.FwcMapdSyncSpec
import qualified Test.LiveUpdateSpec
import qualified Test.MailSpec
import qualified Test.PaySpec
import qualified Test.ProfilingSpec
import qualified Test.PublicHolidaySyncSpec
import qualified Test.RosterGridSpec
import qualified Test.RosterTimesheetsAutomationSpec
import qualified Test.SchemaSpec
import qualified Test.StaffDocumentsRsaSpec
import qualified Test.StripeBillingSpec
import qualified Test.StripeContractSpec
import qualified Test.SurfaceProjectionSpec
import qualified Test.VenueInvitationSpec
import qualified Test.VenueOnboardingInvitationSpec
import qualified Test.XeroContractSpec
import qualified Test.XeroKeepaliveSpec
import qualified Test.XeroTimesheetPreviewSpec
import qualified Test.XeroTimesheetReadinessSpec
import qualified Test.XeroTimesheetSubmissionSpec

data TestSuite = TestSuite
    { suiteLabel :: String
    , suiteSpec  :: Spec
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
                else " [" <> Text.intercalate ", " selectedLabels <> "]"
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
    | otherwise =
        allSuites
            |> zip [0 ..]
            |> filter (\(suiteIndex, _) -> suiteIndex `mod` total == index - 1)
            |> map snd

allSuites :: [TestSuite]
allSuites =
    [ TestSuite "StaticController" Test.Controller.StaticSpec.tests
    , TestSuite "Billing" Test.BillingPersistenceSpec.tests
    , TestSuite "BillingReadOnly" Test.BillingReadOnlySpec.tests
    , TestSuite "BillingController" Test.Controller.BillingSpec.tests
    , TestSuite "BillingWebhook" Test.BillingWebhookSpec.tests
    , TestSuite "StripeBilling" Test.StripeBillingSpec.tests
    , TestSuite "StripeContract" Test.StripeContractSpec.tests
    , TestSuite "AdminController" Test.Controller.AdminSpec.tests
    , TestSuite "ProfilesController" Test.Controller.ProfilesSpec.tests
    , TestSuite "PasskeysController" Test.Controller.PasskeysSpec.tests
    , TestSuite "Schema" Test.SchemaSpec.tests
    , TestSuite "DatabaseProtection" Test.DatabaseProtectionSpec.tests
    , TestSuite "SessionsController" Test.Controller.SessionsSpec.tests
    , TestSuite "RosterWeeksController" Test.Controller.RosterWeeksSpec.tests
    , TestSuite "LeaveRequestsController" Test.Controller.LeaveRequestsSpec.tests
    , TestSuite "SupportController" Test.Controller.SupportSpec.tests
    , TestSuite "RosterGrid" Test.RosterGridSpec.tests
    , TestSuite "UsersController" Test.Controller.UsersSpec.tests
    , TestSuite "ExportsController" Test.Controller.ExportsSpec.tests
    , TestSuite "TimesheetsController" Test.Controller.TimesheetsSpec.tests
    , TestSuite "Pay" Test.PaySpec.tests
    , TestSuite "Profiling" Test.ProfilingSpec.tests
    , TestSuite "PublicHolidaySync" Test.PublicHolidaySyncSpec.tests
    , TestSuite "FwcMapdSync" Test.FwcMapdSyncSpec.tests
    , TestSuite "RosterTimesheetsAutomation" Test.RosterTimesheetsAutomationSpec.tests
    , TestSuite "VenueAccess" Test.Controller.VenueAccessSpec.tests
    , TestSuite "PayrollExportParity" Test.Controller.PayrollExportParitySpec.tests
    , TestSuite "StaffController" Test.Controller.StaffSpec.tests
    , TestSuite "StaffDocumentsController" Test.Controller.StaffDocumentsSpec.tests
    , TestSuite "StaffDocumentsRSA" Test.StaffDocumentsRsaSpec.tests
    , TestSuite "VenueInvitation" Test.VenueInvitationSpec.tests
    , TestSuite "VenueOnboardingInvitation" Test.VenueOnboardingInvitationSpec.tests
    , TestSuite "DevSeed" Test.DevSeedSpec.tests
    , TestSuite "Conflict" Test.ConflictSpec.tests
    , TestSuite "LiveUpdate" Test.LiveUpdateSpec.tests
    , TestSuite "Mail" Test.MailSpec.tests
    , TestSuite "SurfaceProjection" Test.SurfaceProjectionSpec.tests
    , TestSuite "XeroContract" Test.XeroContractSpec.tests
    , TestSuite "XeroKeepalive" Test.XeroKeepaliveSpec.tests
    , TestSuite "XeroTimesheetPreview" Test.XeroTimesheetPreviewSpec.tests
    , TestSuite "XeroTimesheetReadiness" Test.XeroTimesheetReadinessSpec.tests
    , TestSuite "XeroTimesheetSubmission" Test.XeroTimesheetSubmissionSpec.tests
    ]
