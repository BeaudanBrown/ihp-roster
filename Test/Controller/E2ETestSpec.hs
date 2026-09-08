module Test.Controller.E2ETestSpec where

import Application.Helper.Controller (passkeyVerifiedUserSessionKey)
import Config
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.Prelude
import IHP.Hspec
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Test.Hspec
import Test.Support
import Test.Support.Environment (withEnvironmentVariables)
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
                _ <- createVenueMembershipRecord venue user VenueAdmin
                _ <- createTestPasskeyRecord user "Seeded E2E passkey"

                withE2ETestEnv do
                    withUserAndCurrentVenue user venue.id do
                        withRequestHeaders [("X-E2E-Test-Token", "test-token")] do
                            response <- callAction MarkE2EPasskeyVerifiedAction
                            response `responseStatusShouldBe` status200

                            verifiedUserId <- getSession @Text passkeyVerifiedUserSessionKey
                            verifiedUserId `shouldBe` Just (inputValue user.id)

                        withRequestHeaders
                            [ ("X-E2E-Test-Token", "test-token")
                            , ("X-E2E-Passkey-Verified", "false")
                            ]
                            do
                                response <- callAction MarkE2EPasskeyVerifiedAction
                                response `responseStatusShouldBe` status200
                                getSession @Text passkeyVerifiedUserSessionKey `shouldReturn` Nothing

        it "rejects requests when E2E mode is disabled" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "E2E Venue"
                user <- createUserRecord "e2e-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user VenueAdmin
                _ <- createTestPasskeyRecord user "Seeded E2E passkey"

                withEnvironmentVariables [("IHP_ROSTER_E2E", Nothing), ("E2E_TEST_TOKEN", Just "test-token")] do
                    response <- withUserAndCurrentVenue user venue.id do
                        withRequestHeaders [("X-E2E-Test-Token", "test-token")] do
                            callAction MarkE2EPasskeyVerifiedAction
                    response `responseStatusShouldBe` status404

        it "rejects requests with the wrong token" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "E2E Venue"
                user <- createUserRecord "e2e-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user VenueAdmin
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
                _ <- createVenueMembershipRecord venue user VenueAdmin

                withE2ETestEnv do
                    response <- withUserAndCurrentVenue user venue.id do
                        withRequestHeaders [("X-E2E-Test-Token", "test-token")] do
                            callAction MarkE2EPasskeyVerifiedAction
                    response `responseStatusShouldBe` status409

withE2ETestEnv :: IO a -> IO a
withE2ETestEnv =
    withEnvironmentVariables [("IHP_ROSTER_E2E", Just "1"), ("E2E_TEST_TOKEN", Just "test-token")]
