module Web.Staff.Mutations
    ( createTrialStaffInvitationMutation
    , createTrialStaffMember
    , staffCreateTouchedResources
    , staffUpdateTouchedResources
    , staffXeroPayItemScopeChanged
    , updateStaffMember
    ) where

import Application.Helper.Audit (updateVenueMembershipRoleWithAudit)
import Application.Helper.LiveResource
import Application.Helper.LiveUpdate.Runtime (LiveUpdateScope (..),
                                              activeLiveUpdateScopes)
import Application.Helper.Pay (ensureStaffPayVersionForStaff)
import Application.Helper.RosterGroups (syncStaffRosterGroupAssignments)
import Application.Helper.Staff (isAdoptableTrialStaff)
import Application.Helper.StaffShiftPreferences (ShiftPreferenceSelection,
                                                 replaceStaffShiftPreferences)
import Application.Helper.VenueInvitation (venueInvitationLifetime)
import Application.InvitationDelivery.Job (enqueueVenueInvitationDeliveryJob)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import Data.Time.Clock (addUTCTime, getCurrentTime, utctDay)
import Web.Controller.Prelude
import Web.LiveResourceInvalidation (invalidateTouchedResources)

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

trialStaffInvitationTouchedResources :: (?context :: ControllerContext) => Staff -> [LiveResource]
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
    activeScopes <- activeLiveUpdateScopes
    invalidateTouchedResources "staff.create_trial" (liveMutationResult createdStaff (staffCreateTouchedResources createdStaff <> staffRosterGroupResources activeScopes selectedRosterGroupIds))

staffCreateTouchedResources :: Staff -> [LiveResource]
staffCreateTouchedResources staff =
    [ staffProfileResource (unpackId staff.id)
    , staffPreferencesResource (unpackId staff.id)
    ]

updateStaffMember :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> Staff -> [Id RosterGroup] -> [ShiftPreferenceSelection] -> Maybe VenueMembership -> Maybe VenueRoleEnum -> IO (LiveMutationResult Staff)
updateStaffMember originalStaff staff selectedRosterGroupIds submittedSelections maybeMembership maybeVenueRole = do
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
    activeScopes <- activeLiveUpdateScopes
    invalidateTouchedResources "staff.update" (liveMutationResult updatedStaff (staffUpdateTouchedResources payScopeChanged updatedStaff <> staffRosterGroupResources activeScopes selectedRosterGroupIds))

staffUpdateTouchedResources :: Bool -> Staff -> [LiveResource]
staffUpdateTouchedResources payScopeChanged staff =
    [ staffProfileResource (unpackId staff.id)
    , staffPreferencesResource (unpackId staff.id)
    ]
        <> [xeroMappingsResource staff.venueId | payScopeChanged]

staffRosterGroupResources :: (?context :: ControllerContext) => [LiveUpdateScope] -> [Id RosterGroup] -> [LiveResource]
staffRosterGroupResources activeScopes rosterGroupIds =
    Set.toList $ Set.fromList
        [ rosterWeekResource rosterGroupId weekOffset
        | RosterWeekScope { venueId = activeVenueId, rosterGroupId, weekOffset } <- activeScopes
        , activeVenueId == unpackId currentVenueId
        , rosterGroupId `Set.member` rosterGroupIdSet
        ]
    where
        rosterGroupIdSet = Set.fromList (map unpackId rosterGroupIds)
