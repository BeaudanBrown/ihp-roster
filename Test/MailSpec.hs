module Test.MailSpec where

import Application.Billing.NotificationKind (BillingNotificationKind (BillingPaymentTrouble, BillingRenewalResumed))
import Application.Helper.Mail
import Application.WageSourceAlert.Types
import Control.Exception (bracket)
import Data.Text (isInfixOf)
import qualified Data.Text.Lazy as LazyText
import Data.Time.Calendar (fromGregorian)
import Data.Time.Clock (UTCTime (..), secondsToDiffTime)
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
import qualified Text.Blaze.Html.Renderer.Text as HtmlRenderer
import Web.Mail.Billing.Notification
import Web.Mail.FeedbackNotification
import Web.Mail.StaffDocuments.RsaReminder
import Web.Mail.Users.EmailVerification
import Web.Mail.Users.PasskeySetupLink
import Web.Mail.Users.PasswordReset
import Web.Mail.Users.VenueInvitation
import Web.Mail.Users.VenueOnboardingInvitation
import Web.Mail.WageSourceAlert

tests :: Spec
tests = aroundAll withDatabaseTestContext do
    describe "Mail templates" do
        it "renders venue invitation recipient, sender, subject, and role-specific text" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Mail Invite Venue"
                invitation <- createVenueInvitationRecord venue Nothing "manager-invite@example.com" Manager
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
                invitation <- createVenueInvitationRecord venue Nothing "trial-mail-invite@example.com" Worker
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

        it "renders billing notifications without provider or payment details" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Billing Mail Venue"
                user <- createUserRecord "billing-mail@example.com" "staff" True
                let mail =
                        BillingNotificationMail
                            { recipient = user
                            , venue = venue
                            , notificationKind = BillingPaymentTrouble
                            , sourceReference = Nothing
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
                text mail `shouldSatisfy` isInfixOf "manage payment details securely through Stripe"
                text mail `shouldSatisfy` isInfixOf "https://app.example/Billing"
                text mail `shouldSatisfy` isInfixOf "contact support@example.com."
                text mail `shouldSatisfy` (not . isInfixOf "invoice.payment_failed")
                text mail `shouldSatisfy` (not . isInfixOf "pm_secret")

        it "renders escaped feedback triage context in explicit HTML and plain text" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Feedback Mail Venue"
                submitter <- createUserRecord "feedback-mail-submitter@example.com" "staff" True
                let submittedAt = UTCTime (fromGregorian 2026 8 20) (secondsToDiffTime (3 * 60 * 60 + 15 * 60))
                let feedbackItem =
                        newRecord @UserFeedbackItem
                            |> set #venueId (unpackId venue.id)
                            |> set #submittedByUserId (unpackId submitter.id)
                            |> set #feedbackType Bug
                            |> set #content "<script>alert('escaped')</script>\nSecond line"
                            |> set #submittedRole (Just "worker")
                            |> set #submittedPath (Just "/RosterWeeks")
                            |> set #userAgent (Just "Browser <unsafe>")
                            |> set #viewportWidth (Just 390)
                            |> set #viewportHeight (Just 844)
                            |> set #devicePixelRatio (Just 2.625)
                            |> set #deviceClass (Just "mobile")
                            |> set #displayMode (Just "standalone")
                            |> set #createdAt submittedAt
                let mail =
                        FeedbackNotificationMail
                            { recipientAddress = "support-recipient@example.com"
                            , feedbackItem
                            , venue
                            , submitter
                            , venueTimezone = "Australia/Melbourne"
                            , supportUrl = "https://app.example/Support"
                            , fromAddress = "noreply@example.com"
                            , replyToAddress = "support@example.com"
                            }
                let ?context = ?mocking
                let ?mail = mail
                let renderedHtml = LazyText.toStrict (HtmlRenderer.renderHtml (html mail))

                addressEmail (to mail) `shouldBe` "support-recipient@example.com"
                subject `shouldBe` "New Bepis feedback submitted"
                addressEmail from `shouldBe` "noreply@example.com"
                fmap addressEmail (replyTo mail) `shouldBe` Just "support@example.com"
                renderedHtml `shouldSatisfy` isInfixOf "&lt;script&gt;alert(&#39;escaped&#39;)&lt;/script&gt;"
                renderedHtml `shouldSatisfy` (not . isInfixOf "<script>")
                renderedHtml `shouldSatisfy` isInfixOf "Browser &lt;unsafe&gt;"
                text mail `shouldSatisfy` isInfixOf "Type: Bug"
                text mail `shouldSatisfy` isInfixOf "Submission-time role: worker"
                text mail `shouldSatisfy` isInfixOf "Submitted: 2026-08-20 13:15:00 Australia/Melbourne"
                text mail `shouldSatisfy` isInfixOf "<script>alert('escaped')</script>\nSecond line"
                text mail `shouldSatisfy` isInfixOf "Open Bepis Support: https://app.example/Support"

        it "renders distinct safe wage-source failure and stale alerts" $ withContext do
            let detectedAt = UTCTime (fromGregorian 2026 8 20) 0
            let sourceJobId = "00000000-0000-0000-0000-000000000253"
            let failureSnapshot =
                    WageSourceAlertSnapshot
                        { alertKind = RefreshFailedAlert
                        , source = FwcWageSource
                        , detectedAt
                        , sourceJobId
                        , refreshTriggerClass = Just TimerRefresh
                        , affectedYears = []
                        , latestValidSuccessAt = Nothing
                        , freshnessMaximumAge = Nothing
                        , annualRequiredOnOrAfter = Nothing
                        , annualTriggerVenueId = Nothing
                        }
            let staleSnapshot =
                    WageSourceAlertSnapshot
                        { alertKind = SourceStaleAlert
                        , source = DataVicWageSource
                        , detectedAt
                        , sourceJobId
                        , refreshTriggerClass = Nothing
                        , affectedYears = [2025, 2026, 2027]
                        , latestValidSuccessAt = Just (UTCTime (fromGregorian 2026 6 1) 0)
                        , freshnessMaximumAge = Just (45 * 24 * 60 * 60)
                        , annualRequiredOnOrAfter = Nothing
                        , annualTriggerVenueId = Nothing
                        }
            let mailFor snapshot =
                    WageSourceAlertMail
                        { recipientAddress = "support-recipient@example.com"
                        , snapshot
                        , supportUrl = "https://app.example/Support"
                        , fromAddress = "noreply@example.com"
                        , replyToAddress = "support@example.com"
                        }
            let failureMail = mailFor failureSnapshot
            let staleMail = mailFor staleSnapshot
            let ?context = ?mocking
            let ?mail = failureMail

            subject `shouldBe` "Fair Work Commission MAPD refresh failed"
            text failureMail `shouldSatisfy` isInfixOf "Refresh class: timer"
            text failureMail `shouldSatisfy` isInfixOf "Refresh job ID: 00000000-0000-0000-0000-000000000253"
            text failureMail `shouldSatisfy` not . isInfixOf "exception"
            let ?mail = staleMail
            subject `shouldBe` "DataVic public holidays data is stale"
            text staleMail `shouldSatisfy` isInfixOf "Affected years: 2025, 2026, 2027"
            text staleMail `shouldSatisfy` isInfixOf "Open Bepis Support: https://app.example/Support"

        it "renders renewal-resumed billing confirmation copy" $ withContext do
            let copy = billingNotificationCopy BillingRenewalResumed "Billing Mail Venue"
            copy.copySubject `shouldBe` "Subscription will renew"
            copy.copyHeading `shouldBe` "The subscription will continue for Billing Mail Venue."
            copy.copyMessage `shouldSatisfy` isInfixOf "scheduled cancellation was reversed"

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

        it "renders password reset mail with session and passkey consequences" $ withContext do
            withCleanDb do
                user <- createUserRecord "password-reset-mail@example.com" "staff" True
                let mail =
                        PasswordResetMail
                            { user
                            , resetUrl = "https://app.example/NewPasswordReset?token=test"
                            , fromAddress = "accounts@example.com"
                            , replyToAddress = "support@example.com"
                            , supportEmail = "support@example.com"
                            }
                let ?context = ?mocking

                addressEmail (to mail) `shouldBe` user.email
                let ?mail = mail
                subject `shouldBe` "Reset your Bepis password"
                addressName from `shouldBe` Just "Bepis"
                addressEmail from `shouldBe` "accounts@example.com"
                fmap addressEmail (replyTo mail) `shouldBe` Just "support@example.com"
                text mail `shouldSatisfy` isInfixOf "https://app.example/NewPasswordReset?token=test"
                text mail `shouldSatisfy` isInfixOf "signs your account out on all devices"
                text mail `shouldSatisfy` isInfixOf "Your passkeys remain available"
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
