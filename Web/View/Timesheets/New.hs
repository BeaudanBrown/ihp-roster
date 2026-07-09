{-# LANGUAGE TypeApplications #-}

module Web.View.Timesheets.New where

import Application.Helper.FrontendContract.AppShell (CreateTimesheetEntryOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (appShellActionByMarker)
import Web.Timesheets.Paths (timesheetWeekUrl)
import Web.View.Prelude

data NewView = NewView
    { timesheetEntry        :: TimesheetEntry
    , staffMembers          :: [Staff]
    , shiftTypes            :: [ShiftType]
    , weekOffset            :: Int
    , showApproved          :: Bool
    , showAllStaff          :: Bool
    , selectedStaffFilterId :: Maybe UUID
    , currentViewerStaffId  :: Maybe UUID
    , pickerStart           :: Text
    , pickerEnd             :: Text
    }

instance View NewView where
    html NewView { .. } =
        renderTimesheetEntryModal
            (timesheetModalTitle timesheetEntry.workedOn)
            (timesheetWeekUrl weekOffset showApproved showAllStaff selectedStaffFilterId)
            newTimesheetFormId
            (renderTimesheetForm (appShellActionByMarker @CreateTimesheetEntryOverlay) timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd (pathTo CreateTimesheetEntryAction) newTimesheetFormId PageOverlayForm)

newTimesheetFormId :: Text
newTimesheetFormId = "timesheet-entry-create-form"

renderNewTimesheetDialog :: TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Bool -> Bool -> Maybe UUID -> Maybe UUID -> Text -> Text -> Html
renderNewTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd =
    renderTimesheetEntryDialog
        (timesheetModalTitle timesheetEntry.workedOn)
        newTimesheetFormId
        (renderTimesheetForm (appShellActionByMarker @CreateTimesheetEntryOverlay) timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd (pathTo CreateTimesheetEntryAction) newTimesheetFormId HtmxOverlayForm)
