module Web.Users.Mutations
    ( acceptVenueInvitation
    , acceptedVenueInvitationTouchedResources
    ) where

import Application.Helper.LiveResource
import Application.Helper.VenueBootstrap (provisionVenueMembership)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Web.Controller.Prelude
import Web.LiveResourceInvalidation (invalidateTouchedResources)

acceptVenueInvitation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => UTCTime -> VenueInvitation -> User -> Text -> IO (LiveMutationResult User)
acceptVenueInvitation acceptedAt invitation user hashedPassword = do
    acceptedUser <- withTransaction do
        verifiedAt <- getCurrentTime
        acceptedUser <-
            user
                |> set #passwordHash hashedPassword
                |> set #emailVerifiedAt (Just verifiedAt)
                |> createRecord
        venue <- fetch (Id invitation.venueId :: Id Venue)
        membership <- provisionVenueMembership venue acceptedUser (inputValue invitation.inviteRole)
        _ <-
            invitation
                |> set #status (unsafeEnumFromText @InvitationStatusEnum "accepted")
                |> set #acceptedByUserId (Just (unpackId (get #id acceptedUser)))
                |> set #acceptedAt (Just acceptedAt)
                |> updateRecord
        void $
            recordAuditEvent
                invitation.venueId
                (unpackId (get #id acceptedUser))
                "venue_role_assigned"
                "venue_memberships"
                (unpackId (get #id membership))
                ( Aeson.object
                    [ "email" Aeson..= acceptedUser.email
                    , "assignedRole" Aeson..= inputValue membership.venueRole
                    , "invitationId" Aeson..= unpackId (get #id invitation)
                    ]
                )
                requestAuditSourceChannel
        void $
            recordVenueMembershipRoleEvent
                invitation.venueId
                (unpackId (get #id acceptedUser))
                membership
                (unsafeEnumFromText @VenueMembershipRoleEventTypeEnum "assigned")
                Nothing
                membership.venueRole
                ( Aeson.object
                    [ "email" Aeson..= acceptedUser.email
                    , "invitationId" Aeson..= unpackId (get #id invitation)
                    ]
                )
        pure acceptedUser
    invalidateTouchedResources "user.invitation.accept" $
        liveMutationResult acceptedUser (acceptedVenueInvitationTouchedResources invitation)

acceptedVenueInvitationTouchedResources :: VenueInvitation -> [LiveResource]
acceptedVenueInvitationTouchedResources invitation =
    [AdminInvitesResource invitation.venueId]
