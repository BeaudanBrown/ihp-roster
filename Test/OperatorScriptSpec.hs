module Test.OperatorScriptSpec
    ( tests
    ) where

import Application.Fixture.DevFixtures.Deterministic (deterministicChoice)
import Application.Fixture.DevFixtures.Payroll (applyDevTimesheetBoundaries)
import Application.Fixture.Error
import Application.Operator.Error
import qualified Application.Script.BootstrapAccount as Bootstrap
import qualified Application.Script.LiveInvalidationOutboxPrune as OutboxPrune
import qualified Application.Script.ProfileLiveInvalidation as LiveProfile
import qualified Application.Script.SeedDev as SeedDev
import qualified Application.Script.SeedProfile as SeedProfile
import qualified Application.Script.XeroPayItemProbe as XeroProbe
import Data.List.NonEmpty (NonEmpty (..))
import Data.Time.Calendar (fromGregorian)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude (newRecord, set, (|>))
import IHP.Prelude
import Test.Hspec

spec :: Spec
spec = do
    describe "operator script input" do
        it "returns focused typed argument causes" do
            SeedDev.parseSeedDevArgs ["--scenario=unknown"]
                `shouldBe` Left (InvalidScriptArgument "unknown seed scenario: --scenario=unknown")
            SeedProfile.parseProfileSeedArgs ["--venues=0"]
                `shouldBe` Left (InvalidScriptArgument "--venues= value must be greater than zero")
            LiveProfile.parseProfileLiveInvalidationArgs ["--scopes="]
                `shouldBe` Left (InvalidScriptArgument "--scopes requires at least one value")
            XeroProbe.parseOptions XeroProbe.defaultProbeOptions ["--surprise"]
                `shouldBe` Left (InvalidScriptArgument "unknown Xero pay-item probe option: --surprise")
            XeroProbe.validateProbeOptions XeroProbe.defaultProbeOptions
                `shouldBe` Left "No probe action selected; use --help for usage."

        it "returns focused typed configuration causes" do
            Bootstrap.requireSecretValue [] "BOOTSTRAP_ACCOUNT_EMAIL"
                `shouldBe` Left (InvalidScriptConfiguration "missing required bootstrap secret key BOOTSTRAP_ACCOUNT_EMAIL")
            Bootstrap.unquote "'" `shouldBe` "'"
            Bootstrap.unquote "'secret'" `shouldBe` "secret"
            OutboxPrune.parsePositiveEnvironmentInteger "RETENTION" 7 (Just "zero")
                `shouldBe` Left (InvalidScriptConfiguration "RETENTION must be a positive integer")
            renderScriptError (InvalidScriptArgument "bad flag")
                `shouldBe` "Invalid argument: bad flag"
            tryScriptIO "profile output" (ioError (userError "technical path details") :: IO ())
                `shouldReturn` Left (InvalidScriptConfiguration "profile output failed")

    describe "fixture composition" do
        it "identifies missing values, collections, and references" do
            fixtureRequired (MissingFixtureValue "break start") (Nothing :: Maybe Int)
                `shouldBe` Left (MissingFixtureValue "break start")
            fixtureElementAt "staff" 2 [10 :: Int]
                `shouldBe` Left (MissingFixtureReference "staff at index 2")
            renderFixtureError (EmptyFixtureCollection "manager profiles")
                `shouldBe` "empty fixture collection: manager profiles"

        it "returns a typed cause for incomplete break composition" do
            let entry = newRecord @TimesheetEntry |> set #timezone "Australia/Melbourne"
            applyDevTimesheetBoundaries
                (fromGregorian 2026 8 25)
                (TimeOfDay 9 0 0)
                (TimeOfDay 17 0 0)
                True
                Nothing
                (Just (TimeOfDay 12 30 0))
                entry
                `shouldBe` Left (MissingFixtureValue "seeded break start")

        it "selects deterministic non-empty catalogs without partial indexing" do
            let catalog :: NonEmpty String
                catalog = "first" :| ["second", "third"]
            deterministicChoice 42 [1, 2, 3] catalog
                `shouldBe` deterministicChoice 42 [1, 2, 3] catalog

        it "proves the profile clock set across Melbourne DST transition days" do
            let clockSet =
                    [ TimeOfDay 6 30 0
                    , TimeOfDay 7 0 0
                    , TimeOfDay 9 0 0
                    , TimeOfDay 11 0 0
                    , TimeOfDay 11 30 0
                    , TimeOfDay 12 0 0
                    , TimeOfDay 12 30 0
                    , TimeOfDay 16 30 0
                    , TimeOfDay 17 0 0
                    , TimeOfDay 17 30 0
                    , TimeOfDay 22 30 0
                    , TimeOfDay 23 0 0
                    ]
                transitionDays = [fromGregorian 2026 4 5, fromGregorian 2026 10 4]
            map (uncurry SeedProfile.instantText) [(day, clock) | day <- transitionDays, clock <- clockSet]
                `shouldSatisfy` all (not . null)

tests :: Spec
tests = spec
