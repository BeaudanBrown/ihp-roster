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
    , CreateTrialStaffInvitationOverlay
    , StartDateField
    , EndDateField
    , ReasonField
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
data CreateTrialStaffInvitationOverlay
data StartDateField
data EndDateField
data ReasonField
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
