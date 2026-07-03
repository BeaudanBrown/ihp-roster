module Test.VenueInvitationSpec where

import Application.Async.Queue (EnqueueAppJobResult (..))
import Application.Helper.Controller (unsafeEnumFromText)
import Application.Helper.LiveUpdate
import Application.Helper.VenueInvitation (venueInvitationUrl)
import Application.InvitationDelivery.Job (enqueueVenueInvitationDeliveryJob,
                                           performVenueInvitationDeliveryJob,
                                           venueInvitationDeliveryJobKind)
import Config (config)
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (withFrameworkConfig)
import IHP.Job.Types
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

        it "queues venue invitation delivery as a durable app job" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invite Job Venue"
                actor <- createUserRecord "invite-job-actor@example.com" "staff" True
                invitation <- createVenueInvitationRecord venue (Just actor) "invite-job@example.com" "manager"

                enqueueResult <- enqueueVenueInvitationDeliveryJob (Just actor.id) invitation

                appJob <- case enqueueResult of
                    EnqueuedAppJob job       -> pure job
                    ExistingActiveAppJob job -> pure job

                appJob.jobKind `shouldBe` venueInvitationDeliveryJobKind
                appJob.requestedByUserId `shouldBe` Just (unpackId actor.id)
                appJob.venueId `shouldBe` Just (unpackId venue.id)
                appJob.relatedTable `shouldBe` Just "venue_invitations"
                appJob.relatedId `shouldBe` Just (unpackId invitation.id)

        it "delivers pending venue invitations from the app job and broadcasts invite resync" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invite Delivery Venue"
                invitation <- createVenueInvitationRecord venue Nothing "deliver-invite@example.com" "manager"
                EnqueuedAppJob appJob <- enqueueVenueInvitationDeliveryJob Nothing invitation
                versionBefore <- currentLiveUpdateVersion (adminInvitesLiveScope (unpackId venue.id))

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performVenueInvitationDeliveryJob appJob

                updatedInvitation <- fetch invitation.id
                updatedJob <- fetch appJob.id
                inputValue updatedInvitation.deliveryStatus `shouldBe` "sent"
                updatedInvitation.deliveryError `shouldBe` Nothing
                updatedInvitation.deliveredAt `shouldSatisfy` isJust
                updatedJob.status `shouldBe` JobStatusSucceeded
                versionAfter <- currentLiveUpdateVersion (adminInvitesLiveScope (unpackId venue.id))
                versionAfter `shouldBe` versionBefore

        it "does not resend accepted venue invitations when a delivery job is retried" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invite Accepted Venue"
                invitation <- createVenueInvitationRecord venue Nothing "accepted-invite@example.com" "manager"
                now <- getCurrentTime
                acceptedInvitation <-
                    invitation
                        |> set #status (unsafeEnumFromText @InvitationStatusEnum "accepted")
                        |> set #acceptedAt (Just now)
                        |> updateRecord
                EnqueuedAppJob appJob <- enqueueVenueInvitationDeliveryJob Nothing acceptedInvitation

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performVenueInvitationDeliveryJob appJob

                updatedInvitation <- fetch invitation.id
                inputValue updatedInvitation.deliveryStatus `shouldBe` "queued"
                updatedInvitation.deliveredAt `shouldBe` Nothing
