module Web.Types where

import Generated.Types
import IHP.LoginSupport.Types
import IHP.ModelSupport
import IHP.Prelude

data WebApplication = WebApplication deriving (Eq, Show)

data StaticController
    = WelcomeAction
    | InstallAppAction
    | PublicBillingSupportAction
    | LegalTermsAction
    | LegalPrivacyAction
    | LegalRefundsDisputesAction
    | LegalCancellationAction
    deriving (Eq, Show, Data)

data SessionsController
    = NewSessionAction
    | CreateSessionAction
    | DeleteSessionAction
    | VerifyEmailAction
    | ResendVerificationAction
    deriving (Eq, Show, Data)

data AuthController
    = BeginPasskeyRegistrationAction
    | FinishPasskeyRegistrationAction
    | BeginPasskeyAuthenticationAction
    | FinishPasskeyAuthenticationAction
    | BeginPasskeyStepUpAuthenticationAction
    | FinishPasskeyStepUpAuthenticationAction
    | NewPasskeySetupAction
    | BeginPasskeySetupRegistrationAction
    | FinishPasskeySetupRegistrationAction
    deriving (Eq, Show, Data)

data PasskeysController
    = PasskeyStepUpAction
    | PasskeySetupAction
    | DismissMandatoryPasskeySetupAction
    | ShowPasskeySetupDialogAction
    | ShowPasskeyRecoveryCodeDialogAction
    | UsePasskeyRecoveryCodeAction
    | SendNewDevicePasskeySetupEmailAction
    | DeletePasskeyAction { passkeyId :: !(Id Passkey) }
    deriving (Eq, Show, Data)

data UsersController
    = NewUserAction
    | CreateUserAction
    | NewVenueOnboardingUserAction
    | CreateVenueOnboardingUserAction
    deriving (Eq, Show, Data)

data ProfilesController
    = EditProfileAction
    | ShowprofileContentLiveFragmentAction
    | UpdateProfileAction
    deriving (Eq, Show, Data)

data TimesheetsController
    = TimesheetsAction
    | ShowTimesheetWindowAction { anchorDate :: !Day }
    | ShowTimesheetWeekAction { weekOffset :: !Int }
    | ShowtimesheetToolbarLiveFragmentAction { anchorDate :: !Day }
    | ShowtimesheetDayColumnsLiveFragmentAction { anchorDate :: !Day }
    | ShowtimesheetSidePanelContentLiveFragmentAction { anchorDate :: !Day }
    | ShowTimesheetDaySectionFragmentAction { anchorDate :: !Day, operationalDate :: !Day }
    | ToggleTimesheetHideApprovedAction
    | ToggleTimesheetShowSuggestionsAction
    | NewTimesheetEntryAction
    | CreateTimesheetEntryAction
    | NewTimesheetEntryFromSuggestionAction { rosterSlotId :: !(Id RosterSlot) }
    | CreateTimesheetEntryFromSuggestionAction { rosterSlotId :: !(Id RosterSlot) }
    | EditTimesheetEntryAction { timesheetEntryId :: !(Id TimesheetEntry) }
    | UpdateTimesheetEntryAction { timesheetEntryId :: !(Id TimesheetEntry) }
    | DeleteTimesheetEntryAction { timesheetEntryId :: !(Id TimesheetEntry) }
    | ApproveTimesheetEntryAction { timesheetEntryId :: !(Id TimesheetEntry) }
    | UnapproveTimesheetEntryAction { timesheetEntryId :: !(Id TimesheetEntry) }
    deriving (Eq, Show, Data)

data LeaveRequestsController
    = LeaveRequestsAction
    | ShowleaveRequestsContentLiveFragmentAction
    | ShowSelfServiceLeaveFragmentAction
    | ShowVisibleUnavailabilityBlackoutsFragmentAction
    | NewLeaveRequestAction
    | CreateLeaveRequestAction
    | ApproveLeaveRequestAction { leaveRequestId :: !(Id LeaveRequest) }
    | DenyLeaveRequestAction { leaveRequestId :: !(Id LeaveRequest) }
    | CreateUnavailabilityBlackoutAction
    | UpdateUnavailabilityBlackoutAction { unavailabilityBlackoutId :: !(Id UnavailabilityBlackout) }
    | DeleteUnavailabilityBlackoutAction { unavailabilityBlackoutId :: !(Id UnavailabilityBlackout) }
    deriving (Eq, Show, Data)

data ExportsController
    = ExportJobsAction
    | CreateExportJobAction
    | DownloadExportJobAction { exportJobId :: !(Id ExportJob) }
    deriving (Eq, Show, Data)

data StaffDocumentsController
    = ScanStaffDocumentAction
    | CreateStaffDocumentAction
    | DownloadStaffDocumentAction { staffDocumentId :: !(Id StaffDocument) }
    | ReviewStaffDocumentAction { staffDocumentId :: !(Id StaffDocument) }
    deriving (Eq, Show, Data)

data BillingController
    = BillingAction
    | ShowbillingStatusLiveFragmentAction
    | CreateBillingCheckoutSessionAction
    | CreateBillingPortalSessionAction
    | BillingSuccessAction
    | BillingCancelAction
    | ReconcileVenueBillingAction
    | UpdateVenueBillingControlAction
    deriving (Eq, Show, Data)

data StripeWebhooksController
    = StripeWebhookAction
    deriving (Eq, Show, Data)

data E2ETestController
    = MarkE2EPasskeyVerifiedAction
    deriving (Eq, Show, Data)

data AdminController
    = AdminAction
    | XeroAction
    | StartXeroConnectionAction
    | XeroOAuthCallbackAction
    | DisconnectXeroConnectionAction
    | SyncXeroPayrollReferenceDataAction
    | OpenXeroPayItemImportAction
    | ImportXeroPayItemsAction
    | OpenXeroTimesheetPreparationAction
    | RunXeroTimesheetPreparationAction
    | RefreshXeroTimesheetPreparationAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | ShowXeroTimesheetPreparationStaffMappingsFragmentAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | ApplyXeroTimesheetPreparationStaffDecisionAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | ContinueXeroTimesheetPreparationStaffStepAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | SelectXeroTimesheetPreparationPeriodAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | ApproveXeroTimesheetPreparationPayItemsAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | ShowXeroTimesheetPreparationSummaryAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | ConfirmXeroTimesheetPreparationSubmissionAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | RunXeroTimesheetPreparationSubmissionAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | SubmitXeroTimesheetPreparationAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | UpdateRosterEndTimesEnabledAction
    | UpdateMinutePrecisionShiftTimesEnabledAction
    | UpdateUnavailableStaffWarningThresholdAction
    | UpdateRosterTimePickerWindowAction
    | UpdateRosterWeekStartsOnAction
    | ShowAdminVenueSettingsFragmentAction
    | ShowadminInvitesLiveFragmentAction
    | ShowadminShiftTypesLiveFragmentAction
    | ShowadminRosterGroupsLiveFragmentAction
    | ShowadminExportsLiveFragmentAction
    | ShowadminXeroShellLiveFragmentAction
    | ShowadminXeroReferenceSyncLiveFragmentAction
    | ShowadminXeroTimesheetPreparationWaitLiveFragmentAction
    | CreateVenueInvitationAction
    | RevokeVenueInvitationAction { venueInvitationId :: !(Id VenueInvitation) }
    | RenewVenueInvitationAction { venueInvitationId :: !(Id VenueInvitation) }
    | SendStaffPasskeySetupEmailAction { staffId :: !(Id Staff) }
    | SendStaffPasskeyRecoveryEmailAction { staffId :: !(Id Staff) }
    | CreateRosterGroupAction
    | UpdateRosterGroupAction { rosterGroupId :: !(Id RosterGroup) }
    | MoveRosterGroupUpAction { rosterGroupId :: !(Id RosterGroup) }
    | MoveRosterGroupDownAction { rosterGroupId :: !(Id RosterGroup) }
    | CreateShiftTypeAction
    | UpdateShiftTypeAction { shiftTypeId :: !(Id ShiftType) }
    | MoveShiftTypeUpAction { shiftTypeId :: !(Id ShiftType) }
    | MoveShiftTypeDownAction { shiftTypeId :: !(Id ShiftType) }
    | ProfileLiveInvalidateBillingAction
    | ProfileLiveInvalidateAdminInvitesAction
    | ProfileLiveInvalidateXeroAction
    | ProfileLiveInvalidateTimesheetWindowAction { anchorDate :: !Day }
    | ProfileLiveInvalidateRosterWindowAction { rosterGroupId :: !(Id RosterGroup), anchorDate :: !Day }
    | ProfileLiveInvalidateLeaveRequestsAction
    deriving (Eq, Show, Data)

data FeedbackController
    = NewFeedbackAction
    | CreateFeedbackAction
    deriving (Eq, Show, Data)

data HelpController
    = ShowPageHelpAction { topic :: !Text }
    deriving (Eq, Show, Data)

data SupportController
    = SupportAction
    | ShowFwcMapdAwardRatesSectionAction
    | ShowPublicHolidaysSectionAction
    | RunXeroTimesheetDiagnosticAction
    | CreateSupportVenueOnboardingInvitationAction
    | RenewSupportVenueOnboardingInvitationAction { onboardingInvitationId :: !(Id VenueOnboardingInvitation) }
    | CreateFwcMapdRefreshJobAction
    | CreatePublicHolidayRefreshJobAction
    | MarkFeedbackReadAction { feedbackItemId :: !(Id UserFeedbackItem) }
    | MarkAllFeedbackReadAction
    | UpdateFeedbackStatusAction { feedbackItemId :: !(Id UserFeedbackItem) }
    | UpdateFeedbackPriorityAction { feedbackItemId :: !(Id UserFeedbackItem) }
    | UpdateFeedbackSupportNoteAction { feedbackItemId :: !(Id UserFeedbackItem) }
    | StartSupportImpersonationAction
    | ExitSupportImpersonationAction
    | SwitchSupportImpersonationAction
    | SwitchSupportVenueAction
    deriving (Eq, Show, Data)

data StaffController
    = NewStaffAction
    | CreateStaffAction
    | EditStaffAction { staffId :: !(Id Staff) }
    | ShowStaffContentLiveFragmentAction { staffId :: !(Id Staff) }
    | UpdateStaffAction { staffId :: !(Id Staff) }
    | NewRemoveStaffAction { staffId :: !(Id Staff) }
    | RemoveStaffAction { staffId :: !(Id Staff) }
    | NewTrialStaffInvitationAction { staffId :: !(Id Staff) }
    | CreateTrialStaffInvitationAction { staffId :: !(Id Staff) }
    | RenewTrialStaffInvitationAction { venueInvitationId :: !(Id VenueInvitation) }
    deriving (Eq, Show, Data)

newtype LiveUpdatesWSApp
    = LiveUpdatesWSApp
        { subscriptionIds :: [(UUID, Text)]
        }
    deriving (Eq, Show, Data)

data RosterTemplatesController
    = NewRosterTemplateAction { rosterGroupId :: !(Id RosterGroup) }
    | CreateRosterTemplateDraftAction { rosterGroupId :: !(Id RosterGroup) }
    | ShowRosterTemplateReferenceAction { rosterGroupId :: !(Id RosterGroup) }
    | ConfirmRosterTemplateReferenceAction { rosterGroupId :: !(Id RosterGroup) }
    | CreateRosterTemplateFromReferenceAction { rosterGroupId :: !(Id RosterGroup) }
    | DiscardAndRestartRosterTemplateDraftAction { rosterGroupId :: !(Id RosterGroup), rosterTemplateDesignId :: !(Id RosterTemplateDesign) }
    | ShowRosterTemplateDesignerAction { rosterTemplateDesignId :: !(Id RosterTemplateDesign) }
    | UpdateRosterTemplateDayAction { rosterTemplateDesignId :: !(Id RosterTemplateDesign), dayIndex :: !Int }
    | AddRosterTemplateColumnAction { rosterTemplateDesignId :: !(Id RosterTemplateDesign) }
    | UpdateRosterTemplateColumnAction { rosterTemplateDesignId :: !(Id RosterTemplateDesign), columnSortOrder :: !Int }
    | DeleteRosterTemplateColumnAction { rosterTemplateDesignId :: !(Id RosterTemplateDesign), columnSortOrder :: !Int }
    | UpsertRosterTemplateShiftAction { rosterTemplateDesignId :: !(Id RosterTemplateDesign) }
    | DeleteRosterTemplateShiftAction { rosterTemplateDesignId :: !(Id RosterTemplateDesign), dayIndex :: !Int, columnSortOrder :: !Int, rowIndex :: !Int }
    | SaveRosterTemplateAction { rosterTemplateDesignId :: !(Id RosterTemplateDesign) }
    | ReloadRosterTemplateDraftAction { rosterTemplateDesignId :: !(Id RosterTemplateDesign) }
    | SaveRosterTemplateDraftAsNewAction { rosterTemplateDesignId :: !(Id RosterTemplateDesign) }
    | EditRosterTemplateAction { rosterTemplateId :: !(Id RosterTemplate) }
    | DeleteRosterTemplateAction { rosterTemplateId :: !(Id RosterTemplate) }
    | PreviewRosterTemplateDropAction { rosterGroupId :: !(Id RosterGroup) }
    | ShowRosterTemplateApplicationConfirmationAction { rosterTemplateId :: !(Id RosterTemplate), rosterGroupId :: !(Id RosterGroup) }
    | ApplyRosterTemplateAction { rosterTemplateId :: !(Id RosterTemplate), rosterGroupId :: !(Id RosterGroup) }
    | ConfirmDeleteRosterTemplateAction { rosterTemplateId :: !(Id RosterTemplate), rosterGroupId :: !(Id RosterGroup) }
    | ShowRosterTemplateLibraryFragmentAction { rosterGroupId :: !(Id RosterGroup) }
    deriving (Eq, Show, Data)

data RosterWeeksController
    = RosterWeeksAction
    | ShowRosterWindowAction { anchorDate :: !Day }
    | ShowRosterWeekAction { weekOffset :: !Int }
    | ShowRosterDayTimelineAction { weekOffset :: !Int, rosterDayId :: !(Id RosterDay) }
    | ShowRosterDayTimelineContentFragmentAction { anchorDate :: !Day, rosterDayId :: !(Id RosterDay) }
    | ShowRosterWeekOverviewFragmentAction { anchorDate :: !Day }
    | ShowRosterWeekContentFragmentAction { anchorDate :: !Day }
    | ShowRosterWeekGridToolbarFragmentAction { anchorDate :: !Day }
    | ShowRosterWeekGridFrameFragmentAction { anchorDate :: !Day }
    | ShowRosterWeekDayColumnsFragmentAction { anchorDate :: !Day }
    | ShowRosterWeekDayRailFragmentAction { anchorDate :: !Day }
    | ShowRosterWeekWageRailFragmentAction { anchorDate :: !Day }
    | ShowRosterWeekSlotsGridFragmentAction { anchorDate :: !Day }
    | ShowRosterWeekStaffPanelFragmentAction { anchorDate :: !Day }
    | ShowRosterWeekDaySectionFragmentAction { anchorDate :: !Day, rosterDayId :: !(Id RosterDay) }
    | ShowRosterWeekRowFragmentAction { anchorDate :: !Day, rosterDayId :: !(Id RosterDay), rowIndex :: !Int }
    | UpdateRosterAssignmentFiltersAction
    | CreateRosterWeekAction
    | CopyRosterWeekAction
    | ToggleRosterWeekLiveStatusAction { rosterWeekId :: !(Id RosterWeek) }
    | ShowRosterNotificationConfirmationAction { rosterWeekId :: !(Id RosterWeek) }
    | CreateRosterNotificationRunAction { rosterWeekId :: !(Id RosterWeek) }
    | CreateRosterWeekSlotDefinitionAction
    | DeleteRosterWeekSlotDefinitionAction { rosterWeekSlotDefinitionId :: !(Id RosterLane) }
    | SortRosterWeekAction
    | ToggleRosterDayClosedAction { rosterDayId :: !(Id RosterDay) }
    | AddRosterRowAction { rosterDayId :: !(Id RosterDay) }
    | RemoveRosterRowAction { rosterDayId :: !(Id RosterDay) }
    | UpdateRosterLayoutPreferenceAction
    | MoveRosterShiftToSlotAction
    | MoveRosterTimelineShiftAction
    | DuplicateRosterShiftToDayAction
    | DropRosterStaffAction
    | UpdateRosterWarningPreferenceAction
    | UpdateRosterWageEstimatePreferenceAction
    | UpdateRosterOwnLiveShiftHighlightPreferenceAction
    | NewRosterSlotDialogAction { rosterDayId :: !(Id RosterDay), rosterWeekSlotDefinitionId :: !(Id RosterLane), rowIndex :: !Int }
    | EditRosterSlotDialogAction { rosterSlotId :: !(Id RosterSlot) }
    | CreateRosterSlotAction { rosterDayId :: !(Id RosterDay), rosterWeekSlotDefinitionId :: !(Id RosterLane), rowIndex :: !Int }
    | UpdateRosterSlotAction { rosterSlotId :: !(Id RosterSlot) }
    | DeleteRosterSlotAction { rosterSlotId :: !(Id RosterSlot) }
    deriving (Eq, Show, Data)

-- Auth support: where to redirect unauthenticated users
instance HasNewSessionUrl User where
    newSessionUrl _ = "/NewSession"

-- Tell IHP which record type represents the logged-in user
type instance CurrentUserRecord = User
