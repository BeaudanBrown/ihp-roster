module Web.Users.Mutations
    ( acceptVenueInvitation
    , acceptedVenueInvitationTouchedResources
    ) where

import Application.Helper.LiveResource
import Application.Helper.VenueBootstrap (ensureLinkedStaffRecord,
                                          provisionVenueMembership)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Web.Controller.Prelude
import Web.LiveResourceInvalidation (invalidateTouchedResourcesWithoutContext)

acceptVenueInvitation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => UTCTime -> VenueInvitation -> User -> Text -> Staff -> IO (LiveMutationResult User)
acceptVenueInvitation acceptedAt invitation user hashedPassword staffInput = do
    acceptedUser <- withTransaction do
        verifiedAt <- getCurrentTime
        acceptedUser <-
            user
                |> set #passwordHash hashedPassword
                |> set #emailVerifiedAt (Just verifiedAt)
                |> set #isProfileCompleted True
                |> createRecord
        venue <- fetch (Id invitation.venueId :: Id Venue)
        membership <- provisionVenueMembership venue acceptedUser (inputValue invitation.inviteRole)
        adoptedStaff <- acceptInvitationStaffLink invitation venue acceptedUser staffInput
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
                    , "adoptedStaffId" Aeson..= fmap (unpackId . get #id) adoptedStaff
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
    invalidateTouchedResourcesWithoutContext "user.invitation.accept" $
        liveMutationResult acceptedUser (acceptedVenueInvitationTouchedResources invitation)

acceptInvitationStaffLink :: (?modelContext :: ModelContext) => VenueInvitation -> Venue -> User -> Staff -> IO (Maybe Staff)
acceptInvitationStaffLink invitation venue acceptedUser staffInput =
    case invitation.staffId of
        Nothing -> do
            linkedStaff <- ensureLinkedStaffRecord venue acceptedUser staffInput.firstName staffInput.lastName
            _ <- applyAcceptedStaffInput linkedStaff staffInput |> updateRecord
            pure Nothing
        Just staffId -> do
            targetStaff <- query @Staff
                |> filterWhere (#id, staffId)
                |> filterWhere (#venueId, invitation.venueId)
                |> filterWhere (#userId, Nothing :: Maybe UUID)
                |> filterWhere (#isActive, True)
                |> filterWhere (#archivedAt, Nothing :: Maybe UTCTime)
                |> fetchOne
            updatedStaff <- applyAcceptedStaffInput targetStaff staffInput
                |> set #userId (Just (unpackId acceptedUser.id))
                |> updateRecord
            pure (Just updatedStaff)

applyAcceptedStaffInput :: Staff -> Staff -> Staff
applyAcceptedStaffInput staff staffInput =
    staff
        |> set #firstName staffInput.firstName
        |> set #lastName staffInput.lastName
        |> set #preferredName staffInput.preferredName
        |> set #phone staffInput.phone
        |> set #emergencyContactName staffInput.emergencyContactName
        |> set #emergencyContactPhone staffInput.emergencyContactPhone
        |> set #idealShiftsPerWeek staffInput.idealShiftsPerWeek

acceptedVenueInvitationTouchedResources :: VenueInvitation -> [LiveResource]
acceptedVenueInvitationTouchedResources invitation =
    [adminInvitesResource invitation.venueId]
        <> case invitation.staffId of
            Nothing -> []
            Just staffId ->
                [ staffProfileResource (unpackId staffId)
                , staffPreferencesResource (unpackId staffId)
                ]
