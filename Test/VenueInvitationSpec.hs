module Test.VenueInvitationSpec where

import Application.Helper.VenueInvitation (venueInvitationUrl)
import Generated.Types
import IHP.Prelude
import IHP.Test.Mocking (withContext)
import Test.Hspec
import Test.Support

tests :: Spec
tests = beforeAll testContext do
    describe "Venue invitation helper" do
        it "builds the signup URL from the invitation id" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invite URL Venue"
                invitation <- createVenueInvitationRecord venue Nothing "invite-url@example.com" "manager"
                let invitationId = get #id invitation :: Id VenueInvitation

                venueInvitationUrl "http://localhost:8000" invitation
                    `shouldBe` ("http://localhost:8000/NewUser?invitationId=" <> cs (show invitationId))
