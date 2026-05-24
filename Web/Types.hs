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
    deriving (Eq, Show, Data)

data PasskeysController
    = PasskeyStepUpAction
    | UpdatePasskeyNameAction { passkeyId :: !(Id Passkey) }
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
    | ShowProfileContentFragmentAction
    | ShowProfileLeaveRequestsContentFragmentAction
    | UpdateProfileAction
    deriving (Eq, Show, Data)

data TimesheetsController
    = TimesheetsAction
    | ShowTimesheetWeekAction { weekOffset :: !Int }
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
    | ShowLeaveRequestsContentFragmentAction
    | NewLeaveRequestAction
    | CreateLeaveRequestAction
    | ApproveLeaveRequestAction { leaveRequestId :: !(Id LeaveRequest) }
    | DenyLeaveRequestAction { leaveRequestId :: !(Id LeaveRequest) }
    | DeleteLeaveRequestAction { leaveRequestId :: !(Id LeaveRequest) }
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
    | ShowBillingStatusFragmentAction
    | CreateBillingCheckoutSessionAction
    | CreateBillingPortalSessionAction
    | BillingSuccessAction
    | BillingCancelAction
    | UpdateVenueBillingControlAction
    deriving (Eq, Show, Data)

data StripeWebhooksController
    = StripeWebhookAction
    deriving (Eq, Show, Data)

data AdminController
    = AdminAction
    | XeroAction
    | StartXeroConnectionAction
    | XeroOAuthCallbackAction
    | DisconnectXeroConnectionAction
    | SyncXeroPayrollReferenceDataAction
    | CreateMissingXeroPayItemsAction
    | SaveXeroStaffMappingAction
    | SuggestXeroStaffMappingAction { staffId :: !(Id Staff) }
    | SaveXeroEarningsRateMappingAction
    | SaveXeroPayItemAccountCodeSelectionAction
    | SaveXeroPayrollCalendarSelectionAction
    | OpenXeroTimesheetPreparationAction
    | RunXeroTimesheetPreparationAction
    | RefreshXeroTimesheetPreparationAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | SyncXeroTimesheetPreparationReferenceDataAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | SaveXeroTimesheetPreparationCalendarAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | SaveXeroTimesheetPreparationAccountCodeAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | SaveXeroTimesheetPreparationEarningsRateAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | ApplyXeroTimesheetPreparationStaffDecisionAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | ApproveXeroTimesheetPreparationPayItemsAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | PreviewXeroTimesheetPreparationAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | SubmitXeroTimesheetPreparationAction { xeroTimesheetPreparationRunId :: !(Id XeroTimesheetPreparationRun) }
    | PreviewXeroDraftTimesheetsAction
    | SubmitXeroDraftTimesheetsAction
    | RetryXeroDraftTimesheetSubmissionAction { xeroTimesheetSubmissionId :: !(Id XeroTimesheetSubmission) }
    | UpdateVenueConfigAction
    | ShowAdminInvitesFragmentAction
    | ShowAdminShiftTypesFragmentAction
    | ShowAdminRosterGroupsFragmentAction
    | ShowAdminExportsFragmentAction
    | ShowAdminComplianceFragmentAction
    | ShowAdminXeroFragmentAction
    | ShowAdminXeroStaffMappingsFragmentAction
    | ShowAdminXeroPayItemsFragmentAction
    | ShowAdminXeroTimesheetsFragmentAction
    | CreateVenueInvitationAction
    | RevokeVenueInvitationAction { venueInvitationId :: !(Id VenueInvitation) }
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

data SupportController
    = SupportAction
    | ShowFwcMapdAwardRatesSectionAction
    | ShowPublicHolidaysSectionAction
    | CreateSupportVenueOnboardingInvitationAction
    | CreateFwcMapdRefreshJobAction
    | CreatePublicHolidayRefreshJobAction
    | SwitchSupportVenueAction
    deriving (Eq, Show, Data)

data StaffController
    = EditStaffAction { staffId :: !(Id Staff) }
    | UpdateStaffAction { staffId :: !(Id Staff) }
    deriving (Eq, Show, Data)

newtype LiveUpdatesWSApp
    = LiveUpdatesWSApp
        { subscriptionIds :: [(UUID, Text)]
        }
    deriving (Eq, Show, Data)

data RosterWeeksController
    = RosterWeeksAction
    | ShowRosterWeekAction { weekOffset :: !Int }
    | ShowRosterWeekOverviewFragmentAction { weekOffset :: !Int }
    | ShowRosterWeekContentFragmentAction { weekOffset :: !Int }
    | ShowRosterWeekStaffPanelFragmentAction { weekOffset :: !Int }
    | ShowRosterWeekDaySectionFragmentAction { weekOffset :: !Int, rosterDayId :: !(Id RosterDay) }
    | ShowRosterWeekRowFragmentAction { weekOffset :: !Int, rosterDayId :: !(Id RosterDay), rowIndex :: !Int }
    | UpdateRosterAssignmentFiltersAction { weekOffset :: !Int }
    | CreateRosterWeekAction { weekOffset :: !Int }
    | CopyRosterWeekAction { sourceWeekOffset :: !Int, targetWeekOffset :: !Int }
    | ToggleRosterWeekLiveStatusAction { rosterWeekId :: !(Id RosterWeek) }
    | CreateRosterWeekSlotDefinitionAction { rosterWeekId :: !(Id RosterWeek) }
    | UpdateRosterWeekSlotDefinitionAction { rosterWeekSlotDefinitionId :: !(Id RosterWeekSlotDefinition) }
    | DeleteRosterWeekSlotDefinitionAction { rosterWeekSlotDefinitionId :: !(Id RosterWeekSlotDefinition) }
    | SortRosterWeekAction { rosterWeekId :: !(Id RosterWeek) }
    | ToggleRosterDayClosedAction { rosterDayId :: !(Id RosterDay) }
    | AddRosterRowAction { rosterDayId :: !(Id RosterDay) }
    | RemoveRosterRowAction { rosterDayId :: !(Id RosterDay) }
    | UpdateRosterLayoutPreferenceAction { weekOffset :: !Int }
    | CreateRosterSlotAction { rosterDayId :: !(Id RosterDay), rosterWeekSlotDefinitionId :: !(Id RosterWeekSlotDefinition), rowIndex :: !Int }
    | UpdateRosterSlotAction { rosterSlotId :: !(Id RosterSlot) }
    deriving (Eq, Show, Data)

-- Auth support: where to redirect unauthenticated users
instance HasNewSessionUrl User where
    newSessionUrl _ = "/NewSession"

-- Tell IHP which record type represents the logged-in user
type instance CurrentUserRecord = User
