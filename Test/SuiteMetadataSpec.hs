module Test.SuiteMetadataSpec where

import qualified Data.Text as Text
import IHP.Prelude
import Test.Hspec
import Test.Suite.Metadata
import Test.Suite.Selection (hspecArgumentsMayFilter)

tests :: Spec
tests = do
    describe "suite metadata validation" do
        it "rejects committed visibility without broad clean-state isolation" do
            let invalid =
                    suiteMetadataFromDefinition
                        (DatabaseIsolation CleanStateNotRequired CommittedVisibilityRequired)
                        (metadataDefinition "invalid-visibility" RoutineCorrectness FixtureFree [])

            validateSuiteMetadata invalid
                `shouldContain` ["invalid-visibility: committed visibility requires broad clean-state isolation"]

        it "diagnoses duplicate labels, missing families, and mandatory invariants without owners" do
            let duplicated = pureMetadata "duplicate" RoutineCorrectness [A1]
                diagnostics = validateSuiteRegistry [duplicated, duplicated]

            diagnostics `shouldSatisfy` any (Text.isInfixOf "duplicate suite label: duplicate")
            diagnostics `shouldSatisfy` any (Text.isInfixOf "mandatory invariant family has no suite: Billing")
            diagnostics `shouldSatisfy` any (Text.isInfixOf "mandatory complete invariant has no owning suite: A2")

    describe "suite metadata selection" do
        it "selects database and feedback dimensions independently" do
            let registry =
                    [ pureMetadata "pure-routine" RoutineCorrectness [A1]
                    , databaseMetadata "database-routine" RoutineCorrectness [A2]
                    , databaseMetadata "database-acceptance" BroadAcceptance [A3]
                    ]
                selected = selectSuiteMetadata DatabaseTests RoutineFeedbackOnly registry

            map suiteLabel selected `shouldBe` ["database-routine"]
            hspecArgumentsMayFilter ["--match", "FeedbackController"] `shouldBe` True
            hspecArgumentsMayFilter ["--match=FeedbackController"] `shouldBe` True
            hspecArgumentsMayFilter ["--rerun-all-on-success"] `shouldBe` True
            hspecArgumentsMayFilter ["--format=progress", "--no-color"] `shouldBe` False

        it "reports omitted owners while treating the completed billing lifecycle as complete evidence" do
            let routineOwner = pureMetadata "routine-owner" RoutineCorrectness [A1, A2]
                acceptanceOwner = databaseMetadata "acceptance-owner" BroadAcceptance [A2, B6]
                registry = [routineOwner, acceptanceOwner]
                selected = selectSuiteMetadata AllTests RoutineFeedbackOnly registry
                excluded = excludedAcceptanceInvariants registry selected

            excluded `shouldNotContain` [A1]
            excluded `shouldContain` [A2]
            excluded `shouldContain` [B6]
            incompleteAcceptanceInvariants registry `shouldNotContain` [B6]
            acceptanceEvidenceShape B6 `shouldBe` CompleteEvidence
            acceptanceEvidenceShape T4 `shouldBe` ComposedEvidence

pureMetadata :: String -> FeedbackLane -> [AcceptanceInvariant] -> SuiteMetadata
pureMetadata label feedback invariants =
    suiteMetadataFromDefinition PureIsolation (metadataDefinition label feedback FixtureFree invariants)

databaseMetadata :: String -> FeedbackLane -> [AcceptanceInvariant] -> SuiteMetadata
databaseMetadata label feedback invariants =
    suiteMetadataFromDefinition
        (DatabaseIsolation BroadCleanStateRequired CommittedVisibilityNotRequired)
        (metadataDefinition label feedback SmallFixture invariants)

metadataDefinition :: String -> FeedbackLane -> FixtureCost -> [AcceptanceInvariant] -> SuiteDefinition
metadataDefinition label feedback fixtures invariants =
    SuiteDefinition
        { definitionLabel = label
        , definitionEstimatedRuntimeSeconds = 1
        , definitionFeedbackLane = feedback
        , definitionInvariantFamily = TestInfrastructure
        , definitionFixtureCost = fixtures
        , definitionExternalMocks = []
        , definitionOwnedInvariants = invariants
        , definitionPartialInvariants = []
        }
