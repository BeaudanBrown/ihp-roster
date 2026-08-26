module Application.InvitationDelivery.Enqueue
    ( enqueueVenueInvitationEmail
    , enqueueVenueOnboardingInvitationEmail
    ) where

import Application.EmailDelivery.Enqueue
import Application.InvitationDelivery.Types
import Generated.Types
import IHP.ControllerPrelude

enqueueVenueInvitationEmail ::
    (?modelContext :: ModelContext) =>
    Maybe (Id User) ->
    VenueInvitation ->
    IO EmailDeliveryEnqueueResult
enqueueVenueInvitationEmail maybeActorId invitation =
    enqueueEmailDeliveryWithStatus
        EmailDeliveryRequest
            { mailKind = venueInvitationMailKind
            , recipientAccountId = unpackId invitation.id
            , recipientAddress = invitation.email
            , domainReferenceTable = "venue_invitations"
            , domainReferenceId = unpackId invitation.id
            , semanticEventKey = "venue-invitation:" <> tshow invitation.id
            , requestedByUserId = unpackId <$> maybeActorId
            , venueId = Just invitation.venueId
            }

enqueueVenueOnboardingInvitationEmail ::
    (?modelContext :: ModelContext) =>
    Maybe (Id User) ->
    VenueOnboardingInvitation ->
    IO EmailDeliveryEnqueueResult
enqueueVenueOnboardingInvitationEmail maybeActorId invitation =
    enqueueEmailDeliveryWithStatus
        EmailDeliveryRequest
            { mailKind = venueOnboardingInvitationMailKind
            , recipientAccountId = unpackId invitation.id
            , recipientAddress = invitation.email
            , domainReferenceTable = "venue_onboarding_invitations"
            , domainReferenceId = unpackId invitation.id
            , semanticEventKey = "venue-onboarding-invitation:" <> tshow invitation.id
            , requestedByUserId = unpackId <$> maybeActorId
            , venueId = Nothing
            }
