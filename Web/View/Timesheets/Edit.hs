module Web.View.Timesheets.Edit where

import Web.Timesheets.Paths (timesheetWeekUrl)
import Web.View.Prelude

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
        renderTimesheetEntryModalWithStartButtons
            (timesheetModalTitle timesheetEntry.workedOn)
            (timesheetWeekUrl weekOffset showApproved showAllStaff)
            editTimesheetFormId
            (renderTimesheetForm timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff (pathTo (UpdateTimesheetEntryAction (get #id timesheetEntry))) editTimesheetFormId PageOverlayForm)
            (deleteButtonsFor timesheetEntry weekOffset showApproved showAllStaff)

editTimesheetFormId :: Text
editTimesheetFormId = "timesheet-entry-edit-form"

renderEditTimesheetDialog :: TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Bool -> Bool -> Html
renderEditTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff =
    renderTimesheetEntryDialogWithStartButtons
        (timesheetModalTitle timesheetEntry.workedOn)
        editTimesheetFormId
        (renderTimesheetForm timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff (pathTo (UpdateTimesheetEntryAction (get #id timesheetEntry))) editTimesheetFormId HtmxOverlayForm)
        (deleteButtonsFor timesheetEntry weekOffset showApproved showAllStaff)

deleteButtonsFor :: TimesheetEntry -> Int -> Bool -> Bool -> [OverlayButton]
deleteButtonsFor timesheetEntry weekOffset showApproved showAllStaff =
    [ OverlayButton
        { overlayButtonLabel = "Delete"
        , overlayButtonClass = "btn btn-outline-danger"
        , overlayButtonAction =
            OverlayFormAction
                "DELETE"
                deleteUrl
                [ ("weekOffset", tshow weekOffset)
                , ("showApproved", boolText showApproved)
                , ("showAllStaff", boolText showAllStaff)
                ]
                ("#" <> dialogOverlayMountId)
                (Just "Delete this timesheet entry? This cannot be undone.")
        }
    ]
    where
        deleteUrl = appendQueryParams (pathTo (DeleteTimesheetEntryAction (get #id timesheetEntry))) [("weekOffset", tshow weekOffset)]

boolText :: Bool -> Text
boolText True  = "true"
boolText False = "false"
