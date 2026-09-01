module Test.VenueOnboardingInvitationSpec where

import Application.EmailDelivery
import Application.Helper.VenueOnboardingInvitation (venueOnboardingInvitationIsActive,
                                                     venueOnboardingInvitationUrl)
import Application.InvitationDelivery.Enqueue (enqueueVenueOnboardingInvitationEmail)
import Application.InvitationDelivery.Types (venueOnboardingInvitationMailKind)
import Config (config)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.Types as AesonTypes
import qualified Data.Text as Text
import Data.Time.Clock (addUTCTime, getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (withFrameworkConfig)
import IHP.Job.Types
import IHP.Prelude
import IHP.Test.Mocking (withContext)
import Test.Hspec
import Test.Support
import Test.Support.EmailDelivery

tests :: Spec
tests = aroundAll withDatabaseTestContext do
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
                            . set #status (Accepted)
                            . set #acceptedAt (Just now)
                expiredInvitation <-
                    createVenueOnboardingInvitationRecord Nothing "expired-owner@example.com"
                        >>= updateRecord . set #expiresAt (Just (addUTCTime (-3600) now))

                venueOnboardingInvitationIsActive now acceptedInvitation `shouldBe` False
                venueOnboardingInvitationIsActive now expiredInvitation `shouldBe` False

        it "queues onboarding invitation delivery as a durable app job" $ withContext do
            withCleanDb do
                actor <- createUserRecord "onboarding-job-actor@example.com" "staff" True
                invitation <- createVenueOnboardingInvitationRecord (Just actor) "owner-job@example.com"

                enqueueResult <- enqueueVenueOnboardingInvitationEmail (Just actor.id) invitation

                appJob <- case enqueueResult of
                    EnqueuedEmailDelivery job -> pure job
                    ExistingEmailDelivery job -> pure job

                appJob.jobKind `shouldBe` emailDeliveryJobKind
                appJob.requestedByUserId `shouldBe` Just (unpackId actor.id)
                appJob.relatedTable `shouldBe` Just "venue_onboarding_invitations"
                appJob.relatedId `shouldBe` Just (unpackId invitation.id)
                jobJsonText appJob.payload "mailKind" `shouldBe` Just venueOnboardingInvitationMailKind
                jobJsonText appJob.payload "recipientAddress" `shouldBe` Just invitation.email
                tshow appJob.payload `shouldSatisfy` not . Text.isInfixOf "NewVenueOnboardingUser"

        it "delivers pending onboarding invitations through the shared worker" $ withContext do
            withCleanDb do
                invitation <- createVenueOnboardingInvitationRecord Nothing "owner-delivery@example.com"
                EnqueuedEmailDelivery appJob <- enqueueVenueOnboardingInvitationEmail Nothing invitation

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith enabledEmailDeliveryRuntime appJob

                updatedInvitation <- fetch invitation.id
                updatedJob <- fetch appJob.id
                inputValue updatedInvitation.deliveryStatus `shouldBe` "sent"
                updatedInvitation.deliveryError `shouldBe` Nothing
                updatedInvitation.deliveredAt `shouldSatisfy` isJust
                updatedJob.status `shouldBe` JobStatusSucceeded
                jobJsonText updatedJob.result "deliveryStatus" `shouldBe` Just "sent"

        it "truthfully skips expired and revoked onboarding invitations" $ withContext do
            withCleanDb do
                now <- getCurrentTime
                expired <-
                    createVenueOnboardingInvitationRecord Nothing "expired-owner-delivery@example.com"
                        >>= updateRecord . set #expiresAt (Just (addUTCTime (-60) now))
                revoked <-
                    createVenueOnboardingInvitationRecord Nothing "replaced-owner-delivery@example.com"
                        >>= updateRecord . set #status Revoked
                EnqueuedEmailDelivery expiredJob <- enqueueVenueOnboardingInvitationEmail Nothing expired
                EnqueuedEmailDelivery revokedJob <- enqueueVenueOnboardingInvitationEmail Nothing revoked

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith enabledEmailDeliveryRuntime expiredJob
                    performEmailDeliveryJobWith enabledEmailDeliveryRuntime revokedJob

                updatedExpired <- fetch expired.id
                updatedRevoked <- fetch revoked.id
                inputValue updatedExpired.deliveryStatus `shouldBe` "queued"
                inputValue updatedRevoked.deliveryStatus `shouldBe` "queued"
                expiredResult <- fetch expiredJob.id
                revokedResult <- fetch revokedJob.id
                jobJsonText expiredResult.result "deliveryStatus" `shouldBe` Just "delivery_skipped"
                jobJsonText expiredResult.result "reason" `shouldBe` Just "expired"
                jobJsonText revokedResult.result "reason" `shouldBe` Just "revoked_or_replaced"

        it "does not resend accepted onboarding invitations" $ withContext do
            withCleanDb do
                invitation <- createVenueOnboardingInvitationRecord Nothing "accepted-owner-delivery@example.com"
                now <- getCurrentTime
                acceptedInvitation <-
                    invitation
                        |> set #status Accepted
                        |> set #acceptedAt (Just now)
                        |> updateRecord
                EnqueuedEmailDelivery appJob <- enqueueVenueOnboardingInvitationEmail Nothing acceptedInvitation

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith enabledEmailDeliveryRuntime appJob

                updatedInvitation <- fetch invitation.id
                inputValue updatedInvitation.deliveryStatus `shouldBe` "queued"
                updatedInvitation.deliveredAt `shouldBe` Nothing
                completedJob <- fetch appJob.id
                jobJsonText completedJob.result "reason" `shouldBe` Just "consumed"

jobJsonText :: Aeson.Value -> Text -> Maybe Text
jobJsonText value key =
    AesonTypes.parseMaybe (Aeson.withObject "job JSON" (Aeson..: AesonKey.fromText key)) value
