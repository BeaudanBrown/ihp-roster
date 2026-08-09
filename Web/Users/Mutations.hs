module Web.Users.Mutations
    ( acceptVenueInvitationInCurrentTransaction
    , invalidateAcceptedVenueInvitation
    , acceptedVenueInvitationTouchedResources
    , acceptedVenueInvitationTouchedResourcesForScopes
    ) where

import Application.Helper.FrontendContract.Surface.Admin.Resource (adminInvitesResource)
import Application.Helper.FrontendContract.Surface.Profile.Resource (staffPreferencesResource,
                                                                     staffProfileResource)
import Application.Helper.FrontendContract.Surface.Roster.Live (activeRosterWindowScopes)
import Application.Helper.FrontendContract.Surface.Timesheets.Live (activeTimesheetWindowScopes)
import Application.Helper.FrontendContract.Surface.Timesheets.Resource (timesheetWeekResource)
import Application.Helper.RosterGroups (fetchStaffRosterGroupIds)
import Application.Helper.SurfaceResource
import Application.Helper.VenueBootstrap (ensureLinkedStaffRecord,
                                          provisionVenueMembership)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import Data.Time.Calendar (Day)
import Data.UUID (UUID)
import Web.Controller.Prelude
import Web.RosterWeeks.SurfaceInvalidation (activeRosterResourcesForStaffGroups)
import Web.SurfaceInvalidation (invalidateTouchedResources)

acceptVenueInvitationInCurrentTransaction :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => UTCTime -> VenueInvitation -> User -> Text -> Staff -> IO (LiveMutationResult User)
acceptVenueInvitationInCurrentTransaction acceptedAt invitation user hashedPassword staffInput = do
    (acceptedUser, adoptedStaff) <- do
        verifiedAt <- getCurrentTime
        acceptedUser <-
            user
                |> set #passwordHash hashedPassword
                |> set #emailVerifiedAt (Just verifiedAt)
                |> set #isProfileCompleted True
                |> createRecord
        venue <- fetch (Id invitation.venueId :: Id Venue)
        membership <- provisionVenueMembership venue acceptedUser invitation.inviteRole
        adoptedStaff <- acceptInvitationStaffLink invitation venue acceptedUser staffInput
        _ <-
            invitation
                |> set #status (Accepted)
                |> set #acceptedByUserId (Just (unpackId (get #id acceptedUser)))
                |> set #acceptedAt (Just acceptedAt)
                |> updateRecord
        void $
            recordAuditEvent
                invitation.venueId
                (unpackId (get #id acceptedUser))
                VenueRoleAssignedAudit
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
                (Assigned)
                Nothing
                membership.venueRole
                ( Aeson.object
                    [ "email" Aeson..= acceptedUser.email
                    , "invitationId" Aeson..= unpackId (get #id invitation)
                    ]
                )
        pure (acceptedUser, adoptedStaff)
    touchedResources <- case adoptedStaff of
        Nothing -> pure (acceptedVenueInvitationTouchedResources invitation)
        Just staff -> do
            activeRosterScopes <- activeRosterWindowScopes
            activeTimesheetScopes <- activeTimesheetWindowScopes
            rosterGroupIds <- fetchStaffRosterGroupIds staff
            pure (acceptedVenueInvitationTouchedResourcesForScopes invitation activeRosterScopes activeTimesheetScopes rosterGroupIds)
    pure (liveMutationResult acceptedUser touchedResources)

invalidateAcceptedVenueInvitation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => LiveMutationResult User -> IO (LiveMutationResult User)
invalidateAcceptedVenueInvitation =
    invalidateTouchedResources "user.invitation.accept"

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

acceptedVenueInvitationTouchedResources :: VenueInvitation -> [SurfaceResourceValue]
acceptedVenueInvitationTouchedResources invitation =
    acceptedVenueInvitationTouchedResourcesForScopes invitation [] [] []

acceptedVenueInvitationTouchedResourcesForScopes ::
    VenueInvitation ->
    [(UUID, UUID, Day, Day, Int)] ->
    [(UUID, Day, Day, Int)] ->
    [Id RosterGroup] ->
    [SurfaceResourceValue]
acceptedVenueInvitationTouchedResourcesForScopes invitation activeRosterScopes activeTimesheetScopes rosterGroupIds =
    [adminInvitesResource invitation.venueId]
        <> case invitation.staffId of
            Nothing -> []
            Just staffId ->
                [ staffProfileResource (unpackId staffId)
                , staffPreferencesResource (unpackId staffId)
                ]
                    <> activeRosterResourcesForStaffGroups invitation.venueId activeRosterScopes rosterGroupIds
                    <> Set.toList
                        ( Set.fromList
                            [ timesheetWeekResource venueId windowStart windowEnd
                            | (venueId, windowStart, windowEnd, _calendarRevision) <- activeTimesheetScopes
                            , venueId == invitation.venueId
                            ]
                        )
