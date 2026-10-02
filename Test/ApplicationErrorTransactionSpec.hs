module Test.ApplicationErrorTransactionSpec
    ( tests
    ) where

import Application.Error.Domain (projectDomainError)
import Application.Error.Foundation (FoundationError (..))
import Application.Error.Transaction (withAppResultTransaction)
import Application.Error.Types (AppResult)
import Application.Helper.LiveUpdate.DurablePublisher (withDurableLiveMutationOutcomeTransaction)
import qualified Control.Exception as Exception
import Data.Either (isLeft)
import qualified Data.Set as Set
import Generated.Types
import IHP.ControllerPrelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support

rollbackEmail :: Text
rollbackEmail = "typed-error-rollback@example.com"

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "typed application error transactions" do
        it "rolls back writes when the operation returns Left" $ withContext do
            withCleanDb do
                result :: AppResult () <- withAppResultTransaction do
                    _ <- createUserRecord rollbackEmail "staff" True
                    pure (Left (projectDomainError UnexpectedSynchronousError))

                result `shouldBe` Left (projectDomainError UnexpectedSynchronousError)
                persisted <- query @User
                    |> filterWhere (#email, rollbackEmail)
                    |> fetchCount
                persisted `shouldBe` 0

        it "rolls back a nested typed Left while preserving the caller's earlier writes" $ withContext do
            withCleanDb do
                withTransaction do
                    _ <- createUserRecord "outer-survivor@example.test" "staff" True
                    result :: AppResult () <- withAppResultTransaction do
                        Right () <- withAppResultTransaction do
                            _ <- createUserRecord rollbackEmail "staff" True
                            pure (Right ())
                        pure (Left (projectDomainError UnexpectedSynchronousError))
                    result `shouldBe` Left (projectDomainError UnexpectedSynchronousError)
                    query @User |> filterWhere (#email, rollbackEmail) |> fetchCount >>= (`shouldBe` 0)
                query @User |> filterWhere (#email, "outer-survivor@example.test") |> fetchCount >>= (`shouldBe` 1)
                query @User |> filterWhere (#email, rollbackEmail) |> fetchCount >>= (`shouldBe` 0)

        it "rolls back a successful inner operation if durable publication fails" $ withContext do
            withCleanDb do
                result <- Exception.try @Exception.SomeException $
                    withDurableLiveMutationOutcomeTransaction (const (Just ("", Set.empty))) do
                        withAppResultTransaction do
                            _ <- createUserRecord rollbackEmail "staff" True
                            pure (Right ())
                result `shouldSatisfy` isLeft
                query @User |> filterWhere (#email, rollbackEmail) |> fetchCount >>= (`shouldBe` 0)

        it "propagates unexpected inner exceptions and rolls back the outer transaction" $ withContext do
            withCleanDb do
                result <- Exception.try @Exception.IOException $ withTransaction do
                    _ <- createUserRecord rollbackEmail "staff" True
                    withAppResultTransaction @() do
                        Exception.throwIO (userError "fixture failure")
                result `shouldSatisfy` isLeft
                query @User |> filterWhere (#email, rollbackEmail) |> fetchCount >>= (`shouldBe` 0)
