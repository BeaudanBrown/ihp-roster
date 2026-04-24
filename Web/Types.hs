module Web.Types where

import Generated.Types
import IHP.LoginSupport.Types
import IHP.ModelSupport
import IHP.Prelude

data WebApplication = WebApplication deriving (Eq, Show)


data StaticController = WelcomeAction deriving (Eq, Show, Data)

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
    deriving (Eq, Show, Data)

data PasskeysController
    = UpdatePasskeyNameAction { passkeyId :: !(Id Passkey) }
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
    | CreateReportDefinitionAction
    | UpdateReportDefinitionAction { reportDefinitionId :: !(Id ReportDefinition) }
    | DownloadExportJobAction { exportJobId :: !(Id ExportJob) }
    deriving (Eq, Show, Data)

data AdminController
    = AdminAction
    | UpdateVenueConfigAction
    | ShowAdminSlotNamesFragmentAction
    | ShowAdminInvitesFragmentAction
    | CreateVenueInvitationAction
    | RevokeVenueInvitationAction { venueInvitationId :: !(Id VenueInvitation) }
    | CreateRosterGroupAction
    | UpdateRosterGroupAction { rosterGroupId :: !(Id RosterGroup) }
    | MakeDefaultRosterGroupAction { rosterGroupId :: !(Id RosterGroup) }
    | CreatePayLevelAction
    | UpdatePayLevelAction { payLevelId :: !(Id PayLevel) }
    | CreatePayLevelDayRuleAction
    | UpdatePayLevelDayRuleAction { payLevelDayRuleId :: !(Id PayLevelDayRule) }
    | CreateShiftTypeAction
    | UpdateShiftTypeAction { shiftTypeId :: !(Id ShiftType) }
    | CreateSlotNameAction
    | UpdateSlotNameAction { slotNameId :: !(Id SlotName) }
    | MoveSlotNameUpAction { slotNameId :: !(Id SlotName) }
    | MoveSlotNameDownAction { slotNameId :: !(Id SlotName) }
    | DeleteSlotNameAction { slotNameId :: !(Id SlotName) }
    deriving (Eq, Show, Data)

data SupportController
    = SupportAction
    | CreateSupportVenueAction
    | CreateSupportVenueOnboardingInvitationAction
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
    | SyncRosterWeekSlotStructureAction { rosterWeekId :: !(Id RosterWeek) }
    | ToggleRosterDayClosedAction { rosterDayId :: !(Id RosterDay) }
    | AddRosterRowAction { rosterDayId :: !(Id RosterDay) }
    | RemoveRosterRowAction { rosterDayId :: !(Id RosterDay) }
    | UpdateRosterSlotAction { rosterSlotId :: !(Id RosterSlot) }
    deriving (Eq, Show, Data)

-- Auth support: where to redirect unauthenticated users
instance HasNewSessionUrl User where
    newSessionUrl _ = "/NewSession"

-- Tell IHP which record type represents the logged-in user
type instance CurrentUserRecord = User
