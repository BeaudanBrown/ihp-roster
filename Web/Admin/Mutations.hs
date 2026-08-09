module Web.Admin.Mutations
    ( AdminShiftTypeMutationResult (..)
    , adminVenueSettingsTouchedResources
    , createRosterGroupMutation
    , createShiftTypeMutation
    , createVenueInvitationMutation
    , ensureAdminRosterGroupsNormalizedMutation
    , issueStaffPasskeySetupLinkMutation
    , moveRosterGroupMutation
    , moveShiftTypeMutation
    , revokeVenueInvitationMutation
    , renewVenueInvitationMutation
    , rosterEndTimesTouchedResources
    , rosterTimePickerWindowTouchedResources
    , rosterWeekStartsOnTouchedResources
    , setDefaultStaffPayRateMutation
    , setMinutePrecisionShiftTimesEnabledMutation
    , setRosterEndTimesEnabledMutation
    , setUnavailableStaffWarningThresholdMutation
    , setRosterTimePickerWindowMutation
    , setRosterWeekStartsOnMutation
    , shiftTypeAffectsXeroPayItems
    , shiftTypePayResources
    , shiftTypeXeroPayItemScopeChanged
    , updateRosterGroupMutation
    , updateShiftTypeMutation
    ) where

import Application.Helper.Audit
import Application.Helper.FrontendContract.Surface.Admin.Resource
import Application.Helper.FrontendContract.Surface.LeaveRequests.Resource (leaveAvailabilityWarningsResource)
import Application.Helper.FrontendContract.Surface.Roster.Live (activeRosterWindowScopes)
import Application.Helper.FrontendContract.Surface.Roster.Resource
import Application.Helper.FrontendContract.Surface.Timesheets.Live (activeTimesheetWindowScopes)
import Application.Helper.FrontendContract.Surface.Timesheets.Resource
import Application.Helper.InvitationStatus (invitationStatusAllowsRenewal)
import Application.Helper.PasskeySetupTokens
import Application.Helper.Pay (ensureShiftTypePayVersionForShiftType)
import Application.Helper.RosterGroups (createVenueRosterGroupWithDefaults,
                                        ensureDefaultRosterSlots,
                                        syncVenueDefaultRosterGroupToTopActive)
import Application.Helper.ShiftTypeColours (assignShiftTypeColourKey,
                                            blankShiftTypeColourKey,
                                            normalizeShiftTypeColourKey)
import Application.Helper.Staff (isAdoptableTrialStaff)
import Application.Helper.SurfaceResource
import Application.Helper.TimeRules (formatMinuteOfDayText)
import Application.Helper.VenueInvitation
import Application.Helper.WeekBoundaries (defaultWeekOffsetEpochForStartDay)
import Application.InvitationDelivery.Enqueue (enqueueVenueInvitationEmail)
import Application.PayAssignment (selectableShiftAssignmentMode)
import Application.RosterPublication.Mutations (normalizePublishedRosterWindows,
                                                withRosterCalendarLock)
import Application.VenueInvitation.Mutations (withVenueInvitationEmailLock,
                                              withVenueInvitationRenewalLock)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Data.Time.Clock (addUTCTime, getCurrentTime, utctDay)
import Web.Controller.Admin.Support
import Web.Controller.Prelude
import Web.SurfaceInvalidation (invalidateTouchedResources)

issueStaffPasskeySetupLinkMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id Staff ->
    PasskeySetupTokenPurpose ->
    User ->
    IO (PasskeySetupToken, Text)
issueStaffPasskeySetupLinkMutation staffId purpose targetUser =
    issuePasskeySetupTokenWith purpose targetUser (Just currentUser.id) (Just currentVenueId) \_ ->
        void $
            recordCurrentUserAuditEvent
                (staffPasskeySetupAuditEvent purpose)
                "users"
                (unpackId targetUser.id)
                (Aeson.object ["staffId" Aeson..= staffId])

staffPasskeySetupAuditEvent :: PasskeySetupTokenPurpose -> AuditEventType
staffPasskeySetupAuditEvent StaffNewDevicePasskeySetup = StaffPasskeySetupRequestedAudit
staffPasskeySetupAuditEvent StaffPasskeyRecovery = StaffPasskeyRecoveryRequestedAudit
staffPasskeySetupAuditEvent SelfNewDevicePasskeySetup = error "Self passkey setup cannot use the staff credential mutation"

data AdminShiftTypeMutationResult = AdminShiftTypeMutationResult
    { adminShiftTypeMutationShiftType         :: !ShiftType
    , adminShiftTypeMutationShouldRefreshXero :: !Bool
    }

setDefaultStaffPayRateMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueConfig -> PayAssignmentModeEnum -> Maybe (Id AwardLevel) -> IO (LiveMutationResult VenueConfig)
setDefaultStaffPayRateMutation venueConfig payAssignmentMode awardLevelId = do
    updated <- venueConfig
        |> set #defaultStaffPayAssignmentMode payAssignmentMode
        |> set #defaultStaffAwardLevelId awardLevelId
        |> updateRecord
    invalidateTouchedResources
        "admin.venue_config.default_staff_pay_rate"
        (liveMutationResult updated (adminVenueSettingsTouchedResources currentVenueId))

setMinutePrecisionShiftTimesEnabledMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueConfig -> Bool -> IO (LiveMutationResult VenueConfig)
setMinutePrecisionShiftTimesEnabledMutation venueConfig enabled = do
    updated <- venueConfig
        |> set #minutePrecisionShiftTimesEnabled enabled
        |> updateRecord
    invalidateTouchedResources
        "admin.venue_config.minute_precision_shift_times"
        (liveMutationResult updated (rosterTimePickerWindowTouchedResources currentVenueId))

setRosterEndTimesEnabledMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueConfig -> Bool -> IO (LiveMutationResult VenueConfig)
setRosterEndTimesEnabledMutation venueConfig rosterEndTimesEnabled = do
    updated <- venueConfig
        |> set #rosterEndTimesEnabled rosterEndTimesEnabled
        |> updateRecord
    invalidateTouchedResources "admin.venue_config.roster_end_times" (liveMutationResult updated (rosterEndTimesTouchedResources currentVenueId))

setUnavailableStaffWarningThresholdMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueConfig -> Maybe Int -> IO (LiveMutationResult VenueConfig)
setUnavailableStaffWarningThresholdMutation venueConfig threshold = do
    now <- getCurrentTime
    updated <- venueConfig
        |> set #unavailableStaffWarningThreshold threshold
        |> set #updatedAt now
        |> updateRecord
    invalidateTouchedResources
        "admin.venue_config.unavailable_staff_warning_threshold"
        (liveMutationResult updated (adminVenueSettingsTouchedResources currentVenueId <> [leaveAvailabilityWarningsResource (unpackId currentVenueId)]))

setRosterWeekStartsOnMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueConfig -> Int -> IO (LiveMutationResult VenueConfig)
setRosterWeekStartsOnMutation venueConfig rosterWeekStartsOn = do
    updated <- withRosterCalendarLock currentVenueId do
        normalizePublishedRosterWindows currentVenueId rosterWeekStartsOn
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

createVenueInvitationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> IO (Either Text (LiveMutationResult VenueInvitation))
createVenueInvitationMutation email = do
    creation <- withVenueInvitationEmailLock (Text.toCaseFold email) do
        staffLinkedInvitations <- query @VenueInvitation
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhereNot (#staffId, Nothing)
            |> fetch
        let matchingInvitations = filter ((== Text.toCaseFold email) . Text.toCaseFold . (.email)) staffLinkedInvitations
        matchingTrialStaff <- forM (mapMaybe (.staffId) matchingInvitations) fetch
        if any isAdoptableTrialStaff matchingTrialStaff
            then pure (Left "Use the trial-staff renewal workflow for this active trial staff email.")
            else do
                now <- getCurrentTime
                invitation <- newRecord @VenueInvitation
                    |> set #venueId (unpackId currentVenueId)
                    |> set #invitedByUserId (Just (unpackId currentUser.id))
                    |> set #email email
                    |> set #inviteRole (Worker)
                    |> set #status (InvitationStatusEnumPending)
                    |> set #deliveryStatus (Queued)
                    |> set #expiresAt (Just (addUTCTime venueInvitationLifetime now))
                    |> createRecord
                void (enqueueVenueInvitationEmail (Just currentUser.id) invitation)
                pure (Right invitation)
    case creation of
        Left message -> pure (Left message)
        Right invitation ->
            Right <$> invalidateTouchedResources "admin.invite.create" (liveMutationResult invitation [adminInvitesResource (unpackId currentVenueId)])

renewVenueInvitationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueInvitation -> Text -> IO (Either Text (LiveMutationResult VenueInvitation))
renewVenueInvitationMutation invitation correctedEmail
    | invitation.venueId /= unpackId currentVenueId = pure (Left "Choose an invitation from the current venue.")
    | isJust invitation.staffId = pure (Left "Use the trial-staff renewal workflow for staff-linked invitations.")
    | otherwise = do
        maybeRenewal <- withVenueInvitationRenewalLock
            (unpackId invitation.id)
            Nothing
            (Text.toCaseFold correctedEmail)
            do
                lockedInvitation <- fetch invitation.id
                if not (invitationStatusAllowsRenewal lockedInvitation.status)
                    then pure (Left "Only pending invitations can be renewed.")
                    else Right <$> replaceVenueInvitation lockedInvitation correctedEmail
        case maybeRenewal of
            Nothing -> pure (Left "That invitation is no longer available to renew.")
            Just (Left message) -> pure (Left message)
            Just (Right replacement) ->
                Right <$> invalidateTouchedResources "admin.invite.renew" (liveMutationResult replacement [adminInvitesResource (unpackId currentVenueId)])

replaceVenueInvitation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueInvitation -> Text -> IO VenueInvitation
replaceVenueInvitation invitation correctedEmail = do
    now <- getCurrentTime
    _ <- invitation
        |> set #status (Revoked)
        |> updateRecord
    replacement <- newRecord @VenueInvitation
        |> set #venueId invitation.venueId
        |> set #invitedByUserId (Just (unpackId currentUser.id))
        |> set #email correctedEmail
        |> set #inviteRole invitation.inviteRole
        |> set #status (InvitationStatusEnumPending)
        |> set #deliveryStatus (Queued)
        |> set #expiresAt (Just (addUTCTime venueInvitationLifetime now))
        |> createRecord
    void (enqueueVenueInvitationEmail (Just currentUser.id) replacement)
    pure replacement

revokeVenueInvitationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueInvitation -> IO (LiveMutationResult VenueInvitation)
revokeVenueInvitationMutation invitation = do
    updated <- invitation
        |> set #status (Revoked)
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

createShiftTypeMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> Bool -> Maybe (Id AwardLevel) -> Maybe (Id XeroImportedPayItem) -> Bool -> Maybe ShiftTypeColourKeyEnum -> IO (LiveMutationResult AdminShiftTypeMutationResult)
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
    activeRosterScopes <- activeRosterWindowScopes
    activeTimesheetScopes <- activeTimesheetWindowScopes
    let payResources = shiftTypePayResources (unpackId currentVenueId) activeRosterScopes activeTimesheetScopes
    invalidateTouchedResources "admin.shift_type.create" (liveMutationResult (AdminShiftTypeMutationResult shiftType shouldRefreshXero) (shiftTypeTouchedResources <> payResources))

updateShiftTypeMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ShiftType -> Text -> Bool -> Maybe (Id AwardLevel) -> Maybe (Id XeroImportedPayItem) -> Bool -> Maybe ShiftTypeColourKeyEnum -> IO (LiveMutationResult AdminShiftTypeMutationResult)
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
    activeRosterScopes <- activeRosterWindowScopes
    activeTimesheetScopes <- activeTimesheetWindowScopes
    let payResources =
            if shiftTypePayDispositionChanged shiftType updatedShiftType
                then shiftTypePayResources (unpackId currentVenueId) activeRosterScopes activeTimesheetScopes
                else []
    invalidateTouchedResources "admin.shift_type.update" (liveMutationResult (AdminShiftTypeMutationResult updatedShiftType shouldRefreshXero) (shiftTypeTouchedResources <> payResources))

resolveSubmittedShiftTypeColourKey :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe (Id ShiftType) -> Bool -> Maybe ShiftTypeColourKeyEnum -> ShiftTypeColourKeyEnum -> IO ShiftTypeColourKeyEnum
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

shiftTypePayResources :: UUID -> [(UUID, UUID, Day, Day, Int)] -> [(UUID, Day, Day, Int)] -> [SurfaceResourceValue]
shiftTypePayResources venueId activeRosterScopes activeTimesheetScopes =
    Set.toList $ Set.fromList
        ( [ resource
          | (activeVenueId, rosterGroupId, windowStart, windowEnd, _calendarRevision) <- activeRosterScopes
          , activeVenueId == venueId
          , resource <-
                [ rosterWeekResource rosterGroupId windowStart windowEnd
                , rosterSlotsContentResource rosterGroupId windowStart windowEnd
                ]
          ]
            <> [ timesheetWeekResource activeVenueId windowStart windowEnd
               | (activeVenueId, windowStart, windowEnd, _calendarRevision) <- activeTimesheetScopes
               , activeVenueId == venueId
               ]
        )

shiftTypePayDispositionChanged :: ShiftType -> ShiftType -> Bool
shiftTypePayDispositionChanged previous next =
    (previous.payAssignmentMode, previous.overrideAwardLevelId, previous.importedXeroPayItemId)
        /= (next.payAssignmentMode, next.overrideAwardLevelId, next.importedXeroPayItemId)

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
