module Test.ResetIsolationSpec where

import Control.Exception (ErrorCall, IOException, SomeException, displayException, try)
import Data.Either (isLeft)
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (unsafeSqlExecDiscardResult, unsafeSqlQueryScalar)
import IHP.Test.Mocking (withContext)
import System.IO.Error (ioeGetErrorString)
import Test.Hspec
import Test.Support

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "database reset isolation" do
        it "detects a captured IO action escaping rollback and removes its committed writes with canonical reset" $ withContext do
            withCleanDb do
                -- This is deliberately IO User, like withCleanDb's IO a argument:
                -- its model context is captured before entering withTransaction.
                let captured :: IO User
                    captured = createUserRecord "captured-reset@example.com" "staff" True
                result :: Either IOException () <- try do
                    withTransaction do
                        _ <- captured
                        ioError (userError "rollback probe")
                assertProbeFailure result
                query @User |> fetchCount >>= (`shouldBe` 1)
                resetDatabase
                query @User |> fetchCount >>= (`shouldBe` 0)

        it "rolls back bound writes while an independent observer sees only committed rows" $ withContext do
            withCleanDb do
                _ <- createUserRecord "committed-reset@example.com" "staff" True
                result :: Either IOException () <- try do
                    withTransaction do
                        _ <- createUserRecord "bound-reset@example.com" "staff" True
                        query @User |> fetchCount >>= (`shouldBe` 2)
                        observed <- withDatabaseTestContext (withContext (query @User |> fetchCount))
                        observed `shouldBe` 1
                        ioError (userError "rollback probe")
                assertProbeFailure result
                query @User |> fetchCount >>= (`shouldBe` 1)
                _ <- createUserRecord "after-rollback@example.com" "staff" True
                query @User |> fetchCount >>= (`shouldBe` 2)

        it "rejects the existing nested venue fixture transaction instead of pretending it joined an outer transaction" $ withContext do
            withCleanDb do
                result :: Either ErrorCall Venue <- try do
                    withTransaction (createVenueWithConfig "Nested rollback probe")
                case result of
                    Left exception -> cs (displayException exception) `shouldSatisfy` Text.isInfixOf "Nested transactions are not supported"
                    Right _ -> expectationFailure "nested fixture transaction unexpectedly succeeded"
                query @Venue |> fetchCount >>= (`shouldBe` 0)
                _ <- createVenueWithConfig "Normal fixture after failure"
                query @Venue |> fetchCount >>= (`shouldBe` 1)

        it "does not confuse row rollback or canonical reset with rewinding an unowned sequence" $ withContext do
            withCleanDb do
                before <- nextInvalidationSequence
                result :: Either IOException () <- try do
                    withTransaction do
                        nextInvalidationSequence `shouldReturn` (before + 1)
                        ioError (userError "rollback probe")
                assertProbeFailure result
                nextInvalidationSequence `shouldReturn` (before + 2)
                -- Current Schema.sql does not declare OWNED BY for
                -- this sequence. RESTART IDENTITY applies only to owned ones.
                resetDatabase
                nextInvalidationSequence `shouldReturn` (before + 3)

        it "rolls back test-only DDL together with the bound transaction" $ withContext do
            withCleanDb do
                probeTableExists `shouldReturn` False
                result :: Either IOException () <- try do
                    withTransaction do
                        unsafeSqlExecDiscardResult "CREATE TABLE bepis_reset_rollback_probe (id INT PRIMARY KEY)" ()
                        probeTableExists `shouldReturn` True
                        ioError (userError "rollback probe")
                assertProbeFailure result
                probeTableExists `shouldReturn` False

        it "cannot continue ordinary queries after a caught constraint failure without a savepoint" $ withContext do
            withCleanDb do
                result :: Either IOException () <- try do
                    withTransaction do
                        _ <- createUserRecord "constraint-reset@example.com" "staff" True
                        duplicate :: Either SomeException User <- try (createUserRecord "constraint-reset@example.com" "staff" True)
                        duplicate `shouldSatisfy` isLeft
                        aborted :: Either SomeException Int <- try (query @User |> fetchCount)
                        case aborted of
                            Left exception -> cs (displayException exception) `shouldSatisfy` Text.isInfixOf "current transaction is aborted"
                            Right _ -> expectationFailure "constraint failure did not abort the bound transaction"
                        ioError (userError "rollback probe")
                assertProbeFailure result
                query @User |> fetchCount >>= (`shouldBe` 0)

-- Raw SQL is limited to PostgreSQL sequence/DDL semantics under investigation;
-- application row observations above use the normal model API. The probe table
-- exists only inside a rolled-back transaction in the disposable Hspec database.
nextInvalidationSequence :: (?modelContext :: ModelContext) => IO Int
nextInvalidationSequence =
    unsafeSqlQueryScalar "SELECT nextval('live_invalidation_events_sequence_number_seq')::INT4" ()

probeTableExists :: (?modelContext :: ModelContext) => IO Bool
probeTableExists =
    unsafeSqlQueryScalar "SELECT to_regclass('bepis_reset_rollback_probe') IS NOT NULL" ()

assertProbeFailure :: Either IOException () -> Expectation
assertProbeFailure result =
    fmap ioeGetErrorString (either Just (const Nothing) result)
        `shouldBe` Just "rollback probe"
