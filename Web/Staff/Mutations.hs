module Web.Staff.Mutations
    ( createTrialStaffInvitationMutation
    , resendTrialStaffInvitationMutation
    , createTrialStaffMember
    , staffCreateTouchedResources
    , staffRosterGroupResources
    , staffTimesheetResources
    , staffUpdateTouchedResources
    , staffXeroPayItemScopeChanged
    , updateStaffMember
    ) where

import Application.Helper.Audit (updateVenueMembershipRoleWithAudit)
import Application.Helper.FrontendContract.Surface.Admin.Resource (adminInvitesResource)
import Application.Helper.FrontendContract.Surface.Profile.Resource
import Application.Helper.FrontendContract.Surface.Roster.Live (activeRosterWeekScopes)
import Application.Helper.FrontendContract.Surface.Timesheets.Live (activeTimesheetWeekScopes)
import Application.Helper.FrontendContract.Surface.Timesheets.Resource (timesheetWeekResource)
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
import Web.RosterWeeks.SurfaceInvalidation (activeRosterResourcesForStaffGroups)
import Web.SurfaceInvalidation (invalidateTouchedResources)

staffXeroPayItemScopeChanged :: Staff -> Staff -> Bool
staffXeroPayItemScopeChanged oldStaff newStaff =
    staffXeroPayItemScope oldStaff /= staffXeroPayItemScope newStaff

staffXeroPayItemScope :: Staff -> Maybe (PayAssignmentModeEnum, Maybe (Id AwardLevel), Maybe (Id XeroImportedPayItem), StaffEmploymentBasisEnum)
staffXeroPayItemScope staff
    | staff.isActive && isNothing staff.archivedAt =
        Just (staff.payAssignmentMode, staff.defaultAwardLevelId, staff.importedXeroPayItemId, staff.employmentBasis)
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
    activeRosterScopes <- activeRosterWeekScopes
    activeTimesheetScopes <- activeTimesheetWeekScopes
    let affectedRosterGroupIds = nub (previousRosterGroupIds <> selectedRosterGroupIds)
        payResources =
            if staffPayDispositionChanged originalStaff updatedStaff
                then staffTimesheetResources (unpackId currentVenueId) activeTimesheetScopes
                else []
    invalidateTouchedResources "staff.update" (liveMutationResult updatedStaff (staffUpdateTouchedResources updatedStaff <> staffRosterGroupResources (unpackId currentVenueId) activeRosterScopes affectedRosterGroupIds <> payResources))

staffUpdateTouchedResources :: Staff -> [SurfaceResourceValue]
staffUpdateTouchedResources staff =
    [ staffProfileResource (unpackId staff.id)
    , staffPreferencesResource (unpackId staff.id)
    ]

staffRosterGroupResources :: UUID -> [(UUID, UUID, Int)] -> [Id RosterGroup] -> [SurfaceResourceValue]
staffRosterGroupResources = activeRosterResourcesForStaffGroups

staffTimesheetResources :: UUID -> [(UUID, Int)] -> [SurfaceResourceValue]
staffTimesheetResources venueId activeScopes =
    Set.toList $ Set.fromList
        [ timesheetWeekResource activeVenueId weekOffset
        | (activeVenueId, weekOffset) <- activeScopes
        , activeVenueId == venueId
        ]

staffPayDispositionChanged :: Staff -> Staff -> Bool
staffPayDispositionChanged previous next =
    (previous.payAssignmentMode, previous.defaultAwardLevelId, previous.importedXeroPayItemId)
        /= (next.payAssignmentMode, next.defaultAwardLevelId, next.importedXeroPayItemId)
