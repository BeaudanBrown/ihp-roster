module Web.View.Timesheets.New where

import Web.View.Prelude

data NewView = NewView
    { timesheetEntry :: TimesheetEntry
    , staffMembers   :: [Staff]
    , shiftTypes     :: [ShiftType]
    , weekOffset     :: Int
    }

instance View NewView where
    html NewView { .. } =
        renderTimesheetEntryModal
            "New Timesheet Entry"
            weekOffset
            newTimesheetFormId
            (renderTimesheetForm timesheetEntry staffMembers shiftTypes weekOffset CreateTimesheetEntryAction newTimesheetFormId PageOverlayForm)

newTimesheetFormId :: Text
newTimesheetFormId = "timesheet-entry-create-form"

renderNewTimesheetDialog :: TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Html
renderNewTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset =
    renderTimesheetEntryDialog
        "New Timesheet Entry"
        newTimesheetFormId
        (renderTimesheetForm timesheetEntry staffMembers shiftTypes weekOffset CreateTimesheetEntryAction newTimesheetFormId HtmxOverlayForm)
