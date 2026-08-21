module Application.Helper.VenueInvitation where

import Application.Helper.InvitationStatus (invitationStatusAllowsRenewal)
import Application.Helper.Url (appendQueryParams)
import Web.Controller.Prelude
import Web.Types

venueInvitationLifetime :: NominalDiffTime
venueInvitationLifetime = 60 * 60 * 24 * 14

venueInvitationEffectiveExpiresAt :: VenueInvitation -> UTCTime
venueInvitationEffectiveExpiresAt invitation =
    fromMaybe (addUTCTime venueInvitationLifetime invitation.createdAt) invitation.expiresAt

venueInvitationIsActive :: UTCTime -> VenueInvitation -> Bool
venueInvitationIsActive now invitation =
    invitationStatusAllowsRenewal invitation.status
        && isNothing invitation.acceptedAt
        && venueInvitationEffectiveExpiresAt invitation > now

venueInvitationUrl :: Text -> VenueInvitation -> Text
venueInvitationUrl appBaseUrl invitation =
    appBaseUrl <> appendQueryParams (pathTo NewUserAction) [("invitationId", tshow invitation.id)]
