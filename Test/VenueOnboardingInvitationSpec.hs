module Test.VenueOnboardingInvitationSpec where

import Application.Async.Queue (EnqueueAppJobResult (..))
import Application.Helper.Controller (unsafeEnumFromText)
import Application.Helper.VenueOnboardingInvitation (venueOnboardingInvitationIsActive,
                                                     venueOnboardingInvitationUrl)
import Application.InvitationDelivery.Job (enqueueVenueOnboardingInvitationDeliveryJob,
                                           performVenueOnboardingInvitationDeliveryJob,
                                           venueOnboardingInvitationDeliveryJobKind)
import Config (config)
import Data.Time.Clock (addUTCTime, getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (withFrameworkConfig)
import IHP.Job.Types
import IHP.Prelude
import IHP.Test.Mocking (withContext)
import Test.Hspec
import Test.Support

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
                            . set #status (unsafeEnumFromText @InvitationStatusEnum "accepted")
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

                enqueueResult <- enqueueVenueOnboardingInvitationDeliveryJob (Just actor.id) invitation

                appJob <- case enqueueResult of
                    EnqueuedAppJob job       -> pure job
                    ExistingActiveAppJob job -> pure job

                appJob.jobKind `shouldBe` venueOnboardingInvitationDeliveryJobKind
                appJob.requestedByUserId `shouldBe` Just (unpackId actor.id)
                appJob.relatedTable `shouldBe` Just "venue_onboarding_invitations"
                appJob.relatedId `shouldBe` Just (unpackId invitation.id)

        it "delivers pending onboarding invitations from the app job" $ withContext do
            withCleanDb do
                invitation <- createVenueOnboardingInvitationRecord Nothing "owner-delivery@example.com"
                EnqueuedAppJob appJob <- enqueueVenueOnboardingInvitationDeliveryJob Nothing invitation

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performVenueOnboardingInvitationDeliveryJob appJob

                updatedInvitation <- fetch invitation.id
                updatedJob <- fetch appJob.id
                inputValue updatedInvitation.deliveryStatus `shouldBe` "sent"
                updatedInvitation.deliveryError `shouldBe` Nothing
                updatedInvitation.deliveredAt `shouldSatisfy` isJust
                updatedJob.status `shouldBe` JobStatusSucceeded

        it "does not deliver an expired onboarding invitation from an already-queued job" $ withContext do
            withCleanDb do
                now <- getCurrentTime
                invitation <-
                    createVenueOnboardingInvitationRecord Nothing "expired-owner-delivery@example.com"
                        >>= updateRecord . set #expiresAt (Just (addUTCTime (-60) now))
                EnqueuedAppJob appJob <- enqueueVenueOnboardingInvitationDeliveryJob Nothing invitation

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performVenueOnboardingInvitationDeliveryJob appJob

                updatedInvitation <- fetch invitation.id
                updatedJob <- fetch appJob.id
                inputValue updatedInvitation.deliveryStatus `shouldBe` "queued"
                updatedInvitation.deliveredAt `shouldBe` Nothing
                updatedJob.status `shouldBe` JobStatusSucceeded

        it "does not deliver a revoked replacement invitation from an already-queued job" $ withContext do
            withCleanDb do
                invitation <- createVenueOnboardingInvitationRecord Nothing "replaced-owner-delivery@example.com"
                EnqueuedAppJob appJob <- enqueueVenueOnboardingInvitationDeliveryJob Nothing invitation
                _ <- invitation
                    |> set #status (unsafeEnumFromText @InvitationStatusEnum "revoked")
                    |> updateRecord

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performVenueOnboardingInvitationDeliveryJob appJob

                updatedInvitation <- fetch invitation.id
                updatedJob <- fetch appJob.id
                inputValue updatedInvitation.deliveryStatus `shouldBe` "queued"
                updatedInvitation.deliveredAt `shouldBe` Nothing
                updatedJob.status `shouldBe` JobStatusSucceeded

        it "does not resend accepted onboarding invitations when a delivery job is retried" $ withContext do
            withCleanDb do
                invitation <- createVenueOnboardingInvitationRecord Nothing "accepted-owner-delivery@example.com"
                now <- getCurrentTime
                acceptedInvitation <-
                    invitation
                        |> set #status (unsafeEnumFromText @InvitationStatusEnum "accepted")
                        |> set #acceptedAt (Just now)
                        |> updateRecord
                EnqueuedAppJob appJob <- enqueueVenueOnboardingInvitationDeliveryJob Nothing acceptedInvitation

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performVenueOnboardingInvitationDeliveryJob appJob

                updatedInvitation <- fetch invitation.id
                inputValue updatedInvitation.deliveryStatus `shouldBe` "queued"
                updatedInvitation.deliveredAt `shouldBe` Nothing
