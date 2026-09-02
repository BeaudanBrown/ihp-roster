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
    , shiftTypeAffectsXeroPayItems
    , shiftTypePayResources
    , shiftTypeXeroPayItemScopeChanged
    , updateRosterGroupMutation
    , updateRosterWindowStartDayMutation
    , updateShiftTypeMutation
    ) where

import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
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
import Application.Helper.Staff (isAdoptableTrialStaff)
import Application.Helper.ShiftTypeColours (assignShiftTypeColourKey,
                                            blankShiftTypeColourKey,
                                            normalizeShiftTypeColourKey)
import Application.Helper.SurfaceResource
import Application.Helper.TimeRules (formatMinuteOfDayText)
import Application.Helper.VenueInvitation
import Application.InvitationDelivery.Enqueue (enqueueVenueInvitationEmail)
import Application.InvitationEligibility
import Application.PayAssignment (selectableShiftAssignmentMode)
import Application.VenueInvitation.Mutations (withVenueInvitationEmailLockInCurrentTransaction,
                                              withVenueInvitationRenewalLockInCurrentTransaction)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (Day)
import Data.Time.Clock (addUTCTime, getCurrentTime, utctDay)
import Web.Admin.RosterWindowStartDay
import Web.Controller.Admin.Support
import Web.Controller.Prelude
import Web.SurfaceInvalidation (withDurableLiveMutation,
                                withDurableLiveMutationOutcome)

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
staffPasskeySetupAuditEvent SelfNewDevicePasskeySetup = externalRuntimeInvariantFailure PersistedRuntimeInvariant "Self passkey setup cannot use the staff credential mutation"

data AdminShiftTypeMutationResult = AdminShiftTypeMutationResult
    { adminShiftTypeMutationShiftType         :: !ShiftType
    , adminShiftTypeMutationShouldRefreshXero :: !Bool
    }

setDefaultStaffPayRateMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueConfig -> PayAssignmentModeEnum -> Maybe (Id AwardLevel) -> IO (LiveMutationResult VenueConfig)
setDefaultStaffPayRateMutation venueConfig payAssignmentMode awardLevelId =
    withDurableLiveMutation "admin.venue_config.default_staff_pay_rate" do
        updated <- venueConfig
            |> set #defaultStaffPayAssignmentMode payAssignmentMode
            |> set #defaultStaffAwardLevelId awardLevelId
            |> updateRecord
        pure (liveMutationResult updated (adminVenueSettingsTouchedResources currentVenueId))

setMinutePrecisionShiftTimesEnabledMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueConfig -> Bool -> IO (LiveMutationResult VenueConfig)
setMinutePrecisionShiftTimesEnabledMutation venueConfig enabled =
    withDurableLiveMutation "admin.venue_config.minute_precision_shift_times" do
        updated <- venueConfig
            |> set #minutePrecisionShiftTimesEnabled enabled
            |> updateRecord
        pure (liveMutationResult updated (rosterTimePickerWindowTouchedResources currentVenueId))

setRosterEndTimesEnabledMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueConfig -> Bool -> IO (LiveMutationResult VenueConfig)
setRosterEndTimesEnabledMutation venueConfig rosterEndTimesEnabled =
    withDurableLiveMutation "admin.venue_config.roster_end_times" do
        updated <- venueConfig
            |> set #rosterEndTimesEnabled rosterEndTimesEnabled
            |> updateRecord
        pure (liveMutationResult updated (rosterEndTimesTouchedResources currentVenueId))

setUnavailableStaffWarningThresholdMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueConfig -> Maybe Int -> IO (LiveMutationResult VenueConfig)
setUnavailableStaffWarningThresholdMutation venueConfig threshold =
    withDurableLiveMutation "admin.venue_config.unavailable_staff_warning_threshold" do
        now <- getCurrentTime
        updated <- venueConfig
            |> set #unavailableStaffWarningThreshold threshold
            |> set #updatedAt now
            |> updateRecord
        pure (liveMutationResult updated (adminVenueSettingsTouchedResources currentVenueId <> [leaveAvailabilityWarningsResource (unpackId currentVenueId)]))

setRosterTimePickerWindowMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueConfig -> Int -> Int -> IO (LiveMutationResult VenueConfig)
setRosterTimePickerWindowMutation venueConfig startMinute finalSelectableMinute =
    withDurableLiveMutation ("admin.venue_config.time_picker_window " <> formatMinuteOfDayText startMinute <> "-" <> formatMinuteOfDayText finalSelectableMinute) do
        updated <- venueConfig
            |> set #timePickerStartMinuteOfDay startMinute
            |> set #timePickerFinalSelectableMinuteOfDay finalSelectableMinute
            |> updateRecord
        pure (liveMutationResult updated (rosterTimePickerWindowTouchedResources currentVenueId))

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

createVenueInvitationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> IO (Either Text (LiveMutationResult VenueInvitation))
createVenueInvitationMutation email = do
    creation <-
        withDurableLiveMutationOutcome publicationFor $
            withVenueInvitationEmailLockInCurrentTransaction email do
                now <- getCurrentTime
                activeVenueInvitations <- activeVenueInvitationsForEmail now email
                activeOnboardingInvitations <- activeVenueOnboardingInvitationsForEmail now email
                accountExists <- registeredInvitationAccountExists email
                staffLinkedInvitations <- query @VenueInvitation
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhereCaseInsensitive (#email, email)
                    |> filterWhereNot (#staffId, Nothing)
                    |> fetch
                matchingTrialStaff <- forM (mapMaybe (.staffId) staffLinkedInvitations) fetch
                let hasOtherVenueInvitation = any ((/= unpackId currentVenueId) . (.venueId)) activeVenueInvitations
                if any isAdoptableTrialStaff matchingTrialStaff
                    then pure (Left "Use the trial-staff renewal workflow for this active trial staff email.")
                    else if accountExists || not (null activeOnboardingInvitations) || hasOtherVenueInvitation
                        then pure (Left accountInvitationConflictMessage)
                        else do
                            revokePendingOrdinaryVenueInvitations email Nothing
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
    pure (fmap (`liveMutationResult` resources) creation)
    where
        resources = [adminInvitesResource (unpackId currentVenueId)]
        publicationFor = either (const Nothing) (const (Just ("admin.invite.create", Set.fromList resources)))

renewVenueInvitationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueInvitation -> Text -> IO (Either Text (LiveMutationResult VenueInvitation))
renewVenueInvitationMutation invitation correctedEmail
    | invitation.venueId /= unpackId currentVenueId = pure (Left "Choose an invitation from the current venue.")
    | isJust invitation.staffId = pure (Left "Use the trial-staff renewal workflow for staff-linked invitations.")
    | otherwise = do
        maybeRenewal <-
            withDurableLiveMutationOutcome publicationFor $
                withVenueInvitationRenewalLockInCurrentTransaction
                    (unpackId invitation.id)
                    Nothing
                    (Text.toCaseFold correctedEmail)
                    do
                        lockedInvitation <- fetch invitation.id
                        if not (invitationStatusAllowsRenewal lockedInvitation.status)
                            then pure (Left "Only pending invitations can be renewed.")
                            else do
                                now <- getCurrentTime
                                accountExists <- registeredInvitationAccountExists correctedEmail
                                activeOnboardingInvitations <- activeVenueOnboardingInvitationsForEmail now correctedEmail
                                activeVenueInvitations <- activeVenueInvitationsForEmail now correctedEmail
                                let conflictingVenueInvitations = filter
                                        (\candidate -> candidate.id /= lockedInvitation.id && (candidate.venueId /= unpackId currentVenueId || isJust candidate.staffId))
                                        activeVenueInvitations
                                if accountExists || not (null activeOnboardingInvitations) || not (null conflictingVenueInvitations)
                                    then pure (Left accountInvitationConflictMessage)
                                    else Right <$> replaceVenueInvitation lockedInvitation correctedEmail
        pure case maybeRenewal of
            Nothing -> Left "That invitation is no longer available to renew."
            Just (Left message) -> Left message
            Just (Right replacement) -> Right (liveMutationResult replacement resources)
    where
        resources = [adminInvitesResource (unpackId currentVenueId)]
        publicationFor = \case
            Just (Right _) -> Just ("admin.invite.renew", Set.fromList resources)
            _ -> Nothing

replaceVenueInvitation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueInvitation -> Text -> IO VenueInvitation
replaceVenueInvitation invitation correctedEmail = do
    now <- getCurrentTime
    revokePendingOrdinaryVenueInvitations correctedEmail (Just invitation.id)
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

revokePendingOrdinaryVenueInvitations :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Text -> Maybe (Id VenueInvitation) -> IO ()
revokePendingOrdinaryVenueInvitations email excludedInvitationId = do
    pendingInvitations <- query @VenueInvitation
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhereCaseInsensitive (#email, email)
        |> filterWhere (#status, InvitationStatusEnumPending)
        |> filterWhere (#staffId, Nothing)
        |> fetch
    forM_ pendingInvitations \pendingInvitation ->
        when (Just pendingInvitation.id /= excludedInvitationId) do
            pendingInvitation
                |> set #status (Revoked)
                |> updateRecordDiscardResult

revokeVenueInvitationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => VenueInvitation -> IO (LiveMutationResult VenueInvitation)
revokeVenueInvitationMutation invitation =
    withDurableLiveMutation "admin.invite.revoke" do
        updated <- invitation
            |> set #status (Revoked)
            |> updateRecord
        pure (liveMutationResult updated [adminInvitesResource (unpackId currentVenueId)])

ensureAdminRosterGroupsNormalizedMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => IO (LiveMutationResult ())
ensureAdminRosterGroupsNormalizedMutation =
    withDurableLiveMutation "admin.roster_group.normalize" do
        syncVenueDefaultRosterGroupToTopActive currentVenueId
        pure (liveMutationResult () [adminRosterGroupsResource (unpackId currentVenueId)])

createRosterGroupMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Venue -> Text -> Bool -> IO (LiveMutationResult RosterGroup)
createRosterGroupMutation venue name isActive =
    withDurableLiveMutation "admin.roster_group.create" do
        sortOrder <- nextRosterGroupSortOrder
        rosterGroup <- createVenueRosterGroupWithDefaults venue name sortOrder isActive
        syncVenueDefaultRosterGroupToTopActive currentVenueId
        pure (liveMutationResult rosterGroup [adminRosterGroupsResource (unpackId currentVenueId)])

updateRosterGroupMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Venue -> RosterGroup -> Text -> Bool -> IO (LiveMutationResult RosterGroup)
updateRosterGroupMutation venue rosterGroup name isActive =
    withDurableLiveMutation "admin.roster_group.update" do
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
        pure (liveMutationResult updatedRosterGroup [adminRosterGroupsResource (unpackId currentVenueId)])

moveRosterGroupMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => RosterGroup -> Int -> IO (LiveMutationResult ())
moveRosterGroupMutation _rosterGroup direction =
    withDurableLiveMutation "admin.roster_group.move" do
        reorderActiveRosterGroups _rosterGroup.id direction
        syncVenueDefaultRosterGroupToTopActive currentVenueId
        pure (liveMutationResult () [adminRosterGroupsResource (unpackId currentVenueId)])

createShiftTypeMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> Bool -> Maybe (Id AwardLevel) -> Maybe (Id XeroImportedPayItem) -> Bool -> Maybe ShiftTypeColourKeyEnum -> IO (LiveMutationResult AdminShiftTypeMutationResult)
createShiftTypeMutation name isActive overrideAwardLevelId importedXeroPayItemId submittedRosterOnly maybeSubmittedColourKey =
    withDurableLiveMutation "admin.shift_type.create" do
        sortOrder <- nextShiftTypeSortOrder
        colourKey <- resolveSubmittedShiftTypeColourKey Nothing isActive maybeSubmittedColourKey blankShiftTypeColourKey
        now <- getCurrentTime
        let payAssignmentMode = if submittedRosterOnly then RosterOnly else fromMaybe (externalRuntimeInvariantFailure PersistedRuntimeInvariant "validated shift pay selection contains conflicting rate sources") (selectableShiftAssignmentMode overrideAwardLevelId importedXeroPayItemId)
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
        let shouldRefreshXero = shiftTypeAffectsXeroPayItems shiftType
        activeRosterScopes <- activeRosterWindowScopes
        activeTimesheetScopes <- activeTimesheetWindowScopes
        let payResources = shiftTypePayResources (unpackId currentVenueId) activeRosterScopes activeTimesheetScopes
        pure (liveMutationResult (AdminShiftTypeMutationResult shiftType shouldRefreshXero) (shiftTypeTouchedResources <> payResources))

updateShiftTypeMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ShiftType -> Text -> Bool -> Maybe (Id AwardLevel) -> Maybe (Id XeroImportedPayItem) -> Bool -> Maybe ShiftTypeColourKeyEnum -> IO (LiveMutationResult AdminShiftTypeMutationResult)
updateShiftTypeMutation shiftType name isActive overrideAwardLevelId importedXeroPayItemId submittedRosterOnly maybeSubmittedColourKey =
    withDurableLiveMutation "admin.shift_type.update" do
        now <- getCurrentTime
        sortOrder <-
            if not shiftType.isActive && isActive
                then nextShiftTypeSortOrder
                else pure shiftType.sortOrder
        colourKey <- resolveSubmittedShiftTypeColourKey (Just shiftType.id) isActive maybeSubmittedColourKey shiftType.colourKey
        let payAssignmentMode = if submittedRosterOnly then RosterOnly else fromMaybe (externalRuntimeInvariantFailure PersistedRuntimeInvariant "validated shift pay selection contains conflicting rate sources") (selectableShiftAssignmentMode overrideAwardLevelId importedXeroPayItemId)
        updatedShiftType <- shiftType
            |> set #name name
            |> set #sortOrder sortOrder
            |> set #payAssignmentMode payAssignmentMode
            |> set #overrideAwardLevelId overrideAwardLevelId
            |> set #importedXeroPayItemId importedXeroPayItemId
            |> set #colourKey colourKey
            |> set #isActive isActive
            |> updateRecord
        when (shiftType.name /= updatedShiftType.name || shiftType.payAssignmentMode /= updatedShiftType.payAssignmentMode || shiftType.overrideAwardLevelId /= updatedShiftType.overrideAwardLevelId || shiftType.importedXeroPayItemId /= updatedShiftType.importedXeroPayItemId) do
            _ <- ensureShiftTypePayVersionForShiftType currentUser.id updatedShiftType (utctDay now)
            pure ()
        let shouldRefreshXero = shiftTypeXeroPayItemScopeChanged shiftType updatedShiftType
        activeRosterScopes <- activeRosterWindowScopes
        activeTimesheetScopes <- activeTimesheetWindowScopes
        let payResources =
                if shiftTypePayDispositionChanged shiftType updatedShiftType
                    then shiftTypePayResources (unpackId currentVenueId) activeRosterScopes activeTimesheetScopes
                    else []
        pure (liveMutationResult (AdminShiftTypeMutationResult updatedShiftType shouldRefreshXero) (shiftTypeTouchedResources <> payResources))

resolveSubmittedShiftTypeColourKey :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe (Id ShiftType) -> Bool -> Maybe ShiftTypeColourKeyEnum -> ShiftTypeColourKeyEnum -> IO ShiftTypeColourKeyEnum
resolveSubmittedShiftTypeColourKey maybeCurrentShiftTypeId isActive maybeSubmittedColourKey fallbackColourKey =
    case maybeSubmittedColourKey of
        Nothing -> assignShiftTypeColourKey currentVenueId maybeCurrentShiftTypeId isActive fallbackColourKey
        Just submittedColourKey -> pure (normalizeShiftTypeColourKey submittedColourKey)

moveShiftTypeMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => ShiftType -> Int -> IO (LiveMutationResult ())
moveShiftTypeMutation shiftType direction =
    withDurableLiveMutation "admin.shift_type.move" do
        reorderActiveShiftTypes shiftType.id direction
        pure (liveMutationResult () [adminShiftTypesResource (unpackId currentVenueId)])

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
