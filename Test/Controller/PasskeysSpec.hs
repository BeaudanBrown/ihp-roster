module Test.Controller.PasskeysSpec where

import Config
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import IHP.Test.Mocking
import Network.HTTP.Types.Status
import Test.Hspec
import Test.Support
import Web.FrontController ()
import Web.Routes
import Web.Types

tests :: Spec
tests = beforeAll testContext do
    describe "PasskeysController" do
        it "renders passkey login entry points on the login form" $ withContext do
            response <- callAction NewSessionAction

            response `responseStatusShouldBe` status200
            response `responseBodyShouldContain` "Sign in with a passkey"
            response `responseBodyShouldContain` "data-begin-url=\"/BeginPasskeyAuthentication\""
            response `responseBodyShouldContain` "data-finish-url=\"/FinishPasskeyAuthentication\""

        it "requires an authenticated user to begin passkey registration" $ withContext do
            response <- callAction BeginPasskeyRegistrationAction

            response `responseStatusShouldBe` status302

        it "renders passkey management on the security profile section" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Passkey Profile Venue"
                user <- createUserRecord "passkey-profile@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams EditProfileAction [("section", "security")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Sign-In Methods"
                response `responseBodyShouldContain` "Add passkey"
                response `responseBodyShouldContain` "No passkeys registered yet."
                response `responseBodyShouldContain` "data-begin-url=\"/BeginPasskeyRegistration\""
                response `responseBodyShouldContain` "data-finish-url=\"/FinishPasskeyRegistration\""

        it "lists existing passkeys on the security profile section" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Passkey List Venue"
                user <- createUserRecord "passkey-list@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                _ <- createTestPasskeyRecord user "Phone passkey"

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams EditProfileAction [("section", "security")]

                response `responseStatusShouldBe` status200
                response `responseBodyShouldContain` "Phone passkey"
                response `responseBodyShouldContain` "Delete"

        it "renames a user's passkey and normalizes blank names" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Passkey Rename Venue"
                user <- createUserRecord "passkey-rename@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                passkey <- createTestPasskeyRecord user "Original"

                response <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams (UpdatePasskeyNameAction passkey.id) [("name", "  Laptop  ")]

                response `responseStatusShouldBe` status200
                renamedPasskey <- fetch passkey.id
                renamedPasskey.name `shouldBe` "Laptop"

                blankResponse <- withUserAndCurrentVenue user venue.id do
                    callActionWithParams (UpdatePasskeyNameAction passkey.id) [("name", "   ")]

                blankResponse `responseStatusShouldBe` status200
                defaultedPasskey <- fetch passkey.id
                defaultedPasskey.name `shouldBe` "Passkey"

        it "does not let a user rename another user's passkey" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Passkey Access Venue"
                owner <- createUserRecord "passkey-owner@example.com" "staff" True
                other <- createUserRecord "passkey-other@example.com" "staff" True
                _ <- createVenueMembershipRecord venue owner "worker"
                _ <- createVenueMembershipRecord venue other "worker"
                passkey <- createTestPasskeyRecord owner "Owner passkey"

                response <- withUserAndCurrentVenue other venue.id do
                    callActionWithParams (UpdatePasskeyNameAction passkey.id) [("name", "Compromised")]

                response `responseStatusShouldBe` status403
                unchangedPasskey <- fetch passkey.id
                unchangedPasskey.name `shouldBe` "Owner passkey"

        it "deletes a user's own passkey" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Passkey Delete Venue"
                user <- createUserRecord "passkey-delete@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"
                passkey <- createTestPasskeyRecord user "Delete me"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (DeletePasskeyAction passkey.id)

                response `responseStatusShouldBe` status302
                stillExists <- query @Passkey
                    |> filterWhere (#id, passkey.id)
                    |> fetchExists
                stillExists `shouldBe` False
