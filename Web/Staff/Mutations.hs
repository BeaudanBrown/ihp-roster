module Web.Staff.Mutations
    ( createTrialStaffInvitationMutation
    , renewTrialStaffInvitationMutation
    , removeStaffMember
    , staffRemovalBlockReason
    , createTrialStaffMember
    , staffCreateTouchedResources
    , staffRosterGroupResources
    , staffTimesheetResources
    , staffUpdateTouchedResources
    , staffXeroPayItemScopeChanged
    , updateStaffMember
    ) where

import Application.Helper.Audit (AuditEventType (..), AuditSourceChannel (..),
                                 recordCurrentUserAuditEvent,
                                 recordCurrentUserLeaveRequestEvent,
                                 updateCurrentUserVenueMembershipRoleWithAuditInCurrentTransaction)
import Application.Helper.FrontendContract.Surface.Admin.Resource (adminInvitesResource)
import Application.Helper.FrontendContract.Surface.LeaveRequests.Resource (archivedLeaveRequestsResource,
                                                                           deniedLeaveRequestsResource,
                                                                           leaveAvailabilityWarningsResource,
                                                                           pendingLeaveRequestsResource)
import Application.Helper.FrontendContract.Surface.Profile.Resource
import Application.Helper.FrontendContract.Surface.Roster.Live (activeRosterWindowScopes)
import Application.Helper.FrontendContract.Surface.Timesheets.Live (activeTimesheetWindowScopes)
import Application.Helper.FrontendContract.Surface.Timesheets.Resource (timesheetWeekResource)
import Application.Helper.InvitationStatus (invitationStatusAllowsRenewal)
import Application.Helper.Pay (ensureStaffPayVersionForStaff)
import Application.Helper.RosterGroups (fetchStaffRosterGroupIds,
                                        syncStaffRosterGroupAssignments)
import Application.Helper.Staff (isAdoptableTrialStaff)
import Application.Helper.StaffShiftPreferences (ShiftPreferenceSelection,
                                                 replaceStaffShiftPreferences)
import Application.Helper.SurfaceResource
import Application.Helper.TimeRules (operationalDayForUtcTime)
import Application.Helper.VenueInvitation (accountInvitationConflictMessage,
                                           activeVenueInvitationsForEmail,
                                           activeVenueOnboardingInvitationsForEmail,
                                           registeredInvitationAccountExists,
                                           venueInvitationLifetime)
import Application.InvitationDelivery.Enqueue (enqueueVenueInvitationEmail)
import Application.Staff.Mutations (withStaffOperationalLocksInCurrentTransaction,
                                    withStaffRemovalLockInCurrentTransaction)
import Application.VenueInvitation.Mutations (withTrialStaffInvitationLockInCurrentTransaction,
                                              withVenueInvitationRenewalLockInCurrentTransaction)
import Application.Xero.StaffMappings (ClearedXeroStaffMapping (..),
                                       clearXeroStaffMappingsForInactiveStaff)
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import Data.Time.Calendar (Day, addDays)
import Data.Time.Clock (addUTCTime, getCurrentTime, utctDay)
import Data.UUID (UUID)
import Web.Controller.Prelude
import Web.RosterWeeks.SurfaceInvalidation (activeRosterResourcesForStaffGroups)
import Web.SurfaceInvalidation (withDurableLiveMutation,
                                withDurableLiveMutationOutcome)

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
    | otherwise =
        withDurableLiveMutationOutcome publicationFor do
            maybeCreation <- withTrialStaffInvitationLockInCurrentTransaction (unpackId staff.id) (Text.toCaseFold email) do
                lockedStaff <- fetch staff.id
                existingPendingInvitation <- query @VenueInvitation
                    |> filterWhere (#staffId, Just lockedStaff.id)
                    |> filterWhere (#status, InvitationStatusEnumPending)
                    |> fetchOneOrNothing
                now <- getCurrentTime
                accountExists <- registeredInvitationAccountExists email
                activeVenueInvitations <- activeVenueInvitationsForEmail now email
                activeOnboardingInvitations <- activeVenueOnboardingInvitationsForEmail now email
                let conflictingVenueInvitations = filter ((/= Just lockedStaff.id) . (.staffId)) activeVenueInvitations
                case existingPendingInvitation of
                    Just _ -> pure (Left "Renew the existing trial staff invitation instead of creating another link.")
                    Nothing | accountExists || not (null conflictingVenueInvitations) || not (null activeOnboardingInvitations) -> pure (Left accountInvitationConflictMessage)
                    Nothing | not (isAdoptableTrialStaff lockedStaff) -> pure (Left "Only active trial staff without a linked login can be invited.")
                    Nothing -> do
                        invitation <- newRecord @VenueInvitation
                            |> set #venueId (unpackId currentVenueId)
                            |> set #invitedByUserId (Just (unpackId authenticatedCurrentUser.id))
                            |> set #staffId (Just lockedStaff.id)
                            |> set #email email
                            |> set #inviteRole (Worker)
                            |> set #status (InvitationStatusEnumPending)
                            |> set #deliveryStatus (Queued)
                            |> set #expiresAt (Just (addUTCTime venueInvitationLifetime now))
                            |> createRecord
                        void (enqueueVenueInvitationEmail (Just authenticatedCurrentUser.id) invitation)
                        pure (Right invitation)
            pure $
                case maybeCreation of
                    Nothing -> Left "That trial staff member is no longer available to invite."
                    Just (Left message) -> Left message
                    Just (Right invitation) -> Right (liveMutationResult invitation (trialStaffInvitationTouchedResources staff))
  where
    publicationFor = either (const Nothing) (\result -> Just ("staff.invite_trial", result.liveMutationTouchedResources))

renewTrialStaffInvitationMutation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> VenueInvitation -> Text -> IO (Either Text (LiveMutationResult VenueInvitation))
renewTrialStaffInvitationMutation staff invitation correctedEmail
    | staff.venueId /= unpackId currentVenueId = pure (Left "Choose trial staff from the current venue.")
    | invitation.venueId /= unpackId currentVenueId = pure (Left "Choose an invitation from the current venue.")
    | invitation.staffId /= Just staff.id = pure (Left "Choose a pending invitation for this trial staff member.")
    | otherwise =
        withDurableLiveMutationOutcome publicationFor do
            maybeRenewal <- withVenueInvitationRenewalLockInCurrentTransaction
                (unpackId invitation.id)
                (Just (unpackId staff.id))
                (Text.toCaseFold correctedEmail)
                do
                    lockedInvitation <- fetch invitation.id
                    lockedStaff <- fetch staff.id
                    if lockedInvitation.staffId /= Just lockedStaff.id
                        then pure (Left "Choose a pending invitation for this trial staff member.")
                        else if not (invitationStatusAllowsRenewal lockedInvitation.status)
                            then pure (Left "Only pending invitations can be renewed.")
                        else if not (isAdoptableTrialStaff lockedStaff)
                            then pure (Left "Only active trial staff without a linked login can be invited.")
                        else do
                            now <- getCurrentTime
                            accountExists <- registeredInvitationAccountExists correctedEmail
                            activeVenueInvitations <- activeVenueInvitationsForEmail now correctedEmail
                            activeOnboardingInvitations <- activeVenueOnboardingInvitationsForEmail now correctedEmail
                            let conflictingVenueInvitations = filter ((/= lockedInvitation.id) . (.id)) activeVenueInvitations
                            if accountExists || not (null conflictingVenueInvitations) || not (null activeOnboardingInvitations)
                                then pure (Left accountInvitationConflictMessage)
                                else Right <$> replaceTrialStaffInvitation lockedStaff lockedInvitation correctedEmail
            pure $
                case maybeRenewal of
                    Nothing -> Left "That invitation is no longer available to renew."
                    Just (Left message) -> Left message
                    Just (Right renewedInvitation) -> Right (liveMutationResult renewedInvitation (trialStaffInvitationTouchedResources staff))
  where
    publicationFor = either (const Nothing) (\result -> Just ("staff.renew_trial_invite", result.liveMutationTouchedResources))

replaceTrialStaffInvitation :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> VenueInvitation -> Text -> IO VenueInvitation
replaceTrialStaffInvitation staff invitation correctedEmail = do
    now <- getCurrentTime
    pendingInvitations <- query @VenueInvitation
        |> filterWhere (#staffId, Just staff.id)
        |> filterWhere (#status, InvitationStatusEnumPending)
        |> fetch
    forM_ pendingInvitations \pendingInvitation ->
        void $
            pendingInvitation
                |> set #status (Revoked)
                |> updateRecord
    replacement <- newRecord @VenueInvitation
        |> set #venueId invitation.venueId
        |> set #invitedByUserId (Just (unpackId authenticatedCurrentUser.id))
        |> set #staffId (Just staff.id)
        |> set #email correctedEmail
        |> set #inviteRole invitation.inviteRole
        |> set #status (InvitationStatusEnumPending)
        |> set #deliveryStatus (Queued)
        |> set #expiresAt (Just (addUTCTime venueInvitationLifetime now))
        |> createRecord
    void (enqueueVenueInvitationEmail (Just authenticatedCurrentUser.id) replacement)
    pure replacement

trialStaffInvitationTouchedResources :: (?context :: ControllerContext) => Staff -> [SurfaceResourceValue]
trialStaffInvitationTouchedResources staff =
    [ adminInvitesResource (unpackId currentVenueId)
    , staffProfileResource (unpackId staff.id)
    ]

staffRemovalBlockReason :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> IO (Maybe Text)
staffRemovalBlockReason staff
    | staff.venueId /= unpackId currentVenueId = pure (Just "Choose staff from the current venue.")
    | staff.userId == Just (unpackId effectiveCurrentUser.id) = pure (Just "You cannot remove your own staff access.")
    | isJust staff.archivedAt || not staff.isActive = pure (Just "That staff member has already been removed.")
    | otherwise = do
        maybeMembership <- case staff.userId of
            Nothing -> pure Nothing
            Just linkedUserId ->
                query @VenueMembership
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#userId, linkedUserId)
                    |> filterWhere (#isActive, True)
                    |> fetchOneOrNothing
        pure $
            if maybe False ((== VenueOwner) . (.venueRole)) maybeMembership
                then Just "Venue owners cannot be removed from staff."
                else Nothing

removeStaffMember :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> IO (Either Text (LiveMutationResult Staff))
removeStaffMember staff
    | staff.venueId /= unpackId currentVenueId = pure (Left "Choose staff from the current venue.")
    | otherwise =
        withDurableLiveMutationOutcome publicationFor do
            previousRosterGroupIds <- fetchStaffRosterGroupIds staff
            maybeRemovedStaff <- withStaffRemovalLockInCurrentTransaction (unpackId staff.id) do
                lockedStaff <- fetch staff.id
                maybeMembership <- case lockedStaff.userId of
                    Nothing -> pure Nothing
                    Just linkedUserId ->
                        query @VenueMembership
                            |> filterWhere (#venueId, unpackId currentVenueId)
                            |> filterWhere (#userId, linkedUserId)
                            |> filterWhere (#isActive, True)
                            |> fetchOneOrNothing
                if lockedStaff.userId == Just (unpackId effectiveCurrentUser.id)
                    then pure (Left "You cannot remove your own staff access.")
                    else if maybe False ((== VenueOwner) . (.venueRole)) maybeMembership
                        then pure (Left "Venue owners cannot be removed from staff.")
                    else if isJust lockedStaff.archivedAt || not lockedStaff.isActive
                        then pure (Left "That staff member has already been removed.")
                    else do
                        now <- getCurrentTime
                        removedRosterAssignmentCount <- removeCurrentAndFutureRosterAssignments now lockedStaff
                        denyPendingStaffLeaveRequests lockedStaff
                        removedStaff <- lockedStaff
                            |> set #isActive False
                            |> set #archivedAt (Just now)
                            |> set #archivedByUserId (Just (unpackId authenticatedCurrentUser.id))
                            |> set #archiveReason (Just ("Removed from venue staff" :: Text))
                            |> updateRecord
                        clearedXeroStaffMappings <-
                            clearXeroStaffMappingsForInactiveStaff authenticatedCurrentUser.id removedStaff
                        forM_ maybeMembership \membership ->
                            void $
                                membership
                                    |> set #isActive False
                                    |> set #archivedAt (Just now)
                                    |> set #archivedByUserId (Just (unpackId authenticatedCurrentUser.id))
                                    |> set #archiveReason (Just ("Staff removed from venue" :: Text))
                                    |> updateRecord
                        pendingInvitations <- query @VenueInvitation
                            |> filterWhere (#venueId, unpackId currentVenueId)
                            |> filterWhere (#staffId, Just lockedStaff.id)
                            |> filterWhere (#status, InvitationStatusEnumPending)
                            |> fetch
                        forM_ pendingInvitations \invitation ->
                            void $
                                invitation
                                    |> set #status (Revoked)
                                    |> updateRecord
                        forM_ lockedStaff.userId \linkedUserId -> do
                            targetSetupTokens <- query @PasskeySetupToken
                                |> filterWhere (#venueId, Just (unpackId currentVenueId))
                                |> filterWhere (#userId, linkedUserId)
                                |> filterWhere (#consumedAt, Nothing)
                                |> filterWhereIn (#purpose, ["staff_new_device" :: Text, "staff_recovery"])
                                |> fetch
                            issuedSetupTokens <- query @PasskeySetupToken
                                |> filterWhere (#venueId, Just (unpackId currentVenueId))
                                |> filterWhere (#requestedByUserId, Just linkedUserId)
                                |> filterWhere (#consumedAt, Nothing)
                                |> filterWhereIn (#purpose, ["staff_new_device" :: Text, "staff_recovery"])
                                |> fetch
                            forM_ (nubBy (\left right -> left.id == right.id) (targetSetupTokens <> issuedSetupTokens)) \setupToken ->
                                void $
                                    setupToken
                                        |> set #consumedAt (Just now)
                                        |> set #deliveryTokenCiphertext Nothing
                                        |> updateRecord

                            targetResetTokens <- query @PasswordResetToken
                                |> filterWhere (#venueId, unpackId currentVenueId)
                                |> filterWhere (#userId, linkedUserId)
                                |> filterWhere (#consumedAt, Nothing)
                                |> fetch
                            issuedResetTokens <- query @PasswordResetToken
                                |> filterWhere (#venueId, unpackId currentVenueId)
                                |> filterWhere (#requestedByUserId, Just linkedUserId)
                                |> filterWhere (#consumedAt, Nothing)
                                |> fetch
                            forM_ (nubBy (\left right -> left.id == right.id) (targetResetTokens <> issuedResetTokens)) \resetToken ->
                                void $
                                    resetToken
                                        |> set #consumedAt (Just now)
                                        |> set #deliveryTokenCiphertext Nothing
                                        |> updateRecord
                        void $
                            recordCurrentUserAuditEvent
                                StaffRemovedAudit
                                "staff"
                                (unpackId lockedStaff.id)
                                (Aeson.object
                                    [ "linkedUserId" Aeson..= lockedStaff.userId
                                    , "removedRosterAssignmentCount" Aeson..= removedRosterAssignmentCount
                                    , "clearedXeroStaffMappings" Aeson..= map clearedXeroStaffMappingAuditValue clearedXeroStaffMappings
                                    , "reason" Aeson..= ("removed_from_venue_staff" :: Text)
                                    ]
                                )
                        pure (Right removedStaff)
            case maybeRemovedStaff of
                Nothing -> pure (Left "That staff member is no longer available.")
                Just (Left message) -> pure (Left message)
                Just (Right removedStaff) -> do
                    activeRosterScopes <- activeRosterWindowScopes
                    activeTimesheetScopes <- activeTimesheetWindowScopes
                    let activeVenueRosterGroupIds =
                            nub
                                [ Id rosterGroupId
                                | (venueId, rosterGroupId, _windowStart, _windowEnd, _calendarRevision) <- activeRosterScopes
                                , venueId == unpackId currentVenueId
                                ]
                        touchedResources =
                            staffUpdateTouchedResources removedStaff
                                <> [ adminInvitesResource (unpackId currentVenueId)
                                   , staffLeaveRequestsResource (unpackId removedStaff.id)
                                   , pendingLeaveRequestsResource (unpackId currentVenueId)
                                   , leaveAvailabilityWarningsResource (unpackId currentVenueId)
                                   , deniedLeaveRequestsResource (unpackId currentVenueId)
                                   , archivedLeaveRequestsResource (unpackId currentVenueId)
                                   ]
                                <> staffRosterGroupResources (unpackId currentVenueId) activeRosterScopes (nub (previousRosterGroupIds <> activeVenueRosterGroupIds))
                                <> staffTimesheetResources (unpackId currentVenueId) activeTimesheetScopes
                    pure (Right (liveMutationResult removedStaff touchedResources))
  where
    publicationFor = either (const Nothing) (\result -> Just ("staff.remove", result.liveMutationTouchedResources))

clearedXeroStaffMappingAuditValue :: ClearedXeroStaffMapping -> Aeson.Value
clearedXeroStaffMappingAuditValue mapping =
    Aeson.object
        [ "mappingId" Aeson..= unpackId mapping.clearedMappingId
        , "connectionId" Aeson..= unpackId mapping.clearedConnectionId
        , "xeroEmployeeId" Aeson..= mapping.clearedXeroEmployeeId
        , "xeroEmployeeName" Aeson..= mapping.clearedXeroEmployeeName
        , "previousStatus" Aeson..= inputValue mapping.clearedPreviousMappingStatus
        ]

denyPendingStaffLeaveRequests :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Staff -> IO ()
denyPendingStaffLeaveRequests staff = do
    pendingRequests <- query @LeaveRequest
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#staffId, unpackId staff.id)
        |> filterWhere (#status, LeaveRequestStatusEnumPending)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch
    forM_ pendingRequests \pendingRequest -> do
        deniedRequest <- pendingRequest
            |> set #status (LeaveRequestStatusEnumDenied)
            |> updateRecord
        void $
            recordCurrentUserLeaveRequestEvent
                deniedRequest
                (LeaveRequestEventTypeEnumDenied)
                (Just pendingRequest.status)
                (Just deniedRequest.status)
                (Aeson.object ["reason" Aeson..= ("staff_removed" :: Text)])
        void $
            recordCurrentUserAuditEvent
                LeaveDeniedAudit
                "leave_requests"
                (unpackId pendingRequest.id)
                (Aeson.object
                    [ "staffId" Aeson..= pendingRequest.staffId
                    , "startDate" Aeson..= pendingRequest.startDate
                    , "endDate" Aeson..= pendingRequest.endDate
                    , "previousStatus" Aeson..= ("pending" :: Text)
                    , "newStatus" Aeson..= ("denied" :: Text)
                    , "reason" Aeson..= ("staff_removed" :: Text)
                    ]
                )

removeCurrentAndFutureRosterAssignments :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => UTCTime -> Staff -> IO Int
removeCurrentAndFutureRosterAssignments removedAt staff = do
    venueConfig <- query @VenueConfig
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> fetchOne
    operationalToday <- operationalDayForUtcTime venueConfig removedAt
    assignedSlots <- query @RosterSlot
        |> filterWhere (#staffId, Just (unpackId staff.id))
        |> filterWhere (#deletedAt, Nothing)
        |> fetch
    let rosterDayIds = nub (map (.rosterDayId) assignedSlots)
    rosterDays <- if null rosterDayIds
        then pure []
        else query @RosterDay |> filterWhereIn (#id, map Id rosterDayIds) |> fetch
    let rosterDaysById = Map.fromList [(unpackId rosterDay.id, rosterDay) | rosterDay <- rosterDays]
        isCurrentOrFuture slot = do
            rosterDay <- Map.lookup slot.rosterDayId rosterDaysById
            pure (rosterDay.operationalDate >= operationalToday)
    let removedSlots = filter (fromMaybe False . isCurrentOrFuture) assignedSlots
    forM_ removedSlots \slot ->
        void $
            slot
                |> set #deletedAt (Just removedAt)
                |> set #deletedByUserId (Just (unpackId authenticatedCurrentUser.id))
                |> set #deleteReason (Just ("Staff removed from venue" :: Text))
                |> updateRecord
    pure (length removedSlots)

createTrialStaffMember :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> [Id RosterGroup] -> IO (LiveMutationResult Staff)
createTrialStaffMember staff selectedRosterGroupIds =
    withDurableLiveMutation "staff.create_trial" do
        createdStaff <- staff |> createRecord
        syncStaffRosterGroupAssignments createdStaff selectedRosterGroupIds
        activeRosterScopes <- activeRosterWindowScopes
        pure (liveMutationResult createdStaff (staffCreateTouchedResources createdStaff <> staffRosterGroupResources (unpackId currentVenueId) activeRosterScopes selectedRosterGroupIds))

staffCreateTouchedResources :: Staff -> [SurfaceResourceValue]
staffCreateTouchedResources staff =
    [ staffProfileResource (unpackId staff.id)
    , staffPreferencesResource (unpackId staff.id)
    ]

updateStaffMember :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Staff -> Staff -> [Id RosterGroup] -> [ShiftPreferenceSelection] -> Maybe VenueMembership -> Maybe VenueRoleEnum -> IO (Maybe (LiveMutationResult Staff))
updateStaffMember originalStaff staff selectedRosterGroupIds submittedSelections maybeMembership maybeVenueRole =
    withDurableLiveMutationOutcome publicationFor do
        previousRosterGroupIds <- fetchStaffRosterGroupIds originalStaff
        maybeUpdatedStaff <- fmap join $ withStaffOperationalLocksInCurrentTransaction [unpackId originalStaff.id] do
            lockedStaff <- fetch originalStaff.id
            if not lockedStaff.isActive || isJust lockedStaff.archivedAt
                then pure Nothing
                else do
                    updatedStaff <- staff |> updateRecord
                    syncStaffRosterGroupAssignments updatedStaff selectedRosterGroupIds
                    replaceStaffShiftPreferences updatedStaff submittedSelections
                    when (staffXeroPayItemScopeChanged originalStaff updatedStaff) do
                        today <- utctDay <$> getCurrentTime
                        void (ensureStaffPayVersionForStaff authenticatedCurrentUser.id updatedStaff today)
                    -- This workflow is classified as web even when HTMX invokes it.
                    forM_ ((,) <$> maybeMembership <*> maybeVenueRole) \(membership, venueRole) ->
                        void $ updateCurrentUserVenueMembershipRoleWithAuditInCurrentTransaction
                            WebAuditSource
                            membership
                            venueRole
                            (Aeson.object ["staffId" Aeson..= tshow staff.id])
                    pure (Just updatedStaff)
        forM maybeUpdatedStaff \updatedStaff -> do
            activeRosterScopes <- activeRosterWindowScopes
            activeTimesheetScopes <- activeTimesheetWindowScopes
            let affectedRosterGroupIds = nub (previousRosterGroupIds <> selectedRosterGroupIds)
                payResources =
                    if staffPayDispositionChanged originalStaff updatedStaff
                        then staffTimesheetResources (unpackId currentVenueId) activeTimesheetScopes
                        else []
            pure (liveMutationResult updatedStaff (staffUpdateTouchedResources updatedStaff <> staffRosterGroupResources (unpackId currentVenueId) activeRosterScopes affectedRosterGroupIds <> payResources))
  where
    publicationFor = fmap (\result -> ("staff.update", result.liveMutationTouchedResources))

staffUpdateTouchedResources :: Staff -> [SurfaceResourceValue]
staffUpdateTouchedResources staff =
    [ leaveAvailabilityWarningsResource staff.venueId
    , staffProfileResource (unpackId staff.id)
    , staffPreferencesResource (unpackId staff.id)
    ]

staffRosterGroupResources :: UUID -> [(UUID, UUID, Day, Day, Int)] -> [Id RosterGroup] -> [SurfaceResourceValue]
staffRosterGroupResources = activeRosterResourcesForStaffGroups

staffTimesheetResources :: UUID -> [(UUID, Day, Day, Int)] -> [SurfaceResourceValue]
staffTimesheetResources venueId activeScopes =
    Set.toList $ Set.fromList
        [ timesheetWeekResource activeVenueId windowStart windowEnd
        | (activeVenueId, windowStart, windowEnd, _calendarRevision) <- activeScopes
        , activeVenueId == venueId
        ]

staffPayDispositionChanged :: Staff -> Staff -> Bool
staffPayDispositionChanged previous next =
    (previous.payAssignmentMode, previous.defaultAwardLevelId, previous.importedXeroPayItemId)
        /= (next.payAssignmentMode, next.defaultAwardLevelId, next.importedXeroPayItemId)
