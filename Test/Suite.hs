module Test.Suite
    ( ShardSelection (..)
    , TestSuite (..)
    , allSuiteMetadata
    , module Test.Suite.Metadata
    , renderSelectionCoverage
    , renderShardSelection
    , renderSuiteMetadataReport
    , shardSelectionFromEnv
    )
where

import Data.List (minimumBy, sortOn)
import Data.Ord (Down (..), comparing)
import qualified Data.Text as Text
import IHP.Prelude
import System.Environment (lookupEnv)
import Test.Hspec (Spec)
import Test.Suite.Metadata
import Test.Suite.Selection (hspecArgumentsMayFilter)
import Text.Printf (printf)
import Text.Read (readMaybe)

import qualified Test.AsyncQueueSpec
import qualified Test.BillingPersistenceSpec
import qualified Test.BillingReadOnlySpec
import qualified Test.BillingWebhookSpec
import qualified Test.ConflictSpec
import qualified Test.ContextLifecycleSpec
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
import qualified Test.SuiteMetadataSpec
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

data TestSuite = TestSuite
    { testSuiteMetadata :: SuiteMetadata
    , suiteSpec         :: Spec
    }

data ShardSelection = ShardSelection
    { shardIndex                  :: Int
    , shardTotal                  :: Int
    , testLane                    :: TestLane
    , feedbackSelection           :: FeedbackSelection
    , excludedMandatoryInvariants :: [AcceptanceInvariant]
    , suites                      :: [TestSuite]
    }

shardSelectionFromEnv :: IO ShardSelection
shardSelectionFromEnv = do
    validateRegistry
    total <- readShardEnv "TEST_SHARD_TOTAL" 1
    index <- readShardEnv "TEST_SHARD_INDEX" 1
    lane <- readTestLane
    feedback <- readFeedbackSelection

    when (index < 1 || index > total) do
        error $
            "Invalid test shard selection: TEST_SHARD_INDEX="
                <> show index
                <> ", TEST_SHARD_TOTAL="
                <> show total

    let selectedSuites = laneSuites lane feedback
    pure
        ShardSelection
            { shardIndex = index
            , shardTotal = total
            , testLane = lane
            , feedbackSelection = feedback
            , excludedMandatoryInvariants =
                excludedAcceptanceInvariants allSuiteMetadata (map testSuiteMetadata selectedSuites)
            , suites = selectShardSuites selectedSuites total index
            }

validateRegistry :: IO ()
validateRegistry =
    case validateSuiteRegistry allSuiteMetadata of
        [] -> pure ()
        diagnostics ->
            error (cs ("Invalid Hspec suite registry:\n" <> Text.unlines (map ("- " <>) diagnostics)))

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

readFeedbackSelection :: IO FeedbackSelection
readFeedbackSelection = do
    value <- lookupEnv "TEST_FEEDBACK_LANE"
    case value of
        Nothing -> pure CompleteFeedback
        Just "" -> pure CompleteFeedback
        Just "all" -> pure CompleteFeedback
        Just "routine" -> pure RoutineFeedbackOnly
        Just "acceptance" -> pure AcceptanceFeedbackOnly
        Just raw -> error ("TEST_FEEDBACK_LANE must be one of all, routine, or acceptance; got: " <> cs raw)

renderShardSelection :: ShardSelection -> String
renderShardSelection selection =
    let
        selectedLabels = map (cs . suiteLabel . testSuiteMetadata) selection.suites
        summaryTail =
            if null selectedLabels
                then " (no suites assigned)"
                else " weight=" <> renderWeight (sum (map suiteWeight selection.suites)) <> " [" <> Text.intercalate ", " selectedLabels <> "]"
     in
        cs $
            "Hspec "
                <> renderTestLane selection.testLane
                <> " shard "
                <> tshow selection.shardIndex
                <> "/"
                <> tshow selection.shardTotal
                <> summaryTail

renderSelectionCoverage :: [Text] -> ShardSelection -> String
renderSelectionCoverage arguments selection =
    let
        filtered = hspecArgumentsMayFilter arguments
        coverageScope = if filtered then "focused-conservative" else "selected-suites"
        excluded = if filtered then allAcceptanceInvariants else selection.excludedMandatoryInvariants
     in
        cs $
            "Hspec feedback="
                <> renderFeedbackSelection selection.feedbackSelection
                <> " coverage-scope="
                <> coverageScope
                <> " mandatory-acceptance-excluded=["
                <> renderInvariantList excluded
                <> "] mandatory-acceptance-partial=["
                <> renderInvariantList (incompleteAcceptanceInvariants allSuiteMetadata)
                <> "] mandatory-acceptance-composed=["
                <> renderInvariantList composedAcceptanceInvariants
                <> "]"

renderSuiteMetadataReport :: Text
renderSuiteMetadataReport =
    Text.unlines $
        [ "Hspec suite metadata: " <> tshow (length allSuiteMetadata) <> " suites"
        , "Routine feedback mandatory-acceptance-excluded=[" <> renderInvariantList routineExcluded <> "]"
        , "Known partial mandatory-acceptance=[" <> renderInvariantList (incompleteAcceptanceInvariants allSuiteMetadata) <> "]"
        , "Known composed mandatory-acceptance=[" <> renderInvariantList composedAcceptanceInvariants <> "]"
        , "label\tdatabase\tclean-state\tcommitted-visibility\tfeedback\tinvariant-family\testimated-seconds\tfixture-cost\texternal-mocks\towned-invariants\tpartial-invariants"
        ]
            <> map renderSuiteMetadataRow allSuiteMetadata
  where
    routineSuites = selectSuiteMetadata AllTests RoutineFeedbackOnly allSuiteMetadata
    routineExcluded = excludedAcceptanceInvariants allSuiteMetadata routineSuites

renderSuiteMetadataRow :: SuiteMetadata -> Text
renderSuiteMetadataRow metadata =
    Text.intercalate
        "\t"
        [ cs metadata.suiteLabel
        , renderSuiteKind (suiteKind metadata)
        , renderCleanState metadata.isolationRequirement
        , renderCommittedVisibility metadata.isolationRequirement
        , renderFeedbackLane metadata.feedbackLane
        , tshow metadata.invariantFamily
        , tshow metadata.estimatedRuntimeSeconds
        , tshow metadata.fixtureCost
        , renderList metadata.externalMocks
        , renderInvariantList metadata.ownedAcceptanceInvariants
        , renderInvariantList metadata.partiallyCoveredAcceptanceInvariants
        ]

renderSuiteKind :: SuiteKind -> Text
renderSuiteKind = \case
    PureSuite -> "pure"
    DatabaseSuite -> "database"

renderCleanState :: IsolationRequirement -> Text
renderCleanState = \case
    PureIsolation -> "not-applicable"
    DatabaseIsolation CleanStateNotRequired _ -> "not-required"
    DatabaseIsolation BroadCleanStateRequired _ -> "broad-reset-required"

renderCommittedVisibility :: IsolationRequirement -> Text
renderCommittedVisibility = \case
    PureIsolation -> "not-applicable"
    DatabaseIsolation _ CommittedVisibilityNotRequired -> "not-required"
    DatabaseIsolation _ CommittedVisibilityRequired -> "required"

renderFeedbackLane :: FeedbackLane -> Text
renderFeedbackLane = \case
    RoutineCorrectness -> "routine-correctness"
    BroadAcceptance -> "broad-acceptance"

renderWeight :: Double -> Text
renderWeight weight = cs (printf "%.1f" weight :: String)

renderList :: Show value => [value] -> Text
renderList values =
    if null values
        then "none"
        else Text.intercalate "," (map tshow values)

renderInvariantList :: [AcceptanceInvariant] -> Text
renderInvariantList invariants =
    if null invariants
        then "none"
        else Text.intercalate "," (map tshow invariants)

renderTestLane :: TestLane -> Text
renderTestLane = \case
    AllTests -> "all"
    PureTests -> "pure"
    DatabaseTests -> "db"

renderFeedbackSelection :: FeedbackSelection -> Text
renderFeedbackSelection = \case
    CompleteFeedback -> "all"
    RoutineFeedbackOnly -> "routine"
    AcceptanceFeedbackOnly -> "acceptance"

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

selectShardSuites :: [TestSuite] -> Int -> Int -> [TestSuite]
selectShardSuites selectedSuites total index
    | total <= 1 = selectedSuites
    | otherwise = balancedShardSuites selectedSuites total !! (index - 1)

laneSuites :: TestLane -> FeedbackSelection -> [TestSuite]
laneSuites lane feedback =
    allSuites
        |> filter (\suite -> testSuiteMetadata suite `elem` selectedMetadata)
  where
    selectedMetadata = selectSuiteMetadata lane feedback allSuiteMetadata

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
    , bucketWeight :: Double
    , bucketSuites :: [TestSuite]
    }

suiteWeight :: TestSuite -> Double
suiteWeight = estimatedRuntimeSeconds . testSuiteMetadata

pureSuite
    :: String
    -> Double
    -> FeedbackLane
    -> InvariantFamily
    -> FixtureCost
    -> [ExternalMock]
    -> [AcceptanceInvariant]
    -> Spec
    -> TestSuite
pureSuite label weight feedback family fixtures mocks invariants =
    TestSuite (suiteMetadata label weight PureIsolation feedback family fixtures mocks invariants)

databaseSuite
    :: String
    -> Double
    -> CleanStateRequirement
    -> CommittedVisibilityRequirement
    -> FeedbackLane
    -> InvariantFamily
    -> FixtureCost
    -> [ExternalMock]
    -> [AcceptanceInvariant]
    -> Spec
    -> TestSuite
databaseSuite label weight cleanState visibility feedback family fixtures mocks invariants =
    TestSuite (suiteMetadata label weight (DatabaseIsolation cleanState visibility) feedback family fixtures mocks invariants)

databaseSuiteWithPartialCoverage
    :: String
    -> Double
    -> CleanStateRequirement
    -> CommittedVisibilityRequirement
    -> FeedbackLane
    -> InvariantFamily
    -> FixtureCost
    -> [ExternalMock]
    -> [AcceptanceInvariant]
    -> [AcceptanceInvariant]
    -> Spec
    -> TestSuite
databaseSuiteWithPartialCoverage label weight cleanState visibility feedback family fixtures mocks invariants partialInvariants spec =
    let suite = databaseSuite label weight cleanState visibility feedback family fixtures mocks invariants spec
     in suite{testSuiteMetadata = withPartialAcceptanceCoverage partialInvariants suite.testSuiteMetadata}

allSuiteMetadata :: [SuiteMetadata]
allSuiteMetadata = map testSuiteMetadata allSuites

allSuites :: [TestSuite]
allSuites =
    [ databaseSuite "StaticController" 0.3 BroadCleanStateRequired CommittedVisibilityNotRequired RoutineCorrectness AccessAndOnboarding SmallFixture [] [] Test.Controller.StaticSpec.tests
    , databaseSuite "AsyncQueue" 0.5 BroadCleanStateRequired CommittedVisibilityRequired BroadAcceptance TestInfrastructure SmallFixture [] [] Test.AsyncQueueSpec.tests
    , databaseSuite "Billing" 0.4 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance Billing SmallFixture [] [B5, B7] Test.BillingPersistenceSpec.tests
    , databaseSuite "BillingReadOnly" 0.8 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance Billing MediumFixture [] [] Test.BillingReadOnlySpec.tests
    , databaseSuite "BillingController" 1.0 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance Billing MediumFixture [] [A4, B1, B2] Test.Controller.BillingSpec.tests
    , databaseSuiteWithPartialCoverage "BillingWebhook" 0.9 BroadCleanStateRequired CommittedVisibilityRequired BroadAcceptance Billing SmallFixture [] [B4, B5, B7] [B6] Test.BillingWebhookSpec.tests
    , databaseSuite "E2ETestController" 0.4 BroadCleanStateRequired CommittedVisibilityNotRequired RoutineCorrectness AccessAndOnboarding SmallFixture [] [] Test.Controller.E2ETestSpec.tests
    , pureSuite "StripeBilling" 0.1 RoutineCorrectness Billing FixtureFree [] [B1, B2, B4, B7] Test.StripeBillingSpec.tests
    , pureSuite "StripeContract" 0.1 BroadAcceptance Billing SmallFixture [StripeTransportMock] [B1, B2, B3] Test.StripeContractSpec.tests
    , databaseSuite "AdminController.Access" 0.5 BroadCleanStateRequired CommittedVisibilityNotRequired RoutineCorrectness AccessAndOnboarding SmallFixture [] [A4] Test.Controller.Admin.AccessSpec.tests
    , databaseSuite "AdminController.Xero" 11.5 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance XeroPayroll MediumFixture [XeroHttpMock] [A4, P6] Test.Controller.Admin.XeroSpec.tests
    , databaseSuite "AdminController.Config" 3.0 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance PayAndExports MediumFixture [] [A4, P7] Test.Controller.Admin.ConfigSpec.tests
    , databaseSuite "ProfilesController" 2.0 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance AccessAndOnboarding MediumFixture [] [A3, A4] Test.Controller.ProfilesSpec.tests
    , databaseSuite "PasskeysController" 4.0 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance AccessAndOnboarding MediumFixture [] [A4] Test.Controller.PasskeysSpec.tests
    , pureSuite "Schema" 0.1 BroadAcceptance DataIntegrityAndAudit FixtureFree [] [A4, A5, A6, T1, T3, P2] Test.SchemaSpec.tests
    , databaseSuite "DatabaseProtection" 1.0 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance DataIntegrityAndAudit MediumFixture [] [A6, T6, P5] Test.DatabaseProtectionSpec.tests
    , databaseSuite "ContextLifecycle" 0.1 CleanStateNotRequired CommittedVisibilityNotRequired RoutineCorrectness TestInfrastructure FixtureFree [] [] Test.ContextLifecycleSpec.tests
    , databaseSuite "SessionsController" 2.5 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance AccessAndOnboarding MediumFixture [] [A3] Test.Controller.SessionsSpec.tests
    , databaseSuite "RosterWeeksController.Navigation" 1.5 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance Rostering MediumFixture [] [A3, R1] Test.Controller.RosterWeeks.NavigationSpec.tests
    , databaseSuite "RosterWeeksController.Workflow" 6.5 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance Rostering LargeFixture [] [R1, R2, R3, R4] Test.Controller.RosterWeeks.WorkflowSpec.tests
    , databaseSuite "RosterWeeksController.Fragments" 8.0 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance Rostering LargeFixture [] [R1, R4, T4] Test.Controller.RosterWeeks.FragmentsSpec.tests
    , databaseSuite "RosterWeeksController.Baseline" 0.6 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance Rostering SmallFixture [] [R1] Test.Controller.RosterWeeks.BaselineSpec.tests
    , databaseSuite "RosterWeeksController.DirectReadModel" 0.8 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance Rostering MediumFixture [] [R4, R5] Test.Controller.RosterWeeks.DirectReadModelSpec.tests
    , databaseSuite "LeaveRequestsController" 2.5 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance TimesheetsAndLeave LargeFixture [] [T3, T4, T5] Test.Controller.LeaveRequestsSpec.tests
    , databaseSuite "FeedbackController" 0.4 BroadCleanStateRequired CommittedVisibilityNotRequired RoutineCorrectness ProductSupport SmallFixture [] [] Test.Controller.FeedbackSpec.tests
    , databaseSuite "HelpController" 0.2 BroadCleanStateRequired CommittedVisibilityNotRequired RoutineCorrectness ProductSupport SmallFixture [] [] Test.Controller.HelpSpec.tests
    , databaseSuite "SupportController" 0.8 BroadCleanStateRequired CommittedVisibilityRequired BroadAcceptance TestInfrastructure SmallFixture [] [A4] Test.Controller.SupportSpec.tests
    , pureSuite "RosterGrid" 0.1 RoutineCorrectness Rostering FixtureFree [] [] Test.RosterGridSpec.tests
    , databaseSuite "UsersController" 2.0 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance AccessAndOnboarding MediumFixture [] [A1, A2, A3, A4, T7] Test.Controller.UsersSpec.tests
    , databaseSuite "ExportsController" 2.0 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance PayAndExports MediumFixture [] [A7, P6] Test.Controller.ExportsSpec.tests
    , databaseSuite "TimesheetsController" 7.5 BroadCleanStateRequired CommittedVisibilityRequired BroadAcceptance TimesheetsAndLeave LargeFixture [] [A6, T1, T2, T5, T6] Test.Controller.TimesheetsSpec.tests
    , databaseSuite "Pay" 2.5 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance PayAndExports SmallFixture [] [P1, P2, P3, P4, P5] Test.PaySpec.tests
    , pureSuite "PageHelp" 0.1 RoutineCorrectness ProductSupport FixtureFree [] [] Test.PageHelpSpec.tests
    , pureSuite "Profiling" 0.1 RoutineCorrectness Observability FixtureFree [] [] Test.ProfilingSpec.tests
    , databaseSuite "PublicHolidaySync" 0.3 BroadCleanStateRequired CommittedVisibilityNotRequired RoutineCorrectness PayAndExports SmallFixture [] [P2, P3] Test.PublicHolidaySyncSpec.tests
    , databaseSuite "FwcMapdSync" 0.2 BroadCleanStateRequired CommittedVisibilityNotRequired RoutineCorrectness PayAndExports SmallFixture [] [P3, P5] Test.FwcMapdSyncSpec.tests
    , databaseSuite "VenueAccess" 5.5 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance AccessAndOnboarding LargeFixture [] [A4, A5, A6] Test.Controller.VenueAccessSpec.tests
    , databaseSuite "FixedExportGolden" 4.5 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance PayAndExports MediumFixture [] [P4, P5, P6] Test.Controller.FixedExportGoldenSpec.tests
    , databaseSuite "StaffController" 3.5 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance StaffAndCompliance LargeFixture [] [A4, P1, T7] Test.Controller.StaffSpec.tests
    , databaseSuite "StaffDocumentsController" 0.8 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance StaffAndCompliance MediumFixture [] [A6] Test.Controller.StaffDocumentsSpec.tests
    , databaseSuite "StaffDocumentsRSA" 0.5 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance StaffAndCompliance SmallFixture [] [T6] Test.StaffDocumentsRsaSpec.tests
    , databaseSuite "VenueInvitation" 0.4 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance AccessAndOnboarding SmallFixture [] [A1, A4] Test.VenueInvitationSpec.tests
    , databaseSuite "VenueOnboardingInvitation" 0.5 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance AccessAndOnboarding SmallFixture [] [A1, A2] Test.VenueOnboardingInvitationSpec.tests
    , databaseSuite "DevSeed" 7.5 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance TestInfrastructure LargeFixture [] [] Test.DevSeedSpec.tests
    , pureSuite "Conflict" 0.1 RoutineCorrectness Rostering FixtureFree [] [R4, R5, T4] Test.ConflictSpec.tests
    , pureSuite "FrontendContract" 0.1 RoutineCorrectness FrontendContractsAndLiveUpdate FixtureFree [] [] Test.FrontendContractSpec.tests
    , pureSuite "FrontendContracts" 0.1 RoutineCorrectness FrontendContractsAndLiveUpdate FixtureFree [] [] Test.FrontendContractsSpec.tests
    , pureSuite "FrontendSurfaceAdapterGenerator" 0.1 RoutineCorrectness FrontendContractsAndLiveUpdate SmallFixture [] [] Test.FrontendSurfaceAdapterGeneratorSpec.tests
    , pureSuite "FrontendSurfaceRequestAdapter" 0.1 RoutineCorrectness FrontendContractsAndLiveUpdate FixtureFree [] [] Test.FrontendSurfaceRequestAdapterSpec.tests
    , pureSuite "FrontendSurfaceNaming" 0.1 RoutineCorrectness FrontendContractsAndLiveUpdate FixtureFree [] [] Test.FrontendSurfaceNamingSpec.tests
    , pureSuite "FrontendSurfaceDSL" 0.1 RoutineCorrectness FrontendContractsAndLiveUpdate FixtureFree [] [] Test.FrontendSurfaceDslSpec.tests
    , pureSuite "LiveUpdate" 0.1 RoutineCorrectness FrontendContractsAndLiveUpdate FixtureFree [] [] Test.LiveUpdateSpec.tests
    , pureSuite "SurfaceResource" 0.1 RoutineCorrectness FrontendContractsAndLiveUpdate FixtureFree [] [] Test.SurfaceResourceSpec.tests
    , pureSuite "SurfaceInvalidation" 0.1 RoutineCorrectness FrontendContractsAndLiveUpdate FixtureFree [] [] Test.SurfaceInvalidationSpec.tests
    , pureSuite "SurfaceDependency" 0.1 RoutineCorrectness FrontendContractsAndLiveUpdate FixtureFree [] [] Test.SurfaceDependencySpec.tests
    , pureSuite "SurfaceGuard" 0.1 RoutineCorrectness FrontendContractsAndLiveUpdate FixtureFree [] [] Test.SurfaceGuardSpec.tests
    , databaseSuite "ToggleButton" 0.1 CleanStateNotRequired CommittedVisibilityNotRequired RoutineCorrectness FrontendContractsAndLiveUpdate FixtureFree [] [] Test.ToggleButtonSpec.tests
    , pureSuite "HorizontalScroll" 0.1 RoutineCorrectness FrontendContractsAndLiveUpdate FixtureFree [] [] Test.HorizontalScrollSpec.tests
    , pureSuite "PwaInstall" 0.1 RoutineCorrectness FrontendContractsAndLiveUpdate FixtureFree [] [] Test.PwaInstallSpec.tests
    , databaseSuite "OrderedRange" 0.1 CleanStateNotRequired CommittedVisibilityNotRequired RoutineCorrectness FrontendContractsAndLiveUpdate FixtureFree [] [] Test.OrderedRangeSpec.tests
    , databaseSuite "Overlay" 0.1 CleanStateNotRequired CommittedVisibilityNotRequired RoutineCorrectness FrontendContractsAndLiveUpdate FixtureFree [] [] Test.OverlaySpec.tests
    , databaseSuite "TimePicker" 0.1 CleanStateNotRequired CommittedVisibilityNotRequired RoutineCorrectness FrontendContractsAndLiveUpdate FixtureFree [] [] Test.TimePickerSpec.tests
    , databaseSuite "Mail" 0.6 BroadCleanStateRequired CommittedVisibilityNotRequired RoutineCorrectness Communications SmallFixture [] [B7] Test.MailSpec.tests
    , pureSuite "MutationBoundary" 0.1 RoutineCorrectness DataIntegrityAndAudit FixtureFree [] [] Test.MutationBoundarySpec.tests
    , pureSuite "SuiteMetadata" 0.1 RoutineCorrectness TestInfrastructure FixtureFree [] [] Test.SuiteMetadataSpec.tests
    , databaseSuite "XeroCandidateFilter" 0.1 CleanStateNotRequired CommittedVisibilityNotRequired RoutineCorrectness XeroPayroll FixtureFree [] [] Test.XeroCandidateFilterSpec.tests
    , pureSuite "XeroContract" 0.1 RoutineCorrectness XeroPayroll SmallFixture [XeroHttpMock] [] Test.XeroContractSpec.tests
    , pureSuite "XeroImportedPayItems" 0.1 RoutineCorrectness XeroPayroll FixtureFree [] [] Test.XeroImportedPayItemsSpec.tests
    , databaseSuite "XeroKeepalive" 0.3 BroadCleanStateRequired CommittedVisibilityNotRequired RoutineCorrectness XeroPayroll SmallFixture [] [] Test.XeroKeepaliveSpec.tests
    , databaseSuite "XeroTimesheetPreview" 3.5 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance XeroPayroll MediumFixture [] [P5, P6] Test.XeroTimesheetPreviewSpec.tests
    , databaseSuite "XeroTimesheetReadiness" 3.5 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance XeroPayroll MediumFixture [] [P5, P6] Test.XeroTimesheetReadinessSpec.tests
    , databaseSuite "XeroTimesheetSubmission" 2.0 BroadCleanStateRequired CommittedVisibilityNotRequired BroadAcceptance XeroPayroll LargeFixture [XeroHttpMock] [P6] Test.XeroTimesheetSubmissionSpec.tests
    ]
