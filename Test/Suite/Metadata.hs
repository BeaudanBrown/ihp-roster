module Test.Suite.Metadata
    ( AcceptanceInvariant (..)
    , CleanStateRequirement (..)
    , CommittedVisibilityRequirement (..)
    , ExternalMock (..)
    , FeedbackLane (..)
    , FeedbackSelection (..)
    , FixtureCost (..)
    , InvariantFamily (..)
    , IsolationRequirement (..)
    , SuiteKind (..)
    , SuiteMetadata (..)
    , TestLane (..)
    , allAcceptanceInvariants
    , excludedAcceptanceInvariants
    , incompleteAcceptanceInvariants
    , selectSuiteMetadata
    , suiteKind
    , suiteMetadata
    , validateSuiteMetadata
    , validateSuiteRegistry
    , withPartialAcceptanceCoverage
    )
where

import qualified Data.List as List
import qualified Data.Set as Set
import qualified Data.Text as Text
import IHP.Prelude

data SuiteKind
    = PureSuite
    | DatabaseSuite
    deriving (Eq, Show)

data TestLane
    = AllTests
    | PureTests
    | DatabaseTests
    deriving (Eq, Show)

data FeedbackLane
    = RoutineCorrectness
    | BroadAcceptance
    deriving (Eq, Show)

data FeedbackSelection
    = CompleteFeedback
    | RoutineFeedbackOnly
    | AcceptanceFeedbackOnly
    deriving (Eq, Show)

data CleanStateRequirement
    = CleanStateNotRequired
    | BroadCleanStateRequired
    deriving (Eq, Show)

data CommittedVisibilityRequirement
    = CommittedVisibilityNotRequired
    | CommittedVisibilityRequired
    deriving (Eq, Show)

data IsolationRequirement
    = PureIsolation
    | DatabaseIsolation CleanStateRequirement CommittedVisibilityRequirement
    deriving (Eq, Show)

data FixtureCost
    = FixtureFree
    | SmallFixture
    | MediumFixture
    | LargeFixture
    deriving (Eq, Ord, Show)

data ExternalMock
    = StripeTransportMock
    | XeroHttpMock
    deriving (Eq, Ord, Show)

data InvariantFamily
    = AccessAndOnboarding
    | Billing
    | Communications
    | DataIntegrityAndAudit
    | FrontendContractsAndLiveUpdate
    | Observability
    | PayAndExports
    | ProductSupport
    | Rostering
    | StaffAndCompliance
    | TestInfrastructure
    | TimesheetsAndLeave
    | XeroPayroll
    deriving (Bounded, Enum, Eq, Ord, Show)

data AcceptanceInvariant
    = A1
    | A2
    | A3
    | A4
    | A5
    | A6
    | A7
    | R1
    | R2
    | R3
    | R4
    | R5
    | T1
    | T2
    | T3
    | T4
    | T5
    | T6
    | T7
    | P1
    | P2
    | P3
    | P4
    | P5
    | P6
    | P7
    | B1
    | B2
    | B3
    | B4
    | B5
    | B6
    | B7
    deriving (Bounded, Enum, Eq, Ord, Show)

data SuiteMetadata = SuiteMetadata
    { suiteLabel                           :: String
    , estimatedRuntimeSeconds              :: Double
    , isolationRequirement                 :: IsolationRequirement
    , feedbackLane                         :: FeedbackLane
    , invariantFamily                      :: InvariantFamily
    , fixtureCost                          :: FixtureCost
    , externalMocks                        :: [ExternalMock]
    , ownedAcceptanceInvariants            :: [AcceptanceInvariant]
    , partiallyCoveredAcceptanceInvariants :: [AcceptanceInvariant]
    }
    deriving (Eq, Show)

suiteMetadata
    :: String
    -> Double
    -> IsolationRequirement
    -> FeedbackLane
    -> InvariantFamily
    -> FixtureCost
    -> [ExternalMock]
    -> [AcceptanceInvariant]
    -> SuiteMetadata
suiteMetadata label runtime isolation feedback family fixtures mocks invariants =
    SuiteMetadata
        { suiteLabel = label
        , estimatedRuntimeSeconds = runtime
        , isolationRequirement = isolation
        , feedbackLane = feedback
        , invariantFamily = family
        , fixtureCost = fixtures
        , externalMocks = mocks
        , ownedAcceptanceInvariants = invariants
        , partiallyCoveredAcceptanceInvariants = []
        }

withPartialAcceptanceCoverage :: [AcceptanceInvariant] -> SuiteMetadata -> SuiteMetadata
withPartialAcceptanceCoverage invariants metadata =
    metadata{partiallyCoveredAcceptanceInvariants = invariants}

suiteKind :: SuiteMetadata -> SuiteKind
suiteKind metadata =
    case metadata.isolationRequirement of
        PureIsolation         -> PureSuite
        DatabaseIsolation _ _ -> DatabaseSuite

allAcceptanceInvariants :: [AcceptanceInvariant]
allAcceptanceInvariants = [minBound .. maxBound]

selectSuiteMetadata :: TestLane -> FeedbackSelection -> [SuiteMetadata] -> [SuiteMetadata]
selectSuiteMetadata lane feedback = filter \metadata ->
    matchesTestLane lane metadata && matchesFeedbackSelection feedback metadata

excludedAcceptanceInvariants :: [SuiteMetadata] -> [SuiteMetadata] -> [AcceptanceInvariant]
excludedAcceptanceInvariants registry selected =
    filter invariantIsExcluded allAcceptanceInvariants
  where
    selectedLabels = Set.fromList (map suiteLabel selected)
    invariantIsExcluded invariant =
        let ownerLabels =
                registry
                    |> filter (elem invariant . declaredAcceptanceInvariants)
                    |> map suiteLabel
         in null ownerLabels || any (`Set.notMember` selectedLabels) ownerLabels

incompleteAcceptanceInvariants :: [SuiteMetadata] -> [AcceptanceInvariant]
incompleteAcceptanceInvariants registry =
    allAcceptanceInvariants
        |> filter (\invariant -> all (notElem invariant . ownedAcceptanceInvariants) registry)

declaredAcceptanceInvariants :: SuiteMetadata -> [AcceptanceInvariant]
declaredAcceptanceInvariants metadata =
    metadata.ownedAcceptanceInvariants <> metadata.partiallyCoveredAcceptanceInvariants

validateSuiteRegistry :: [SuiteMetadata] -> [Text]
validateSuiteRegistry registry =
    concatMap validateSuiteMetadata registry
        <> duplicateLabelDiagnostics
        <> missingInvariantDiagnostics
  where
    duplicateLabelDiagnostics =
        duplicateValues (map suiteLabel registry)
            |> map (\label -> "duplicate suite label: " <> cs label)
    missingInvariantDiagnostics =
        allAcceptanceInvariants
            |> filter (\invariant -> all (notElem invariant . declaredAcceptanceInvariants) registry)
            |> map (\invariant -> "mandatory invariant has no coverage declaration: " <> tshow invariant)

validateSuiteMetadata :: SuiteMetadata -> [Text]
validateSuiteMetadata metadata =
    emptyLabelDiagnostic
        <> runtimeDiagnostics
        <> isolationDiagnostics
        <> duplicateInvariantDiagnostics
        <> duplicatePartialInvariantDiagnostics
        <> overlappingInvariantDiagnostics
        <> duplicateMockDiagnostics
  where
    label = cs metadata.suiteLabel :: Text
    emptyLabelDiagnostic =
        ["suite label must not be empty" | Text.null (Text.strip label)]
    runtimeDiagnostics =
        [ label <> ": estimated runtime must be a finite positive number of seconds"
        | metadata.estimatedRuntimeSeconds <= 0
            || isNaN metadata.estimatedRuntimeSeconds
            || isInfinite metadata.estimatedRuntimeSeconds
        ]
    isolationDiagnostics =
        case metadata.isolationRequirement of
            DatabaseIsolation CleanStateNotRequired CommittedVisibilityRequired ->
                [label <> ": committed visibility requires broad clean-state isolation"]
            _ -> []
    duplicateInvariantDiagnostics =
        duplicateValues metadata.ownedAcceptanceInvariants
            |> map (\invariant -> label <> ": duplicate mandatory invariant: " <> tshow invariant)
    duplicatePartialInvariantDiagnostics =
        duplicateValues metadata.partiallyCoveredAcceptanceInvariants
            |> map (\invariant -> label <> ": duplicate partial mandatory invariant: " <> tshow invariant)
    overlappingInvariantDiagnostics =
        metadata.ownedAcceptanceInvariants
            |> filter (`elem` metadata.partiallyCoveredAcceptanceInvariants)
            |> map (\invariant -> label <> ": invariant cannot be both complete and partial: " <> tshow invariant)
    duplicateMockDiagnostics =
        duplicateValues metadata.externalMocks
            |> map (\mock -> label <> ": duplicate external mock requirement: " <> tshow mock)

matchesTestLane :: TestLane -> SuiteMetadata -> Bool
matchesTestLane lane metadata =
    case lane of
        AllTests      -> True
        PureTests     -> suiteKind metadata == PureSuite
        DatabaseTests -> suiteKind metadata == DatabaseSuite

matchesFeedbackSelection :: FeedbackSelection -> SuiteMetadata -> Bool
matchesFeedbackSelection selection metadata =
    case selection of
        CompleteFeedback       -> True
        RoutineFeedbackOnly    -> metadata.feedbackLane == RoutineCorrectness
        AcceptanceFeedbackOnly -> metadata.feedbackLane == BroadAcceptance

duplicateValues :: Ord value => [value] -> [value]
duplicateValues values =
    values
        |> List.sort
        |> List.group
        |> filter ((> 1) . length)
        |> mapMaybe head
