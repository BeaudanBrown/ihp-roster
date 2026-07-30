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
import qualified Test.BillingReconciliationSpec
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
import qualified Test.PasskeySpec
import qualified Test.PaySpec
import qualified Test.ProfilingSpec
import qualified Test.PublicHolidaySyncSpec
import qualified Test.PwaInstallSpec
import qualified Test.RosterAwardDurationSpec
import qualified Test.RosterGridSpec
import qualified Test.SchemaSpec
import qualified Test.StaffDocumentsRsaSpec
import qualified Test.StripeBillingSpec
import qualified Test.StripeContractSpec
import qualified Test.StripeOpenApiSpec
import qualified Test.SuiteMetadataSpec
import qualified Test.SurfaceDependencySpec
import qualified Test.SurfaceGuardSpec
import qualified Test.SurfaceInvalidationSpec
import qualified Test.SurfaceResourceSpec
import qualified Test.TimePickerSpec
import qualified Test.ToggleButtonSpec
import qualified Test.VenueInvitationSpec
import qualified Test.VenueOnboardingInvitationSpec
import qualified Test.VenueTimeSpec
import qualified Test.WageCutoverMigrationSpec
import qualified Test.WageEngine.AdapterSpec
import qualified Test.WageEngine.ComponentsSpec
import qualified Test.WageEngine.ContractSpec
import qualified Test.WageEngine.MealBreakSpec
import qualified Test.WageEngine.MinimumPaymentSpec
import qualified Test.WageEngine.RulesSpec
import qualified Test.WageSourceEnforcementSpec
import qualified Test.WageSourcePolicySpec
import qualified Test.XeroCandidateFilterSpec
import qualified Test.XeroContractSpec
import qualified Test.XeroImportedPayItemsSpec
import qualified Test.XeroKeepaliveSpec
import qualified Test.XeroReferenceDemandSpec
import qualified Test.XeroReferenceSyncJobSpec
import qualified Test.XeroReferenceSyncPolicySpec
import qualified Test.XeroReferenceTrustReadModelSpec
import qualified Test.XeroReferenceTrustSpec
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

pureSuite :: SuiteDefinition -> Spec -> TestSuite
pureSuite definition =
    TestSuite (suiteMetadataFromDefinition PureIsolation definition)

databaseSuite
    :: CleanStateRequirement
    -> CommittedVisibilityRequirement
    -> SuiteDefinition
    -> Spec
    -> TestSuite
databaseSuite cleanState visibility definition =
    TestSuite (suiteMetadataFromDefinition (DatabaseIsolation cleanState visibility) definition)

allSuiteMetadata :: [SuiteMetadata]
allSuiteMetadata = map testSuiteMetadata allSuites

allSuites :: [TestSuite]
allSuites =
    [ databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "StaticController", definitionEstimatedRuntimeSeconds = 0.3, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = AccessAndOnboarding, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.Controller.StaticSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityRequired SuiteDefinition{definitionLabel = "AsyncQueue", definitionEstimatedRuntimeSeconds = 0.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = TestInfrastructure, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.AsyncQueueSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "Billing", definitionEstimatedRuntimeSeconds = 0.6, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = Billing, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [B5, B7], definitionPartialInvariants = []} Test.BillingPersistenceSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "BillingReadOnly", definitionEstimatedRuntimeSeconds = 0.8, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = Billing, definitionFixtureCost = MediumFixture, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.BillingReadOnlySpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "BillingReconciliation", definitionEstimatedRuntimeSeconds = 0.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = Billing, definitionFixtureCost = SmallFixture, definitionExternalMocks = [StripeTransportMock], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.BillingReconciliationSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityRequired SuiteDefinition{definitionLabel = "BillingController", definitionEstimatedRuntimeSeconds = 1.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = Billing, definitionFixtureCost = MediumFixture, definitionExternalMocks = [StripeTransportMock], definitionOwnedInvariants = [A4], definitionPartialInvariants = []} Test.Controller.BillingSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityRequired SuiteDefinition{definitionLabel = "BillingWebhook", definitionEstimatedRuntimeSeconds = 0.9, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = Billing, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [B4, B5, B6, B7], definitionPartialInvariants = []} Test.BillingWebhookSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "E2ETestController", definitionEstimatedRuntimeSeconds = 0.4, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = AccessAndOnboarding, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.Controller.E2ETestSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "StripeBilling", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = Billing, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [B1, B2, B4, B7], definitionPartialInvariants = []} Test.StripeBillingSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "StripeContract", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = Billing, definitionFixtureCost = SmallFixture, definitionExternalMocks = [StripeTransportMock], definitionOwnedInvariants = [B1, B2, B3], definitionPartialInvariants = []} Test.StripeContractSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "StripeOpenApi", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = Billing, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.StripeOpenApiSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "AdminController.Access", definitionEstimatedRuntimeSeconds = 0.5, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = AccessAndOnboarding, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [A4], definitionPartialInvariants = []} Test.Controller.Admin.AccessSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "AdminController.Xero", definitionEstimatedRuntimeSeconds = 11.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = XeroPayroll, definitionFixtureCost = MediumFixture, definitionExternalMocks = [XeroHttpMock], definitionOwnedInvariants = [A4, P6], definitionPartialInvariants = []} Test.Controller.Admin.XeroSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "AdminController.Config", definitionEstimatedRuntimeSeconds = 3.0, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = PayAndExports, definitionFixtureCost = MediumFixture, definitionExternalMocks = [], definitionOwnedInvariants = [A4, P7], definitionPartialInvariants = []} Test.Controller.Admin.ConfigSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "ProfilesController", definitionEstimatedRuntimeSeconds = 2.0, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = AccessAndOnboarding, definitionFixtureCost = MediumFixture, definitionExternalMocks = [], definitionOwnedInvariants = [A3, A4], definitionPartialInvariants = []} Test.Controller.ProfilesSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "PasskeysController", definitionEstimatedRuntimeSeconds = 4.0, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = AccessAndOnboarding, definitionFixtureCost = MediumFixture, definitionExternalMocks = [], definitionOwnedInvariants = [A4], definitionPartialInvariants = []} Test.Controller.PasskeysSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "Schema", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = DataIntegrityAndAudit, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [A4, A5, A6, T1, T3, P2], definitionPartialInvariants = []} Test.SchemaSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "DatabaseProtection", definitionEstimatedRuntimeSeconds = 1.0, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = DataIntegrityAndAudit, definitionFixtureCost = MediumFixture, definitionExternalMocks = [], definitionOwnedInvariants = [A6, T6, P5], definitionPartialInvariants = []} Test.DatabaseProtectionSpec.tests
    , databaseSuite CleanStateNotRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "ContextLifecycle", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = TestInfrastructure, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.ContextLifecycleSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "SessionsController", definitionEstimatedRuntimeSeconds = 2.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = AccessAndOnboarding, definitionFixtureCost = MediumFixture, definitionExternalMocks = [], definitionOwnedInvariants = [A3], definitionPartialInvariants = []} Test.Controller.SessionsSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "RosterWeeksController.Navigation", definitionEstimatedRuntimeSeconds = 1.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = Rostering, definitionFixtureCost = MediumFixture, definitionExternalMocks = [], definitionOwnedInvariants = [A3, R1], definitionPartialInvariants = []} Test.Controller.RosterWeeks.NavigationSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "RosterWeeksController.Workflow", definitionEstimatedRuntimeSeconds = 6.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = Rostering, definitionFixtureCost = LargeFixture, definitionExternalMocks = [], definitionOwnedInvariants = [R1, R2, R3, R4], definitionPartialInvariants = []} Test.Controller.RosterWeeks.WorkflowSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "RosterWeeksController.Fragments", definitionEstimatedRuntimeSeconds = 8.0, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = Rostering, definitionFixtureCost = LargeFixture, definitionExternalMocks = [], definitionOwnedInvariants = [R1, R4, T4], definitionPartialInvariants = []} Test.Controller.RosterWeeks.FragmentsSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "RosterWeeksController.Baseline", definitionEstimatedRuntimeSeconds = 0.6, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = Rostering, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [R1], definitionPartialInvariants = []} Test.Controller.RosterWeeks.BaselineSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "RosterWeeksController.DirectReadModel", definitionEstimatedRuntimeSeconds = 0.8, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = Rostering, definitionFixtureCost = MediumFixture, definitionExternalMocks = [], definitionOwnedInvariants = [R4, R5], definitionPartialInvariants = []} Test.Controller.RosterWeeks.DirectReadModelSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "LeaveRequestsController", definitionEstimatedRuntimeSeconds = 2.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = TimesheetsAndLeave, definitionFixtureCost = LargeFixture, definitionExternalMocks = [], definitionOwnedInvariants = [T3, T4, T5], definitionPartialInvariants = []} Test.Controller.LeaveRequestsSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "FeedbackController", definitionEstimatedRuntimeSeconds = 0.4, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = ProductSupport, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.Controller.FeedbackSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "HelpController", definitionEstimatedRuntimeSeconds = 0.2, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = ProductSupport, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.Controller.HelpSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityRequired SuiteDefinition{definitionLabel = "SupportController", definitionEstimatedRuntimeSeconds = 0.8, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = TestInfrastructure, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [A4], definitionPartialInvariants = []} Test.Controller.SupportSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "RosterAwardDuration", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = Rostering, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.RosterAwardDurationSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "RosterGrid", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = Rostering, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.RosterGridSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "UsersController", definitionEstimatedRuntimeSeconds = 2.0, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = AccessAndOnboarding, definitionFixtureCost = MediumFixture, definitionExternalMocks = [], definitionOwnedInvariants = [A1, A2, A3, A4, T7], definitionPartialInvariants = []} Test.Controller.UsersSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "ExportsController", definitionEstimatedRuntimeSeconds = 2.0, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = PayAndExports, definitionFixtureCost = MediumFixture, definitionExternalMocks = [], definitionOwnedInvariants = [A7, P6], definitionPartialInvariants = []} Test.Controller.ExportsSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityRequired SuiteDefinition{definitionLabel = "TimesheetsController", definitionEstimatedRuntimeSeconds = 7.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = TimesheetsAndLeave, definitionFixtureCost = LargeFixture, definitionExternalMocks = [], definitionOwnedInvariants = [A6, T1, T2, T5, T6], definitionPartialInvariants = []} Test.Controller.TimesheetsSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "VenueTime", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = PayAndExports, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.VenueTimeSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "PayHelpers", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = PayAndExports, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.PaySpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "WageCutoverMigration", definitionEstimatedRuntimeSeconds = 0.2, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = PayAndExports, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.WageCutoverMigrationSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "WageEngine.Components", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = PayAndExports, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.WageEngine.ComponentsSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "WageEngine.Contract", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = PayAndExports, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.WageEngine.ContractSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "WageEngine.MealBreak", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = PayAndExports, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.WageEngine.MealBreakSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "WageEngine.MinimumPayment", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = PayAndExports, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [P2], definitionPartialInvariants = []} Test.WageEngine.MinimumPaymentSpec.pureTests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "WageEngine.MinimumPaymentDataVic", definitionEstimatedRuntimeSeconds = 0.2, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = PayAndExports, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [P3], definitionPartialInvariants = []} Test.WageEngine.MinimumPaymentSpec.databaseTests
    , pureSuite SuiteDefinition{definitionLabel = "WageEngine.Rules", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = PayAndExports, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.WageEngine.RulesSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "WageEngine.AdapterStructure", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = PayAndExports, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.WageEngine.AdapterSpec.pureTests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "WageEngine.Adapter", definitionEstimatedRuntimeSeconds = 0.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = PayAndExports, definitionFixtureCost = MediumFixture, definitionExternalMocks = [], definitionOwnedInvariants = [P1], definitionPartialInvariants = []} Test.WageEngine.AdapterSpec.databaseTests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "WageSourceEnforcement", definitionEstimatedRuntimeSeconds = 0.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = PayAndExports, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.WageSourceEnforcementSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "WageSourcePolicy", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = PayAndExports, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.WageSourcePolicySpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "PageHelp", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = ProductSupport, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.PageHelpSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "Profiling", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = Observability, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.ProfilingSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "PublicHolidaySync", definitionEstimatedRuntimeSeconds = 0.3, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = PayAndExports, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [P2, P3], definitionPartialInvariants = []} Test.PublicHolidaySyncSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "FwcMapdSync", definitionEstimatedRuntimeSeconds = 0.2, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = PayAndExports, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [P3, P5], definitionPartialInvariants = []} Test.FwcMapdSyncSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "VenueAccess", definitionEstimatedRuntimeSeconds = 5.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = AccessAndOnboarding, definitionFixtureCost = LargeFixture, definitionExternalMocks = [], definitionOwnedInvariants = [A4, A5, A6], definitionPartialInvariants = []} Test.Controller.VenueAccessSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "FixedExportGolden", definitionEstimatedRuntimeSeconds = 4.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = PayAndExports, definitionFixtureCost = MediumFixture, definitionExternalMocks = [], definitionOwnedInvariants = [P4, P5, P6], definitionPartialInvariants = []} Test.Controller.FixedExportGoldenSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "StaffController", definitionEstimatedRuntimeSeconds = 3.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = StaffAndCompliance, definitionFixtureCost = LargeFixture, definitionExternalMocks = [], definitionOwnedInvariants = [A4, P1, T7], definitionPartialInvariants = []} Test.Controller.StaffSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "StaffDocumentsController", definitionEstimatedRuntimeSeconds = 0.8, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = StaffAndCompliance, definitionFixtureCost = MediumFixture, definitionExternalMocks = [], definitionOwnedInvariants = [A6], definitionPartialInvariants = []} Test.Controller.StaffDocumentsSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "StaffDocumentsRSA", definitionEstimatedRuntimeSeconds = 0.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = StaffAndCompliance, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [T6], definitionPartialInvariants = []} Test.StaffDocumentsRsaSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "VenueInvitation", definitionEstimatedRuntimeSeconds = 0.4, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = AccessAndOnboarding, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [A1, A4], definitionPartialInvariants = []} Test.VenueInvitationSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "VenueOnboardingInvitation", definitionEstimatedRuntimeSeconds = 0.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = AccessAndOnboarding, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [A1, A2], definitionPartialInvariants = []} Test.VenueOnboardingInvitationSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "DevSeed", definitionEstimatedRuntimeSeconds = 7.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = TestInfrastructure, definitionFixtureCost = LargeFixture, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.DevSeedSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "Conflict", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = Rostering, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [R4, R5, T4], definitionPartialInvariants = []} Test.ConflictSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "FrontendContract", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.FrontendContractSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "FrontendContracts", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.FrontendContractsSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "FrontendSurfaceAdapterGenerator", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.FrontendSurfaceAdapterGeneratorSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "FrontendSurfaceRequestAdapter", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.FrontendSurfaceRequestAdapterSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "FrontendSurfaceNaming", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.FrontendSurfaceNamingSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "FrontendSurfaceDSL", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.FrontendSurfaceDslSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "LiveUpdate", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.LiveUpdateSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "SurfaceResource", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.SurfaceResourceSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "SurfaceInvalidation", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.SurfaceInvalidationSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "SurfaceDependency", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.SurfaceDependencySpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "SurfaceGuard", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.SurfaceGuardSpec.tests
    , databaseSuite CleanStateNotRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "ToggleButton", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.ToggleButtonSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "HorizontalScroll", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.HorizontalScrollSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "PwaInstall", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.PwaInstallSpec.tests
    , databaseSuite CleanStateNotRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "OrderedRange", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.OrderedRangeSpec.tests
    , databaseSuite CleanStateNotRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "Overlay", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.OverlaySpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "Passkey", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.PasskeySpec.tests
    , databaseSuite CleanStateNotRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "TimePicker", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = FrontendContractsAndLiveUpdate, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.TimePickerSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "Mail", definitionEstimatedRuntimeSeconds = 0.6, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = Communications, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [B7], definitionPartialInvariants = []} Test.MailSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "MutationBoundary", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = DataIntegrityAndAudit, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.MutationBoundarySpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "SuiteMetadata", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = TestInfrastructure, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.SuiteMetadataSpec.tests
    , databaseSuite CleanStateNotRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "XeroCandidateFilter", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = XeroPayroll, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.XeroCandidateFilterSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "XeroContract", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = XeroPayroll, definitionFixtureCost = SmallFixture, definitionExternalMocks = [XeroHttpMock], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.XeroContractSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "XeroImportedPayItems", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = XeroPayroll, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.XeroImportedPayItemsSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "XeroKeepalive", definitionEstimatedRuntimeSeconds = 0.3, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = XeroPayroll, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.XeroKeepaliveSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "XeroReferenceDemand", definitionEstimatedRuntimeSeconds = 0.4, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = XeroPayroll, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.XeroReferenceDemandSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "XeroReferenceSyncJob", definitionEstimatedRuntimeSeconds = 0.5, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = XeroPayroll, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.XeroReferenceSyncJobSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "XeroReferenceSyncPolicy", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = XeroPayroll, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.XeroReferenceSyncPolicySpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "XeroReferenceTrustReadModel", definitionEstimatedRuntimeSeconds = 0.3, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = XeroPayroll, definitionFixtureCost = SmallFixture, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.XeroReferenceTrustReadModelSpec.tests
    , pureSuite SuiteDefinition{definitionLabel = "XeroReferenceTrust", definitionEstimatedRuntimeSeconds = 0.1, definitionFeedbackLane = RoutineCorrectness, definitionInvariantFamily = XeroPayroll, definitionFixtureCost = FixtureFree, definitionExternalMocks = [], definitionOwnedInvariants = [], definitionPartialInvariants = []} Test.XeroReferenceTrustSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "XeroTimesheetPreview", definitionEstimatedRuntimeSeconds = 3.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = XeroPayroll, definitionFixtureCost = MediumFixture, definitionExternalMocks = [], definitionOwnedInvariants = [P5, P6], definitionPartialInvariants = []} Test.XeroTimesheetPreviewSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "XeroTimesheetReadiness", definitionEstimatedRuntimeSeconds = 3.5, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = XeroPayroll, definitionFixtureCost = MediumFixture, definitionExternalMocks = [], definitionOwnedInvariants = [P5, P6], definitionPartialInvariants = []} Test.XeroTimesheetReadinessSpec.tests
    , databaseSuite BroadCleanStateRequired CommittedVisibilityNotRequired SuiteDefinition{definitionLabel = "XeroTimesheetSubmission", definitionEstimatedRuntimeSeconds = 2.0, definitionFeedbackLane = BroadAcceptance, definitionInvariantFamily = XeroPayroll, definitionFixtureCost = LargeFixture, definitionExternalMocks = [XeroHttpMock], definitionOwnedInvariants = [P6], definitionPartialInvariants = []} Test.XeroTimesheetSubmissionSpec.tests
    ]
