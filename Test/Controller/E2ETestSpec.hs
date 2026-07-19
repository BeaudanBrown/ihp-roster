module Test.Controller.E2ETestSpec where

import Application.Helper.Controller (passkeyVerifiedUserSessionKey)
import Config
import Control.Exception (finally)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import qualified System.Environment as Environment
import Test.Hspec
import Test.Support
import Web.Controller.E2ETest ()
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "E2ETestController" do
        it "marks the authenticated E2E session as passkey verified" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "E2E Venue"
                user <- createUserRecord "e2e-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                _ <- createTestPasskeyRecord user "Seeded E2E passkey"

                withE2ETestEnv do
                    withUserAndCurrentVenue user venue.id do
                        withRequestHeaders [("X-E2E-Test-Token", "test-token")] do
                            response <- callAction MarkE2EPasskeyVerifiedAction
                            response `responseStatusShouldBe` status200

                            verifiedUserId <- getSession @Text passkeyVerifiedUserSessionKey
                            verifiedUserId `shouldBe` Just (inputValue user.id)

        it "rejects requests when E2E mode is disabled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "E2E Venue"
                user <- createUserRecord "e2e-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                _ <- createTestPasskeyRecord user "Seeded E2E passkey"

                withTestEnv [("IHP_ROSTER_E2E", Nothing), ("E2E_TEST_TOKEN", Just "test-token")] do
                    response <- withUserAndCurrentVenue user venue.id do
                        withRequestHeaders [("X-E2E-Test-Token", "test-token")] do
                            callAction MarkE2EPasskeyVerifiedAction
                    response `responseStatusShouldBe` status404

        it "rejects requests with the wrong token" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "E2E Venue"
                user <- createUserRecord "e2e-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                _ <- createTestPasskeyRecord user "Seeded E2E passkey"

                withE2ETestEnv do
                    response <- withUserAndCurrentVenue user venue.id do
                        withRequestHeaders [("X-E2E-Test-Token", "wrong-token")] do
                            callAction MarkE2EPasskeyVerifiedAction
                    response `responseStatusShouldBe` status403

        it "rejects authenticated users without a passkey row" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "E2E Venue"
                user <- createUserRecord "e2e-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"

                withE2ETestEnv do
                    response <- withUserAndCurrentVenue user venue.id do
                        withRequestHeaders [("X-E2E-Test-Token", "test-token")] do
                            callAction MarkE2EPasskeyVerifiedAction
                    response `responseStatusShouldBe` status409

withE2ETestEnv :: IO a -> IO a
withE2ETestEnv =
    withTestEnv [("IHP_ROSTER_E2E", Just "1"), ("E2E_TEST_TOKEN", Just "test-token")]

withTestEnv :: [(String, Maybe String)] -> IO a -> IO a
withTestEnv vars action = do
    previous <- forM vars \(name, value) -> do
        oldValue <- Environment.lookupEnv name
        applyEnv name value
        pure (name, oldValue)
    action `finally` forM_ previous (uncurry applyEnv)

applyEnv :: String -> Maybe String -> IO ()
applyEnv name maybeValue =
    case maybeValue of
        Just value -> Environment.setEnv name value
        Nothing    -> Environment.unsetEnv name
