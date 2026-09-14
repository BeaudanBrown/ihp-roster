module Test.ApplicationErrorTransactionSpec
    ( tests
    ) where

import Application.Error.Domain (projectDomainError)
import Application.Error.Foundation (FoundationError (..))
import Application.Error.Transaction (withAppResultTransaction)
import Application.Error.Types (AppResult)
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
