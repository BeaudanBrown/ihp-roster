module Application.InvitationDelivery.Types
    ( venueInvitationMailKind
    , venueOnboardingInvitationMailKind
    ) where

import IHP.Prelude

venueInvitationMailKind :: Text
venueInvitationMailKind = "venue_invitation_v1"

venueOnboardingInvitationMailKind :: Text
venueOnboardingInvitationMailKind = "venue_onboarding_invitation_v1"
