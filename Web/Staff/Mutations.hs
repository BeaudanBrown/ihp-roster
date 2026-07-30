module Web.Staff.Mutations
    ( createTrialStaffInvitationMutation
    , renewTrialStaffInvitationMutation
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
import Application.VenueInvitation.Mutations (withTrialStaffInvitationLock,
                                              withVenueInvitationRenewalLock)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import qualified Data.Text as Text
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
        maybeCreation <- withTrialStaffInvitationLock (unpackId staff.id) (Text.toCaseFold email) do
            lockedStaff <- fetch staff.id
            existingPendingInvitation <- query @VenueInvitation
                |> filterWhere (#staffId, Just lockedStaff.id)
                |> filterWhere (#status, unsafeEnumFromText @InvitationStatusEnum "pending")
                |> fetchOneOrNothing
            existingUser <- query @User
                |> filterWhere (#email, email)
                |> fetchOneOrNothing
            case (existingPendingInvitation, existingUser) of
                (Just _, _) -> pure (Left "Renew the existing trial staff invitation instead of creating another link.")
                (_, Just _) -> pure (Left "That email already has an account. Trial adoption invites must create a new account.")
                _ | not (isAdoptableTrialStaff lockedStaff) -> pure (Left "Only active trial staff without a linked login can be invited.")
                _ -> do
                    now <- getCurrentTime
                    invitation <- newRecord @VenueInvitation
                        |> set #venueId (unpackId currentVenueId)
                        |> set #invitedByUserId (Just (unpackId currentUser.id))
                        |> set #staffId (Just lockedStaff.id)
                        |> set #email email
                        |> set #inviteRole (venueRoleToEnum WorkerRole)
                        |> set #status (unsafeEnumFromText @InvitationStatusEnum "pending")
                        |> set #deliveryStatus (unsafeEnumFromText @InvitationDeliveryStatusEnum "queued")
                        |> set #expiresAt (Just (addUTCTime venueInvitationLifetime now))
                        |> createRecord
                    void (enqueueVenueInvitationDeliveryJob (Just currentUser.id) invitation)
                    pure (Right invitation)
        case maybeCreation of
            Nothing -> pure (Left "That trial staff member is no longer available to invite.")
            Just (Left message) -> pure (Left message)
            Just (Right invitation) ->
                Right <$> invalidateTouchedResources "staff.invite_trial" (liveMutationResult invitation (trialStaffInvitationTouchedResources staff))

renewTrialStaffInvitationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> VenueInvitation -> Text -> IO (Either Text (LiveMutationResult VenueInvitation))
renewTrialStaffInvitationMutation staff invitation correctedEmail
    | staff.venueId /= unpackId currentVenueId = pure (Left "Choose trial staff from the current venue.")
    | invitation.venueId /= unpackId currentVenueId = pure (Left "Choose an invitation from the current venue.")
    | invitation.staffId /= Just staff.id = pure (Left "Choose a pending invitation for this trial staff member.")
    | otherwise = do
        maybeRenewal <- withVenueInvitationRenewalLock
            (unpackId invitation.id)
            (Just (unpackId staff.id))
            (Text.toCaseFold correctedEmail)
            do
                lockedInvitation <- fetch invitation.id
                lockedStaff <- fetch staff.id
                if lockedInvitation.staffId /= Just lockedStaff.id
                    then pure (Left "Choose a pending invitation for this trial staff member.")
                    else if inputValue lockedInvitation.status /= ("pending" :: Text)
                        then pure (Left "Only pending invitations can be renewed.")
                    else if not (isAdoptableTrialStaff lockedStaff)
                        then pure (Left "Only active trial staff without a linked login can be invited.")
                    else do
                        existingUser <- query @User
                            |> filterWhere (#email, correctedEmail)
                            |> fetchOneOrNothing
                        case existingUser of
                            Just _ -> pure (Left "That email already has an account. Trial adoption invites must create a new account.")
                            Nothing -> Right <$> replaceTrialStaffInvitation lockedStaff lockedInvitation correctedEmail
        case maybeRenewal of
            Nothing -> pure (Left "That invitation is no longer available to renew.")
            Just (Left message) -> pure (Left message)
            Just (Right renewedInvitation) ->
                Right <$> invalidateTouchedResources "staff.renew_trial_invite" (liveMutationResult renewedInvitation (trialStaffInvitationTouchedResources staff))

replaceTrialStaffInvitation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> VenueInvitation -> Text -> IO VenueInvitation
replaceTrialStaffInvitation staff invitation correctedEmail = do
    now <- getCurrentTime
    pendingInvitations <- query @VenueInvitation
        |> filterWhere (#staffId, Just staff.id)
        |> filterWhere (#status, unsafeEnumFromText @InvitationStatusEnum "pending")
        |> fetch
    forM_ pendingInvitations \pendingInvitation ->
        void $
            pendingInvitation
                |> set #status (unsafeEnumFromText @InvitationStatusEnum "revoked")
                |> updateRecord
    replacement <- newRecord @VenueInvitation
        |> set #venueId invitation.venueId
        |> set #invitedByUserId (Just (unpackId currentUser.id))
        |> set #staffId (Just staff.id)
        |> set #email correctedEmail
        |> set #inviteRole invitation.inviteRole
        |> set #status (unsafeEnumFromText @InvitationStatusEnum "pending")
        |> set #deliveryStatus (unsafeEnumFromText @InvitationDeliveryStatusEnum "queued")
        |> set #expiresAt (Just (addUTCTime venueInvitationLifetime now))
        |> createRecord
    void (enqueueVenueInvitationDeliveryJob (Just currentUser.id) replacement)
    pure replacement

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
