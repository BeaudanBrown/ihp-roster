module Test.MailSpec where

import Data.Text (isInfixOf)
import Generated.Types
import IHP.ControllerPrelude (createRecord, getCurrentTime, newRecord, set,
                              unpackId, (|>))
import IHP.Mail
import IHP.Prelude
import IHP.Test.Mocking
import Network.Mail.Mime (Address (..))
import Test.Hspec
import Test.Support
import Web.Mail.Billing.Notification
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

        it "renders staff adoption invitation mail with claim-profile copy and the existing invite URL" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Mail Adoption Invite Venue"
                staff <- createStaffRecord venue Nothing "Mail" "Trial"
                invitation <- createVenueInvitationRecord venue Nothing "trial-mail-invite@example.com" "worker"
                    >>= updateRecord . set #staffId (Just staff.id)
                let mail =
                        VenueInvitationMail
                            { invitation = invitation
                            , inviteUrl = "https://app.example/NewUser?invitationId=trial"
                            , fromAddress = "noreply@example.com"
                            }
                let ?context = ?mocking
                let ?mail = mail

                addressEmail (to mail) `shouldBe` "trial-mail-invite@example.com"
                text mail `shouldBe` "You have been invited to claim your Bepis staff profile and create your account.\n\nAccept invitation:\nhttps://app.example/NewUser?invitationId=trial\n\nThis invitation expires in 24 hours."

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

        it "renders billing notifications without Stripe raw payloads" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Mail Venue"
                user <- createUserRecord "billing-mail@example.com" "staff" True
                now <- getCurrentTime
                billingEvent <-
                    newRecord @BillingEvent
                        |> set #stripeEventId "evt_billing_mail"
                        |> set #eventType "invoice.payment_failed"
                        |> set #venueId (Just (unpackId venue.id))
                        |> set #status "processed"
                        |> set #processedAt (Just now)
                        |> createRecord
                let mail =
                        BillingNotificationMail
                            { recipient = user
                            , venue = venue
                            , billingEvent = billingEvent
                            , notificationKind = "payment_failed"
                            , billingUrl = "https://app.example/Billing"
                            , fromAddress = "billing@example.com"
                            }
                let ?context = ?mocking

                addressEmail (to mail) `shouldBe` "billing-mail@example.com"
                let ?mail = mail
                subject `shouldBe` "Billing needs attention"
                addressEmail from `shouldBe` "billing@example.com"
                text mail `shouldSatisfy` isInfixOf "Billing needs attention for Billing Mail Venue."
                text mail `shouldSatisfy` isInfixOf "Event: invoice.payment_failed"
                text mail `shouldSatisfy` isInfixOf "https://app.example/Billing"
