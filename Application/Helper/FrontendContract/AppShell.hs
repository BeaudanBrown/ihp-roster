{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.AppShell
    ( AppShellContract
    , AppShell
    , PartialNavigate
    , PartialNavigationHtmxAttrs
    , OpenFeedbackDialog
    , OpenPageHelpDialog
    , OpenPayrollWorkbookConfigurationDialog
    , OpenPayrollWorkbookConfigurationDeleteDialog
    , CreatePayrollWorkbookConfigurationOverlay
    , UpdatePayrollWorkbookConfigurationOverlay
    , AddPayrollWorkbookConfigurationSheetOverlay
    , RemovePayrollWorkbookConfigurationSheetOverlay
    , MovePayrollWorkbookConfigurationSheetUpOverlay
    , MovePayrollWorkbookConfigurationSheetDownOverlay
    , PayrollWorkbookConfigurationDraftFields
    , ExportAnchorDateField
    , PayrollWorkbookConfigurationNameField
    , PayrollWorkbookSheetFamiliesField
    , PayrollWorkbookConfigurationRevisionField
    , PayrollWorkbookConfigurationIdField
    , PayrollWorkbookConfigurationSheetField
    , SubmitFeedback
    , FeedbackTypeField
    , ContentField
    , FeedbackViewportWidthField
    , FeedbackViewportHeightField
    , FeedbackDevicePixelRatioField
    , FeedbackDisplayModeField
    , OpenTimesheetEntryDialog
    , EditTimesheetEntryDialog
    , CreateTimesheetEntryOverlay
    , UpdateTimesheetEntryOverlay
    , DeleteTimesheetEntryOverlay
    , StaffFilterIdField
    , StaffIdField
    , ShiftTypeIdField
    , WorkedOnField
    , StartTimeField
    , EndTimeField
    , HadBreakField
    , BreakStartTimeField
    , BreakEndTimeField
    , StaffCommentField
    , ManagerNoteField
    , OpenPasskeySetupDialog
    , OpenPasskeyRecoveryCodeDialog
    , SubmitPasskeyProtectedAction
    , CreateLeaveRequestOverlay
    , OpenXeroStaffMappingsOverlay
    , ApplyXeroStaffMappingOverlay
    , OpenXeroTimesheetPreparationOverlay
    , RunXeroTimesheetPreparationOverlay
    , ContinueXeroTimesheetPreparationStaffOverlay
    , SelectXeroTimesheetPreparationPeriodOverlay
    , ApproveXeroTimesheetPreparationPayItemsOverlay
    , ConfirmXeroTimesheetPreparationSubmissionOverlay
    , RunXeroTimesheetPreparationSubmissionOverlay
    , ApplyXeroTimesheetPreparationStaffDecisionOverlay
    , RefreshXeroProblemTimesheetApprovalOverlay
    , RefreshXeroTimesheetPreparationOverlay
    , SubmitXeroTimesheetPreparationOverlay
    , OpenXeroPayItemImportOverlay
    , ImportXeroPayItemsOverlay
    , OpenRosterShiftDialog
    , OpenRosterStaffCreateDialog
    , OpenRosterStaffEditDialog
    , OpenTrialStaffInvitationDialog
    , OpenStaffRemovalDialog
    , CreateRosterShiftOverlay
    , UpdateRosterShiftOverlay
    , OpenRosterSlotDeleteConfirmationDialog
    , ConfirmDeleteRosterSlotOverlay
    , ConfirmRemoveRosterRowOverlay
    , CreateTrialStaffOverlay
    , UpdateStaffProfileOverlay
    , UpdateStaffShiftPreferencesOverlay
    , CreateTrialStaffInvitationOverlay
    , RemoveStaffOverlay
    , AnchorDateField
    , RosterCalendarRevisionField
    , StartDateField
    , EndDateField
    , ReasonField
    , FirstNameField
    , LastNameField
    , PreferredNameField
    , PhoneField
    , IdealShiftsPerWeekField
    , EmergencyContactNameField
    , EmergencyContactPhoneField
    , SectionField
    , VenueRoleField
    , EmploymentBasisField
    , PayRateSelectionField
    , RosterGroupIdsField
    , RosterGroupIdField
    , ShiftPreferenceKeysField
    , ConfirmDeletePopulatedRowField
    , PeriodKeyField
    , XeroEmployeeSelectionField
    , XeroEarningsRateIdField
    , AccountCodeField
    , ExpectedActiveCalculationIdField
    , ExpectedApprovalTimestampField
    , InvitationEmailField
    ) where

import Application.Helper.FrontendContract.DSL
import Application.Helper.FrontendContract.Overlay (DialogOverlayMount)
import Application.Helper.FrontendContract.Surface.Profile (StaffProfileSectionValue)
import Application.PayRateSelection (StaffPayRateSelection)
import Application.Xero.EmployeeId (XeroEmployeeSelection)
import Generated.Types (FeedbackTypeEnum, StaffEmploymentBasisEnum,
                        VenueRoleEnum)

data AppShell
data PartialNavigate
data PartialNavigationHtmxAttrs

data OpenFeedbackDialog
data OpenPageHelpDialog
data OpenPayrollWorkbookConfigurationDialog
data OpenPayrollWorkbookConfigurationDeleteDialog
data CreatePayrollWorkbookConfigurationOverlay
data UpdatePayrollWorkbookConfigurationOverlay
data AddPayrollWorkbookConfigurationSheetOverlay
data RemovePayrollWorkbookConfigurationSheetOverlay
data MovePayrollWorkbookConfigurationSheetUpOverlay
data MovePayrollWorkbookConfigurationSheetDownOverlay
data ExportAnchorDateField
data PayrollWorkbookConfigurationNameField
data PayrollWorkbookSheetFamiliesField
data PayrollWorkbookConfigurationRevisionField
data PayrollWorkbookConfigurationIdField
data PayrollWorkbookConfigurationSheetField
data SubmitFeedback
data FeedbackTypeField
data ContentField
data FeedbackViewportWidthField
data FeedbackViewportHeightField
data FeedbackDevicePixelRatioField
data FeedbackDisplayModeField

data OpenTimesheetEntryDialog
data EditTimesheetEntryDialog
data CreateTimesheetEntryOverlay
data UpdateTimesheetEntryOverlay
data DeleteTimesheetEntryOverlay
data StaffFilterIdField
data StaffIdField
data ShiftTypeIdField
data WorkedOnField
data StartTimeField
data EndTimeField
data HadBreakField
data BreakStartTimeField
data BreakEndTimeField
data StaffCommentField
data ManagerNoteField

data OpenPasskeySetupDialog
data OpenPasskeyRecoveryCodeDialog
data SubmitPasskeyProtectedAction
data CreateLeaveRequestOverlay
data OpenXeroStaffMappingsOverlay
data ApplyXeroStaffMappingOverlay
data OpenXeroTimesheetPreparationOverlay
data RunXeroTimesheetPreparationOverlay
data ContinueXeroTimesheetPreparationStaffOverlay
data SelectXeroTimesheetPreparationPeriodOverlay
data ApproveXeroTimesheetPreparationPayItemsOverlay
data ConfirmXeroTimesheetPreparationSubmissionOverlay
data RunXeroTimesheetPreparationSubmissionOverlay
data ApplyXeroTimesheetPreparationStaffDecisionOverlay
data RefreshXeroTimesheetPreparationOverlay
data RefreshXeroProblemTimesheetApprovalOverlay
data SubmitXeroTimesheetPreparationOverlay
data OpenXeroPayItemImportOverlay
data ImportXeroPayItemsOverlay
data OpenRosterShiftDialog
data OpenRosterStaffCreateDialog
data OpenRosterStaffEditDialog
data OpenTrialStaffInvitationDialog
data OpenStaffRemovalDialog
data CreateRosterShiftOverlay
data UpdateRosterShiftOverlay
data OpenRosterSlotDeleteConfirmationDialog
data ConfirmDeleteRosterSlotOverlay
data ConfirmRemoveRosterRowOverlay
data CreateTrialStaffOverlay
data UpdateStaffProfileOverlay
data UpdateStaffShiftPreferencesOverlay
data CreateTrialStaffInvitationOverlay
data RemoveStaffOverlay
data AnchorDateField
data RosterCalendarRevisionField
data StartDateField
data EndDateField
data ReasonField
data FirstNameField
data LastNameField
data PreferredNameField
data PhoneField
data IdealShiftsPerWeekField
data EmergencyContactNameField
data EmergencyContactPhoneField
data SectionField
data VenueRoleField
data EmploymentBasisField
data PayRateSelectionField
data RosterGroupIdsField
data RosterGroupIdField
data ShiftPreferenceKeysField
data ConfirmDeletePopulatedRowField
data PeriodKeyField
data XeroEmployeeSelectionField
data XeroEarningsRateIdField
data AccountCodeField
data ExpectedActiveCalculationIdField
data ExpectedApprovalTimestampField
data InvitationEmailField

type AppShellContract =
    Global AppShell
        '[ AppShellAction PartialNavigate
            '[]
            '[ AppShellHtmxMethod 'AppShellGet
             , AppShellCustomHtmx PartialNavigationHtmxAttrs "partial navigation supplies route-specific target, swap, select, push-url, and sync attrs"
             ]
         , AppShellAction OpenFeedbackDialog
            '[]
            '[ AppShellHtmxMethod 'AppShellGet
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             ]
         , AppShellAction OpenPageHelpDialog
            '[]
            DialogLauncherOptions
         , AppShellAction OpenPayrollWorkbookConfigurationDialog '[] DialogLauncherOptions
         , AppShellAction OpenPayrollWorkbookConfigurationDeleteDialog '[] DialogLauncherOptions
         , AppShellAction CreatePayrollWorkbookConfigurationOverlay
            '[ Field ExportAnchorDateField 'WireDay
             , Field PayrollWorkbookConfigurationNameField 'WireText
             , Field PayrollWorkbookSheetFamiliesField ('WireList 'WireText)
             ]
            DialogSubmitOptions
         , AppShellAction UpdatePayrollWorkbookConfigurationOverlay
            '[ Field ExportAnchorDateField 'WireDay
             , Field PayrollWorkbookConfigurationNameField 'WireText
             , Field PayrollWorkbookSheetFamiliesField ('WireList 'WireText)
             , Field PayrollWorkbookConfigurationRevisionField 'WireInt
             ]
            DialogSubmitOptions
         , AppShellAction AddPayrollWorkbookConfigurationSheetOverlay PayrollWorkbookConfigurationDraftFields PayrollWorkbookConfigurationDraftOptions
         , AppShellAction RemovePayrollWorkbookConfigurationSheetOverlay PayrollWorkbookConfigurationDraftFields PayrollWorkbookConfigurationDraftOptions
         , AppShellAction MovePayrollWorkbookConfigurationSheetUpOverlay PayrollWorkbookConfigurationDraftFields PayrollWorkbookConfigurationDraftOptions
         , AppShellAction MovePayrollWorkbookConfigurationSheetDownOverlay PayrollWorkbookConfigurationDraftFields PayrollWorkbookConfigurationDraftOptions
         , AppShellAction SubmitFeedback
            '[ Field FeedbackTypeField ('WireClosed FeedbackTypeEnum)
             , Field ContentField 'WireText
             , OptionalField FeedbackViewportWidthField 'WireText
             , OptionalField FeedbackViewportHeightField 'WireText
             , OptionalField FeedbackDevicePixelRatioField 'WireText
             , OptionalField FeedbackDisplayModeField 'WireText
             ]
            '[ AppShellHtmxMethod 'AppShellPost
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             ]
         , AppShellAction OpenTimesheetEntryDialog
            '[]
            '[ AppShellHtmxMethod 'AppShellGet
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             ]
         , AppShellAction EditTimesheetEntryDialog
            '[]
            '[ AppShellHtmxMethod 'AppShellGet
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             ]
         , AppShellAction CreateTimesheetEntryOverlay TimesheetEntryFields TimesheetEntrySubmitOptions
         , AppShellAction UpdateTimesheetEntryOverlay TimesheetEntryFields TimesheetEntrySubmitOptions
         , AppShellAction DeleteTimesheetEntryOverlay
            '[ Field AnchorDateField 'WireText
             , Field RosterCalendarRevisionField 'WireText
             , Field StaffFilterIdField 'WireText
             ]
            '[ AppShellHtmxMethod 'AppShellDelete
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             , AppShellHtmxConfirm "Delete this timesheet entry? This cannot be undone."
             ]
         , AppShellAction OpenPasskeySetupDialog DialogLauncherFields DialogLauncherOptions
         , AppShellAction OpenPasskeyRecoveryCodeDialog DialogLauncherFields DialogLauncherOptions
         , AppShellAction SubmitPasskeyProtectedAction
            '[]
            '[ AppShellHtmxMethod 'AppShellPost
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             ]
         , AppShellAction CreateLeaveRequestOverlay
            '[ Field StartDateField 'WireText
             , Field EndDateField 'WireText
             , Field ReasonField 'WireText
             ]
            DialogSubmitOptions
         , AppShellAction OpenXeroStaffMappingsOverlay '[] DialogSubmitOptions
         , AppShellAction ApplyXeroStaffMappingOverlay
            '[ Field StaffIdField 'WireUUID
             , Field XeroEmployeeSelectionField ('WireDomain XeroEmployeeSelection)
             ]
            '[ AppShellHtmxMethod 'AppShellPost
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             , AppShellHtmxTrigger "change, submit"
             , AppShellHtmxSync "#xero-staff-mappings:queue all"
             ]
         , AppShellAction OpenXeroTimesheetPreparationOverlay '[] DialogSubmitOptions
         , AppShellAction RunXeroTimesheetPreparationOverlay
            '[]
            '[ AppShellHtmxMethod 'AppShellPost
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             , AppShellHtmxTrigger "load"
             , AppShellHtmxIndicator "#xero-timesheet-preparation-modal-loading-indicator"
             ]
         , AppShellAction ContinueXeroTimesheetPreparationStaffOverlay '[] DialogSubmitOptions
         , AppShellAction SelectXeroTimesheetPreparationPeriodOverlay
            '[ Field PeriodKeyField 'WireText
             ]
            DialogSubmitOptions
         , AppShellAction ApproveXeroTimesheetPreparationPayItemsOverlay
            '[ OptionalField AccountCodeField 'WireText
             ]
            DialogSubmitOptions
         , AppShellAction ConfirmXeroTimesheetPreparationSubmissionOverlay '[] DialogSubmitOptions
         , AppShellAction RunXeroTimesheetPreparationSubmissionOverlay '[] DialogSubmitOptions
         , AppShellAction ApplyXeroTimesheetPreparationStaffDecisionOverlay
            '[ Field StaffIdField 'WireUUID
             , Field XeroEmployeeSelectionField ('WireDomain XeroEmployeeSelection)
             ]
            '[ AppShellHtmxMethod 'AppShellPost
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             , AppShellHtmxTrigger "change, submit"
             , AppShellHtmxSync "#xero-preparation-staff-mappings:queue all"
             ]
         , AppShellAction RefreshXeroTimesheetPreparationOverlay '[] DialogSubmitOptions
         , AppShellAction RefreshXeroProblemTimesheetApprovalOverlay
            '[ Field ExpectedActiveCalculationIdField 'WireUUID
             , Field ExpectedApprovalTimestampField 'WireText
             ]
            '[ AppShellHtmxMethod 'AppShellPost
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             , AppShellHtmxConfirm "Refresh this problem Timesheet approval using current pay facts and Xero mappings?"
             ]
         , AppShellAction SubmitXeroTimesheetPreparationOverlay
            '[ OptionalField AccountCodeField 'WireText
             ]
            '[ AppShellHtmxMethod 'AppShellPost
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             , AppShellHtmxConfirm "Submit draft timesheets to Xero?"
             ]
         , AppShellAction OpenXeroPayItemImportOverlay DialogLauncherFields DialogLauncherOptions
         , AppShellAction ImportXeroPayItemsOverlay
            '[ Field XeroEarningsRateIdField 'WireText
             ]
            DialogSubmitOptions
         , AppShellAction OpenRosterShiftDialog DialogLauncherFields DialogLauncherOptions
         , AppShellAction OpenRosterStaffCreateDialog DialogLauncherFields DialogLauncherOptions
         , AppShellAction OpenRosterStaffEditDialog DialogLauncherFields DialogLauncherOptions
         , AppShellAction OpenTrialStaffInvitationDialog DialogLauncherFields DialogLauncherOptions
         , AppShellAction OpenStaffRemovalDialog DialogLauncherFields DialogLauncherOptions
         , AppShellAction CreateRosterShiftOverlay RosterShiftFields DialogSubmitOptions
         , AppShellAction UpdateRosterShiftOverlay RosterShiftFields DialogSubmitOptions
         , AppShellAction OpenRosterSlotDeleteConfirmationDialog
            '[ Field AnchorDateField 'WireDay
             , Field RosterCalendarRevisionField 'WireInt
             ]
            DialogLauncherOptions
         , AppShellAction ConfirmDeleteRosterSlotOverlay
            '[ Field AnchorDateField 'WireDay
             , Field RosterCalendarRevisionField 'WireInt
             ]
            '[ AppShellHtmxMethod 'AppShellDelete
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             ]
         , AppShellAction ConfirmRemoveRosterRowOverlay
            '[ Field ConfirmDeletePopulatedRowField 'WireText
             , Field AnchorDateField 'WireText
             , Field RosterCalendarRevisionField 'WireText
             ]
            '[ AppShellHtmxMethod 'AppShellPost
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             , AppShellHtmxSync "#roster-week-shell:replace"
             ]
         , AppShellAction CreateTrialStaffOverlay StaffProfileFields DialogSubmitOptions
         , AppShellAction UpdateStaffProfileOverlay StaffProfileFields DialogSubmitOptions
         , AppShellAction UpdateStaffShiftPreferencesOverlay StaffShiftPreferenceFields DialogSubmitOptions
         , AppShellAction CreateTrialStaffInvitationOverlay
            '[ Field InvitationEmailField 'WireText
             ]
            DialogSubmitOptions
         , AppShellAction RemoveStaffOverlay
            '[]
            '[ AppShellHtmxMethod 'AppShellPost
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             ]
         ]

type DialogLauncherFields = '[]

type DialogLauncherOptions =
    '[ AppShellHtmxMethod 'AppShellGet
     , AppShellHtmxTarget DialogOverlayMount
     , AppShellHtmxSwap "innerHTML"
     , AppShellHtmxPushUrl 'AppShellPushUrlFalse
     ]

type DialogSubmitOptions =
    '[ AppShellHtmxMethod 'AppShellPost
     , AppShellHtmxTarget DialogOverlayMount
     , AppShellHtmxSwap "innerHTML"
     , AppShellHtmxPushUrl 'AppShellPushUrlFalse
     ]

type PayrollWorkbookConfigurationDraftFields =
    '[ Field ExportAnchorDateField 'WireDay
     , Field PayrollWorkbookConfigurationNameField 'WireText
     , Field PayrollWorkbookSheetFamiliesField ('WireList 'WireText)
     , Field PayrollWorkbookConfigurationRevisionField 'WireInt
     , OptionalField PayrollWorkbookConfigurationIdField 'WireUUID
     , Field PayrollWorkbookConfigurationSheetField 'WireText
     ]

type PayrollWorkbookConfigurationDraftOptions =
    '[ AppShellHtmxMethod 'AppShellPost
     , AppShellHtmxInclude "#payroll-workbook-configuration-editor-form"
     , AppShellHtmxTarget DialogOverlayMount
     , AppShellHtmxSwap "innerHTML"
     , AppShellHtmxPushUrl 'AppShellPushUrlFalse
     , AppShellHtmxSync "#payroll-workbook-configuration-editor-form:replace"
     ]

type RosterShiftFields =
    '[ Field StaffIdField 'WireText
     , Field ShiftTypeIdField 'WireText
     , Field StartTimeField 'WireText
     , Field EndTimeField 'WireText
     , Field AnchorDateField 'WireText
     , Field RosterCalendarRevisionField 'WireText
     ]

type StaffProfileFields =
    '[ Field FirstNameField 'WireText
     , Field LastNameField 'WireText
     , Field PreferredNameField 'WireText
     , Field PhoneField 'WireText
     , Field IdealShiftsPerWeekField 'WireText
     , Field EmergencyContactNameField 'WireText
     , Field EmergencyContactPhoneField 'WireText
     , Field SectionField ('WireClosed StaffProfileSectionValue)
     , Field AnchorDateField 'WireText
     , Field RosterGroupIdField 'WireText
     , Field VenueRoleField ('WireClosed VenueRoleEnum)
     , Field EmploymentBasisField ('WireClosed StaffEmploymentBasisEnum)
     , Field PayRateSelectionField ('WireDomain StaffPayRateSelection)
     , Field RosterGroupIdsField 'WireText
     ]

type StaffShiftPreferenceFields =
    '[ Field SectionField ('WireClosed StaffProfileSectionValue)
     , Field AnchorDateField 'WireText
     , Field RosterGroupIdField 'WireText
     , Field ShiftPreferenceKeysField 'WireText
     ]

type TimesheetEntryFields =
    '[ Field AnchorDateField 'WireText
     , Field RosterCalendarRevisionField 'WireText
     , Field StaffFilterIdField 'WireText
     , Field StaffIdField 'WireText
     , Field ShiftTypeIdField 'WireText
     , Field WorkedOnField 'WireText
     , Field StartTimeField 'WireText
     , Field EndTimeField 'WireText
     , Field HadBreakField 'WireText
     , Field BreakStartTimeField 'WireText
     , Field BreakEndTimeField 'WireText
     , Field StaffCommentField 'WireText
     , Field ManagerNoteField 'WireText
     ]

type TimesheetEntrySubmitOptions =
    '[ AppShellHtmxMethod 'AppShellPost
     , AppShellHtmxTarget DialogOverlayMount
     , AppShellHtmxSwap "innerHTML"
     , AppShellHtmxPushUrl 'AppShellPushUrlFalse
     ]
