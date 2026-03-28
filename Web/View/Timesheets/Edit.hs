module Web.View.Timesheets.Edit where

import Web.View.Prelude

data EditView = EditView
    { timesheetEntry :: TimesheetEntry
    , staffMembers   :: [Staff]
    , shiftTypes     :: [ShiftType]
    , weekOffset     :: Int
    }

instance View EditView where
    html EditView { .. } =
        renderTimesheetEntryModal
            "Edit Timesheet Entry"
            weekOffset
            editTimesheetFormId
            (renderTimesheetForm timesheetEntry staffMembers shiftTypes weekOffset (UpdateTimesheetEntryAction (get #id timesheetEntry)) editTimesheetFormId PageOverlayForm)

editTimesheetFormId :: Text
editTimesheetFormId = "timesheet-entry-edit-form"

renderEditTimesheetDialog :: TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Html
renderEditTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset =
    renderTimesheetEntryDialog
        "Edit Timesheet Entry"
        editTimesheetFormId
        (renderTimesheetForm timesheetEntry staffMembers shiftTypes weekOffset (UpdateTimesheetEntryAction (get #id timesheetEntry)) editTimesheetFormId HtmxOverlayForm)
