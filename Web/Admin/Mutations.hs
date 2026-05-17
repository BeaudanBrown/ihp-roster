module Web.Admin.Mutations
    ( AdminShiftTypeMutationResult (..)
    , adminVenueConfigTouchedResources
    , createRosterGroupMutation
    , createShiftTypeMutation
    , createVenueInvitationMutation
    , ensureAdminRosterGroupsNormalizedMutation
    , moveRosterGroupMutation
    , moveShiftTypeMutation
    , revokeVenueInvitationMutation
    , setAutoTimesheetCreationEnabledMutation
    , setRosterEndTimesEnabledMutation
    , setRosterWeekStartsOnMutation
    , shiftTypeAffectsXeroPayItems
    , shiftTypeXeroPayItemScopeChanged
    , updateRosterGroupMutation
    , updateShiftTypeMutation
    ) where

import Application.Helper.LiveResource
import Application.Helper.Pay (ensureShiftTypePayVersionForShiftType)
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        ensureDefaultRosterSlots,
                                        syncVenueDefaultRosterGroupToTopActive)
import Application.Helper.VenueInvitation
import Application.Helper.WeekBoundaries (defaultWeekOffsetEpochForStartDay)
import Application.InvitationDelivery.Job (enqueueVenueInvitationDeliveryJob)
import Control.Monad (void)
import Data.Time.Clock (addUTCTime, getCurrentTime, utctDay)
import Web.Controller.Admin.Support
import Web.Controller.Admin.Xero.Responses (refreshAdminXero)
import Web.Controller.Prelude

data AdminShiftTypeMutationResult = AdminShiftTypeMutationResult
    { adminShiftTypeMutationShiftType         :: !ShiftType
    , adminShiftTypeMutationShouldRefreshXero :: !Bool
    }

setRosterEndTimesEnabledMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueConfig -> Bool -> IO (LiveMutationResult VenueConfig)
setRosterEndTimesEnabledMutation venueConfig rosterEndTimesEnabled = do
    updated <- venueConfig
        |> set #rosterEndTimesEnabled rosterEndTimesEnabled
        |> updateRecord
    pure (liveMutationResult updated (adminVenueConfigTouchedResources currentVenueId))

setAutoTimesheetCreationEnabledMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueConfig -> Bool -> IO (LiveMutationResult VenueConfig)
setAutoTimesheetCreationEnabledMutation venueConfig autoTimesheetCreationEnabled = do
    updated <- venueConfig
        |> set #autoTimesheetCreationEnabled autoTimesheetCreationEnabled
        |> updateRecord
    pure (liveMutationResult updated (adminVenueConfigTouchedResources currentVenueId))

setRosterWeekStartsOnMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueConfig -> Int -> IO (LiveMutationResult VenueConfig)
setRosterWeekStartsOnMutation venueConfig rosterWeekStartsOn = do
    updated <- withTransaction do
        venueConfig
            |> set #rosterWeekStartsOn rosterWeekStartsOn
            |> set #weekOffsetEpoch (defaultWeekOffsetEpochForStartDay rosterWeekStartsOn)
            |> updateRecord
    pure (liveMutationResult updated (adminVenueConfigTouchedResources currentVenueId))

adminVenueConfigTouchedResources :: Id Venue -> [LiveResource]
adminVenueConfigTouchedResources venueId =
    [AdminVenueConfigResource (unpackId venueId)]

createVenueInvitationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> IO (LiveMutationResult VenueInvitation)
createVenueInvitationMutation email = do
    now <- getCurrentTime
    invitation <- newRecord @VenueInvitation
        |> set #venueId (unpackId currentVenueId)
        |> set #invitedByUserId (Just (unpackId currentUser.id))
        |> set #email email
        |> set #inviteRole (venueRoleToEnum WorkerRole)
        |> set #status (unsafeEnumFromText @InvitationStatusEnum "pending")
        |> set #deliveryStatus (unsafeEnumFromText @InvitationDeliveryStatusEnum "queued")
        |> set #expiresAt (Just (addUTCTime venueInvitationLifetime now))
        |> createRecord
    refreshAdminInvites currentVenueId
    void (enqueueVenueInvitationDeliveryJob (Just currentUser.id) invitation)
    pure (liveMutationResult invitation [AdminInvitesResource (unpackId currentVenueId)])

revokeVenueInvitationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueInvitation -> IO (LiveMutationResult VenueInvitation)
revokeVenueInvitationMutation invitation = do
    updated <- invitation
        |> set #status (unsafeEnumFromText @InvitationStatusEnum "revoked")
        |> updateRecord
    refreshAdminInvites currentVenueId
    pure (liveMutationResult updated [AdminInvitesResource (unpackId currentVenueId)])

ensureAdminRosterGroupsNormalizedMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO (LiveMutationResult ())
ensureAdminRosterGroupsNormalizedMutation = do
    syncVenueDefaultRosterGroupToTopActive currentVenueId
    pure (liveMutationResult () [AdminRosterGroupsResource (unpackId currentVenueId)])

createRosterGroupMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Venue -> Text -> Bool -> IO (LiveMutationResult RosterGroup)
createRosterGroupMutation venue name isActive = do
    sortOrder <- nextRosterGroupSortOrder
    rosterGroup <- createVenueRosterGroupWithDefaults venue name sortOrder isActive
    syncVenueDefaultRosterGroupToTopActive currentVenueId
    refreshAdminRosterGroups currentVenueId
    pure (liveMutationResult rosterGroup [AdminRosterGroupsResource (unpackId currentVenueId)])

updateRosterGroupMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Venue -> RosterGroup -> Text -> Bool -> IO (LiveMutationResult RosterGroup)
updateRosterGroupMutation venue rosterGroup name isActive = do
    sortOrder <-
        if not rosterGroup.isActive && isActive
            then nextRosterGroupSortOrder
            else pure rosterGroup.sortOrder
    updatedRosterGroup <- rosterGroup
        |> set #name name
        |> set #sortOrder sortOrder
        |> set #isActive isActive
        |> updateRecord
    when isActive do
        _ <- ensureDefaultRosterSlots venue updatedRosterGroup
        pure ()
    syncVenueDefaultRosterGroupToTopActive currentVenueId
    refreshAdminRosterGroups currentVenueId
    pure (liveMutationResult updatedRosterGroup [AdminRosterGroupsResource (unpackId currentVenueId)])

moveRosterGroupMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterGroup -> Int -> IO (LiveMutationResult ())
moveRosterGroupMutation _rosterGroup direction = do
    withTransaction do
        reorderActiveRosterGroups _rosterGroup.id direction
        syncVenueDefaultRosterGroupToTopActive currentVenueId
    refreshAdminRosterGroups currentVenueId
    pure (liveMutationResult () [AdminRosterGroupsResource (unpackId currentVenueId)])

createShiftTypeMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> Bool -> Maybe (Id AwardLevel) -> IO (LiveMutationResult AdminShiftTypeMutationResult)
createShiftTypeMutation name isActive overrideAwardLevelId = do
    sortOrder <- nextShiftTypeSortOrder
    now <- getCurrentTime
    shiftType <- withTransaction do
        shiftType <- newRecord @ShiftType
            |> set #venueId (unpackId currentVenueId)
            |> set #name name
            |> set #sortOrder sortOrder
            |> set #overrideAwardLevelId overrideAwardLevelId
            |> set #isActive isActive
            |> createRecord
        _ <- ensureShiftTypePayVersionForShiftType currentUser.id shiftType (utctDay now)
        pure shiftType
    let shouldRefreshXero = shiftTypeAffectsXeroPayItems shiftType
    refreshShiftTypeSurfaces shouldRefreshXero
    pure (liveMutationResult (AdminShiftTypeMutationResult shiftType shouldRefreshXero) (shiftTypeTouchedResources shouldRefreshXero))

updateShiftTypeMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ShiftType -> Text -> Bool -> Maybe (Id AwardLevel) -> IO (LiveMutationResult AdminShiftTypeMutationResult)
updateShiftTypeMutation shiftType name isActive overrideAwardLevelId = do
    now <- getCurrentTime
    sortOrder <-
        if not shiftType.isActive && isActive
            then nextShiftTypeSortOrder
            else pure shiftType.sortOrder
    updatedShiftType <- withTransaction do
        updated <- shiftType
            |> set #name name
            |> set #sortOrder sortOrder
            |> set #overrideAwardLevelId overrideAwardLevelId
            |> set #isActive isActive
            |> updateRecord
        when (shiftType.name /= updated.name || shiftType.overrideAwardLevelId /= updated.overrideAwardLevelId) do
            _ <- ensureShiftTypePayVersionForShiftType currentUser.id updated (utctDay now)
            pure ()
        pure updated
    let shouldRefreshXero = shiftTypeXeroPayItemScopeChanged shiftType updatedShiftType
    refreshShiftTypeSurfaces shouldRefreshXero
    pure (liveMutationResult (AdminShiftTypeMutationResult updatedShiftType shouldRefreshXero) (shiftTypeTouchedResources shouldRefreshXero))

moveShiftTypeMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ShiftType -> Int -> IO (LiveMutationResult ())
moveShiftTypeMutation shiftType direction = do
    withTransaction do
        reorderActiveShiftTypes shiftType.id direction
        pure ()
    refreshAdminShiftTypes currentVenueId
    pure (liveMutationResult () [AdminShiftTypesResource (unpackId currentVenueId)])

refreshShiftTypeSurfaces :: (?context :: ControllerContext, ?request :: Request) => Bool -> IO ()
refreshShiftTypeSurfaces shouldRefreshXero = do
    refreshAdminShiftTypes currentVenueId
    when shouldRefreshXero do
        refreshAdminXero currentVenueId

shiftTypeTouchedResources :: (?context :: ControllerContext) => Bool -> [LiveResource]
shiftTypeTouchedResources shouldRefreshXero =
    [AdminShiftTypesResource (unpackId currentVenueId)]
        <> [XeroPayItemsResource (unpackId currentVenueId) | shouldRefreshXero]

shiftTypeAffectsXeroPayItems :: ShiftType -> Bool
shiftTypeAffectsXeroPayItems shiftType =
    shiftType.isActive && isJust shiftType.overrideAwardLevelId

shiftTypeXeroPayItemScopeChanged :: ShiftType -> ShiftType -> Bool
shiftTypeXeroPayItemScopeChanged oldShiftType newShiftType =
    shiftTypeXeroPayItemScope oldShiftType /= shiftTypeXeroPayItemScope newShiftType

shiftTypeXeroPayItemScope :: ShiftType -> Maybe (Id AwardLevel)
shiftTypeXeroPayItemScope shiftType
    | shiftType.isActive = shiftType.overrideAwardLevelId
    | otherwise = Nothing
