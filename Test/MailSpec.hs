module Test.MailSpec where

import Application.Helper.Mail
import Control.Exception (bracket)
import Data.Text (isInfixOf)
import Data.Time.Calendar (fromGregorian)
import Generated.Types
import IHP.ControllerPrelude (createRecord, getCurrentTime, newRecord, set,
                              unpackId, (|>))
import IHP.Mail
import IHP.Prelude
import IHP.Test.Mocking
import Network.Mail.Mime (Address (..))
import qualified System.Environment as Environment
import Test.Hspec
import Test.Support
import Web.Mail.Billing.Notification
import Web.Mail.StaffDocuments.RsaReminder
import Web.Mail.Users.EmailVerification
import Web.Mail.Users.PasskeySetupLink
import Web.Mail.Users.VenueInvitation
import Web.Mail.Users.VenueOnboardingInvitation

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Mail templates" do
        it "renders venue invitation recipient, sender, subject, and role-specific text" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Mail Invite Venue"
                invitation <- createVenueInvitationRecord venue Nothing "manager-invite@example.com" "manager"
                let mail =
                        VenueInvitationMail
                            { invitation = invitation
                            , venue = venue
                            , inviteUrl = "https://app.example/NewUser?invitationId=test"
                            , fromAddress = "noreply@example.com"
                            , replyToAddress = "support@example.com"
                            , supportEmail = "support@example.com"
                            }
                let ?context = ?mocking

                addressEmail (to mail) `shouldBe` "manager-invite@example.com"
                let ?mail = mail
                subject `shouldBe` "You're invited to join Mail Invite Venue on Bepis"
                addressName from `shouldBe` Just "Bepis"
                addressEmail from `shouldBe` "noreply@example.com"
                fmap addressEmail (replyTo mail) `shouldBe` Just "support@example.com"
                text mail `shouldSatisfy` isInfixOf "You’ve been invited to join Mail Invite Venue on Bepis as manager."
                text mail `shouldSatisfy` isInfixOf "Bepis helps venues manage rosters, availability, timesheets, and staff details."
                text mail `shouldSatisfy` isInfixOf "https://app.example/NewUser?invitationId=test"
                text mail `shouldSatisfy` isInfixOf "contact support@example.com."

        it "renders staff adoption invitation mail with claim-profile copy and the existing invite URL" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Mail Adoption Invite Venue"
                staff <- createStaffRecord venue Nothing "Mail" "Trial"
                invitation <- createVenueInvitationRecord venue Nothing "trial-mail-invite@example.com" "worker"
                    >>= updateRecord . set #staffId (Just staff.id)
                let mail =
                        VenueInvitationMail
                            { invitation = invitation
                            , venue = venue
                            , inviteUrl = "https://app.example/NewUser?invitationId=trial"
                            , fromAddress = "noreply@example.com"
                            , replyToAddress = "support@example.com"
                            , supportEmail = "support@example.com"
                            }
                let ?context = ?mocking
                let ?mail = mail

                addressEmail (to mail) `shouldBe` "trial-mail-invite@example.com"
                text mail `shouldSatisfy` isInfixOf "You’ve been invited to claim your Bepis staff profile for Mail Adoption Invite Venue and create your account."
                text mail `shouldSatisfy` isInfixOf "https://app.example/NewUser?invitationId=trial"

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
                            , replyToAddress = "support@example.com"
                            , supportEmail = "support@example.com"
                            }
                let ?context = ?mocking

                addressEmail (to mail) `shouldBe` "owner-invite@example.com"
                let ?mail = mail
                subject `shouldBe` "Create your Bepis venue"
                addressName from `shouldBe` Just "Bepis"
                addressEmail from `shouldBe` "support@example.com"
                fmap addressEmail (replyTo mail) `shouldBe` Just "support@example.com"
                text mail `shouldSatisfy` isInfixOf "You’ve been invited to create and configure a venue in Bepis."
                text mail `shouldSatisfy` isInfixOf "https://app.example/NewVenueOnboardingUser?invitationId=test"
                text mail `shouldSatisfy` isInfixOf "contact support@example.com."

        it "renders email verification mail to the account email with the verification URL" $ withContext do
            withCleanDb do
                user <- createUserRecord "verify-mail@example.com" "staff" False
                let mail =
                        EmailVerificationMail
                            { user = user
                            , verificationUrl = "https://app.example/VerifyEmail?token=test"
                            , fromAddress = "verify@example.com"
                            , replyToAddress = "support@example.com"
                            , supportEmail = "support@example.com"
                            }
                let ?context = ?mocking

                addressEmail (to mail) `shouldBe` "verify-mail@example.com"
                let ?mail = mail
                subject `shouldBe` "Verify your email"
                addressName from `shouldBe` Just "Bepis"
                addressEmail from `shouldBe` "verify@example.com"
                fmap addressEmail (replyTo mail) `shouldBe` Just "support@example.com"
                text mail `shouldSatisfy` isInfixOf "Verify your email to finish setting up your Bepis account:"
                text mail `shouldSatisfy` isInfixOf "https://app.example/VerifyEmail?token=test"
                text mail `shouldSatisfy` isInfixOf "contact support@example.com."

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
                            , replyToAddress = "support@example.com"
                            , supportEmail = "support@example.com"
                            }
                let ?context = ?mocking

                addressEmail (to mail) `shouldBe` "billing-mail@example.com"
                let ?mail = mail
                subject `shouldBe` "Billing needs attention"
                addressEmail from `shouldBe` "billing@example.com"
                fmap addressEmail (replyTo mail) `shouldBe` Just "support@example.com"
                text mail `shouldSatisfy` isInfixOf "Billing needs attention for Billing Mail Venue."
                text mail `shouldSatisfy` isInfixOf "Event: invoice.payment_failed"
                text mail `shouldSatisfy` isInfixOf "https://app.example/Billing"
                text mail `shouldSatisfy` isInfixOf "contact support@example.com."

        it "renders passkey setup mail with the setup URL, reply-to, and support footer" $ withContext do
            withCleanDb do
                user <- createUserRecord "passkey-mail@example.com" "staff" True
                let mail =
                        PasskeySetupLinkMail
                            { user = user
                            , setupUrl = "https://app.example/NewPasskeySetup?token=test"
                            , fromAddress = "accounts@example.com"
                            , replyToAddress = "support@example.com"
                            , supportEmail = "support@example.com"
                            , purposeLabel = "Set up a new device passkey"
                            }
                let ?context = ?mocking

                addressEmail (to mail) `shouldBe` "passkey-mail@example.com"
                let ?mail = mail
                subject `shouldBe` "Set up a new passkey"
                addressName from `shouldBe` Just "Bepis"
                addressEmail from `shouldBe` "accounts@example.com"
                fmap addressEmail (replyTo mail) `shouldBe` Just "support@example.com"
                text mail `shouldSatisfy` isInfixOf "Set up a new device passkey for your Bepis account:"
                text mail `shouldSatisfy` isInfixOf "https://app.example/NewPasskeySetup?token=test"
                text mail `shouldSatisfy` isInfixOf "This link expires in one hour and can only be used once."
                text mail `shouldSatisfy` isInfixOf "contact support@example.com."

        it "renders RSA reminder mail with venue context, reply-to, and support footer" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "RSA Mail Venue"
                user <- createUserRecord "rsa-mail@example.com" "staff" True
                staff <- createStaffRecord venue (Just user) "Riley" "RSA"
                let staffDocument =
                        newRecord @StaffDocument
                            |> set #expiryDate (fromGregorian 2026 1 31)
                let mail =
                        RsaReminderMail
                            { recipient = user
                            , venue = venue
                            , staff = staff
                            , staffDocument = staffDocument
                            , reminderSubject = "RSA document expires soon"
                            , reminderIntro = "Your RSA document expires soon."
                            , fromAddress = "accounts@example.com"
                            , replyToAddress = "support@example.com"
                            , supportEmail = "support@example.com"
                            }
                let ?context = ?mocking

                addressEmail (to mail) `shouldBe` "rsa-mail@example.com"
                let ?mail = mail
                subject `shouldBe` "RSA document expires soon"
                addressName from `shouldBe` Just "Bepis"
                addressEmail from `shouldBe` "accounts@example.com"
                fmap addressEmail (replyTo mail) `shouldBe` Just "support@example.com"
                text mail `shouldSatisfy` isInfixOf "Your RSA document expires soon."
                text mail `shouldSatisfy` isInfixOf "Venue: RSA Mail Venue"
                text mail `shouldSatisfy` isInfixOf "Staff member: Riley RSA"
                text mail `shouldSatisfy` isInfixOf "Please upload a current RSA document in your Bepis profile."
                text mail `shouldSatisfy` isInfixOf "contact support@example.com."

    describe "Mail settings" do
        it "loads production-safe reply-to and support defaults" $ withContext do
            withEnv "MAIL_FROM" Nothing do
                withEnv "MAIL_REPLY_TO" Nothing do
                    withEnv "MAIL_SUPPORT_EMAIL" Nothing do
                        settings <- loadAppMailSettings
                        settings.mailFromAddress `shouldBe` "noreply@dev.local"
                        settings.mailReplyToAddress `shouldBe` "support@bepis.lol"
                        settings.mailSupportEmail `shouldBe` "support@bepis.lol"

        it "loads sender, reply-to, and support overrides from the environment" $ withContext do
            withEnv "MAIL_FROM" (Just "accounts@bepis.lol") do
                withEnv "MAIL_REPLY_TO" (Just "help@bepis.lol") do
                    withEnv "MAIL_SUPPORT_EMAIL" (Just "support@bepis.lol") do
                        settings <- loadAppMailSettings
                        settings.mailFromAddress `shouldBe` "accounts@bepis.lol"
                        settings.mailReplyToAddress `shouldBe` "help@bepis.lol"
                        settings.mailSupportEmail `shouldBe` "support@bepis.lol"

withEnv :: String -> Maybe String -> IO a -> IO a
withEnv name value action =
    bracket (Environment.lookupEnv name <* apply value) restore (const action)
  where
    restore previous = apply previous
    apply Nothing        = Environment.unsetEnv name
    apply (Just current) = Environment.setEnv name current
