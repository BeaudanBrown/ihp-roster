module Test.VenueInvitationSpec where

import Application.Async.Queue (EnqueueAppJobResult (..))
import qualified Application.Helper.FrontendContract.Surface.Admin.Live as AdminLive
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
tests = aroundAll withDatabaseTestContext do
    describe "Venue invitation helper" do
        it "builds the signup URL from the invitation id" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invite URL Venue"
                invitation <- createVenueInvitationRecord venue Nothing "invite-url@example.com" Manager
                let invitationId = get #id invitation :: Id VenueInvitation

                venueInvitationUrl "http://localhost:8000" invitation
                    `shouldBe` ("http://localhost:8000/NewUser?invitationId=" <> cs (show invitationId))

        it "queues venue invitation delivery as a durable app job" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invite Job Venue"
                actor <- createUserRecord "invite-job-actor@example.com" "staff" True
                invitation <- createVenueInvitationRecord venue (Just actor) "invite-job@example.com" Manager

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
                invitation <- createVenueInvitationRecord venue Nothing "deliver-invite@example.com" Manager
                EnqueuedAppJob appJob <- enqueueVenueInvitationDeliveryJob Nothing invitation
                versionBefore <- currentLiveUpdateVersion (AdminLive.adminInvitesLiveScope (unpackId venue.id))

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performVenueInvitationDeliveryJob appJob

                updatedInvitation <- fetch invitation.id
                updatedJob <- fetch appJob.id
                inputValue updatedInvitation.deliveryStatus `shouldBe` "sent"
                updatedInvitation.deliveryError `shouldBe` Nothing
                updatedInvitation.deliveredAt `shouldSatisfy` isJust
                updatedJob.status `shouldBe` JobStatusSucceeded
                versionAfter <- currentLiveUpdateVersion (AdminLive.adminInvitesLiveScope (unpackId venue.id))
                versionAfter `shouldBe` versionBefore

        it "treats legacy invitations without an explicit expiry as expired two weeks after creation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invite Legacy Expiry Venue"
                now <- getCurrentTime
                invitation <- createVenueInvitationRecord venue Nothing "legacy-expired-invite@example.com" Worker
                    >>= updateRecord
                        . set #createdAt (addUTCTime (negate (15 * 24 * 60 * 60)) now)
                        . set #expiresAt Nothing
                EnqueuedAppJob appJob <- enqueueVenueInvitationDeliveryJob Nothing invitation

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performVenueInvitationDeliveryJob appJob

                updatedInvitation <- fetch invitation.id
                updatedInvitation.deliveredAt `shouldBe` Nothing

        it "does not deliver expired or revoked venue invitations from already queued jobs" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invite Stale Delivery Venue"
                now <- getCurrentTime
                expired <- createVenueInvitationRecord venue Nothing "expired-queued-invite@example.com" Worker
                    >>= updateRecord . set #expiresAt (Just (addUTCTime (-60) now))
                revoked <- createVenueInvitationRecord venue Nothing "revoked-queued-invite@example.com" Worker
                    >>= updateRecord . set #status (Revoked)
                EnqueuedAppJob expiredJob <- enqueueVenueInvitationDeliveryJob Nothing expired
                EnqueuedAppJob revokedJob <- enqueueVenueInvitationDeliveryJob Nothing revoked

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performVenueInvitationDeliveryJob expiredJob
                    performVenueInvitationDeliveryJob revokedJob

                updatedExpired <- fetch expired.id
                updatedRevoked <- fetch revoked.id
                updatedExpired.deliveredAt `shouldBe` Nothing
                updatedRevoked.deliveredAt `shouldBe` Nothing
                inputValue updatedExpired.deliveryStatus `shouldBe` "queued"
                inputValue updatedRevoked.deliveryStatus `shouldBe` "queued"

        it "does not resend accepted venue invitations when a delivery job is retried" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invite Accepted Venue"
                invitation <- createVenueInvitationRecord venue Nothing "accepted-invite@example.com" Manager
                now <- getCurrentTime
                acceptedInvitation <-
                    invitation
                        |> set #status (Accepted)
                        |> set #acceptedAt (Just now)
                        |> updateRecord
                EnqueuedAppJob appJob <- enqueueVenueInvitationDeliveryJob Nothing acceptedInvitation

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performVenueInvitationDeliveryJob appJob

                updatedInvitation <- fetch invitation.id
                inputValue updatedInvitation.deliveryStatus `shouldBe` "queued"
                updatedInvitation.deliveredAt `shouldBe` Nothing
