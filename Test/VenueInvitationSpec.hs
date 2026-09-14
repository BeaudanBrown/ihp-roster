module Test.VenueInvitationSpec where

import Application.Async.Queue (appJobMaxAttempts)
import Application.EmailDelivery
import qualified Application.Helper.FrontendContract.Surface.Admin.Live as AdminLive
import Application.Helper.LiveUpdate
import Application.Helper.VenueInvitation (venueInvitationUrl)
import Application.InvitationDelivery.Enqueue (enqueueVenueInvitationEmail)
import Application.InvitationDelivery.Types (venueInvitationMailKind)
import Config (config)
import Control.Exception (SomeException, try)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.Types as AesonTypes
import Data.Either (isLeft)
import qualified Data.Text as Text
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

                enqueueResult <- enqueueVenueInvitationEmail (Just actor.id) invitation

                appJob <- case enqueueResult of
                    EnqueuedEmailDelivery job -> pure job
                    ExistingEmailDelivery job -> pure job

                appJob.jobKind `shouldBe` emailDeliveryJobKind
                appJob.requestedByUserId `shouldBe` Just (unpackId actor.id)
                appJob.venueId `shouldBe` Just (unpackId venue.id)
                appJob.relatedTable `shouldBe` Just "venue_invitations"
                appJob.relatedId `shouldBe` Just (unpackId invitation.id)
                jobJsonText appJob.payload "mailKind" `shouldBe` Just venueInvitationMailKind
                jobJsonText appJob.payload "recipientAddress" `shouldBe` Just invitation.email
                tshow appJob.payload `shouldSatisfy` not . Text.isInfixOf "NewUser"

        it "delivers pending venue invitations and durably publishes invite resync without a browser hub" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invite Delivery Venue"
                invitation <- createVenueInvitationRecord venue Nothing "deliver-invite@example.com" Manager
                EnqueuedEmailDelivery appJob <- enqueueVenueInvitationEmail Nothing invitation
                versionBefore <- currentLiveUpdateVersion (AdminLive.adminInvitesLiveScope (unpackId venue.id))

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith enabledEmailDeliveryRuntime appJob

                updatedInvitation <- fetch invitation.id
                updatedJob <- fetch appJob.id
                inputValue updatedInvitation.deliveryStatus `shouldBe` "sent"
                updatedInvitation.deliveryError `shouldBe` Nothing
                updatedInvitation.deliveredAt `shouldSatisfy` isJust
                updatedJob.status `shouldBe` JobStatusSucceeded
                versionAfter <- currentLiveUpdateVersion (AdminLive.adminInvitesLiveScope (unpackId venue.id))
                versionAfter `shouldBe` versionBefore
                [durableEvent] <- query @LiveInvalidationEvent |> filterWhere (#source, "admin.invites.delivery" :: Text) |> fetch
                [durableResource] <- query @LiveInvalidationEventResource |> filterWhere (#eventId, unpackId durableEvent.id) |> fetch
                durableResource.resourceKey `shouldSatisfy` Text.isPrefixOf "admin-invites:"

        it "treats legacy invitations without an explicit expiry as expired two weeks after creation" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invite Legacy Expiry Venue"
                now <- getCurrentTime
                invitation <- createVenueInvitationRecord venue Nothing "legacy-expired-invite@example.com" Worker
                    >>= updateRecord
                        . set #createdAt (addUTCTime (negate (15 * 24 * 60 * 60)) now)
                        . set #expiresAt Nothing
                EnqueuedEmailDelivery appJob <- enqueueVenueInvitationEmail Nothing invitation

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith enabledEmailDeliveryRuntime appJob

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
                EnqueuedEmailDelivery expiredJob <- enqueueVenueInvitationEmail Nothing expired
                EnqueuedEmailDelivery revokedJob <- enqueueVenueInvitationEmail Nothing revoked

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith enabledEmailDeliveryRuntime expiredJob
                    performEmailDeliveryJobWith enabledEmailDeliveryRuntime revokedJob

                updatedExpired <- fetch expired.id
                updatedRevoked <- fetch revoked.id
                updatedExpired.deliveredAt `shouldBe` Nothing
                updatedRevoked.deliveredAt `shouldBe` Nothing
                inputValue updatedExpired.deliveryStatus `shouldBe` "queued"
                inputValue updatedRevoked.deliveryStatus `shouldBe` "queued"
                expiredResult <- fetch expiredJob.id
                revokedResult <- fetch revokedJob.id
                jobJsonText expiredResult.result "deliveryStatus" `shouldBe` Just "delivery_skipped"
                jobJsonText expiredResult.result "reason" `shouldBe` Just "expired"
                jobJsonText revokedResult.result "reason" `shouldBe` Just "revoked_or_replaced"

        it "completes disabled delivery once and permanently deduplicates the invitation event" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invite Disabled Venue"
                invitation <- createVenueInvitationRecord venue Nothing "disabled-invite@example.com" Manager
                EnqueuedEmailDelivery appJob <- enqueueVenueInvitationEmail Nothing invitation

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith
                        disabledEmailDeliveryRuntime
                        appJob

                deliveredInvitation <- fetch invitation.id
                deliveredInvitation.deliveredAt `shouldSatisfy` isJust
                completedJob <- fetch appJob.id
                jobJsonText completedJob.result "deliveryStatus" `shouldBe` Just "delivery_disabled"
                repeated <- enqueueVenueInvitationEmail Nothing invitation
                case repeated of
                    ExistingEmailDelivery existing -> existing.id `shouldBe` appJob.id
                    EnqueuedEmailDelivery _ -> expectationFailure "invitation event must remain permanently deduplicated"

        it "does not reclassify a completed skip after a publication-side exception" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invite Completed Skip Venue"
                invitation <- createVenueInvitationRecord venue Nothing "snapshot-before@example.com" Manager
                EnqueuedEmailDelivery queuedJob <- enqueueVenueInvitationEmail Nothing invitation
                finalAttemptJob <- queuedJob |> set #attemptsCount appJobMaxAttempts |> updateRecord
                _ <- invitation |> set #email "snapshot-after@example.com" |> updateRecord

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith enabledEmailDeliveryRuntime finalAttemptJob
                handleEmailDeliveryFailureAfterFinalAttempt finalAttemptJob

                unchangedInvitation <- fetch invitation.id
                inputValue unchangedInvitation.deliveryStatus `shouldBe` "queued"
                completedJob <- fetch queuedJob.id
                jobJsonText completedJob.result "deliveryStatus" `shouldBe` Just "delivery_skipped"
                jobJsonText completedJob.result "reason" `shouldBe` Just "recipient_snapshot_mismatch"

        it "records bounded invitation failure only after the shared final attempt" $ withContext do
            withCleanDb do
                venue <- createVenueWithConfig "Invite Failure Venue"
                invitation <- createVenueInvitationRecord venue Nothing "failed-invite@example.com" Manager
                EnqueuedEmailDelivery queuedJob <- enqueueVenueInvitationEmail Nothing invitation
                finalAttemptJob <- queuedJob |> set #attemptsCount appJobMaxAttempts |> updateRecord

                failure <- withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    try
                        ( performEmailDeliveryJobWith
                            (failingEmailDeliveryRuntime "SMTP detail containing secret@example.com")
                            finalAttemptJob
                        ) :: IO (Either SomeException ())
                failure `shouldSatisfy` isLeft
                handleEmailDeliveryFailureAfterFinalAttempt finalAttemptJob

                failedInvitation <- fetch invitation.id
                inputValue failedInvitation.deliveryStatus `shouldBe` "failed"
                failedInvitation.deliveryError `shouldBe` Just "Email delivery failed after ten attempts."
                tshow failedInvitation.deliveryError `shouldSatisfy` not . Text.isInfixOf "secret@example.com"

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
                EnqueuedEmailDelivery appJob <- enqueueVenueInvitationEmail Nothing acceptedInvitation

                withFrameworkConfig config \frameworkConfig -> do
                    let ?context = frameworkConfig
                    performEmailDeliveryJobWith enabledEmailDeliveryRuntime appJob

                updatedInvitation <- fetch invitation.id
                inputValue updatedInvitation.deliveryStatus `shouldBe` "queued"
                updatedInvitation.deliveredAt `shouldBe` Nothing
                completedJob <- fetch appJob.id
                jobJsonText completedJob.result "deliveryStatus" `shouldBe` Just "delivery_skipped"
                jobJsonText completedJob.result "reason" `shouldBe` Just "consumed"

jobJsonText :: Aeson.Value -> Text -> Maybe Text
jobJsonText value key =
    AesonTypes.parseMaybe (Aeson.withObject "job JSON" (Aeson..: AesonKey.fromText key)) value
