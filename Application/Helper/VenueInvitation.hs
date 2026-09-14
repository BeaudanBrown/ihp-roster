module Application.Helper.VenueInvitation where

import Application.Helper.InvitationStatus (invitationStatusAllowsRenewal)
import Application.Helper.Url (appendQueryParams)
import Application.Helper.VenueOnboardingInvitation (venueOnboardingInvitationIsActive)
import Web.Controller.Prelude

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

accountInvitationConflictMessage :: Text
accountInvitationConflictMessage = "This email already has an account or pending invitation."

registeredInvitationAccountExists :: (?modelContext :: ModelContext) => Text -> IO Bool
registeredInvitationAccountExists email =
    query @User
        |> filterWhereCaseInsensitive (#email, email)
        |> fetchExists

activeVenueInvitationsForEmail :: (?modelContext :: ModelContext) => UTCTime -> Text -> IO [VenueInvitation]
activeVenueInvitationsForEmail now email = do
    pendingInvitations <- query @VenueInvitation
        |> filterWhereCaseInsensitive (#email, email)
        |> filterWhere (#status, InvitationStatusEnumPending)
        |> fetch
    pure (filter (venueInvitationIsActive now) pendingInvitations)

activeVenueOnboardingInvitationsForEmail :: (?modelContext :: ModelContext) => UTCTime -> Text -> IO [VenueOnboardingInvitation]
activeVenueOnboardingInvitationsForEmail now email = do
    pendingInvitations <- query @VenueOnboardingInvitation
        |> filterWhereCaseInsensitive (#email, email)
        |> filterWhere (#status, InvitationStatusEnumPending)
        |> filterWhere (#acceptedAt, Nothing)
        |> fetch
    pure (filter (venueOnboardingInvitationIsActive now) pendingInvitations)
