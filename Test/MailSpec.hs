module Test.MailSpec where

import Generated.Types
import IHP.Mail
import IHP.Prelude
import IHP.Test.Mocking
import Network.Mail.Mime (Address (..))
import Test.Hspec
import Test.Support
import Web.Mail.Users.EmailVerification
import Web.Mail.Users.VenueInvitation
import Web.Mail.Users.VenueOnboardingInvitation

tests :: Spec
tests = beforeAll testContext do
    describe "Mail templates" do
        it "renders venue invitation recipient, sender, subject, and role-specific text" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Mail Invite Venue"
                invitation <- createVenueInvitationRecord venue Nothing "manager-invite@example.com" "manager"
                let mail =
                        VenueInvitationMail
                            { invitation = invitation
                            , inviteUrl = "https://app.example/NewUser?invitationId=test"
                            , fromAddress = "noreply@example.com"
                            }
                let ?context = ?mocking

                addressEmail (to mail) `shouldBe` "manager-invite@example.com"
                let ?mail = mail
                subject `shouldBe` "You're invited to join Bepis"
                addressName from `shouldBe` Just "Bepis"
                addressEmail from `shouldBe` "noreply@example.com"
                text mail `shouldBe` "You have been invited to join this venue as manager.\n\nAccept invitation:\nhttps://app.example/NewUser?invitationId=test\n\nThis invitation expires in 24 hours."

        it "maps venue invitation roles to stable user-facing labels" $ withContext do
            inviteRoleLabel ("venue_owner" :: Text) `shouldBe` "venue owner"
            inviteRoleLabel ("venue_admin" :: Text) `shouldBe` "venue admin"
            inviteRoleLabel ("manager" :: Text) `shouldBe` "manager"
            inviteRoleLabel ("worker" :: Text) `shouldBe` "worker"
            inviteRoleLabel ("unexpected" :: Text) `shouldBe` "worker"

        it "renders venue onboarding invitation mail with setup copy" $ withContext do
            withCleanDb do
                invitation <- createVenueOnboardingInvitationRecord Nothing "owner-invite@example.com"
                let mail =
                        VenueOnboardingInvitationMail
                            { invitation = invitation
                            , inviteUrl = "https://app.example/NewVenueOnboardingUser?invitationId=test"
                            , fromAddress = "support@example.com"
                            }
                let ?context = ?mocking

                addressEmail (to mail) `shouldBe` "owner-invite@example.com"
                let ?mail = mail
                subject `shouldBe` "Create your Bepis venue"
                addressName from `shouldBe` Just "Bepis"
                addressEmail from `shouldBe` "support@example.com"
                text mail `shouldBe` "You have been invited to create and configure a new venue in Bepis.\n\nCreate your account and set up your venue:\nhttps://app.example/NewVenueOnboardingUser?invitationId=test\n\nThis invitation expires in 24 hours."

        it "renders email verification mail to the account email with the verification URL" $ withContext do
            withCleanDb do
                user <- createUserRecord "verify-mail@example.com" "staff" False
                let mail =
                        EmailVerificationMail
                            { user = user
                            , verificationUrl = "https://app.example/VerifyEmail?token=test"
                            , fromAddress = "verify@example.com"
                            }
                let ?context = ?mocking

                addressEmail (to mail) `shouldBe` "verify-mail@example.com"
                let ?mail = mail
                subject `shouldBe` "Verify your email"
                addressName from `shouldBe` Just "Bepis"
                addressEmail from `shouldBe` "verify@example.com"
                text mail `shouldBe` "Verify your email to finish setting up your account:\n\nhttps://app.example/VerifyEmail?token=test"
