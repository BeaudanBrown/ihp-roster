module Web.Staff.Mutations
    ( createTrialStaffInvitationMutation
    , resendTrialStaffInvitationMutation
    , createTrialStaffMember
    , staffCreateTouchedResources
    , staffRosterGroupResources
    , staffUpdateTouchedResources
    , staffXeroPayItemScopeChanged
    , updateStaffMember
    ) where

import Application.Helper.Audit (updateVenueMembershipRoleWithAudit)
import Application.Helper.FrontendContract.Surface.Roster.Live (activeRosterWeekScopes)
import Application.Helper.Pay (ensureStaffPayVersionForStaff)
import Application.Helper.RosterGroups (fetchStaffRosterGroupIds,
                                        syncStaffRosterGroupAssignments)
import Application.Helper.Staff (isAdoptableTrialStaff)
import Application.Helper.StaffShiftPreferences (ShiftPreferenceSelection,
                                                 replaceStaffShiftPreferences)
import Application.Helper.SurfaceResource
import Application.Helper.VenueInvitation (venueInvitationLifetime)
import Application.InvitationDelivery.Job (enqueueVenueInvitationDeliveryJob)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import Data.Time.Clock (addUTCTime, getCurrentTime, utctDay)
import Data.UUID (UUID)
import Web.Controller.Prelude
import Web.SurfaceInvalidation (invalidateTouchedResources)

staffXeroPayItemScopeChanged :: Staff -> Staff -> Bool
staffXeroPayItemScopeChanged oldStaff newStaff =
    staffXeroPayItemScope oldStaff /= staffXeroPayItemScope newStaff

staffXeroPayItemScope :: Staff -> Maybe (Maybe (Id AwardLevel), Maybe (Id XeroImportedPayItem), StaffEmploymentBasisEnum)
staffXeroPayItemScope staff
    | staff.isActive && isNothing staff.archivedAt =
        Just (staff.defaultAwardLevelId, staff.importedXeroPayItemId, staff.employmentBasis)
    | otherwise = Nothing

createTrialStaffInvitationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> Text -> IO (Either Text (LiveMutationResult VenueInvitation))
createTrialStaffInvitationMutation staff email
    | staff.venueId /= unpackId currentVenueId = pure (Left "Choose trial staff from the current venue.")
    | not (isAdoptableTrialStaff staff) = pure (Left "Only active trial staff without a linked login can be invited.")
    | otherwise = do
        existingUser <- query @User
            |> filterWhere (#email, email)
            |> fetchOneOrNothing
        case existingUser of
            Just _ -> pure (Left "That email already has an account. Trial adoption invites must create a new account.")
            Nothing -> do
                now <- getCurrentTime
                invitation <- newRecord @VenueInvitation
                    |> set #venueId (unpackId currentVenueId)
                    |> set #invitedByUserId (Just (unpackId currentUser.id))
                    |> set #staffId (Just staff.id)
                    |> set #email email
                    |> set #inviteRole (venueRoleToEnum WorkerRole)
                    |> set #status (unsafeEnumFromText @InvitationStatusEnum "pending")
                    |> set #deliveryStatus (unsafeEnumFromText @InvitationDeliveryStatusEnum "queued")
                    |> set #expiresAt (Just (addUTCTime venueInvitationLifetime now))
                    |> createRecord
                void (enqueueVenueInvitationDeliveryJob (Just currentUser.id) invitation)
                Right <$> invalidateTouchedResources "staff.invite_trial" (liveMutationResult invitation (trialStaffInvitationTouchedResources staff))

resendTrialStaffInvitationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> VenueInvitation -> IO (Either Text (LiveMutationResult VenueInvitation))
resendTrialStaffInvitationMutation staff invitation
    | staff.venueId /= unpackId currentVenueId = pure (Left "Choose trial staff from the current venue.")
    | invitation.venueId /= unpackId currentVenueId = pure (Left "Choose an invitation from the current venue.")
    | invitation.staffId /= Just staff.id = pure (Left "Choose a pending invitation for this trial staff member.")
    | inputValue invitation.status /= ("pending" :: Text) = pure (Left "Only pending invitations can be resent.")
    | not (isAdoptableTrialStaff staff) = pure (Left "Only active trial staff without a linked login can be invited.")
    | otherwise = do
        now <- getCurrentTime
        resentInvitation <- invitation
            |> set #deliveryStatus (unsafeEnumFromText @InvitationDeliveryStatusEnum "queued")
            |> set #deliveryError Nothing
            |> set #expiresAt (Just (addUTCTime venueInvitationLifetime now))
            |> updateRecord
        void (enqueueVenueInvitationDeliveryJob (Just currentUser.id) resentInvitation)
        Right <$> invalidateTouchedResources "staff.resend_trial_invite" (liveMutationResult resentInvitation (trialStaffInvitationTouchedResources staff))

trialStaffInvitationTouchedResources :: (?context :: ControllerContext) => Staff -> [SurfaceResourceValue]
trialStaffInvitationTouchedResources staff =
    [ adminInvitesResource (unpackId currentVenueId)
    , staffProfileResource (unpackId staff.id)
    ]

createTrialStaffMember :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> [Id RosterGroup] -> IO (LiveMutationResult Staff)
createTrialStaffMember staff selectedRosterGroupIds = do
    createdStaff <- withTransaction do
        createdStaff <- staff |> createRecord
        syncStaffRosterGroupAssignments createdStaff selectedRosterGroupIds
        pure createdStaff
    activeRosterScopes <- activeRosterWeekScopes
    invalidateTouchedResources "staff.create_trial" (liveMutationResult createdStaff (staffCreateTouchedResources createdStaff <> staffRosterGroupResources (unpackId currentVenueId) activeRosterScopes selectedRosterGroupIds))

staffCreateTouchedResources :: Staff -> [SurfaceResourceValue]
staffCreateTouchedResources staff =
    [ staffProfileResource (unpackId staff.id)
    , staffPreferencesResource (unpackId staff.id)
    ]

updateStaffMember :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> Staff -> [Id RosterGroup] -> [ShiftPreferenceSelection] -> Maybe VenueMembership -> Maybe VenueRoleEnum -> IO (LiveMutationResult Staff)
updateStaffMember originalStaff staff selectedRosterGroupIds submittedSelections maybeMembership maybeVenueRole = do
    previousRosterGroupIds <- fetchStaffRosterGroupIds originalStaff
    updatedStaff <- withTransaction do
        updatedStaff <- staff |> updateRecord
        syncStaffRosterGroupAssignments updatedStaff selectedRosterGroupIds
        replaceStaffShiftPreferences updatedStaff submittedSelections
        when (staffXeroPayItemScopeChanged originalStaff updatedStaff) do
            today <- utctDay <$> getCurrentTime
            void (ensureStaffPayVersionForStaff currentUser.id updatedStaff today)
        pure updatedStaff
    forM_ ((,) <$> maybeMembership <*> maybeVenueRole) \(membership, venueRole) ->
        void $ updateVenueMembershipRoleWithAudit
            (unpackId currentUser.id)
            "web"
            membership
            venueRole
            (Aeson.object ["staffId" Aeson..= tshow staff.id])
    let payScopeChanged = staffXeroPayItemScopeChanged originalStaff updatedStaff
    activeRosterScopes <- activeRosterWeekScopes
    let affectedRosterGroupIds = nub (previousRosterGroupIds <> selectedRosterGroupIds)
    invalidateTouchedResources "staff.update" (liveMutationResult updatedStaff (staffUpdateTouchedResources payScopeChanged updatedStaff <> staffRosterGroupResources (unpackId currentVenueId) activeRosterScopes affectedRosterGroupIds))

staffUpdateTouchedResources :: Bool -> Staff -> [SurfaceResourceValue]
staffUpdateTouchedResources payScopeChanged staff =
    [ staffProfileResource (unpackId staff.id)
    , staffPreferencesResource (unpackId staff.id)
    ]
        <> [xeroMappingsResource staff.venueId | payScopeChanged]

staffRosterGroupResources :: UUID -> [(UUID, UUID, Int)] -> [Id RosterGroup] -> [SurfaceResourceValue]
staffRosterGroupResources venueId activeScopes rosterGroupIds =
    Set.toList $ Set.fromList
        [ rosterWeekResource rosterGroupId weekOffset
        | (activeVenueId, rosterGroupId, weekOffset) <- activeScopes
        , activeVenueId == venueId
        , rosterGroupId `Set.member` rosterGroupIdSet
        ]
    where
        rosterGroupIdSet = Set.fromList (map unpackId rosterGroupIds)
