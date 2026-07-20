module Test.SuiteMetadataSpec where

import qualified Data.Text as Text
import IHP.Prelude
import Test.Hspec
import Test.Suite.Metadata

tests :: Spec
tests = do
    describe "suite metadata validation" do
        it "rejects committed visibility without broad clean-state isolation" do
            let invalid =
                    suiteMetadata "invalid-visibility" 5
                        (DatabaseIsolation CleanStateNotRequired CommittedVisibilityRequired)
                        RoutineCorrectness
                        TestInfrastructure
                        FixtureFree
                        []
                        []

            validateSuiteMetadata invalid
                `shouldContain` ["invalid-visibility: committed visibility requires broad clean-state isolation"]

        it "diagnoses duplicate labels and mandatory invariants without owners" do
            let duplicated = pureMetadata "duplicate" RoutineCorrectness [A1]
                diagnostics = validateSuiteRegistry [duplicated, duplicated]

            diagnostics `shouldSatisfy` any (Text.isInfixOf "duplicate suite label: duplicate")
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

        it "reports omitted owners and known partial acceptance coverage" do
            let routineOwner = pureMetadata "routine-owner" RoutineCorrectness [A1, A2]
                acceptanceOwner = databaseMetadata "acceptance-owner" BroadAcceptance [A2]
                partialOwner =
                    databaseMetadata "partial-owner" BroadAcceptance []
                        |> withPartialAcceptanceCoverage [B6]
                registry = [routineOwner, acceptanceOwner, partialOwner]
                selected = selectSuiteMetadata AllTests RoutineFeedbackOnly registry
                excluded = excludedAcceptanceInvariants registry selected

            excluded `shouldNotContain` [A1]
            excluded `shouldContain` [A2]
            excluded `shouldContain` [B6]
            incompleteAcceptanceInvariants registry `shouldContain` [B6]
            acceptanceEvidenceShape T4 `shouldBe` ComposedEvidence

pureMetadata :: String -> FeedbackLane -> [AcceptanceInvariant] -> SuiteMetadata
pureMetadata label feedback invariants =
    suiteMetadata label 1 PureIsolation feedback TestInfrastructure FixtureFree [] invariants

databaseMetadata :: String -> FeedbackLane -> [AcceptanceInvariant] -> SuiteMetadata
databaseMetadata label feedback invariants =
    suiteMetadata label 1
        (DatabaseIsolation BroadCleanStateRequired CommittedVisibilityNotRequired)
        feedback
        TestInfrastructure
        SmallFixture
        []
        invariants
