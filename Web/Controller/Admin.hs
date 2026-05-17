module Web.Controller.Admin where

import Application.Helper.Export
import Application.Helper.LiveSurface (ensureTypedLiveSurfaceAuthorized)
import Application.Helper.LiveResource (LiveMutationResult (..))
import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Application.Helper.WeekBoundaries (validRosterWeekStartDays,
                                          weekdayIndexLabel)
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroPayItems
import Application.StaffDocuments.Rsa (staffRsaComplianceRowsForVenue)
import Application.Xero.Connection
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Time.Clock (utctDay)
import Web.Admin.Mutations
import Web.Controller.Admin.Support
import Web.Controller.Admin.Xero
import Web.Controller.Admin.Xero.Responses
import Web.Controller.Prelude
import Web.View.Admin.Compliance
import Web.View.Admin.Exports
import Web.View.Admin.Index
import Web.View.Admin.Invites
import Web.View.Admin.RosterGroups
import Web.View.Admin.ShiftTypes
import Web.View.Admin.Xero

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
        _ <- ensureAdminRosterGroupsNormalizedMutation
        rosterGroups <- fetchCurrentVenueRosterGroups
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        shiftTypes <- fetchCurrentVenueShiftTypes
        venueConfig <- fetchVenueConfig
        awardLevels <- fetchActiveAwardLevels
        awardLevelBaseRates <- fetchCurrentAwardLevelBaseRates
        currentWeekOffset <- currentReportWeekOffset
        reportWeekSelection <- fetchReportWeekSelection currentWeekOffset
        let defaultRangeStart = reportWeekSelection.weekStart
        let defaultRangeEnd = reportWeekSelection.weekEnd
        exportJobs <- fetchCurrentVenueExportJobs
        let showInactiveRosterGroups = parseShowInactiveParam "showInactiveRosterGroups"
        let showInactiveShiftTypes = parseShowInactiveParam "showInactiveShiftTypes"
        invitations <- fetchCurrentVenueInvitations
        rsaComplianceRows <- staffRsaComplianceRowsForVenue currentVenueId
        today <- utctDay <$> getCurrentTime
        render IndexView { .. }

    action XeroAction = do
        redirectPermissionDeniedUnless currentUserCanManageXeroIntegration "Only the venue owner or a super admin can manage Xero for this venue."
        let xeroAutoSyncAfterReconnect = paramOrDefault @Text "false" "syncAfterReconnect" == "true"
        xeroSectionData <- fetchCurrentVenueXeroAdminSectionData
        render XeroView { .. }

    action StartXeroConnectionAction = do
        ensureVenueWritable
        startXeroConnectionAction

    action XeroOAuthCallbackAction =
        xeroOAuthCallbackAction

    action DisconnectXeroConnectionAction = do
        ensureVenueWritable
        disconnectXeroConnectionAction

    action SyncXeroPayrollReferenceDataAction = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero syncXeroPayrollReferenceDataAction

    action CreateMissingXeroPayItemsAction = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero createMissingXeroPayItemsAction

    action SaveXeroStaffMappingAction = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero saveXeroStaffMappingAction

    action SuggestXeroStaffMappingAction { staffId } = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (suggestXeroStaffMappingAction staffId)

    action SaveXeroEarningsRateMappingAction = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero saveXeroEarningsRateMappingAction

    action SaveXeroPayItemAccountCodeSelectionAction = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero saveXeroPayItemAccountCodeSelectionAction

    action SaveXeroPayrollCalendarSelectionAction = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero saveXeroPayrollCalendarSelectionAction

    action OpenXeroTimesheetPreparationAction = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero openXeroTimesheetPreparationAction

    action RunXeroTimesheetPreparationAction = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero runXeroTimesheetPreparationAction

    action RefreshXeroTimesheetPreparationAction { xeroTimesheetPreparationRunId } = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (refreshXeroTimesheetPreparationAction xeroTimesheetPreparationRunId)

    action SyncXeroTimesheetPreparationReferenceDataAction { xeroTimesheetPreparationRunId } = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (syncXeroTimesheetPreparationReferenceDataAction xeroTimesheetPreparationRunId)

    action SaveXeroTimesheetPreparationCalendarAction { xeroTimesheetPreparationRunId } = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (saveXeroTimesheetPreparationCalendarAction xeroTimesheetPreparationRunId)

    action SaveXeroTimesheetPreparationAccountCodeAction { xeroTimesheetPreparationRunId } = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (saveXeroTimesheetPreparationAccountCodeAction xeroTimesheetPreparationRunId)

    action SaveXeroTimesheetPreparationEarningsRateAction { xeroTimesheetPreparationRunId } = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (saveXeroTimesheetPreparationEarningsRateAction xeroTimesheetPreparationRunId)

    action ApplyXeroTimesheetPreparationStaffDecisionAction { xeroTimesheetPreparationRunId } = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (applyXeroTimesheetPreparationStaffDecisionAction xeroTimesheetPreparationRunId)

    action ApproveXeroTimesheetPreparationPayItemsAction { xeroTimesheetPreparationRunId } = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (approveXeroTimesheetPreparationPayItemsAction xeroTimesheetPreparationRunId)

    action PreviewXeroTimesheetPreparationAction { xeroTimesheetPreparationRunId } = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (previewXeroTimesheetPreparationAction xeroTimesheetPreparationRunId)

    action SubmitXeroTimesheetPreparationAction { xeroTimesheetPreparationRunId } = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (submitXeroTimesheetPreparationAction xeroTimesheetPreparationRunId)

    action PreviewXeroDraftTimesheetsAction = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero previewXeroDraftTimesheetsAction

    action SubmitXeroDraftTimesheetsAction = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero submitXeroDraftTimesheetsAction

    action RetryXeroDraftTimesheetSubmissionAction { xeroTimesheetSubmissionId } = do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (retryXeroDraftTimesheetSubmissionAction xeroTimesheetSubmissionId)

    action UpdateVenueConfigAction = do
        ensureVenueWritable
        venueConfig <- fetchVenueConfig
        let configField = paramOrDefault @Text "rosterWeekStartsOn" "configField"
        case configField of
            "rosterEndTimesEnabled" -> do
                let rosterEndTimesEnabled = isJust (paramOrNothing @Text "rosterEndTimesEnabled")
                _ <- setRosterEndTimesEnabledMutation venueConfig rosterEndTimesEnabled
                setSuccessMessage $
                    if rosterEndTimesEnabled
                        then "Roster end times enabled."
                        else "Roster end times disabled."
                redirectToAdminFor (paramOrNothing "rosterGroupId")
            "autoTimesheetCreationEnabled" -> do
                let autoTimesheetCreationEnabled = isJust (paramOrNothing @Text "autoTimesheetCreationEnabled")
                _ <- setAutoTimesheetCreationEnabledMutation venueConfig autoTimesheetCreationEnabled
                setSuccessMessage $
                    if autoTimesheetCreationEnabled
                        then "Auto-created pending timesheets enabled."
                        else "Auto-created pending timesheets disabled."
                redirectToAdminFor (paramOrNothing "rosterGroupId")
            _ -> do
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
                                _ <- setRosterWeekStartsOnMutation venueConfig rosterWeekStartsOn
                                setSuccessMessage ("Roster week will start on " <> weekdayIndexLabel rosterWeekStartsOn)
                                redirectToAdminFor (paramOrNothing "rosterGroupId")

    action ShowAdminInvitesFragmentAction = do
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        ensureTypedLiveSurfaceAuthorized adminInvitesLiveSurfaceDefinition AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Just currentRosterGroup.id }
        invitations <- fetchCurrentVenueInvitations
        respondHtml (renderInvitesSectionFragment invitations currentRosterGroup.id)

    action ShowAdminShiftTypesFragmentAction = do
        ensureTypedLiveSurfaceAuthorized adminShiftTypesLiveSurfaceDefinition ()
        shiftTypes <- fetchCurrentVenueShiftTypes
        awardLevels <- fetchActiveAwardLevels
        awardLevelBaseRates <- fetchCurrentAwardLevelBaseRates
        let showInactiveShiftTypes = parseShowInactiveParam "showInactiveShiftTypes"
        respondHtml (renderShiftTypesSectionFragment shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates)

    action ShowAdminRosterGroupsFragmentAction = do
        ensureTypedLiveSurfaceAuthorized adminRosterGroupsLiveSurfaceDefinition ()
        _ <- ensureAdminRosterGroupsNormalizedMutation
        rosterGroups <- fetchCurrentVenueRosterGroups
        let showInactiveRosterGroups = parseShowInactiveParam "showInactiveRosterGroups"
        respondHtml (renderRosterGroupsSectionFragment rosterGroups showInactiveRosterGroups)

    action ShowAdminExportsFragmentAction = do
        ensureTypedLiveSurfaceAuthorized adminExportsLiveSurfaceDefinition ()
        currentWeekOffset <- currentReportWeekOffset
        reportWeekSelection <- fetchReportWeekSelection currentWeekOffset
        let defaultRangeStart = reportWeekSelection.weekStart
        let defaultRangeEnd = reportWeekSelection.weekEnd
        exportJobs <- fetchCurrentVenueExportJobs
        respondHtml (renderExportsSectionFragment reportWeekSelection defaultRangeStart defaultRangeEnd exportJobs)

    action ShowAdminComplianceFragmentAction = do
        ensureTypedLiveSurfaceAuthorized staffComplianceLiveSurfaceDefinition ()
        rsaComplianceRows <- staffRsaComplianceRowsForVenue currentVenueId
        today <- utctDay <$> getCurrentTime
        respondHtml (renderComplianceSectionFragment rsaComplianceRows today)

    action ShowAdminXeroFragmentAction = do
        ensureTypedLiveSurfaceAuthorized adminXeroLiveSurfaceDefinition ()
        requireCurrentVenueOwnerForXero respondWithXeroSectionFragment

    action ShowAdminXeroStaffMappingsFragmentAction = do
        ensureTypedLiveSurfaceAuthorized adminXeroLiveSurfaceDefinition ()
        requireCurrentVenueOwnerForXero respondWithXeroStaffMappingsFragment

    action ShowAdminXeroPayItemsFragmentAction = do
        ensureTypedLiveSurfaceAuthorized adminXeroLiveSurfaceDefinition ()
        requireCurrentVenueOwnerForXero respondWithXeroPayItemsFragment

    action ShowAdminXeroTimesheetsFragmentAction = do
        ensureTypedLiveSurfaceAuthorized adminXeroLiveSurfaceDefinition ()
        requireCurrentVenueOwnerForXero respondWithXeroTimesheetsFragment

    action CreateVenueInvitationAction = do
        ensureVenueWritable
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        maybeEmail <- parseRequiredEmail "email" "Invite email is required."
        case maybeEmail of
            Just email -> do
                _ <- createVenueInvitationMutation email
                if isHtmxRequest
                    then do
                        invitations <- fetchCurrentVenueInvitations
                        setSuccessMessage ("Invitation queued for " <> email)
                        respondHtml (renderInvitesSectionFragment invitations currentRosterGroup.id)
                    else do
                        respondToInvitesSectionMutation ("Invitation queued for " <> email) currentRosterGroup.id
            _ ->
                respondToInvitesSectionMutation "" currentRosterGroup.id

    action RevokeVenueInvitationAction { venueInvitationId } = do
        ensureVenueWritable
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        invitation <- fetch venueInvitationId
        ensureRecordInCurrentVenue invitation.venueId
        if invitation.status /= unsafeEnumFromText @InvitationStatusEnum "pending"
            then respondToInvitesSectionMutation "Only pending invitations can be revoked." currentRosterGroup.id
            else do
                _ <- revokeVenueInvitationMutation invitation
                respondToInvitesSectionMutation "Invitation revoked." currentRosterGroup.id

    action CreateRosterGroupAction = do
        ensureVenueWritable
        venue <- fetch currentVenueId
        maybeName <- parseRequiredName "name" "Roster group name is required."
        case maybeName of
            Nothing -> respondToRosterGroupsSectionMutation Nothing
            Just name -> do
                let isActive = parseIsActiveParam
                LiveMutationResult { liveMutationValue = rosterGroup } <- createRosterGroupMutation venue name isActive
                setSuccessMessage "Roster group added"
                respondToRosterGroupsSectionMutation (Just rosterGroup.id)

    action UpdateRosterGroupAction { rosterGroupId } = do
        ensureVenueWritable
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
                        LiveMutationResult { liveMutationValue = updatedRosterGroup } <- updateRosterGroupMutation venue rosterGroup name isActive
                        setSuccessMessage "Roster group updated"
                        respondToRosterGroupsSectionMutation (Just updatedRosterGroup.id)

    action MoveRosterGroupUpAction { rosterGroupId } = do
        ensureVenueWritable
        rosterGroup <- fetch rosterGroupId
        ensureRecordInCurrentVenue rosterGroup.venueId
        _ <- moveRosterGroupMutation rosterGroup (-1)
        setSuccessMessage "Roster group order updated"
        redirectToAdminFor (Just rosterGroup.id)

    action MoveRosterGroupDownAction { rosterGroupId } = do
        ensureVenueWritable
        rosterGroup <- fetch rosterGroupId
        ensureRecordInCurrentVenue rosterGroup.venueId
        _ <- moveRosterGroupMutation rosterGroup 1
        setSuccessMessage "Roster group order updated"
        redirectToAdminFor (Just rosterGroup.id)

    action CreateShiftTypeAction = do
        ensureVenueWritable
        maybeName <- parseRequiredName "name" "Shift type name is required."
        case maybeName of
            Nothing -> respondToShiftTypesSectionMutation
            Just name -> do
                let isActive = parseIsActiveParam
                maybeOverrideAwardLevelId <- parseSubmittedOverrideAwardLevelId
                case maybeOverrideAwardLevelId of
                    Nothing -> respondToShiftTypesSectionMutation
                    Just overrideAwardLevelId -> do
                        LiveMutationResult { liveMutationValue = AdminShiftTypeMutationResult { adminShiftTypeMutationShouldRefreshXero = shouldRefreshXero } } <- createShiftTypeMutation name isActive overrideAwardLevelId
                        setSuccessMessage "Shift type added"
                        respondToShiftTypesSectionMutationWithXeroRefresh shouldRefreshXero

    action UpdateShiftTypeAction { shiftTypeId } = do
        ensureVenueWritable
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
                        LiveMutationResult { liveMutationValue = AdminShiftTypeMutationResult { adminShiftTypeMutationShouldRefreshXero = shouldRefreshXero } } <- updateShiftTypeMutation shiftType name isActive overrideAwardLevelId
                        unless isHtmxRequest do
                            setSuccessMessage "Shift type updated"
                        respondToShiftTypesSectionMutationWithXeroRefresh shouldRefreshXero

    action MoveShiftTypeUpAction { shiftTypeId } = do
        ensureVenueWritable
        shiftType <- fetch shiftTypeId
        ensureRecordInCurrentVenue shiftType.venueId
        _ <- moveShiftTypeMutation shiftType (-1)
        setSuccessMessage "Shift type order updated"
        redirectToAdminFor (paramOrNothing "rosterGroupId")

    action MoveShiftTypeDownAction { shiftTypeId } = do
        ensureVenueWritable
        shiftType <- fetch shiftTypeId
        ensureRecordInCurrentVenue shiftType.venueId
        _ <- moveShiftTypeMutation shiftType 1
        setSuccessMessage "Shift type order updated"
        redirectToAdminFor (paramOrNothing "rosterGroupId")
