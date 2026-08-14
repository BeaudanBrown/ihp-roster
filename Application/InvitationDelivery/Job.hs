module Application.InvitationDelivery.Job
    ( enqueueVenueInvitationDeliveryJob
    , enqueueVenueOnboardingInvitationDeliveryJob
    , performVenueInvitationDeliveryJob
    , performVenueOnboardingInvitationDeliveryJob
    , venueInvitationDeliveryJobKind
    , venueOnboardingInvitationDeliveryJobKind
    ) where

import Application.Async.Queue
import Application.Helper.FrontendContract.Surface.Admin.Resource (adminInvitesResource)
import Application.Helper.SurfaceResource
import Application.Helper.VenueInvitation (deliverVenueInvitationEmail,
                                           venueInvitationIsActive)
import Application.Helper.VenueOnboardingInvitation (deliverVenueOnboardingInvitationEmail,
                                                     venueOnboardingInvitationIsActive)
import Application.VenueInvitation.Mutations (withVenueInvitationLock)
import Application.VenueOnboardingInvitation.Mutations (withVenueOnboardingInvitationLock)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (FrameworkConfig)
import Web.SurfaceInvalidation (publishTouchedResourcesWithoutContext)

venueInvitationDeliveryJobKind :: Text
venueInvitationDeliveryJobKind = "venue_invitation_delivery"

venueOnboardingInvitationDeliveryJobKind :: Text
venueOnboardingInvitationDeliveryJobKind = "venue_onboarding_invitation_delivery"

enqueueVenueInvitationDeliveryJob ::
    (?modelContext :: ModelContext) =>
    Maybe (Id User) ->
    VenueInvitation ->
    IO EnqueueAppJobResult
enqueueVenueInvitationDeliveryJob maybeActorId invitation =
    enqueueAppJob
        AppJobRequest
            { jobKind = venueInvitationDeliveryJobKind
            , payload = invitationPayload (unpackId invitation.id)
            , payloadSchemaVersion = 1
            , requestedByUserId = unpackId <$> maybeActorId
            , venueId = Just invitation.venueId
            , relatedTable = Just "venue_invitations"
            , relatedId = Just (unpackId invitation.id)
            , dedupeKey = Just ("venue-invitation-delivery:" <> tshow invitation.id)
            , runAt = Nothing
            }

enqueueVenueOnboardingInvitationDeliveryJob ::
    (?modelContext :: ModelContext) =>
    Maybe (Id User) ->
    VenueOnboardingInvitation ->
    IO EnqueueAppJobResult
enqueueVenueOnboardingInvitationDeliveryJob maybeActorId invitation =
    enqueueAppJob
        AppJobRequest
            { jobKind = venueOnboardingInvitationDeliveryJobKind
            , payload = invitationPayload (unpackId invitation.id)
            , payloadSchemaVersion = 1
            , requestedByUserId = unpackId <$> maybeActorId
            , venueId = Nothing
            , relatedTable = Just "venue_onboarding_invitations"
            , relatedId = Just (unpackId invitation.id)
            , dedupeKey = Just ("venue-onboarding-invitation-delivery:" <> tshow invitation.id)
            , runAt = Nothing
            }

performVenueInvitationDeliveryJob ::
    (?context :: FrameworkConfig, ?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
performVenueInvitationDeliveryJob appJob = do
    invitation <- fetchVenueInvitation appJob
    void $ withVenueInvitationLock (unpackId invitation.id) do
        lockedInvitation <- fetch invitation.id
        now <- getCurrentTime
        when (venueInvitationNeedsDelivery now lockedInvitation) do
            void (deliverVenueInvitationEmail lockedInvitation)
    void
        ( appJob
            |> set #result (Aeson.object ["invitationId" Aeson..= tshow invitation.id])
            |> set #status JobStatusSucceeded
            |> updateRecord
        )
    void $
        publishTouchedResourcesWithoutContext "admin.invites.delivery" $
            liveMutationResult invitation [adminInvitesResource invitation.venueId]

performVenueOnboardingInvitationDeliveryJob ::
    (?context :: FrameworkConfig, ?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
performVenueOnboardingInvitationDeliveryJob appJob = do
    invitation <- fetchVenueOnboardingInvitation appJob
    void $ withVenueOnboardingInvitationLock (unpackId invitation.id) do
        lockedInvitation <- fetch invitation.id
        now <- getCurrentTime
        when (venueOnboardingInvitationNeedsDelivery now lockedInvitation) do
            void (deliverVenueOnboardingInvitationEmail lockedInvitation)
    void
        ( appJob
            |> set #result (Aeson.object ["invitationId" Aeson..= tshow invitation.id])
            |> set #status JobStatusSucceeded
            |> updateRecord
        )

invitationPayload :: UUID -> Aeson.Value
invitationPayload invitationId =
    Aeson.object ["invitationId" Aeson..= tshow invitationId]

fetchVenueInvitation ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO VenueInvitation
fetchVenueInvitation appJob =
    case (appJob.relatedTable, appJob.relatedId) of
        (Just "venue_invitations", Just rawId) ->
            fetch (Id rawId :: Id VenueInvitation)
        _ ->
            fail ("Invalid invitation delivery job payload for job " <> cs (tshow appJob.id))

fetchVenueOnboardingInvitation ::
    (?modelContext :: ModelContext) =>
    AppJob ->
    IO VenueOnboardingInvitation
fetchVenueOnboardingInvitation appJob =
    case (appJob.relatedTable, appJob.relatedId) of
        (Just "venue_onboarding_invitations", Just rawId) ->
            fetch (Id rawId :: Id VenueOnboardingInvitation)
        _ ->
            fail ("Invalid onboarding invitation delivery job payload for job " <> cs (tshow appJob.id))

venueInvitationNeedsDelivery :: UTCTime -> VenueInvitation -> Bool
venueInvitationNeedsDelivery now invitation =
    venueInvitationIsActive now invitation
        && invitation.deliveryStatus /= Sent

venueOnboardingInvitationNeedsDelivery :: UTCTime -> VenueOnboardingInvitation -> Bool
venueOnboardingInvitationNeedsDelivery now invitation =
    venueOnboardingInvitationIsActive now invitation
        && invitation.deliveryStatus /= Sent
