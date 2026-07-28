module Web.Admin.Mutations
    ( AdminShiftTypeMutationResult (..)
    , adminVenueSettingsTouchedResources
    , createRosterGroupMutation
    , createShiftTypeMutation
    , createVenueInvitationMutation
    , ensureAdminRosterGroupsNormalizedMutation
    , moveRosterGroupMutation
    , moveShiftTypeMutation
    , revokeVenueInvitationMutation
    , rosterEndTimesTouchedResources
    , rosterTimePickerWindowTouchedResources
    , rosterWeekStartsOnTouchedResources
    , setRosterEndTimesEnabledMutation
    , setRosterTimePickerWindowMutation
    , setRosterWeekStartsOnMutation
    , shiftTypeAffectsXeroPayItems
    , shiftTypeXeroPayItemScopeChanged
    , updateRosterGroupMutation
    , updateShiftTypeMutation
    ) where

import Application.Helper.FrontendContract.Surface.Admin.Resource
import Application.Helper.FrontendContract.Surface.Roster.Resource
import Application.Helper.FrontendContract.Surface.Timesheets.Resource
import Application.Helper.Pay (ensureShiftTypePayVersionForShiftType)
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        ensureDefaultRosterSlots,
                                        syncVenueDefaultRosterGroupToTopActive)
import Application.Helper.ShiftTypeColours (assignShiftTypeColourKey,
                                            blankShiftTypeColourKey,
                                            normalizeShiftTypeColourKey)
import Application.Helper.SurfaceResource
import Application.Helper.TimeRules (formatMinuteOfDayText)
import Application.Helper.VenueInvitation
import Application.Helper.WeekBoundaries (defaultWeekOffsetEpochForStartDay)
import Application.InvitationDelivery.Job (enqueueVenueInvitationDeliveryJob)
import Application.PayAssignment (selectableShiftAssignmentMode)
import Control.Monad (void)
import Data.Time.Clock (addUTCTime, getCurrentTime, utctDay)
import Web.Controller.Admin.Support
import Web.Controller.Prelude
import Web.SurfaceInvalidation (invalidateTouchedResources)

data AdminShiftTypeMutationResult = AdminShiftTypeMutationResult
    { adminShiftTypeMutationShiftType         :: !ShiftType
    , adminShiftTypeMutationShouldRefreshXero :: !Bool
    }

setRosterEndTimesEnabledMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueConfig -> Bool -> IO (LiveMutationResult VenueConfig)
setRosterEndTimesEnabledMutation venueConfig rosterEndTimesEnabled = do
    updated <- venueConfig
        |> set #rosterEndTimesEnabled rosterEndTimesEnabled
        |> updateRecord
    invalidateTouchedResources "admin.venue_config.roster_end_times" (liveMutationResult updated (rosterEndTimesTouchedResources currentVenueId))

setRosterWeekStartsOnMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueConfig -> Int -> IO (LiveMutationResult VenueConfig)
setRosterWeekStartsOnMutation venueConfig rosterWeekStartsOn = do
    updated <- withTransaction do
        venueConfig
            |> set #rosterWeekStartsOn rosterWeekStartsOn
            |> set #weekOffsetEpoch (defaultWeekOffsetEpochForStartDay rosterWeekStartsOn)
            |> updateRecord
    invalidateTouchedResources "admin.venue_config.week_start" (liveMutationResult updated (rosterWeekStartsOnTouchedResources currentVenueId))

setRosterTimePickerWindowMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueConfig -> Int -> Int -> IO (LiveMutationResult VenueConfig)
setRosterTimePickerWindowMutation venueConfig startMinute finalSelectableMinute = do
    updated <- venueConfig
        |> set #timePickerStartMinuteOfDay startMinute
        |> set #timePickerFinalSelectableMinuteOfDay finalSelectableMinute
        |> updateRecord
    invalidateTouchedResources
        ("admin.venue_config.time_picker_window " <> formatMinuteOfDayText startMinute <> "-" <> formatMinuteOfDayText finalSelectableMinute)
        (liveMutationResult updated (rosterTimePickerWindowTouchedResources currentVenueId))

adminVenueSettingsTouchedResources :: Id Venue -> [SurfaceResourceValue]
adminVenueSettingsTouchedResources venueId =
    [adminVenueSettingsResource (unpackId venueId)]

rosterEndTimesTouchedResources :: Id Venue -> [SurfaceResourceValue]
rosterEndTimesTouchedResources venueId =
    adminVenueSettingsTouchedResources venueId <> [rosterEndTimesConfigResource (unpackId venueId)]

rosterTimePickerWindowTouchedResources :: Id Venue -> [SurfaceResourceValue]
rosterTimePickerWindowTouchedResources venueId =
    adminVenueSettingsTouchedResources venueId
        <> [ timePickerConfigResource (unpackId venueId) ]

rosterWeekStartsOnTouchedResources :: Id Venue -> [SurfaceResourceValue]
rosterWeekStartsOnTouchedResources venueId =
    adminVenueSettingsTouchedResources venueId
        <> [ rosterWeekBoundaryConfigResource (unpackId venueId)
           , timesheetWeekBoundaryConfigResource (unpackId venueId)
           ]

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
    void (enqueueVenueInvitationDeliveryJob (Just currentUser.id) invitation)
    invalidateTouchedResources "admin.invite.create" (liveMutationResult invitation [adminInvitesResource (unpackId currentVenueId)])

revokeVenueInvitationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueInvitation -> IO (LiveMutationResult VenueInvitation)
revokeVenueInvitationMutation invitation = do
    updated <- invitation
        |> set #status (unsafeEnumFromText @InvitationStatusEnum "revoked")
        |> updateRecord
    invalidateTouchedResources "admin.invite.revoke" (liveMutationResult updated [adminInvitesResource (unpackId currentVenueId)])

ensureAdminRosterGroupsNormalizedMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO (LiveMutationResult ())
ensureAdminRosterGroupsNormalizedMutation = do
    syncVenueDefaultRosterGroupToTopActive currentVenueId
    pure (liveMutationResult () [adminRosterGroupsResource (unpackId currentVenueId)])

createRosterGroupMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Venue -> Text -> Bool -> IO (LiveMutationResult RosterGroup)
createRosterGroupMutation venue name isActive = do
    sortOrder <- nextRosterGroupSortOrder
    rosterGroup <- createVenueRosterGroupWithDefaults venue name sortOrder isActive
    syncVenueDefaultRosterGroupToTopActive currentVenueId
    invalidateTouchedResources "admin.roster_group.create" (liveMutationResult rosterGroup [adminRosterGroupsResource (unpackId currentVenueId)])

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
    invalidateTouchedResources "admin.roster_group.update" (liveMutationResult updatedRosterGroup [adminRosterGroupsResource (unpackId currentVenueId)])

moveRosterGroupMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterGroup -> Int -> IO (LiveMutationResult ())
moveRosterGroupMutation _rosterGroup direction = do
    withTransaction do
        reorderActiveRosterGroups _rosterGroup.id direction
        syncVenueDefaultRosterGroupToTopActive currentVenueId
    invalidateTouchedResources "admin.roster_group.move" (liveMutationResult () [adminRosterGroupsResource (unpackId currentVenueId)])

createShiftTypeMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> Bool -> Maybe (Id AwardLevel) -> Maybe (Id XeroImportedPayItem) -> Bool -> Maybe Text -> IO (LiveMutationResult AdminShiftTypeMutationResult)
createShiftTypeMutation name isActive overrideAwardLevelId importedXeroPayItemId submittedRosterOnly maybeSubmittedColourKey = do
    sortOrder <- nextShiftTypeSortOrder
    colourKey <- resolveSubmittedShiftTypeColourKey Nothing isActive maybeSubmittedColourKey blankShiftTypeColourKey
    now <- getCurrentTime
    let payAssignmentMode = if submittedRosterOnly then RosterOnly else fromMaybe (error "validated shift pay selection contains conflicting rate sources") (selectableShiftAssignmentMode overrideAwardLevelId importedXeroPayItemId)
    shiftType <- withTransaction do
        shiftType <- newRecord @ShiftType
            |> set #venueId (unpackId currentVenueId)
            |> set #name name
            |> set #sortOrder sortOrder
            |> set #payAssignmentMode payAssignmentMode
            |> set #overrideAwardLevelId overrideAwardLevelId
            |> set #importedXeroPayItemId importedXeroPayItemId
            |> set #colourKey colourKey
            |> set #isActive isActive
            |> createRecord
        _ <- ensureShiftTypePayVersionForShiftType currentUser.id shiftType (utctDay now)
        pure shiftType
    let shouldRefreshXero = shiftTypeAffectsXeroPayItems shiftType
    invalidateTouchedResources "admin.shift_type.create" (liveMutationResult (AdminShiftTypeMutationResult shiftType shouldRefreshXero) shiftTypeTouchedResources)

updateShiftTypeMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ShiftType -> Text -> Bool -> Maybe (Id AwardLevel) -> Maybe (Id XeroImportedPayItem) -> Bool -> Maybe Text -> IO (LiveMutationResult AdminShiftTypeMutationResult)
updateShiftTypeMutation shiftType name isActive overrideAwardLevelId importedXeroPayItemId submittedRosterOnly maybeSubmittedColourKey = do
    now <- getCurrentTime
    sortOrder <-
        if not shiftType.isActive && isActive
            then nextShiftTypeSortOrder
            else pure shiftType.sortOrder
    colourKey <- resolveSubmittedShiftTypeColourKey (Just shiftType.id) isActive maybeSubmittedColourKey shiftType.colourKey
    let payAssignmentMode = if submittedRosterOnly then RosterOnly else fromMaybe (error "validated shift pay selection contains conflicting rate sources") (selectableShiftAssignmentMode overrideAwardLevelId importedXeroPayItemId)
    updatedShiftType <- withTransaction do
        updated <- shiftType
            |> set #name name
            |> set #sortOrder sortOrder
            |> set #payAssignmentMode payAssignmentMode
            |> set #overrideAwardLevelId overrideAwardLevelId
            |> set #importedXeroPayItemId importedXeroPayItemId
            |> set #colourKey colourKey
            |> set #isActive isActive
            |> updateRecord
        when (shiftType.name /= updated.name || shiftType.payAssignmentMode /= updated.payAssignmentMode || shiftType.overrideAwardLevelId /= updated.overrideAwardLevelId || shiftType.importedXeroPayItemId /= updated.importedXeroPayItemId) do
            _ <- ensureShiftTypePayVersionForShiftType currentUser.id updated (utctDay now)
            pure ()
        pure updated
    let shouldRefreshXero = shiftTypeXeroPayItemScopeChanged shiftType updatedShiftType
    invalidateTouchedResources "admin.shift_type.update" (liveMutationResult (AdminShiftTypeMutationResult updatedShiftType shouldRefreshXero) shiftTypeTouchedResources)

resolveSubmittedShiftTypeColourKey :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe (Id ShiftType) -> Bool -> Maybe Text -> Text -> IO Text
resolveSubmittedShiftTypeColourKey maybeCurrentShiftTypeId isActive maybeSubmittedColourKey fallbackColourKey =
    case maybeSubmittedColourKey of
        Nothing -> assignShiftTypeColourKey currentVenueId maybeCurrentShiftTypeId isActive fallbackColourKey
        Just submittedColourKey -> pure (normalizeShiftTypeColourKey submittedColourKey)

moveShiftTypeMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ShiftType -> Int -> IO (LiveMutationResult ())
moveShiftTypeMutation shiftType direction = do
    withTransaction do
        reorderActiveShiftTypes shiftType.id direction
        pure ()
    invalidateTouchedResources "admin.shift_type.move" (liveMutationResult () [adminShiftTypesResource (unpackId currentVenueId)])

shiftTypeTouchedResources :: (?context :: ControllerContext) => [SurfaceResourceValue]
shiftTypeTouchedResources =
    [adminShiftTypesResource (unpackId currentVenueId)]

shiftTypeAffectsXeroPayItems :: ShiftType -> Bool
shiftTypeAffectsXeroPayItems shiftType =
    shiftType.isActive && (isJust shiftType.overrideAwardLevelId || isJust shiftType.importedXeroPayItemId)

shiftTypeXeroPayItemScopeChanged :: ShiftType -> ShiftType -> Bool
shiftTypeXeroPayItemScopeChanged oldShiftType newShiftType =
    shiftTypeXeroPayItemScope oldShiftType /= shiftTypeXeroPayItemScope newShiftType

shiftTypeXeroPayItemScope :: ShiftType -> Maybe (PayAssignmentModeEnum, Maybe (Id AwardLevel), Maybe (Id XeroImportedPayItem))
shiftTypeXeroPayItemScope shiftType
    | shiftType.isActive = Just (shiftType.payAssignmentMode, shiftType.overrideAwardLevelId, shiftType.importedXeroPayItemId)
    | otherwise = Nothing
