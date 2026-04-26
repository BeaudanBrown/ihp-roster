module Test.Controller.PasskeysSpec where

import Application.Helper.Controller (currentVenueSessionKey,
                                      passkeyVerifiedUserSessionKey)
import Config
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig
import IHP.HaskellSupport
import IHP.Prelude
import qualified Data.ByteString.Char8 as ByteString
import qualified Data.Serialize as Serialize
import qualified IHP.LoginSupport.Helper.Controller as LoginSupport
import IHP.Test.Mocking
import qualified Network.HTTP.Types as HTTP
import Network.HTTP.Types.Status
import Network.Wai (responseHeaders)
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

        it "requires venue admins without passkeys to finish security setup before operational pages" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Mandatory Admin Passkey Venue"
                user <- createUserRecord "mandatory-admin-passkey@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction RosterWeeksAction

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/EditProfile?section=security"

        it "does not require workers without passkeys to finish passkey setup before roster access" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Worker Optional Passkey Venue"
                user <- createUserRecord "worker-passkey-optional@example.com" "staff" True
                _ <- createVenueMembershipRecord venue user "worker"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction RosterWeeksAction

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response)
                    `shouldSatisfy` maybe False ("http://localhost/ShowRosterWeek?weekOffset=" `ByteString.isPrefixOf`)

        it "requires passkey verification before venue admin pages when a passkey exists" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Admin Step Up Venue"
                user <- createUserRecord "admin-step-up@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                _ <- createTestPasskeyRecord user "Admin security key"

                withUserAndCurrentVenue user venue.id do
                    response <- callAction AdminAction
                    response `responseStatusShouldBe` status302
                    lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/PasskeyStepUp"

                    stepUpResponse <- callAction PasskeyStepUpAction
                    stepUpResponse `responseStatusShouldBe` status200
                    stepUpResponse `responseBodyShouldContain` "Verify with a passkey"
                    stepUpResponse `responseBodyShouldContain` "data-begin-url=\"/BeginPasskeyStepUpAuthentication\""
                    stepUpResponse `responseBodyShouldContain` "data-finish-url=\"/FinishPasskeyStepUpAuthentication\""
                    stepUpResponse `responseBodyShouldContain` "data-success-redirect=\"/RosterWeeks\""

        it "allows venue admin pages after the session has passkey verification" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Verified Admin Venue"
                user <- createUserRecord "verified-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                _ <- createTestPasskeyRecord user "Admin passkey"

                response <- withSessionValues
                    [ (cs (LoginSupport.sessionKey @User), Serialize.encode user.id)
                    , (currentVenueSessionKey, Serialize.encode venue.id)
                    , (passkeyVerifiedUserSessionKey, Serialize.encode (inputValue user.id :: Text))
                    ]
                    do
                        callAction AdminAction

                response `responseStatusShouldBe` status200

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

        it "does not let a venue admin delete their last passkey" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Passkey Last Admin Venue"
                user <- createUserRecord "passkey-last-admin@example.com" "admin" True
                _ <- createVenueMembershipRecord venue user "venue_admin"
                passkey <- createTestPasskeyRecord user "Last admin passkey"

                response <- withUserAndCurrentVenue user venue.id do
                    callAction (DeletePasskeyAction passkey.id)

                response `responseStatusShouldBe` status302
                lookup HTTP.hLocation (responseHeaders response) `shouldBe` Just "http://localhost/EditProfile?section=security"
                stillExists <- query @Passkey
                    |> filterWhere (#id, passkey.id)
                    |> fetchExists
                stillExists `shouldBe` True
