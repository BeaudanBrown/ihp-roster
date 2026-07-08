{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Overlay
    ( OverlayContract
    , Overlay
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

data Overlay

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

type OverlayContract =
    Global Overlay
        '[ OverlayAction OpenFeedbackDialog
            '[]
            '[ OverlayHtmxMethod 'OverlayGet
             , OverlayHtmxTarget DialogOverlayMount
             , OverlayHtmxSwap "innerHTML"
             , OverlayHtmxPushUrl 'OverlayPushUrlFalse
             ]
         , OverlayAction SubmitFeedback
            '[ Field FeedbackTypeField 'WireText
             , Field ContentField 'WireText
             ]
            '[ OverlayHtmxMethod 'OverlayPost
             , OverlayHtmxTarget DialogOverlayMount
             , OverlayHtmxSwap "innerHTML"
             , OverlayHtmxPushUrl 'OverlayPushUrlFalse
             ]
         , OverlayAction OpenTimesheetEntryDialog
            '[]
            '[ OverlayHtmxMethod 'OverlayGet
             , OverlayHtmxTarget DialogOverlayMount
             , OverlayHtmxSwap "innerHTML"
             , OverlayHtmxPushUrl 'OverlayPushUrlFalse
             ]
         , OverlayAction EditTimesheetEntryDialog
            '[]
            '[ OverlayHtmxMethod 'OverlayGet
             , OverlayHtmxTarget DialogOverlayMount
             , OverlayHtmxSwap "innerHTML"
             , OverlayHtmxPushUrl 'OverlayPushUrlFalse
             ]
         , OverlayAction CreateTimesheetEntryOverlay TimesheetEntryFields TimesheetEntrySubmitOptions
         , OverlayAction UpdateTimesheetEntryOverlay TimesheetEntryFields TimesheetEntrySubmitOptions
         , OverlayAction DeleteTimesheetEntryOverlay
            '[ Field WeekOffsetField 'WireText
             , Field ShowApprovedField 'WireText
             , Field ShowAllStaffField 'WireText
             , Field StaffFilterIdField 'WireText
             ]
            '[ OverlayHtmxMethod 'OverlayDelete
             , OverlayHtmxTarget DialogOverlayMount
             , OverlayHtmxSwap "innerHTML"
             , OverlayHtmxPushUrl 'OverlayPushUrlFalse
             , OverlayHtmxConfirm "Delete this timesheet entry? This cannot be undone."
             ]
         , OverlayAction OpenPasskeySetupDialog DialogLauncherFields DialogLauncherOptions
         , OverlayAction OpenPasskeyRecoveryCodeDialog DialogLauncherFields DialogLauncherOptions
         , OverlayAction CreateLeaveRequestOverlay
            '[ Field StartDateField 'WireText
             , Field EndDateField 'WireText
             , Field ReasonField 'WireText
             ]
            DialogSubmitOptions
         , OverlayAction OpenXeroTimesheetPreparationOverlay DialogLauncherFields DialogSubmitOptions
         , OverlayAction RunXeroTimesheetPreparationOverlay
            '[]
            '[ OverlayHtmxMethod 'OverlayPost
             , OverlayHtmxTarget DialogOverlayMount
             , OverlayHtmxSwap "innerHTML"
             , OverlayHtmxPushUrl 'OverlayPushUrlFalse
             , OverlayHtmxTrigger "load"
             , OverlayHtmxIndicator "#xero-timesheet-preparation-modal-loading-indicator"
             ]
         , OverlayAction ContinueXeroTimesheetPreparationStaffOverlay '[] DialogSubmitOptions
         , OverlayAction SelectXeroTimesheetPreparationPeriodOverlay
            '[ Field PeriodKeyField 'WireText
             ]
            DialogSubmitOptions
         , OverlayAction ApproveXeroTimesheetPreparationPayItemsOverlay '[] DialogSubmitOptions
         , OverlayAction ConfirmXeroTimesheetPreparationSubmissionOverlay '[] DialogSubmitOptions
         , OverlayAction RunXeroTimesheetPreparationSubmissionOverlay
            '[]
            '[ OverlayHtmxMethod 'OverlayPost
             , OverlayHtmxTarget DialogOverlayMount
             , OverlayHtmxSwap "innerHTML"
             , OverlayHtmxPushUrl 'OverlayPushUrlFalse
             , OverlayHtmxTrigger "load"
             , OverlayHtmxIndicator "#xero-timesheet-preparation-submitting-indicator"
             ]
         , OverlayAction ApplyXeroTimesheetPreparationStaffDecisionOverlay
            '[ Field StaffIdField 'WireText
             , Field DecisionField 'WireText
             , Field XeroEmployeeSelectionField 'WireText
             ]
            '[ OverlayHtmxMethod 'OverlayPost
             , OverlayHtmxTarget DialogOverlayMount
             , OverlayHtmxSwap "innerHTML"
             , OverlayHtmxPushUrl 'OverlayPushUrlFalse
             , OverlayHtmxTrigger "change, submit"
             ]
         , OverlayAction RefreshXeroTimesheetPreparationOverlay '[] DialogSubmitOptions
         , OverlayAction SubmitXeroTimesheetPreparationOverlay
            '[]
            '[ OverlayHtmxMethod 'OverlayPost
             , OverlayHtmxTarget DialogOverlayMount
             , OverlayHtmxSwap "innerHTML"
             , OverlayHtmxPushUrl 'OverlayPushUrlFalse
             , OverlayHtmxConfirm "Submit draft timesheets to Xero?"
             ]
         , OverlayAction OpenXeroPayItemImportOverlay DialogLauncherFields DialogLauncherOptions
         , OverlayAction LoadXeroPayItemImportOverlay
            '[ Field LoadCandidatesField 'WireText
             ]
            '[ OverlayHtmxMethod 'OverlayGet
             , OverlayHtmxTarget DialogOverlayMount
             , OverlayHtmxSwap "innerHTML"
             , OverlayHtmxPushUrl 'OverlayPushUrlFalse
             , OverlayHtmxTrigger "load"
             , OverlayHtmxIndicator "#xero-import-pay-items-loading-indicator"
             ]
         , OverlayAction ImportXeroPayItemsOverlay
            '[ Field XeroEarningsRateIdField 'WireText
             ]
            DialogSubmitOptions
         , OverlayAction OpenRosterShiftDialog DialogLauncherFields DialogLauncherOptions
         , OverlayAction OpenRosterStaffCreateDialog DialogLauncherFields DialogLauncherOptions
         , OverlayAction OpenRosterStaffEditDialog DialogLauncherFields DialogLauncherOptions
         , OverlayAction CreateRosterShiftOverlay RosterShiftFields DialogSubmitOptions
         , OverlayAction UpdateRosterShiftOverlay RosterShiftFields DialogSubmitOptions
         , OverlayAction DeleteRosterSlotOverlay
            '[]
            '[ OverlayHtmxMethod 'OverlayDelete
             , OverlayHtmxTarget DialogOverlayMount
             , OverlayHtmxSwap "innerHTML"
             , OverlayHtmxPushUrl 'OverlayPushUrlFalse
             , OverlayHtmxConfirm "Delete this shift?"
             ]
         , OverlayAction ConfirmRemoveRosterRowOverlay
            '[ Field ConfirmDeletePopulatedRowField 'WireText
             ]
            '[ OverlayHtmxMethod 'OverlayPost
             , OverlayHtmxTarget DialogOverlayMount
             , OverlayHtmxSwap "innerHTML"
             , OverlayHtmxPushUrl 'OverlayPushUrlFalse
             , OverlayHtmxSync "#roster-week-shell:replace"
             ]
         , OverlayAction CreateTrialStaffOverlay StaffProfileFields DialogSubmitOptions
         , OverlayAction UpdateStaffProfileOverlay StaffProfileFields DialogSubmitOptions
         , OverlayAction UpdateStaffShiftPreferencesOverlay StaffShiftPreferenceFields DialogSubmitOptions
         , OverlayAction CreateTrialStaffInvitationOverlay
            '[ Field InvitationEmailField 'WireText
             ]
            DialogSubmitOptions
         ]

type DialogLauncherFields = '[]

type DialogLauncherOptions =
    '[ OverlayHtmxMethod 'OverlayGet
     , OverlayHtmxTarget DialogOverlayMount
     , OverlayHtmxSwap "innerHTML"
     , OverlayHtmxPushUrl 'OverlayPushUrlFalse
     ]

type DialogSubmitOptions =
    '[ OverlayHtmxMethod 'OverlayPost
     , OverlayHtmxTarget DialogOverlayMount
     , OverlayHtmxSwap "innerHTML"
     , OverlayHtmxPushUrl 'OverlayPushUrlFalse
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
    '[ OverlayHtmxMethod 'OverlayPost
     , OverlayHtmxTarget DialogOverlayMount
     , OverlayHtmxSwap "innerHTML"
     , OverlayHtmxPushUrl 'OverlayPushUrlFalse
     ]
