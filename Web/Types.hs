module Web.Types where

import Generated.Types
import IHP.LoginSupport.Types
import IHP.ModelSupport
import IHP.Prelude

data WebApplication = WebApplication deriving (Eq, Show)

data PasskeySetupPromptMode
    = FirstPasskeyPrompt
    | AdditionalDevicePasskeyPrompt
    deriving (Eq, Show)

data StaticController
    = WelcomeAction
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
    | ShowTimesheetWeekAction { weekOffset :: !Int }
    | ShowtimesheetToolbarLiveFragmentAction { weekOffset :: !Int }
    | ShowtimesheetDayColumnsLiveFragmentAction { weekOffset :: !Int }
    | ShowTimesheetDaySectionFragmentAction { weekOffset :: !Int, dayOffset :: !Int }
    | NewTimesheetEntryAction
    | CreateTimesheetEntryAction
    | EditTimesheetEntryAction { timesheetEntryId :: !(Id TimesheetEntry) }
    | UpdateTimesheetEntryAction { timesheetEntryId :: !(Id TimesheetEntry) }
    | DeleteTimesheetEntryAction { timesheetEntryId :: !(Id TimesheetEntry) }
    | ApproveTimesheetEntryAction { timesheetEntryId :: !(Id TimesheetEntry) }
    | UnapproveTimesheetEntryAction { timesheetEntryId :: !(Id TimesheetEntry) }
    deriving (Eq, Show, Data)

data LeaveRequestsController
    = LeaveRequestsAction
    | ShowleaveRequestsContentLiveFragmentAction
    | NewLeaveRequestAction
    | CreateLeaveRequestAction
    | ApproveLeaveRequestAction { leaveRequestId :: !(Id LeaveRequest) }
    | DenyLeaveRequestAction { leaveRequestId :: !(Id LeaveRequest) }
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
    | UpdateVenueConfigAction
    | ShowAdminVenueSettingsFragmentAction
    | ShowadminInvitesLiveFragmentAction
    | ShowadminShiftTypesLiveFragmentAction
    | ShowadminRosterGroupsLiveFragmentAction
    | ShowadminExportsLiveFragmentAction
    | ShowadminXeroShellLiveFragmentAction
    | CreateVenueInvitationAction
    | RevokeVenueInvitationAction { venueInvitationId :: !(Id VenueInvitation) }
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
    | ProfileLiveInvalidateVenueAction
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
    | FrontendSurfaceLabAction
    | ShowFrontendSurfaceLabPanelFragmentAction { panelId :: !Text }
    | RefreshFrontendSurfaceLabPanelAction
    | MoveFrontendSurfaceLabCardAction
    | ShowFwcMapdAwardRatesSectionAction
    | ShowPublicHolidaysSectionAction
    | CreateSupportVenueOnboardingInvitationAction
    | CreateFwcMapdRefreshJobAction
    | CreatePublicHolidayRefreshJobAction
    | MarkFeedbackReadAction { feedbackItemId :: !(Id UserFeedbackItem) }
    | MarkAllFeedbackReadAction
    | UpdateFeedbackStatusAction { feedbackItemId :: !(Id UserFeedbackItem) }
    | UpdateFeedbackPriorityAction { feedbackItemId :: !(Id UserFeedbackItem) }
    | UpdateFeedbackSupportNoteAction { feedbackItemId :: !(Id UserFeedbackItem) }
    | SwitchSupportVenueAction
    deriving (Eq, Show, Data)

data StaffController
    = NewStaffAction
    | CreateStaffAction
    | EditStaffAction { staffId :: !(Id Staff) }
    | ShowStaffContentLiveFragmentAction { staffId :: !(Id Staff) }
    | UpdateStaffAction { staffId :: !(Id Staff) }
    | NewTrialStaffInvitationAction { staffId :: !(Id Staff) }
    | CreateTrialStaffInvitationAction { staffId :: !(Id Staff) }
    | ResendTrialStaffInvitationAction { venueInvitationId :: !(Id VenueInvitation) }
    deriving (Eq, Show, Data)

newtype LiveUpdatesWSApp
    = LiveUpdatesWSApp
        { subscriptionIds :: [(UUID, Text)]
        }
    deriving (Eq, Show, Data)

data RosterWeeksController
    = RosterWeeksAction
    | ShowRosterWeekAction { weekOffset :: !Int }
    | ShowRosterDayTimelineAction { weekOffset :: !Int, rosterDayId :: !(Id RosterDay) }
    | ShowRosterDayTimelineContentFragmentAction { weekOffset :: !Int, rosterDayId :: !(Id RosterDay) }
    | ShowRosterWeekOverviewFragmentAction { weekOffset :: !Int }
    | ShowRosterWeekContentFragmentAction { weekOffset :: !Int }
    | ShowRosterWeekGridToolbarFragmentAction { weekOffset :: !Int }
    | ShowRosterWeekGridFrameFragmentAction { weekOffset :: !Int }
    | ShowRosterWeekDayColumnsFragmentAction { weekOffset :: !Int }
    | ShowRosterWeekDayRailFragmentAction { weekOffset :: !Int }
    | ShowRosterWeekWageRailFragmentAction { weekOffset :: !Int }
    | ShowRosterWeekSlotsGridFragmentAction { weekOffset :: !Int }
    | ShowRosterWeekStaffPanelFragmentAction { weekOffset :: !Int }
    | ShowRosterStaffSelfServiceLeaveFormFragmentAction { weekOffset :: !Int }
    | ShowRosterWeekDaySectionFragmentAction { weekOffset :: !Int, rosterDayId :: !(Id RosterDay) }
    | ShowRosterWeekRowFragmentAction { weekOffset :: !Int, rosterDayId :: !(Id RosterDay), rowIndex :: !Int }
    | UpdateRosterAssignmentFiltersAction { weekOffset :: !Int }
    | CreateRosterWeekAction { weekOffset :: !Int }
    | CopyRosterWeekAction { sourceWeekOffset :: !Int, targetWeekOffset :: !Int }
    | ToggleRosterWeekLiveStatusAction { rosterWeekId :: !(Id RosterWeek) }
    | CreateRosterWeekSlotDefinitionAction { rosterWeekId :: !(Id RosterWeek) }
    | DeleteRosterWeekSlotDefinitionAction { rosterWeekSlotDefinitionId :: !(Id RosterWeekSlotDefinition) }
    | SortRosterWeekAction { rosterWeekId :: !(Id RosterWeek) }
    | ToggleRosterDayClosedAction { rosterDayId :: !(Id RosterDay) }
    | AddRosterRowAction { rosterDayId :: !(Id RosterDay) }
    | RemoveRosterRowAction { rosterDayId :: !(Id RosterDay) }
    | UpdateRosterLayoutPreferenceAction { weekOffset :: !Int }
    | MoveRosterShiftToSlotAction { weekOffset :: !Int }
    | MoveRosterTimelineShiftAction { weekOffset :: !Int }
    | DuplicateRosterShiftToDayAction { weekOffset :: !Int }
    | DropRosterStaffAction { weekOffset :: !Int }
    | UpdateRosterWarningPreferenceAction { weekOffset :: !Int }
    | UpdateRosterWageEstimatePreferenceAction { weekOffset :: !Int }
    | NewRosterSlotDialogAction { rosterDayId :: !(Id RosterDay), rosterWeekSlotDefinitionId :: !(Id RosterWeekSlotDefinition), rowIndex :: !Int }
    | EditRosterSlotDialogAction { rosterSlotId :: !(Id RosterSlot) }
    | CreateRosterSlotAction { rosterDayId :: !(Id RosterDay), rosterWeekSlotDefinitionId :: !(Id RosterWeekSlotDefinition), rowIndex :: !Int }
    | UpdateRosterSlotAction { rosterSlotId :: !(Id RosterSlot) }
    | DeleteRosterSlotAction { rosterSlotId :: !(Id RosterSlot) }
    deriving (Eq, Show, Data)

-- Auth support: where to redirect unauthenticated users
instance HasNewSessionUrl User where
    newSessionUrl _ = "/NewSession"

-- Tell IHP which record type represents the logged-in user
type instance CurrentUserRecord = User
