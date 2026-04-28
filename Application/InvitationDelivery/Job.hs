module Application.InvitationDelivery.Job
    ( enqueueVenueInvitationDeliveryJob
    , enqueueVenueOnboardingInvitationDeliveryJob
    , performVenueInvitationDeliveryJob
    , performVenueOnboardingInvitationDeliveryJob
    , venueInvitationDeliveryJobKind
    , venueOnboardingInvitationDeliveryJobKind
    ) where

import Application.Async.Queue
import Application.Helper.Controller (unsafeEnumFromText)
import Application.Helper.LiveUpdate (LiveUpdateScope (..),
                                      broadcastLiveResyncWithoutContext)
import Application.Helper.VenueInvitation (deliverVenueInvitationEmail)
import Application.Helper.VenueOnboardingInvitation (deliverVenueOnboardingInvitationEmail)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (FrameworkConfig)

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
    when (venueInvitationNeedsDelivery invitation) do
        _ <- deliverVenueInvitationEmail invitation
        pure ()
    void
        ( appJob
            |> set #result (Aeson.object ["invitationId" Aeson..= tshow invitation.id])
            |> set #status JobStatusSucceeded
            |> updateRecord
        )
    broadcastLiveResyncWithoutContext
        AdminInvitesScope { venueId = invitation.venueId }
        Nothing

performVenueOnboardingInvitationDeliveryJob ::
    (?context :: FrameworkConfig, ?modelContext :: ModelContext) =>
    AppJob ->
    IO ()
performVenueOnboardingInvitationDeliveryJob appJob = do
    invitation <- fetchVenueOnboardingInvitation appJob
    when (venueOnboardingInvitationNeedsDelivery invitation) do
        _ <- deliverVenueOnboardingInvitationEmail invitation
        pure ()
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

venueInvitationNeedsDelivery :: VenueInvitation -> Bool
venueInvitationNeedsDelivery invitation =
    invitation.status == unsafeEnumFromText @InvitationStatusEnum "pending"
        && invitation.acceptedAt == Nothing
        && invitation.deliveryStatus /= unsafeEnumFromText @InvitationDeliveryStatusEnum "sent"

venueOnboardingInvitationNeedsDelivery :: VenueOnboardingInvitation -> Bool
venueOnboardingInvitationNeedsDelivery invitation =
    invitation.status == unsafeEnumFromText @InvitationStatusEnum "pending"
        && invitation.acceptedAt == Nothing
        && invitation.deliveryStatus /= unsafeEnumFromText @InvitationDeliveryStatusEnum "sent"
