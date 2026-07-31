module Web.Controller.Admin where

import Application.Helper.Export
import qualified Application.Helper.FrontendContract.Surface.Admin as Surface
import qualified Application.Helper.FrontendContract.Surface.Admin.Action as AdminAction
import Application.Helper.FrontendContract.Surface.Admin.Live (adminShiftTypesLiveScope)
import Application.Helper.FrontendContract.Surface.Admin.Resource (adminInvitesResource,
                                                                   xeroConnectionResource)
import Application.Helper.FrontendContract.Surface.Billing.Resource (billingResource)
import Application.Helper.FrontendContract.Surface.LeaveRequests.Resource (pendingLeaveRequestsResource)
import Application.Helper.FrontendContract.Surface.Request (SurfaceRequestFieldError,
                                                            surfaceActionParamsPresent,
                                                            surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Roster.Resource (rosterWeekResource)
import Application.Helper.FrontendContract.Surface.Timesheets.Resource (timesheetWeekResource)
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.LiveUpdate (setActorLiveResourcesRefresh)
import Application.Helper.PasskeySetupTokens
import Application.Helper.Profiling
import Application.Helper.RosterGroups
import Application.Helper.SurfaceResource
import Application.Helper.TimeRules (parseQuarterHourMinuteOfDay)
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
import qualified Web.Admin.FrontendSurface as AdminSurface
import Web.Admin.Mutations
import Web.Controller.Admin.Support
import Web.Controller.Admin.Xero
import Web.Controller.Admin.Xero.Responses
import Web.Controller.Prelude
import Web.Staff.Mutations (renewTrialStaffInvitationMutation)
import Web.SurfaceInvalidation (invalidateTouchedResources)
import Web.View.Admin.Exports
import Web.View.Admin.Index
import Web.View.Admin.Invites
import Web.View.Admin.RosterGroups
import Web.View.Admin.ShiftTypes
import Web.View.Admin.VenueSettings
import Web.View.Admin.Xero

respondToProfileLiveInvalidation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    [SurfaceResourceValue] ->
    IO ()
respondToProfileLiveInvalidation label resources = do
    profilingEnabled <- liftIO isRequestProfilingEnabled
    redirectPermissionDeniedUnless profilingEnabled "Live profiling endpoints are only available while profiling is enabled."
    _ <- invalidateTouchedResources ("profile.live." <> label) (liveMutationResult () resources)
    respondHtml "ok"

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

reportSurfaceRequestErrors ::
    (?context :: ControllerContext, ?request :: Request) =>
    [SurfaceRequestFieldError] ->
    IO ()
reportSurfaceRequestErrors errors =
    setErrorMessage ("Check the submitted fields: " <> surfaceRequestFieldErrorsMessage errors)

respondToShiftTypesSectionMutationWithXeroRefresh ::
    (?context :: ControllerContext, ?request :: Request) =>
    LiveMutationResult value ->
    IO ()
respondToShiftTypesSectionMutationWithXeroRefresh mutationResult =
    if isHtmxRequest
        then do
            setHeader ("HX-Reswap", "none")
            setActorLiveResourcesRefresh (adminShiftTypesLiveScope (unpackId currentVenueId)) mutationResult.liveMutationTouchedResources [AdminSurface.adminShiftTypesFragment]
            respondHtml mempty
        else redirectToAdminFor (paramOrNothing "rosterGroupId")

sendStaffPasskeySetupLink ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Id Staff ->
    PasskeySetupTokenPurpose ->
    Text ->
    IO ()
sendStaffPasskeySetupLink staffId purpose successMessage = do
    redirectPermissionDeniedUnless
        (currentUserIsSuperAdmin || hasRole VenueOwner)
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

parseAdminShiftTypesVisibility :: (?request :: Request) => Either [SurfaceRequestFieldError] Bool
parseAdminShiftTypesVisibility
    | not (surfaceActionParamsPresent @Surface.AdminShiftTypesSurface @Surface.ToggleInactiveShiftTypes) = Right False
    | otherwise = surfaceFieldValue @Surface.ShowInactiveShiftTypes <$> AdminAction.parseToggleInactiveShiftTypesActionParams

parseAdminRosterGroupsVisibility :: (?request :: Request) => Either [SurfaceRequestFieldError] Bool
parseAdminRosterGroupsVisibility
    | not (surfaceActionParamsPresent @Surface.AdminRosterGroupsSurface @Surface.ToggleInactiveRosterGroups) = Right False
    | otherwise = surfaceFieldValue @Surface.ShowInactiveRosterGroups <$> AdminAction.parseToggleInactiveRosterGroupsActionParams

instance Controller AdminController where
    beforeAction = bepisBeforeAction BepisAdminVenueController do
        annotateTelemetryAction
        ensureIsUser
        ensureCurrentVenueOrSupportRedirect
        ensureProfileCompleted
        ensureAdminRole

    action currentAction@AdminAction = runBepis currentAction BepisPageAction $
        profileActionSpan "admin.page.render" do
            _ <- profileActionSpan "admin.page.normalize_roster_groups" ensureAdminRosterGroupsNormalizedMutation
            rosterGroups <- profileActionSpan "admin.page.fetch_roster_groups" fetchCurrentVenueRosterGroups
            currentRosterGroup <- profileActionSpan "admin.page.resolve_current_group" (fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId"))
            shiftTypes <- profileActionSpan "admin.page.fetch_shift_types" fetchCurrentVenueShiftTypes
            venueConfig <- profileActionSpan "admin.page.fetch_venue_config" fetchVenueConfig
            awardLevels <- profileActionSpan "admin.page.fetch_award_levels" fetchActiveAwardLevels
            awardLevelBaseRates <- profileActionSpan "admin.page.fetch_award_rates" fetchCurrentAwardLevelBaseRates
            importedPayItems <- profileActionSpan "admin.page.fetch_imported_pay_items" fetchActiveImportedXeroPayItems
            showInactiveRosterGroups <- case parseAdminRosterGroupsVisibility of
                Left errors -> reportSurfaceRequestErrors errors >> pure False
                Right value -> pure value
            showInactiveShiftTypes <- case parseAdminShiftTypesVisibility of
                Left errors -> reportSurfaceRequestErrors errors >> pure False
                Right value -> pure value
            invitations <- profileActionSpan "admin.page.fetch_invitations" fetchCurrentVenueInvitations
            let maybeExportWeekOffset = paramOrNothing @Int "weekOffset"
            exportWeekSelection <- profileActionSpan "admin.page.export_week_selection" $
                maybe currentExportWeekSelection exportWeekSelectionForOffset maybeExportWeekOffset
            let exportSectionOpen = paramOrDefault False "showExports" || isJust maybeExportWeekOffset
            currentTime <- getCurrentTime
            let today = utctDay currentTime
            profileActionSpan "admin.page.render_response" (render IndexView { .. })

    action currentAction@XeroAction = runBepis currentAction BepisPageAction $
        profileActionSpan "admin.xero.page.render" do
            redirectPermissionDeniedUnless currentUserCanManageXeroIntegration "Only the venue owner or a super admin can manage Xero for this venue."
            xeroSectionData <- profileActionSpan "admin.xero.page.fetch_section_data" fetchCurrentVenueXeroAdminSectionData
            profileActionSpan "admin.xero.page.render_response" (render XeroView { .. })

    action currentAction@ProfileLiveInvalidateBillingAction = runBepis currentAction BepisPageAction $
        respondToProfileLiveInvalidation "billing" [billingResource (unpackId currentVenueId)]

    action currentAction@ProfileLiveInvalidateAdminInvitesAction = runBepis currentAction BepisPageAction $
        respondToProfileLiveInvalidation "admin_invites" [adminInvitesResource (unpackId currentVenueId)]

    action currentAction@ProfileLiveInvalidateXeroAction = runBepis currentAction BepisPageAction $
        respondToProfileLiveInvalidation "xero" [xeroConnectionResource (unpackId currentVenueId)]

    action currentAction@ProfileLiveInvalidateTimesheetWeekAction { weekOffset } = runBepis currentAction BepisPageAction $
        respondToProfileLiveInvalidation "timesheet_week" [timesheetWeekResource (unpackId currentVenueId) weekOffset]

    action currentAction@ProfileLiveInvalidateRosterWeekAction { rosterGroupId, weekOffset } = runBepis currentAction BepisPageAction $
        respondToProfileLiveInvalidation "roster_week" [rosterWeekResource (unpackId rosterGroupId) weekOffset]

    action currentAction@ProfileLiveInvalidateLeaveRequestsAction = runBepis currentAction BepisPageAction $
        respondToProfileLiveInvalidation "leave_requests" [pendingLeaveRequestsResource (unpackId currentVenueId)]

    action currentAction@SendStaffPasskeySetupEmailAction { staffId } = runBepis currentAction BepisMutationAction do
        sendStaffPasskeySetupLink staffId StaffNewDevicePasskeySetup "Passkey setup email sent."

    action currentAction@SendStaffPasskeyRecoveryEmailAction { staffId } = runBepis currentAction BepisMutationAction do
        sendStaffPasskeySetupLink staffId StaffPasskeyRecovery "Passkey recovery email sent."

    action currentAction@StartXeroConnectionAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        startXeroConnectionAction

    action currentAction@XeroOAuthCallbackAction = runBepis currentAction BepisIntegrationAction $
        xeroOAuthCallbackAction

    action currentAction@DisconnectXeroConnectionAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        disconnectXeroConnectionAction

    action currentAction@SyncXeroPayrollReferenceDataAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero syncXeroPayrollReferenceDataAction

    action currentAction@OpenXeroPayItemImportAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero openXeroPayItemImportAction

    action currentAction@ImportXeroPayItemsAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero importXeroPayItemsAction

    action currentAction@OpenXeroTimesheetPreparationAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero openXeroTimesheetPreparationAction

    action currentAction@RunXeroTimesheetPreparationAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero runXeroTimesheetPreparationAction

    action currentAction@RefreshXeroTimesheetPreparationAction { xeroTimesheetPreparationRunId } = runBepis currentAction BepisPageAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (refreshXeroTimesheetPreparationAction xeroTimesheetPreparationRunId)

    action currentAction@ShowXeroTimesheetPreparationStaffMappingsFragmentAction { xeroTimesheetPreparationRunId } = runBepis currentAction BepisFragmentAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (showXeroTimesheetPreparationStaffMappingsFragmentAction xeroTimesheetPreparationRunId)

    action currentAction@ApplyXeroTimesheetPreparationStaffDecisionAction { xeroTimesheetPreparationRunId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (applyXeroTimesheetPreparationStaffDecisionAction xeroTimesheetPreparationRunId)

    action currentAction@ContinueXeroTimesheetPreparationStaffStepAction { xeroTimesheetPreparationRunId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (continueXeroTimesheetPreparationStaffStepAction xeroTimesheetPreparationRunId)

    action currentAction@SelectXeroTimesheetPreparationPeriodAction { xeroTimesheetPreparationRunId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (selectXeroTimesheetPreparationPeriodAction xeroTimesheetPreparationRunId)

    action currentAction@ApproveXeroTimesheetPreparationPayItemsAction { xeroTimesheetPreparationRunId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (approveXeroTimesheetPreparationPayItemsAction xeroTimesheetPreparationRunId)

    action currentAction@ShowXeroTimesheetPreparationSummaryAction { xeroTimesheetPreparationRunId } = runBepis currentAction BepisPageAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (showXeroTimesheetPreparationSummaryAction xeroTimesheetPreparationRunId)

    action currentAction@ConfirmXeroTimesheetPreparationSubmissionAction { xeroTimesheetPreparationRunId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (confirmXeroTimesheetPreparationSubmissionAction xeroTimesheetPreparationRunId)

    action currentAction@RunXeroTimesheetPreparationSubmissionAction { xeroTimesheetPreparationRunId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (runXeroTimesheetPreparationSubmissionAction xeroTimesheetPreparationRunId)

    action currentAction@SubmitXeroTimesheetPreparationAction { xeroTimesheetPreparationRunId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        requireCurrentVenueOwnerForXero (submitXeroTimesheetPreparationAction xeroTimesheetPreparationRunId)

    action currentAction@UpdateVenueConfigAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        venueConfig <- fetchVenueConfig
        case AdminAction.parseUpdateVenueConfigActionParams of
            Left errors -> do
                reportSurfaceRequestErrors errors
                respondToVenueSettingsMutation
            Right fields ->
                case surfaceFieldValue @Surface.ConfigFieldField fields of
                    "rosterEndTimesEnabled" -> do
                        let rosterEndTimesEnabled = fromMaybe False (surfaceFieldValue @Surface.RosterEndTimesEnabled fields)
                        _ <- setRosterEndTimesEnabledMutation venueConfig rosterEndTimesEnabled
                        setSuccessMessage $
                            if rosterEndTimesEnabled
                                then "Roster end times shown in the roster."
                                else "Roster end times hidden from the roster."
                        respondToVenueSettingsMutation
                    "autoTimesheetCreationEnabled" -> do
                        setErrorMessage "Automatic timesheet creation has been replaced by rostered timesheet suggestions."
                        respondToVenueSettingsMutation
                    "unavailableStaffWarningThreshold" -> do
                        let threshold = surfaceFieldValue @Surface.UnavailableStaffWarningThreshold fields
                        if maybe True (\value -> value >= 1 && value <= 100) threshold
                            then do
                                _ <- setUnavailableStaffWarningThresholdMutation venueConfig threshold
                                setSuccessMessage $
                                    maybe
                                        "Unavailable-staff warnings disabled."
                                        (\value -> "Managers will be warned at " <> tshow value <> " unavailable staff.")
                                        threshold
                                respondToVenueSettingsMutation
                            else do
                                setErrorMessage "Enter a threshold from 1 to 100, or leave it blank to disable warnings."
                                respondToVenueSettingsMutation
                    "timePickerWindow" -> do
                        let maybeStartMinute = parseQuarterHourMinuteOfDay =<< surfaceFieldValue @Surface.TimePickerStart fields
                        let maybeFinalSelectableMinute = parseQuarterHourMinuteOfDay =<< surfaceFieldValue @Surface.TimePickerEnd fields
                        case (maybeStartMinute, maybeFinalSelectableMinute) of
                            (Just startMinute, Just finalSelectableMinute) | startMinute /= finalSelectableMinute -> do
                                _ <- setRosterTimePickerWindowMutation venueConfig startMinute finalSelectableMinute
                                setSuccessMessage "Valid shift window updated."
                                respondToVenueSettingsMutation
                            _ -> do
                                setErrorMessage "Choose different start and end times on 15-minute increments."
                                respondToVenueSettingsMutation
                    _ -> do
                        requestedRosterWeekStartsOn <- validateRosterWeekStartsOn (surfaceFieldValue @Surface.RosterWeekStartsOn fields)
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

    action currentAction@ShowAdminVenueSettingsFragmentAction = runBepis currentAction BepisFragmentAction $
        profileActionSpan "admin.venue_settings_fragment.respond" do
            venueConfig <- profileActionSpan "admin.venue_settings_fragment.fetch_venue_config" fetchVenueConfig
            profileActionSpan "admin.venue_settings_fragment.render_response" (respondFragmentHtml (renderVenueSettingsSectionFragment venueConfig))

    action currentAction@ShowadminInvitesLiveFragmentAction = runBepis currentAction BepisFragmentAction $
        profileActionSpan "admin.invites_fragment.respond" do
            currentRosterGroup <- profileActionSpan "admin.invites_fragment.resolve_current_group" (fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId"))
            invitations <- profileActionSpan "admin.invites_fragment.fetch_invitations" fetchCurrentVenueInvitations
            currentTime <- getCurrentTime
            profileActionSpan "admin.invites_fragment.render_response" (respondFragmentHtml (renderInvitesSectionFragment currentTime invitations currentRosterGroup.id))

    action currentAction@ShowadminShiftTypesLiveFragmentAction = runBepis currentAction BepisFragmentAction $
        profileActionSpan "admin.shift_types_fragment.respond" do
            shiftTypes <- profileActionSpan "admin.shift_types_fragment.fetch_shift_types" fetchCurrentVenueShiftTypes
            awardLevels <- profileActionSpan "admin.shift_types_fragment.fetch_award_levels" fetchActiveAwardLevels
            awardLevelBaseRates <- profileActionSpan "admin.shift_types_fragment.fetch_award_rates" fetchCurrentAwardLevelBaseRates
            importedPayItems <- profileActionSpan "admin.shift_types_fragment.fetch_imported_pay_items" fetchActiveImportedXeroPayItems
            showInactiveShiftTypes <- case parseAdminShiftTypesVisibility of
                Left errors -> reportSurfaceRequestErrors errors >> pure False
                Right value -> pure value
            profileActionSpan "admin.shift_types_fragment.render_response" (respondFragmentHtml (renderShiftTypesSectionFragment shiftTypes showInactiveShiftTypes awardLevels awardLevelBaseRates importedPayItems))

    action currentAction@ShowadminRosterGroupsLiveFragmentAction = runBepis currentAction BepisFragmentAction $
        profileActionSpan "admin.roster_groups_fragment.respond" do
            _ <- profileActionSpan "admin.roster_groups_fragment.normalize_roster_groups" ensureAdminRosterGroupsNormalizedMutation
            rosterGroups <- profileActionSpan "admin.roster_groups_fragment.fetch_roster_groups" fetchCurrentVenueRosterGroups
            showInactiveRosterGroups <- case parseAdminRosterGroupsVisibility of
                Left errors -> reportSurfaceRequestErrors errors >> pure False
                Right value -> pure value
            profileActionSpan "admin.roster_groups_fragment.render_response" (respondFragmentHtml (renderRosterGroupsSectionFragment rosterGroups showInactiveRosterGroups))

    action currentAction@ShowadminExportsLiveFragmentAction = runBepis currentAction BepisFragmentAction $
        profileActionSpan "admin.exports_fragment.respond" do
            exportWeekSelection <- profileActionSpan "admin.exports_fragment.week_selection" $
                maybe currentExportWeekSelection exportWeekSelectionForOffset (paramOrNothing @Int "weekOffset")
            profileActionSpan "admin.exports_fragment.render_response" (respondFragmentHtml (renderExportsSectionFragment exportWeekSelection))

    action currentAction@ShowadminXeroShellLiveFragmentAction = runBepis currentAction BepisFragmentAction $
        profileActionSpan "admin.xero_fragment.respond" do
            requireCurrentVenueOwnerForXero respondWithXeroSectionFragment

    action currentAction@CreateVenueInvitationAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        case AdminAction.parseCreateVenueInvitationActionParams of
            Left errors -> do
                reportSurfaceRequestErrors errors
                respondToInvitesSectionMutation "" currentRosterGroup.id
            Right fields -> do
                maybeEmail <- validateRequiredEmail (surfaceFieldValue @Surface.Email fields) "Invite email is required."
                case maybeEmail of
                    Just email ->
                        createVenueInvitationMutation email >>= \case
                            Right _ -> respondToInvitesSectionMutation ("Invitation queued for " <> email) currentRosterGroup.id
                            Left message -> respondToInvitesSectionError message currentRosterGroup.id
                    Nothing -> respondToInvitesSectionMutation "" currentRosterGroup.id

    action currentAction@RenewVenueInvitationAction { venueInvitationId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        invitation <- fetch venueInvitationId
        ensureRecordInCurrentVenue invitation.venueId
        case AdminAction.parseRenewVenueInvitationActionParams of
            Left errors -> do
                reportSurfaceRequestErrors errors
                respondToInvitesSectionMutation "" currentRosterGroup.id
            Right fields -> do
                let rawSubmittedEmail = paramOrDefault @Text "" "email"
                let submittedEmail = fromMaybe invitation.email (surfaceFieldValue @Surface.Email fields)
                if hasParam "email" && Text.null (Text.strip rawSubmittedEmail)
                    then do
                        setErrorMessage "Invite email cannot be blank."
                        respondToInvitesSectionMutation "" currentRosterGroup.id
                    else validateRequiredEmail submittedEmail "Invite email is required." >>= \case
                        Nothing -> respondToInvitesSectionMutation "" currentRosterGroup.id
                        Just correctedEmail -> do
                            result <- case invitation.staffId of
                                Nothing -> renewVenueInvitationMutation invitation correctedEmail
                                Just staffId -> do
                                    staff <- fetch staffId
                                    ensureRecordInCurrentVenue staff.venueId
                                    renewTrialStaffInvitationMutation staff invitation correctedEmail
                            case result of
                                Left message -> respondToInvitesSectionError message currentRosterGroup.id
                                Right _ -> respondToInvitesSectionMutation ("Invitation renewed for " <> correctedEmail) currentRosterGroup.id

    action currentAction@RevokeVenueInvitationAction { venueInvitationId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        currentRosterGroup <- fetchCurrentVenueRosterGroupOrDefault (paramOrNothing "rosterGroupId")
        invitation <- fetch venueInvitationId
        ensureRecordInCurrentVenue invitation.venueId
        if invitation.status /= InvitationStatusEnumPending
            then respondToInvitesSectionMutation "Only pending invitations can be revoked." currentRosterGroup.id
            else do
                _ <- revokeVenueInvitationMutation invitation
                respondToInvitesSectionMutation "Invitation revoked." currentRosterGroup.id

    action currentAction@CreateRosterGroupAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        venue <- fetch currentVenueId
        case AdminAction.parseCreateRosterGroupActionParams of
            Left errors -> do
                reportSurfaceRequestErrors errors
                respondToRosterGroupsSectionMutation Nothing
            Right fields -> do
                maybeName <- validateRequiredName (surfaceFieldValue @Surface.Name fields) "Roster group name is required."
                case maybeName of
                    Nothing -> respondToRosterGroupsSectionMutation Nothing
                    Just name -> do
                        mutationResult <- createRosterGroupMutation venue name (surfaceFieldValue @Surface.IsActive fields)
                        let rosterGroup = mutationResult.liveMutationValue
                        setSuccessMessage "Roster group added"
                        respondToRosterGroupsResourceMutation mutationResult (Just rosterGroup.id)

    action currentAction@UpdateRosterGroupAction { rosterGroupId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        venue <- fetch currentVenueId
        rosterGroup <- fetch rosterGroupId
        ensureRecordInCurrentVenue rosterGroup.venueId
        case AdminAction.parseUpdateRosterGroupActionParams of
            Left errors -> do
                reportSurfaceRequestErrors errors
                respondToRosterGroupsSectionMutation (Just rosterGroup.id)
            Right fields -> do
                maybeName <- validateRequiredName (surfaceFieldValue @Surface.Name fields) "Roster group name is required."
                case maybeName of
                    Nothing -> respondToRosterGroupsSectionMutation (Just rosterGroup.id)
                    Just name -> do
                        let isActive = surfaceFieldValue @Surface.IsActive fields
                        rosterGroups <- fetchCurrentVenueRosterGroups
                        let otherActiveGroups = filter (\group -> group.id /= rosterGroup.id && group.isActive) rosterGroups
                        if not isActive && null otherActiveGroups
                            then do
                                setErrorMessage "Each venue needs at least one active roster group."
                                respondToRosterGroupsSectionMutation (Just rosterGroup.id)
                            else do
                                mutationResult <- updateRosterGroupMutation venue rosterGroup name isActive
                                let updatedRosterGroup = mutationResult.liveMutationValue
                                setSuccessMessage "Roster group updated"
                                respondToRosterGroupsResourceMutation mutationResult (Just updatedRosterGroup.id)

    action currentAction@MoveRosterGroupUpAction { rosterGroupId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        rosterGroup <- fetch rosterGroupId
        ensureRecordInCurrentVenue rosterGroup.venueId
        case AdminAction.parseMoveRosterGroupUpActionParams of
            Left errors -> reportSurfaceRequestErrors errors >> respondToRosterGroupsSectionMutation (Just rosterGroup.id)
            Right _ -> do
                mutationResult <- moveRosterGroupMutation rosterGroup (-1)
                setSuccessMessage "Roster group order updated"
                respondToRosterGroupsResourceMutation mutationResult (Just rosterGroup.id)

    action currentAction@MoveRosterGroupDownAction { rosterGroupId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        rosterGroup <- fetch rosterGroupId
        ensureRecordInCurrentVenue rosterGroup.venueId
        case AdminAction.parseMoveRosterGroupDownActionParams of
            Left errors -> reportSurfaceRequestErrors errors >> respondToRosterGroupsSectionMutation (Just rosterGroup.id)
            Right _ -> do
                mutationResult <- moveRosterGroupMutation rosterGroup 1
                setSuccessMessage "Roster group order updated"
                respondToRosterGroupsResourceMutation mutationResult (Just rosterGroup.id)

    action currentAction@CreateShiftTypeAction = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        case AdminAction.parseCreateShiftTypeActionParams of
            Left errors -> reportSurfaceRequestErrors errors >> respondToShiftTypesSectionMutation False
            Right fields -> do
                maybeName <- validateRequiredName (surfaceFieldValue @Surface.Name fields) "Shift type name is required."
                case maybeName of
                    Nothing -> respondToShiftTypesSectionMutation (surfaceFieldValue @Surface.ShowInactiveShiftTypes fields)
                    Just name -> do
                        maybePayRateSelection <- parseSubmittedPayRateSelectionValue (surfaceFieldValue @Surface.PayRateSelection fields)
                        case maybePayRateSelection of
                            Just payRateSelection -> do
                                mutationResult <- createShiftTypeMutation name (surfaceFieldValue @Surface.IsActive fields) payRateSelection.submittedAwardLevelId payRateSelection.submittedImportedXeroPayItemId payRateSelection.submittedRosterOnly (Just (surfaceFieldValue @Surface.ColourKey fields))
                                setSuccessMessage "Shift type added"
                                respondToShiftTypesSectionMutationWithXeroRefresh mutationResult
                            Nothing -> respondToShiftTypesSectionMutation (surfaceFieldValue @Surface.ShowInactiveShiftTypes fields)

    action currentAction@UpdateShiftTypeAction { shiftTypeId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        shiftType <- fetch shiftTypeId
        ensureRecordInCurrentVenue shiftType.venueId
        case AdminAction.parseUpdateShiftTypeActionParams of
            Left errors -> reportSurfaceRequestErrors errors >> respondToShiftTypesSectionMutation False
            Right fields -> do
                maybeName <- validateRequiredName (surfaceFieldValue @Surface.Name fields) "Shift type name is required."
                case maybeName of
                    Nothing -> respondToShiftTypesSectionMutation (surfaceFieldValue @Surface.ShowInactiveShiftTypes fields)
                    Just name -> do
                        maybePayRateSelection <- parseSubmittedPayRateSelectionValue (surfaceFieldValue @Surface.PayRateSelection fields)
                        case maybePayRateSelection of
                            Just payRateSelection -> do
                                mutationResult <- updateShiftTypeMutation shiftType name (surfaceFieldValue @Surface.IsActive fields) payRateSelection.submittedAwardLevelId payRateSelection.submittedImportedXeroPayItemId payRateSelection.submittedRosterOnly (Just (surfaceFieldValue @Surface.ColourKey fields))
                                unless isHtmxRequest do
                                    setSuccessMessage "Shift type updated"
                                respondToShiftTypesSectionMutationWithXeroRefresh mutationResult
                            Nothing -> respondToShiftTypesSectionMutation (surfaceFieldValue @Surface.ShowInactiveShiftTypes fields)

    action currentAction@MoveShiftTypeUpAction { shiftTypeId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        shiftType <- fetch shiftTypeId
        ensureRecordInCurrentVenue shiftType.venueId
        case AdminAction.parseMoveShiftTypeUpActionParams of
            Left errors -> reportSurfaceRequestErrors errors >> respondToShiftTypesSectionMutation False
            Right _ -> do
                mutationResult <- moveShiftTypeMutation shiftType (-1)
                setSuccessMessage "Shift type order updated"
                respondToShiftTypesSectionMutationWithXeroRefresh mutationResult

    action currentAction@MoveShiftTypeDownAction { shiftTypeId } = runBepis currentAction BepisMutationAction do
        ensureVenueWritable
        shiftType <- fetch shiftTypeId
        ensureRecordInCurrentVenue shiftType.venueId
        case AdminAction.parseMoveShiftTypeDownActionParams of
            Left errors -> reportSurfaceRequestErrors errors >> respondToShiftTypesSectionMutation False
            Right _ -> do
                mutationResult <- moveShiftTypeMutation shiftType 1
                setSuccessMessage "Shift type order updated"
                respondToShiftTypesSectionMutationWithXeroRefresh mutationResult
