module Application.InvitationEligibility
    ( accountInvitationConflictMessage
    , activeVenueInvitationsForEmail
    , activeVenueOnboardingInvitationsForEmail
    , registeredInvitationAccountExists
    ) where

import Application.Helper.VenueInvitation (venueInvitationIsActive)
import Application.Helper.VenueOnboardingInvitation (venueOnboardingInvitationIsActive)
import Generated.Types
import IHP.ControllerPrelude

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
