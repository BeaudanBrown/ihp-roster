module Test.VenueOnboardingInvitationSpec where

import Application.Helper.Controller (unsafeEnumFromText)
import Application.Helper.VenueOnboardingInvitation (venueOnboardingInvitationIsActive,
                                                     venueOnboardingInvitationUrl)
import Data.Time.Clock (addUTCTime, getCurrentTime)
import Generated.Types
import IHP.Prelude
import IHP.Test.Mocking (withContext)
import Test.Hspec
import Test.Support

tests :: Spec
tests = beforeAll testContext do
    describe "Venue onboarding invitation helper" do
        it "builds the onboarding signup URL from the invitation id" $ withContext do
            withCleanDb do
                invitation <- createVenueOnboardingInvitationRecord Nothing "owner-onboarding@example.com"
                let invitationId = get #id invitation :: Id VenueOnboardingInvitation

                venueOnboardingInvitationUrl "http://localhost:8000" invitation
                    `shouldBe` ("http://localhost:8000/NewVenueOnboardingUser?invitationId=" <> cs (show invitationId))

        it "treats pending unexpired invites as active" $ withContext do
            withCleanDb do
                now <- getCurrentTime
                invitation <-
                    createVenueOnboardingInvitationRecord Nothing "pending-owner@example.com"
                        >>= updateRecord . set #expiresAt (Just (addUTCTime 3600 now))

                venueOnboardingInvitationIsActive now invitation `shouldBe` True

        it "rejects accepted or expired invites" $ withContext do
            withCleanDb do
                now <- getCurrentTime
                acceptedInvitation <-
                    createVenueOnboardingInvitationRecord Nothing "accepted-owner@example.com"
                        >>= updateRecord
                            . set #status (unsafeEnumFromText @InvitationStatusEnum "accepted")
                            . set #acceptedAt (Just now)
                expiredInvitation <-
                    createVenueOnboardingInvitationRecord Nothing "expired-owner@example.com"
                        >>= updateRecord . set #expiresAt (Just (addUTCTime (-3600) now))

                venueOnboardingInvitationIsActive now acceptedInvitation `shouldBe` False
                venueOnboardingInvitationIsActive now expiredInvitation `shouldBe` False
