module Web.View.Timesheets.New where

import Web.View.Prelude
import Web.View.Timesheets.Index (timesheetWeekUrl)

data NewView = NewView
    { timesheetEntry :: TimesheetEntry
    , staffMembers   :: [Staff]
    , shiftTypes     :: [ShiftType]
    , weekOffset     :: Int
    , showApproved   :: Bool
    , showAllStaff   :: Bool
    }

instance View NewView where
    html NewView { .. } =
        renderTimesheetEntryModal
            "New Timesheet Entry"
            (timesheetWeekUrl weekOffset showApproved showAllStaff)
            newTimesheetFormId
            (renderTimesheetForm timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff (pathTo CreateTimesheetEntryAction) newTimesheetFormId PageOverlayForm)

newTimesheetFormId :: Text
newTimesheetFormId = "timesheet-entry-create-form"

renderNewTimesheetDialog :: TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Bool -> Bool -> Html
renderNewTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff =
    renderTimesheetEntryDialog
        "New Timesheet Entry"
        newTimesheetFormId
        (renderTimesheetForm timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff (pathTo CreateTimesheetEntryAction) newTimesheetFormId HtmxOverlayForm)
