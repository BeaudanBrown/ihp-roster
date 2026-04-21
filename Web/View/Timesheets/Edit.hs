module Web.View.Timesheets.Edit where

import Web.View.Prelude
import Web.Timesheets.Paths (timesheetWeekUrl)

data EditView = EditView
    { timesheetEntry :: TimesheetEntry
    , staffMembers   :: [Staff]
    , shiftTypes     :: [ShiftType]
    , weekOffset     :: Int
    , showApproved   :: Bool
    , showAllStaff   :: Bool
    }

instance View EditView where
    html EditView { .. } =
        renderTimesheetEntryModal
            "Edit Timesheet Entry"
            (timesheetWeekUrl weekOffset showApproved showAllStaff)
            editTimesheetFormId
            (renderTimesheetForm timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff (pathTo (UpdateTimesheetEntryAction (get #id timesheetEntry))) editTimesheetFormId PageOverlayForm)

editTimesheetFormId :: Text
editTimesheetFormId = "timesheet-entry-edit-form"

renderEditTimesheetDialog :: TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Bool -> Bool -> Html
renderEditTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff =
    renderTimesheetEntryDialog
        "Edit Timesheet Entry"
        editTimesheetFormId
        (renderTimesheetForm timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff (pathTo (UpdateTimesheetEntryAction (get #id timesheetEntry))) editTimesheetFormId HtmxOverlayForm)
