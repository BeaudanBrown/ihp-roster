module Application.Helper.VenueOnboardingInvitation where

import Application.Helper.InvitationStatus (invitationStatusAllowsRenewal)
import Application.Helper.Url (appendQueryParams)
import Web.Controller.Prelude

venueOnboardingInvitationLifetime :: NominalDiffTime
venueOnboardingInvitationLifetime = 60 * 60 * 24 * 14

venueOnboardingInvitationUrl :: Text -> VenueOnboardingInvitation -> Text
venueOnboardingInvitationUrl appBaseUrl invitation =
    appBaseUrl <> appendQueryParams (pathTo NewVenueOnboardingUserAction) [("invitationId", tshow invitation.id)]

venueOnboardingInvitationIsActive :: UTCTime -> VenueOnboardingInvitation -> Bool
venueOnboardingInvitationIsActive now invitation =
    invitationStatusAllowsRenewal invitation.status
        && isNothing invitation.acceptedAt
        && maybe True (> now) invitation.expiresAt
