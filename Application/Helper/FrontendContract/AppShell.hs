{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.AppShell
    ( AppShellContract
    , AppShell
    , PartialNavigate
    , PartialNavigationHtmxAttrs
    , OpenFeedbackDialog
    , SubmitFeedback
    , FeedbackTypeField
    , ContentField
    , OpenTimesheetEntryDialog
    , EditTimesheetEntryDialog
    , CreateTimesheetEntryOverlay
    , UpdateTimesheetEntryOverlay
    , DeleteTimesheetEntryOverlay
    , WeekOffsetField
    , ShowApprovedField
    , ShowAllStaffField
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
    , CreateLeaveRequestOverlay
    , OpenXeroTimesheetPreparationOverlay
    , RunXeroTimesheetPreparationOverlay
    , ContinueXeroTimesheetPreparationStaffOverlay
    , SelectXeroTimesheetPreparationPeriodOverlay
    , ApproveXeroTimesheetPreparationPayItemsOverlay
    , ConfirmXeroTimesheetPreparationSubmissionOverlay
    , RunXeroTimesheetPreparationSubmissionOverlay
    , ApplyXeroTimesheetPreparationStaffDecisionOverlay
    , RefreshXeroTimesheetPreparationOverlay
    , SubmitXeroTimesheetPreparationOverlay
    , OpenXeroPayItemImportOverlay
    , LoadXeroPayItemImportOverlay
    , ImportXeroPayItemsOverlay
    , OpenRosterShiftDialog
    , OpenRosterStaffCreateDialog
    , OpenRosterStaffEditDialog
    , CreateRosterShiftOverlay
    , UpdateRosterShiftOverlay
    , DeleteRosterSlotOverlay
    , ConfirmRemoveRosterRowOverlay
    , CreateTrialStaffOverlay
    , UpdateStaffProfileOverlay
    , UpdateStaffShiftPreferencesOverlay
    , CreateTrialStaffInvitationOverlay
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
    , IsActiveField
    , RosterGroupIdsField
    , RosterGroupIdField
    , ShiftPreferenceKeysField
    , ConfirmDeletePopulatedRowField
    , LoadCandidatesField
    , PeriodKeyField
    , DecisionField
    , XeroEmployeeSelectionField
    , XeroEarningsRateIdField
    , InvitationEmailField
    ) where

import Application.Helper.FrontendContract.App (DialogOverlayMount)
import Application.Helper.FrontendContract.DSL

data AppShell
data PartialNavigate
data PartialNavigationHtmxAttrs

data OpenFeedbackDialog
data SubmitFeedback
data FeedbackTypeField
data ContentField

data OpenTimesheetEntryDialog
data EditTimesheetEntryDialog
data CreateTimesheetEntryOverlay
data UpdateTimesheetEntryOverlay
data DeleteTimesheetEntryOverlay
data WeekOffsetField
data ShowApprovedField
data ShowAllStaffField
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
data CreateLeaveRequestOverlay
data OpenXeroTimesheetPreparationOverlay
data RunXeroTimesheetPreparationOverlay
data ContinueXeroTimesheetPreparationStaffOverlay
data SelectXeroTimesheetPreparationPeriodOverlay
data ApproveXeroTimesheetPreparationPayItemsOverlay
data ConfirmXeroTimesheetPreparationSubmissionOverlay
data RunXeroTimesheetPreparationSubmissionOverlay
data ApplyXeroTimesheetPreparationStaffDecisionOverlay
data RefreshXeroTimesheetPreparationOverlay
data SubmitXeroTimesheetPreparationOverlay
data OpenXeroPayItemImportOverlay
data LoadXeroPayItemImportOverlay
data ImportXeroPayItemsOverlay
data OpenRosterShiftDialog
data OpenRosterStaffCreateDialog
data OpenRosterStaffEditDialog
data CreateRosterShiftOverlay
data UpdateRosterShiftOverlay
data DeleteRosterSlotOverlay
data ConfirmRemoveRosterRowOverlay
data CreateTrialStaffOverlay
data UpdateStaffProfileOverlay
data UpdateStaffShiftPreferencesOverlay
data CreateTrialStaffInvitationOverlay
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
data IsActiveField
data RosterGroupIdsField
data RosterGroupIdField
data ShiftPreferenceKeysField
data ConfirmDeletePopulatedRowField
data LoadCandidatesField
data PeriodKeyField
data DecisionField
data XeroEmployeeSelectionField
data XeroEarningsRateIdField
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
         , AppShellAction SubmitFeedback
            '[ Field FeedbackTypeField 'WireText
             , Field ContentField 'WireText
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
            '[ Field WeekOffsetField 'WireText
             , Field ShowApprovedField 'WireText
             , Field ShowAllStaffField 'WireText
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
         , AppShellAction CreateLeaveRequestOverlay
            '[ Field StartDateField 'WireText
             , Field EndDateField 'WireText
             , Field ReasonField 'WireText
             ]
            DialogSubmitOptions
         , AppShellAction OpenXeroTimesheetPreparationOverlay DialogLauncherFields DialogSubmitOptions
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
         , AppShellAction ApproveXeroTimesheetPreparationPayItemsOverlay '[] DialogSubmitOptions
         , AppShellAction ConfirmXeroTimesheetPreparationSubmissionOverlay '[] DialogSubmitOptions
         , AppShellAction RunXeroTimesheetPreparationSubmissionOverlay
            '[]
            '[ AppShellHtmxMethod 'AppShellPost
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             , AppShellHtmxTrigger "load"
             , AppShellHtmxIndicator "#xero-timesheet-preparation-submitting-indicator"
             ]
         , AppShellAction ApplyXeroTimesheetPreparationStaffDecisionOverlay
            '[ Field StaffIdField 'WireText
             , Field DecisionField 'WireText
             , Field XeroEmployeeSelectionField 'WireText
             ]
            '[ AppShellHtmxMethod 'AppShellPost
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             , AppShellHtmxTrigger "change, submit"
             ]
         , AppShellAction RefreshXeroTimesheetPreparationOverlay '[] DialogSubmitOptions
         , AppShellAction SubmitXeroTimesheetPreparationOverlay
            '[]
            '[ AppShellHtmxMethod 'AppShellPost
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             , AppShellHtmxConfirm "Submit draft timesheets to Xero?"
             ]
         , AppShellAction OpenXeroPayItemImportOverlay DialogLauncherFields DialogLauncherOptions
         , AppShellAction LoadXeroPayItemImportOverlay
            '[ Field LoadCandidatesField 'WireText
             ]
            '[ AppShellHtmxMethod 'AppShellGet
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             , AppShellHtmxTrigger "load"
             , AppShellHtmxIndicator "#xero-import-pay-items-loading-indicator"
             ]
         , AppShellAction ImportXeroPayItemsOverlay
            '[ Field XeroEarningsRateIdField 'WireText
             ]
            DialogSubmitOptions
         , AppShellAction OpenRosterShiftDialog DialogLauncherFields DialogLauncherOptions
         , AppShellAction OpenRosterStaffCreateDialog DialogLauncherFields DialogLauncherOptions
         , AppShellAction OpenRosterStaffEditDialog DialogLauncherFields DialogLauncherOptions
         , AppShellAction CreateRosterShiftOverlay RosterShiftFields DialogSubmitOptions
         , AppShellAction UpdateRosterShiftOverlay RosterShiftFields DialogSubmitOptions
         , AppShellAction DeleteRosterSlotOverlay
            '[]
            '[ AppShellHtmxMethod 'AppShellDelete
             , AppShellHtmxTarget DialogOverlayMount
             , AppShellHtmxSwap "innerHTML"
             , AppShellHtmxPushUrl 'AppShellPushUrlFalse
             , AppShellHtmxConfirm "Delete this shift?"
             ]
         , AppShellAction ConfirmRemoveRosterRowOverlay
            '[ Field ConfirmDeletePopulatedRowField 'WireText
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

type RosterShiftFields =
    '[ Field StaffIdField 'WireText
     , Field ShiftTypeIdField 'WireText
     , Field StartTimeField 'WireText
     , Field EndTimeField 'WireText
     ]

type StaffProfileFields =
    '[ Field FirstNameField 'WireText
     , Field LastNameField 'WireText
     , Field PreferredNameField 'WireText
     , Field PhoneField 'WireText
     , Field IdealShiftsPerWeekField 'WireText
     , Field EmergencyContactNameField 'WireText
     , Field EmergencyContactPhoneField 'WireText
     , Field SectionField 'WireText
     , Field WeekOffsetField 'WireText
     , Field RosterGroupIdField 'WireText
     , Field VenueRoleField 'WireText
     , Field EmploymentBasisField 'WireText
     , Field PayRateSelectionField 'WireText
     , Field IsActiveField 'WireText
     , Field RosterGroupIdsField 'WireText
     ]

type StaffShiftPreferenceFields =
    '[ Field SectionField 'WireText
     , Field WeekOffsetField 'WireText
     , Field RosterGroupIdField 'WireText
     , Field ShiftPreferenceKeysField 'WireText
     ]

type TimesheetEntryFields =
    '[ Field WeekOffsetField 'WireText
     , Field ShowApprovedField 'WireText
     , Field ShowAllStaffField 'WireText
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
