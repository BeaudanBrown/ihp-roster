module Web.Controller.Admin where

import Application.Helper.Export
import Application.Helper.LiveResource (LiveMutationResult (..),
                                        LiveResource (..), liveMutationResult)
import Application.Helper.LiveSurface (serveTypedLiveFragment)
import Application.Helper.PasskeySetupTokens
import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Application.Helper.Url (appendQueryParams)
import Application.Helper.WeekBoundaries (validRosterWeekStartDays,
                                          weekdayIndexLabel)
import Application.Helper.Xero
import Application.Helper.XeroAdminTypes
import Application.Helper.XeroPayItems
import Application.Xero.Connection
import qualified Data.Aeson as Aeson
import qualified Data.List as List
import qualified Data.Text as Text
import Data.Time.Clock (utctDay)
import Data.UUID (UUID)
import Web.Admin.Mutations
import Web.Controller.Admin.Support
import Web.Controller.Admin.Xero
import Web.Controller.Admin.Xero.Responses
import Web.Controller.Prelude
import Web.LiveResourceInvalidation (invalidateTouchedResources)
import Web.View.Admin.Exports
import Web.View.Admin.Index
import Web.View.Admin.Invites
import Web.View.Admin.RosterGroups
import Web.View.Admin.ShiftTypes
import Web.View.Admin.VenueSettings
import Web.View.Admin.Xero

profileLiveResourcesFor ::
    (?context :: ControllerContext, ?request :: Request) =>
    Text ->
    IO [LiveResource]
profileLiveResourcesFor resourceName = do
    let venueUuid = unpackId currentVenueId
    let weekOffset = paramOrDefault @Int 0 "weekOffset"
    let dayOffset = paramOrDefault @Int 0 "dayOffset"
    let rosterGroupId = paramOrNothing @UUID "rosterGroupId"
    let staffId = paramOrNothing @UUID "staffId"
    pure case resourceName of
        "billing" -> [BillingResource venueUuid]
        "admin-venue-config" -> [AdminVenueSettingsResource venueUuid]
        "roster-end-times-config" -> [RosterEndTimesConfigResource venueUuid]
        "roster-week-boundary-config" -> [RosterWeekBoundaryConfigResource venueUuid]
        "timesheet-week-boundary-config" -> [TimesheetWeekBoundaryConfigResource venueUuid]
        "admin-invites" -> [AdminInvitesResource venueUuid]
        "admin-roster-groups" -> [AdminRosterGroupsResource venueUuid]
        "admin-shift-types" -> [AdminShiftTypesResource venueUuid]
        "admin-exports" -> [AdminExportsResource venueUuid]
        "xero-connection" -> [XeroConnectionResource venueUuid]
        "xero-mappings" -> [XeroMappingsResource venueUuid]
        "xero-pay-items" -> [XeroPayItemsResource venueUuid]
        "xero-timesheets" -> [XeroTimesheetsResource venueUuid]
        "timesheet-week" -> [TimesheetWeekResource venueUuid weekOffset]
        "timesheet-day" -> [TimesheetDayResource venueUuid weekOffset dayOffset]
        "leave-requests" -> [LeaveRequestsResource venueUuid]
        "leave-calendar" -> [LeaveCalendarResource venueUuid weekOffset]
        "roster-week" -> maybe [] (\value -> [RosterWeekResource value weekOffset]) rosterGroupId
        "staff-leave" -> maybe [] (\value -> [StaffLeaveRequestsResource value]) staffId
        "staff-profile" -> maybe [] (\value -> [StaffProfileResource value]) staffId
        "staff-preferences" -> maybe [] (\value -> [StaffPreferencesResource value]) staffId
        "staff-roster-membership" -> maybe [] (\value -> [StaffRosterMembershipResource value]) staffId
        _ -> []

respondToVenueSettingsMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    IO ()
respondToVenueSettingsMutation =
    if isHtmxRequest
        then do
            setHeader ("HX-Reswap", "none")
            venueConfig <- fetchVenueConfig
            respondHtml (renderVenueSettingsSectionFragmentWithSwap (Just "outerHTML") venueConfig)
        else redirectToAdminFor (paramOrNothing "rosterGroupId")

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
            importedPayItems <- fetchActiveImportedXeroPayItems
            let showInactiveShiftTypes = parseShowInactiveParam "showInactiveShiftTypes"
            xeroFragment <- if shouldRefreshXero && currentUserCanManageXeroIntegration then renderCurrentVenueXeroSectionFragmentOob else pure mempty
            respondHtml $
                mconcat
                    [ renderShiftTypesSectionFragment shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates importedPayItems
                    , xeroFragment
                    ]
        else redirectToAdminFor (paramOrNothing "rosterGroupId")

sendStaffPasskeySetupLink ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id Staff ->
    PasskeySetupTokenPurpose ->
    Text ->
    IO ()
sendStaffPasskeySetupLink staffId purpose successMessage = do
    redirectPermissionDeniedUnless
        (currentUserIsSuperAdmin || hasRole VenueOwnerRole)
        "Only the venue owner or a super admin can send passkey setup links."
    maybeTarget <- fetchCurrentVenueStaffUser staffId
    case maybeTarget of
        Nothing -> do
            setErrorMessage "Choose a linked staff login from this venue."
            redirectTo AdminAction
        Just targetUser -> do
            (_, rawToken) <- issuePasskeySetupToken purpose targetUser (Just currentUser.id) (Just currentVenueId)
            sendPasskeySetupTokenEmail targetUser purpose rawToken
            setSuccessMessage successMessage
            redirectToPath staffPasskeyReturnPath

staffPasskeyReturnPath :: (?request :: Request) => Text
staffPasskeyReturnPath =
    case paramOrDefault @Text "admin" "returnTo" of
        "staff" ->
            appendQueryParams
                (pathTo ShowRosterWeekAction { weekOffset = paramOrDefault @Int 0 "weekOffset" })
                (maybe [] (\rosterGroupId -> [("rosterGroupId", tshow (rosterGroupId :: Id RosterGroup))]) (paramOrNothing "rosterGroupId"))
        _ -> pathTo AdminAction

fetchCurrentVenueStaffUser :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id Staff -> IO (Maybe User)
fetchCurrentVenueStaffUser staffId = do
    maybeStaff <-
        query @Staff
            |> filterWhere (#id, staffId)
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> fetchOneOrNothing
    case maybeStaff >>= (.userId) of
        Nothing     -> pure Nothing
        Just userId -> Just <$> fetch (Id userId :: Id User)

adminVenueMutationSpec :: BepisMutationSpec
adminVenueMutationSpec = BepisMutationSpec
    { auditPolicy = BepisAuditRequired
    , realtimePolicy = BepisNoRealtimeInvalidation
    , scopePolicy = BepisCurrentVenueScope
    }

adminXeroMutationSpec :: BepisMutationSpec
adminXeroMutationSpec = BepisMutationSpec
    { auditPolicy = BepisAuditRequired
    , realtimePolicy = BepisNoRealtimeInvalidation
    , scopePolicy = BepisCurrentVenueScope
    }

instance Controller AdminController where
    beforeAction = bepisBeforeAction BepisAdminVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted
        ensureAdminRole

    action currentAction@AdminAction = bepisPageAction currentAction $
        profileActionSpan "admin.page.render" do
            _ <- profileActionSpan "admin.page.normalize_roster_groups" ensureAdminRosterGroupsNormalizedMutation
            rosterGroups <- profileActionSpan "admin.page.fetch_roster_groups" fetchCurrentVenueRosterGroups
            currentRosterGroup <- profileActionSpan "admin.page.resolve_current_group" (fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId"))
            shiftTypes <- profileActionSpan "admin.page.fetch_shift_types" fetchCurrentVenueShiftTypes
            venueConfig <- profileActionSpan "admin.page.fetch_venue_config" fetchVenueConfig
            awardLevels <- profileActionSpan "admin.page.fetch_award_levels" fetchActiveAwardLevels
            awardLevelBaseRates <- profileActionSpan "admin.page.fetch_award_rates" fetchCurrentAwardLevelBaseRates
            importedPayItems <- profileActionSpan "admin.page.fetch_imported_pay_items" fetchActiveImportedXeroPayItems
            currentWeekOffset <- profileActionSpan "admin.page.current_report_week" currentReportWeekOffset
            reportWeekSelection <- profileActionSpan "admin.page.fetch_report_week_selection" (fetchReportWeekSelection currentWeekOffset)
            let defaultRangeStart = reportWeekSelection.weekStart
            let defaultRangeEnd = reportWeekSelection.weekEnd
            exportJobs <- profileActionSpan "admin.page.fetch_export_jobs" fetchCurrentVenueExportJobs
            let showInactiveRosterGroups = parseShowInactiveParam "showInactiveRosterGroups"
            let showInactiveShiftTypes = parseShowInactiveParam "showInactiveShiftTypes"
            invitations <- profileActionSpan "admin.page.fetch_invitations" fetchCurrentVenueInvitations
            today <- utctDay <$> getCurrentTime
            profileActionSpan "admin.page.render_response" (render IndexView { .. })

    action currentAction@XeroAction = bepisPageAction currentAction $
        profileActionSpan "admin.xero.page.render" do
            redirectPermissionDeniedUnless currentUserCanManageXeroIntegration "Only the venue owner or a super admin can manage Xero for this venue."
            let xeroAutoSyncAfterConnect = paramOrDefault @Text "false" "syncAfterConnect" == "true"
            xeroSectionData <- profileActionSpan "admin.xero.page.fetch_section_data" fetchCurrentVenueXeroAdminSectionData
            profileActionSpan "admin.xero.page.render_response" (render XeroView { .. })

    action currentAction@ProfileLiveInvalidateVenueAction = bepisPageAction currentAction do
        profilingEnabled <- liftIO isRequestProfilingEnabled
        redirectPermissionDeniedUnless profilingEnabled "Live profiling endpoints are only available while profiling is enabled."
        let resourceName = param @Text "resource"
        resources <- profileLiveResourcesFor resourceName
        _ <- invalidateTouchedResources ("profile.live." <> resourceName) (liveMutationResult () resources)
        respondHtml "ok"

    action currentAction@SendStaffPasskeySetupEmailAction { staffId } = bepisMutationAction currentAction adminVenueMutationSpec do
        sendStaffPasskeySetupLink staffId StaffNewDevicePasskeySetup "Passkey setup email sent."

    action currentAction@SendStaffPasskeyRecoveryEmailAction { staffId } = bepisMutationAction currentAction adminVenueMutationSpec do
        sendStaffPasskeySetupLink staffId StaffPasskeyRecovery "Passkey recovery email sent."

    action currentAction@StartXeroConnectionAction = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        startXeroConnectionAction

    action currentAction@XeroOAuthCallbackAction = bepisIntegrationAction currentAction $
        xeroOAuthCallbackAction

    action currentAction@DisconnectXeroConnectionAction = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        disconnectXeroConnectionAction

    action currentAction@SyncXeroPayrollReferenceDataAction = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero syncXeroPayrollReferenceDataAction

    action currentAction@CreateMissingXeroPayItemsAction = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero createMissingXeroPayItemsAction

    action currentAction@OpenXeroPayItemImportAction = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero openXeroPayItemImportAction

    action currentAction@ImportXeroPayItemsAction = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero importXeroPayItemsAction

    action currentAction@ArchiveXeroImportedPayItemAction { xeroImportedPayItemId } = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (archiveXeroImportedPayItemAction xeroImportedPayItemId)

    action currentAction@SaveXeroStaffMappingAction = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero saveXeroStaffMappingAction

    action currentAction@SuggestXeroStaffMappingAction { staffId } = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (suggestXeroStaffMappingAction staffId)

    action currentAction@SaveXeroEarningsRateMappingAction = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero saveXeroEarningsRateMappingAction

    action currentAction@SaveXeroPayItemAccountCodeSelectionAction = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero saveXeroPayItemAccountCodeSelectionAction

    action currentAction@SaveXeroPayrollCalendarSelectionAction = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero saveXeroPayrollCalendarSelectionAction

    action currentAction@OpenXeroTimesheetPreparationAction = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero openXeroTimesheetPreparationAction

    action currentAction@RunXeroTimesheetPreparationAction = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero runXeroTimesheetPreparationAction

    action currentAction@RefreshXeroTimesheetPreparationAction { xeroTimesheetPreparationRunId } = bepisPageAction currentAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (refreshXeroTimesheetPreparationAction xeroTimesheetPreparationRunId)

    action currentAction@ShowXeroTimesheetPreparationStaffMappingsFragmentAction { xeroTimesheetPreparationRunId } = bepisFragmentAction currentAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (showXeroTimesheetPreparationStaffMappingsFragmentAction xeroTimesheetPreparationRunId)

    action currentAction@ApplyXeroTimesheetPreparationStaffDecisionAction { xeroTimesheetPreparationRunId } = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (applyXeroTimesheetPreparationStaffDecisionAction xeroTimesheetPreparationRunId)

    action currentAction@ContinueXeroTimesheetPreparationStaffStepAction { xeroTimesheetPreparationRunId } = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (continueXeroTimesheetPreparationStaffStepAction xeroTimesheetPreparationRunId)

    action currentAction@SelectXeroTimesheetPreparationPeriodAction { xeroTimesheetPreparationRunId } = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (selectXeroTimesheetPreparationPeriodAction xeroTimesheetPreparationRunId)

    action currentAction@ApproveXeroTimesheetPreparationPayItemsAction { xeroTimesheetPreparationRunId } = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (approveXeroTimesheetPreparationPayItemsAction xeroTimesheetPreparationRunId)

    action currentAction@ShowXeroTimesheetPreparationSummaryAction { xeroTimesheetPreparationRunId } = bepisPageAction currentAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (showXeroTimesheetPreparationSummaryAction xeroTimesheetPreparationRunId)

    action currentAction@ConfirmXeroTimesheetPreparationSubmissionAction { xeroTimesheetPreparationRunId } = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (confirmXeroTimesheetPreparationSubmissionAction xeroTimesheetPreparationRunId)

    action currentAction@RunXeroTimesheetPreparationSubmissionAction { xeroTimesheetPreparationRunId } = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (runXeroTimesheetPreparationSubmissionAction xeroTimesheetPreparationRunId)

    action currentAction@SubmitXeroTimesheetPreparationAction { xeroTimesheetPreparationRunId } = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (submitXeroTimesheetPreparationAction xeroTimesheetPreparationRunId)

    action currentAction@PreviewXeroDraftTimesheetsAction = bepisPageAction currentAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero previewXeroDraftTimesheetsAction

    action currentAction@SubmitXeroDraftTimesheetsAction = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero submitXeroDraftTimesheetsAction

    action currentAction@RetryXeroDraftTimesheetSubmissionAction { xeroTimesheetSubmissionId } = bepisMutationAction currentAction adminXeroMutationSpec do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (retryXeroDraftTimesheetSubmissionAction xeroTimesheetSubmissionId)

    action currentAction@UpdateVenueConfigAction = bepisMutationAction currentAction adminVenueMutationSpec do
        ensureVenueWritable
        venueConfig <- fetchVenueConfig
        let configField = paramOrDefault @Text "rosterWeekStartsOn" "configField"
        case configField of
            "rosterEndTimesEnabled" -> do
                let rosterEndTimesEnabled = isJust (paramOrNothing @Text "rosterEndTimesEnabled")
                _ <- setRosterEndTimesEnabledMutation venueConfig rosterEndTimesEnabled
                setSuccessMessage $
                    if rosterEndTimesEnabled
                        then "Roster end times shown in the roster."
                        else "Roster end times hidden from the roster."
                respondToVenueSettingsMutation
            "autoTimesheetCreationEnabled" -> do
                let autoTimesheetCreationEnabled = isJust (paramOrNothing @Text "autoTimesheetCreationEnabled")
                _ <- setAutoTimesheetCreationEnabledMutation venueConfig autoTimesheetCreationEnabled
                setSuccessMessage $
                    if autoTimesheetCreationEnabled
                        then "Auto-created pending timesheets enabled."
                        else "Auto-created pending timesheets disabled."
                respondToVenueSettingsMutation
            _ -> do
                requestedRosterWeekStartsOn <- parseRosterWeekStartsOn
                case requestedRosterWeekStartsOn of
                    Nothing -> respondToVenueSettingsMutation
                    Just rosterWeekStartsOn -> do
                        isLocked <- isVenueRosterWeekStartLocked
                        if isLocked
                            then do
                                setErrorMessage "Roster week start can only be configured before roster, timesheet, leave, export, or payroll version data exists."
                                respondToVenueSettingsMutation
                            else do
                                _ <- setRosterWeekStartsOnMutation venueConfig rosterWeekStartsOn
                                setSuccessMessage ("Roster week will start on " <> weekdayIndexLabel rosterWeekStartsOn)
                                respondToVenueSettingsMutation

    action currentAction@ShowAdminVenueSettingsFragmentAction = bepisFragmentAction currentAction $
        profileActionSpan "admin.venue_settings_fragment.respond" do
            serveTypedLiveFragment adminVenueSettingsLiveSurfaceDefinition () adminVenueSettingsFragment \_ -> do
                venueConfig <- profileActionSpan "admin.venue_settings_fragment.fetch_venue_config" fetchVenueConfig
                profileActionSpan "admin.venue_settings_fragment.render_response" (respondHtml (renderVenueSettingsSectionFragment venueConfig))

    action currentAction@ShowAdminInvitesFragmentAction = bepisFragmentAction currentAction $
        profileActionSpan "admin.invites_fragment.respond" do
            currentRosterGroup <- profileActionSpan "admin.invites_fragment.resolve_current_group" (fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId"))
            serveTypedLiveFragment adminInvitesLiveSurfaceDefinition AdminInvitesSurfaceKey { adminInvitesRosterGroupId = Just currentRosterGroup.id } adminInvitesFragment \_ -> do
                invitations <- profileActionSpan "admin.invites_fragment.fetch_invitations" fetchCurrentVenueInvitations
                profileActionSpan "admin.invites_fragment.render_response" (respondHtml (renderInvitesSectionFragment invitations currentRosterGroup.id))

    action currentAction@ShowAdminShiftTypesFragmentAction = bepisFragmentAction currentAction $
        profileActionSpan "admin.shift_types_fragment.respond" do
            serveTypedLiveFragment adminShiftTypesLiveSurfaceDefinition () adminShiftTypesFragment \_ -> do
                shiftTypes <- profileActionSpan "admin.shift_types_fragment.fetch_shift_types" fetchCurrentVenueShiftTypes
                awardLevels <- profileActionSpan "admin.shift_types_fragment.fetch_award_levels" fetchActiveAwardLevels
                awardLevelBaseRates <- profileActionSpan "admin.shift_types_fragment.fetch_award_rates" fetchCurrentAwardLevelBaseRates
                importedPayItems <- profileActionSpan "admin.shift_types_fragment.fetch_imported_pay_items" fetchActiveImportedXeroPayItems
                let showInactiveShiftTypes = parseShowInactiveParam "showInactiveShiftTypes"
                profileActionSpan "admin.shift_types_fragment.render_response" (respondHtml (renderShiftTypesSectionFragment shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates importedPayItems))

    action currentAction@ShowAdminRosterGroupsFragmentAction = bepisFragmentAction currentAction $
        profileActionSpan "admin.roster_groups_fragment.respond" do
            serveTypedLiveFragment adminRosterGroupsLiveSurfaceDefinition () adminRosterGroupsFragment \_ -> do
                _ <- profileActionSpan "admin.roster_groups_fragment.normalize_roster_groups" ensureAdminRosterGroupsNormalizedMutation
                rosterGroups <- profileActionSpan "admin.roster_groups_fragment.fetch_roster_groups" fetchCurrentVenueRosterGroups
                let showInactiveRosterGroups = parseShowInactiveParam "showInactiveRosterGroups"
                profileActionSpan "admin.roster_groups_fragment.render_response" (respondHtml (renderRosterGroupsSectionFragment rosterGroups showInactiveRosterGroups))

    action currentAction@ShowAdminExportsFragmentAction = bepisFragmentAction currentAction $
        profileActionSpan "admin.exports_fragment.respond" do
            serveTypedLiveFragment adminExportsLiveSurfaceDefinition () adminExportsFragment \_ -> do
                currentWeekOffset <- profileActionSpan "admin.exports_fragment.current_report_week" currentReportWeekOffset
                reportWeekSelection <- profileActionSpan "admin.exports_fragment.fetch_report_week_selection" (fetchReportWeekSelection currentWeekOffset)
                let defaultRangeStart = reportWeekSelection.weekStart
                let defaultRangeEnd = reportWeekSelection.weekEnd
                exportJobs <- profileActionSpan "admin.exports_fragment.fetch_export_jobs" fetchCurrentVenueExportJobs
                profileActionSpan "admin.exports_fragment.render_response" (respondHtml (renderExportsSectionFragment reportWeekSelection defaultRangeStart defaultRangeEnd exportJobs))

    action currentAction@ShowAdminXeroFragmentAction = bepisFragmentAction currentAction $
        profileActionSpan "admin.xero_fragment.respond" do
            serveTypedLiveFragment adminXeroLiveSurfaceDefinition () adminXeroShellFragment \_ ->
                requireCurrentVenueOwnerForXero respondWithXeroSectionFragment

    action currentAction@ShowAdminXeroStaffMappingsFragmentAction = bepisFragmentAction currentAction $
        serveTypedLiveFragment adminXeroLiveSurfaceDefinition () adminXeroStaffMappingsFragment \_ ->
            requireCurrentVenueOwnerForXero respondWithXeroStaffMappingsFragment

    action currentAction@ShowAdminXeroPayItemsFragmentAction = bepisFragmentAction currentAction $
        serveTypedLiveFragment adminXeroLiveSurfaceDefinition () adminXeroPayItemsFragment \_ ->
            requireCurrentVenueOwnerForXero respondWithXeroPayItemsFragment

    action currentAction@ShowAdminXeroTimesheetsFragmentAction = bepisFragmentAction currentAction $
        serveTypedLiveFragment adminXeroLiveSurfaceDefinition () adminXeroTimesheetsFragment \_ ->
            requireCurrentVenueOwnerForXero respondWithXeroTimesheetsFragment

    action currentAction@CreateVenueInvitationAction = bepisMutationAction currentAction adminVenueMutationSpec do
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

    action currentAction@RevokeVenueInvitationAction { venueInvitationId } = bepisMutationAction currentAction adminVenueMutationSpec do
        ensureVenueWritable
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        invitation <- fetch venueInvitationId
        ensureRecordInCurrentVenue invitation.venueId
        if invitation.status /= unsafeEnumFromText @InvitationStatusEnum "pending"
            then respondToInvitesSectionMutation "Only pending invitations can be revoked." currentRosterGroup.id
            else do
                _ <- revokeVenueInvitationMutation invitation
                respondToInvitesSectionMutation "Invitation revoked." currentRosterGroup.id

    action currentAction@CreateRosterGroupAction = bepisMutationAction currentAction adminVenueMutationSpec do
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

    action currentAction@UpdateRosterGroupAction { rosterGroupId } = bepisMutationAction currentAction adminVenueMutationSpec do
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

    action currentAction@MoveRosterGroupUpAction { rosterGroupId } = bepisMutationAction currentAction adminVenueMutationSpec do
        ensureVenueWritable
        rosterGroup <- fetch rosterGroupId
        ensureRecordInCurrentVenue rosterGroup.venueId
        _ <- moveRosterGroupMutation rosterGroup (-1)
        setSuccessMessage "Roster group order updated"
        respondToRosterGroupsSectionMutation (Just rosterGroup.id)

    action currentAction@MoveRosterGroupDownAction { rosterGroupId } = bepisMutationAction currentAction adminVenueMutationSpec do
        ensureVenueWritable
        rosterGroup <- fetch rosterGroupId
        ensureRecordInCurrentVenue rosterGroup.venueId
        _ <- moveRosterGroupMutation rosterGroup 1
        setSuccessMessage "Roster group order updated"
        respondToRosterGroupsSectionMutation (Just rosterGroup.id)

    action currentAction@CreateShiftTypeAction = bepisMutationAction currentAction adminVenueMutationSpec do
        ensureVenueWritable
        maybeName <- parseRequiredName "name" "Shift type name is required."
        case maybeName of
            Nothing -> respondToShiftTypesSectionMutation
            Just name -> do
                let isActive = parseIsActiveParam
                maybePayRateSelection <- parseSubmittedPayRateSelection "payRateSelection"
                case maybePayRateSelection of
                    Just payRateSelection -> do
                        let maybeColourKey = parseSubmittedShiftTypeColourKey
                        LiveMutationResult { liveMutationValue = AdminShiftTypeMutationResult { adminShiftTypeMutationShouldRefreshXero = shouldRefreshXero } } <- createShiftTypeMutation name isActive payRateSelection.submittedAwardLevelId payRateSelection.submittedImportedXeroPayItemId maybeColourKey
                        setSuccessMessage "Shift type added"
                        respondToShiftTypesSectionMutationWithXeroRefresh shouldRefreshXero
                    Nothing -> respondToShiftTypesSectionMutation

    action currentAction@UpdateShiftTypeAction { shiftTypeId } = bepisMutationAction currentAction adminVenueMutationSpec do
        ensureVenueWritable
        shiftType <- fetch shiftTypeId
        ensureRecordInCurrentVenue shiftType.venueId
        maybeName <- parseRequiredName "name" "Shift type name is required."
        case maybeName of
            Nothing -> respondToShiftTypesSectionMutation
            Just name -> do
                let isActive = parseIsActiveParam
                maybePayRateSelection <- parseSubmittedPayRateSelection "payRateSelection"
                case maybePayRateSelection of
                    Just payRateSelection -> do
                        let maybeColourKey = parseSubmittedShiftTypeColourKey
                        LiveMutationResult { liveMutationValue = AdminShiftTypeMutationResult { adminShiftTypeMutationShouldRefreshXero = shouldRefreshXero } } <- updateShiftTypeMutation shiftType name isActive payRateSelection.submittedAwardLevelId payRateSelection.submittedImportedXeroPayItemId maybeColourKey
                        unless isHtmxRequest do
                            setSuccessMessage "Shift type updated"
                        respondToShiftTypesSectionMutationWithXeroRefresh shouldRefreshXero
                    Nothing -> respondToShiftTypesSectionMutation

    action currentAction@MoveShiftTypeUpAction { shiftTypeId } = bepisMutationAction currentAction adminVenueMutationSpec do
        ensureVenueWritable
        shiftType <- fetch shiftTypeId
        ensureRecordInCurrentVenue shiftType.venueId
        _ <- moveShiftTypeMutation shiftType (-1)
        setSuccessMessage "Shift type order updated"
        respondToShiftTypesSectionMutationWithXeroRefresh False

    action currentAction@MoveShiftTypeDownAction { shiftTypeId } = bepisMutationAction currentAction adminVenueMutationSpec do
        ensureVenueWritable
        shiftType <- fetch shiftTypeId
        ensureRecordInCurrentVenue shiftType.venueId
        _ <- moveShiftTypeMutation shiftType 1
        setSuccessMessage "Shift type order updated"
        respondToShiftTypesSectionMutationWithXeroRefresh False
