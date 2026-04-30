module Web.Controller.Admin where

import Application.Helper.Export
import Application.Helper.LiveUpdate
import Application.Helper.Pay
import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Application.Helper.VenueInvitation
import Application.Helper.WeekBoundaries (defaultWeekOffsetEpochForStartDay,
                                          validRosterWeekStartDays,
                                          weekdayIndexLabel)
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroPayItems
import Application.InvitationDelivery.Job (enqueueVenueInvitationDeliveryJob)
import Application.Xero.Connection
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Data.Text as Text
import Web.Controller.Admin.Support
import Web.Controller.Admin.Xero
import Web.Controller.Admin.Xero.Responses
import Web.Controller.Prelude
import Web.View.Admin.Index
import Web.View.Admin.Invites
import Web.View.Admin.RosterGroups
import Web.View.Admin.ShiftTypes
import Web.View.Admin.Xero

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

respondToShiftTypesSectionMutationWithXeroRefresh ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Bool ->
    IO ()
respondToShiftTypesSectionMutationWithXeroRefresh shouldRefreshXero =
    if isHtmxRequest
        then do
            shiftTypes <- fetchCurrentVenueShiftTypes
            awardLevels <- fetchActiveAwardLevels
            awardLevelBaseRates <- fetchCurrentAwardLevelBaseRates
            let showInactiveShiftTypes = parseShowInactiveParam "showInactiveShiftTypes"
            xeroFragment <- if shouldRefreshXero && currentUserCanManageXeroIntegration then renderCurrentVenueXeroSectionFragmentOob else pure mempty
            respondHtml $
                mconcat
                    [ renderShiftTypesSectionFragment shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates
                    , xeroFragment
                    ]
        else redirectToAdminFor (paramOrNothing "rosterGroupId")

instance Controller AdminController where
    beforeAction = do
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted
        ensureAdminRole

    action AdminAction = do
        syncVenueDefaultRosterGroupToTopActive currentVenueId
        rosterGroups <- fetchCurrentVenueRosterGroups
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        shiftTypes <- fetchCurrentVenueShiftTypes
        awardLevels <- fetchActiveAwardLevels
        awardLevelBaseRates <- fetchCurrentAwardLevelBaseRates
        slotNames <- fetchActiveCurrentVenueSlotNames
        currentWeekOffset <- currentReportWeekOffset
        reportWeekSelection <- fetchReportWeekSelection currentWeekOffset
        let defaultRangeStart = reportWeekSelection.weekStart
        let defaultRangeEnd = reportWeekSelection.weekEnd
        exportJobs <- fetchCurrentVenueExportJobs
        let showInactiveRosterGroups = parseShowInactiveParam "showInactiveRosterGroups"
        let showInactiveShiftTypes = parseShowInactiveParam "showInactiveShiftTypes"
        invitations <- fetchCurrentVenueInvitations
        let invitesLiveUpdateScope = Just (adminInvitesScope currentVenueId)
        render IndexView { .. }

    action XeroAction = do
        redirectPermissionDeniedUnless currentUserCanManageXeroIntegration "Only the venue owner or a super admin can manage Xero for this venue."
        xeroSectionData <- fetchCurrentVenueXeroAdminSectionData
        render XeroView { .. }

    action StartXeroConnectionAction =
        startXeroConnectionAction

    action XeroOAuthCallbackAction =
        xeroOAuthCallbackAction

    action DisconnectXeroConnectionAction =
        disconnectXeroConnectionAction

    action SyncXeroPayrollReferenceDataAction =
        requireCurrentVenueOwnerForXero syncXeroPayrollReferenceDataAction

    action CreateMissingXeroPayItemsAction =
        requireCurrentVenueOwnerForXero createMissingXeroPayItemsAction

    action SaveXeroStaffMappingAction =
        requireCurrentVenueOwnerForXero saveXeroStaffMappingAction

    action SuggestXeroStaffMappingAction { staffId } =
        requireCurrentVenueOwnerForXero (suggestXeroStaffMappingAction staffId)

    action SaveXeroEarningsRateMappingAction =
        requireCurrentVenueOwnerForXero saveXeroEarningsRateMappingAction

    action SaveXeroPayItemAccountCodeSelectionAction =
        requireCurrentVenueOwnerForXero saveXeroPayItemAccountCodeSelectionAction

    action SaveXeroPayrollCalendarSelectionAction =
        requireCurrentVenueOwnerForXero saveXeroPayrollCalendarSelectionAction

    action PreviewXeroDraftTimesheetsAction =
        requireCurrentVenueOwnerForXero previewXeroDraftTimesheetsAction

    action SubmitXeroDraftTimesheetsAction =
        requireCurrentVenueOwnerForXero submitXeroDraftTimesheetsAction

    action RetryXeroDraftTimesheetSubmissionAction { xeroTimesheetSubmissionId } =
        requireCurrentVenueOwnerForXero (retryXeroDraftTimesheetSubmissionAction xeroTimesheetSubmissionId)

    action UpdateVenueConfigAction = do
        venueConfig <- fetchVenueConfig
        requestedRosterWeekStartsOn <- parseRosterWeekStartsOn
        case requestedRosterWeekStartsOn of
            Nothing -> redirectToAdminFor (paramOrNothing "rosterGroupId")
            Just rosterWeekStartsOn -> do
                isLocked <- isVenueRosterWeekStartLocked
                if isLocked
                    then do
                        setErrorMessage "Roster week start can only be configured before roster, timesheet, leave, export, or payroll version data exists."
                        redirectToAdminFor (paramOrNothing "rosterGroupId")
                    else do
                        _ <- withTransaction do
                            venueConfig
                                |> set #rosterWeekStartsOn rosterWeekStartsOn
                                |> set #weekOffsetEpoch (defaultWeekOffsetEpochForStartDay rosterWeekStartsOn)
                                |> updateRecord
                        setSuccessMessage ("Roster week will start on " <> weekdayIndexLabel rosterWeekStartsOn)
                        redirectToAdminFor (paramOrNothing "rosterGroupId")

    action ShowAdminSlotNamesFragmentAction = do
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        slotNames <- fetchActiveRosterGroupSlotNames currentRosterGroup.id
        respondHtml (renderRosterGroupSlotNamesFragment currentRosterGroup slotNames)

    action ShowAdminInvitesFragmentAction = do
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        invitations <- fetchCurrentVenueInvitations
        respondHtml (renderInvitesSectionFragment invitations currentRosterGroup.id)

    action ShowAdminShiftTypesFragmentAction = do
        shiftTypes <- fetchCurrentVenueShiftTypes
        awardLevels <- fetchActiveAwardLevels
        awardLevelBaseRates <- fetchCurrentAwardLevelBaseRates
        let showInactiveShiftTypes = parseShowInactiveParam "showInactiveShiftTypes"
        respondHtml (renderShiftTypesSectionFragment shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates)

    action ShowAdminRosterGroupsFragmentAction = do
        syncVenueDefaultRosterGroupToTopActive currentVenueId
        rosterGroups <- fetchCurrentVenueRosterGroups
        slotNames <- fetchActiveCurrentVenueSlotNames
        let showInactiveRosterGroups = parseShowInactiveParam "showInactiveRosterGroups"
        respondHtml (renderRosterGroupsSectionFragment rosterGroups slotNames showInactiveRosterGroups)

    action ShowAdminXeroFragmentAction = do
        requireCurrentVenueOwnerForXero respondWithXeroSectionFragment

    action ShowAdminXeroStaffMappingsFragmentAction = do
        requireCurrentVenueOwnerForXero respondWithXeroStaffMappingsFragment

    action CreateVenueInvitationAction = do
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        maybeEmail <- parseRequiredEmail "email" "Invite email is required."
        case maybeEmail of
            Just email -> do
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
                broadcastAdminInvitesInvalidation currentVenueId
                if isHtmxRequest
                    then do
                        invitations <- fetchCurrentVenueInvitations
                        void (enqueueVenueInvitationDeliveryJob (Just currentUser.id) invitation)
                        setSuccessMessage ("Invitation queued for " <> email)
                        respondHtml (renderInvitesSectionFragment invitations currentRosterGroup.id)
                    else do
                        void (enqueueVenueInvitationDeliveryJob (Just currentUser.id) invitation)
                        respondToInvitesSectionMutation ("Invitation queued for " <> email) currentRosterGroup.id
            _ ->
                respondToInvitesSectionMutation "" currentRosterGroup.id

    action RevokeVenueInvitationAction { venueInvitationId } = do
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        invitation <- fetch venueInvitationId
        ensureRecordInCurrentVenue invitation.venueId
        if invitation.status /= unsafeEnumFromText @InvitationStatusEnum "pending"
            then respondToInvitesSectionMutation "Only pending invitations can be revoked." currentRosterGroup.id
            else do
                _ <- invitation
                    |> set #status (unsafeEnumFromText @InvitationStatusEnum "revoked")
                    |> updateRecord
                broadcastAdminInvitesInvalidation currentVenueId
                respondToInvitesSectionMutation "Invitation revoked." currentRosterGroup.id

    action CreateRosterGroupAction = do
        venue <- fetch currentVenueId
        maybeName <- parseRequiredName "name" "Roster group name is required."
        case maybeName of
            Nothing -> respondToRosterGroupsSectionMutation Nothing
            Just name -> do
                let isActive = parseIsActiveParam
                sortOrder <- nextRosterGroupSortOrder
                rosterGroup <- createVenueRosterGroupWithDefaults venue name sortOrder isActive
                syncVenueDefaultRosterGroupToTopActive currentVenueId
                setSuccessMessage "Roster group added"
                broadcastAdminRosterGroupsInvalidation currentVenueId
                respondToRosterGroupsSectionMutation (Just rosterGroup.id)

    action UpdateRosterGroupAction { rosterGroupId } = do
        venue <- fetch currentVenueId
        rosterGroup <- fetch rosterGroupId
        ensureRecordInCurrentVenue rosterGroup.venueId
        maybeName <- parseRequiredName "name" "Roster group name is required."
        case maybeName of
            Nothing -> respondToRosterGroupsSectionMutation (Just rosterGroup.id)
            Just name -> do
                let isActive = parseIsActiveParam
                rosterGroups <- fetchCurrentVenueRosterGroups
                let otherActiveGroups = filter (\group -> group.id /= rosterGroup.id && group.isActive) rosterGroups
                if not isActive && null otherActiveGroups
                    then do
                        setErrorMessage "Each venue needs at least one active roster group."
                        respondToRosterGroupsSectionMutation (Just rosterGroup.id)
                    else do
                        sortOrder <-
                            if not rosterGroup.isActive && isActive
                                then nextRosterGroupSortOrder
                                else pure rosterGroup.sortOrder
                        updatedRosterGroup <-
                            rosterGroup
                                |> set #name name
                                |> set #sortOrder sortOrder
                                |> set #isActive isActive
                                |> updateRecord
                        when isActive do
                            _ <- ensureDefaultRosterSlots venue updatedRosterGroup
                            pure ()
                        syncVenueDefaultRosterGroupToTopActive currentVenueId
                        setSuccessMessage "Roster group updated"
                        broadcastAdminRosterGroupsInvalidation currentVenueId
                        respondToRosterGroupsSectionMutation (Just updatedRosterGroup.id)

    action MoveRosterGroupUpAction { rosterGroupId } = do
        rosterGroup <- fetch rosterGroupId
        ensureRecordInCurrentVenue rosterGroup.venueId
        withTransaction do
            reorderActiveRosterGroups rosterGroup.id (-1)
            syncVenueDefaultRosterGroupToTopActive currentVenueId
        setSuccessMessage "Roster group order updated"
        broadcastAdminRosterGroupsInvalidation currentVenueId
        redirectToAdminFor (Just rosterGroup.id)

    action MoveRosterGroupDownAction { rosterGroupId } = do
        rosterGroup <- fetch rosterGroupId
        ensureRecordInCurrentVenue rosterGroup.venueId
        withTransaction do
            reorderActiveRosterGroups rosterGroup.id 1
            syncVenueDefaultRosterGroupToTopActive currentVenueId
        setSuccessMessage "Roster group order updated"
        broadcastAdminRosterGroupsInvalidation currentVenueId
        redirectToAdminFor (Just rosterGroup.id)

    action CreateShiftTypeAction = do
        maybeName <- parseRequiredName "name" "Shift type name is required."
        case maybeName of
            Nothing -> respondToShiftTypesSectionMutation
            Just name -> do
                let isActive = parseIsActiveParam
                sortOrder <- nextShiftTypeSortOrder
                maybeOverrideAwardLevelId <- parseSubmittedOverrideAwardLevelId
                case maybeOverrideAwardLevelId of
                    Nothing -> respondToShiftTypesSectionMutation
                    Just overrideAwardLevelId -> do
                        now <- getCurrentTime
                        shiftType <- withTransaction do
                            shiftType <-
                                newRecord @ShiftType
                                    |> set #venueId (unpackId currentVenueId)
                                    |> set #name name
                                    |> set #sortOrder sortOrder
                                    |> set #overrideAwardLevelId overrideAwardLevelId
                                    |> set #isActive isActive
                                    |> createRecord
                            _ <- ensureShiftTypePayVersionForShiftType currentUser.id shiftType (utctDay now)
                            pure shiftType
                        setSuccessMessage "Shift type added"
                        broadcastAdminShiftTypesInvalidation currentVenueId
                        let shouldRefreshXero = shiftTypeAffectsXeroPayItems shiftType
                        when shouldRefreshXero do
                            broadcastAdminXeroInvalidation currentVenueId
                        respondToShiftTypesSectionMutationWithXeroRefresh shouldRefreshXero

    action UpdateShiftTypeAction { shiftTypeId } = do
        shiftType <- fetch shiftTypeId
        ensureRecordInCurrentVenue shiftType.venueId
        maybeName <- parseRequiredName "name" "Shift type name is required."
        case maybeName of
            Nothing -> respondToShiftTypesSectionMutation
            Just name -> do
                let isActive = parseIsActiveParam
                maybeOverrideAwardLevelId <- parseSubmittedOverrideAwardLevelId
                case maybeOverrideAwardLevelId of
                    Nothing -> respondToShiftTypesSectionMutation
                    Just overrideAwardLevelId -> do
                        now <- getCurrentTime
                        sortOrder <-
                            if not shiftType.isActive && isActive
                                then nextShiftTypeSortOrder
                                else pure shiftType.sortOrder
                        updatedShiftType <- withTransaction do
                            updatedShiftType <-
                                shiftType
                                    |> set #name name
                                    |> set #sortOrder sortOrder
                                    |> set #overrideAwardLevelId overrideAwardLevelId
                                    |> set #isActive isActive
                                    |> updateRecord
                            when (shiftType.name /= updatedShiftType.name || shiftType.overrideAwardLevelId /= updatedShiftType.overrideAwardLevelId) do
                                _ <- ensureShiftTypePayVersionForShiftType currentUser.id updatedShiftType (utctDay now)
                                pure ()
                            pure updatedShiftType
                        setSuccessMessage "Shift type updated"
                        broadcastAdminShiftTypesInvalidation currentVenueId
                        let shouldRefreshXero = shiftTypeXeroPayItemScopeChanged shiftType updatedShiftType
                        when shouldRefreshXero do
                            broadcastAdminXeroInvalidation currentVenueId
                        respondToShiftTypesSectionMutationWithXeroRefresh shouldRefreshXero

    action MoveShiftTypeUpAction { shiftTypeId } = do
        shiftType <- fetch shiftTypeId
        ensureRecordInCurrentVenue shiftType.venueId
        withTransaction do
            reorderActiveShiftTypes shiftType.id (-1)
            pure ()
        setSuccessMessage "Shift type order updated"
        broadcastAdminShiftTypesInvalidation currentVenueId
        redirectToAdminFor (paramOrNothing "rosterGroupId")

    action MoveShiftTypeDownAction { shiftTypeId } = do
        shiftType <- fetch shiftTypeId
        ensureRecordInCurrentVenue shiftType.venueId
        withTransaction do
            reorderActiveShiftTypes shiftType.id 1
            pure ()
        setSuccessMessage "Shift type order updated"
        broadcastAdminShiftTypesInvalidation currentVenueId
        redirectToAdminFor (paramOrNothing "rosterGroupId")

    action CreateSlotNameAction = do
        maybeName <- parseRequiredName "name" "Slot name is required."
        case maybeName of
            Nothing -> redirectToAdminFor (paramOrNothing "rosterGroupId")
            Just name -> do
                rosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
                _ <- do
                    nextSortOrder <- nextSlotNameSortOrder rosterGroup.id
                    newRecord @SlotName
                        |> set #venueId (unpackId currentVenueId)
                        |> set #rosterGroupId (unpackId rosterGroup.id)
                        |> set #name name
                        |> set #sortOrder nextSortOrder
                        |> set #isActive True
                        |> createRecord
                broadcastAdminSlotNamesInvalidation rosterGroup.id
                broadcastSlotNameInvalidation rosterGroup.id
                respondToSlotNameSectionMutation "Slot name added" rosterGroup.id

    action UpdateSlotNameAction { slotNameId } = do
        slotName <- fetch slotNameId
        ensureRecordInCurrentVenue slotName.venueId
        maybeName <- parseRequiredName "name" "Slot name is required."
        case maybeName of
            Nothing -> redirectToAdminFor (Just (Id slotName.rosterGroupId :: Id RosterGroup))
            Just name -> do
                _ <- slotName
                    |> set #name name
                    |> updateRecord
                broadcastAdminSlotNamesInvalidation (Id slotName.rosterGroupId :: Id RosterGroup)
                broadcastSlotNameInvalidation (Id slotName.rosterGroupId :: Id RosterGroup)
                respondToSlotNameMutation "Slot name updated" (Id slotName.rosterGroupId :: Id RosterGroup)

    action MoveSlotNameUpAction { slotNameId } = do
        slotName <- fetch slotNameId
        ensureRecordInCurrentVenue slotName.venueId
        let rosterGroupId = Id slotName.rosterGroupId :: Id RosterGroup
        withTransaction do
            reorderActiveSlotNames rosterGroupId slotName.id (-1)
        broadcastAdminSlotNamesInvalidation rosterGroupId
        broadcastSlotNameInvalidation rosterGroupId
        respondToSlotNameSectionMutation "Slot order updated" rosterGroupId

    action MoveSlotNameDownAction { slotNameId } = do
        slotName <- fetch slotNameId
        ensureRecordInCurrentVenue slotName.venueId
        let rosterGroupId = Id slotName.rosterGroupId :: Id RosterGroup
        withTransaction do
            reorderActiveSlotNames rosterGroupId slotName.id 1
        broadcastAdminSlotNamesInvalidation rosterGroupId
        broadcastSlotNameInvalidation rosterGroupId
        respondToSlotNameSectionMutation "Slot order updated" rosterGroupId

    action DeleteSlotNameAction { slotNameId } = do
        slotName <- fetch slotNameId
        ensureRecordInCurrentVenue slotName.venueId
        let rosterGroupId = Id slotName.rosterGroupId :: Id RosterGroup
        _ <- slotName
            |> set #isActive False
            |> updateRecord
        broadcastAdminSlotNamesInvalidation rosterGroupId
        broadcastSlotNameInvalidation rosterGroupId
        respondToSlotNameSectionMutation "Slot deleted" rosterGroupId
