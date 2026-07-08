{-# LANGUAGE TypeApplications #-}

module Web.View.Timesheets.Edit where

import Application.Helper.FrontendContract.Overlay (UpdateTimesheetEntryOverlay)
import Application.Helper.FrontendContract.Overlay.Runtime (overlayActionByMarker)
import Web.Timesheets.Paths (timesheetWeekUrl)
import Web.View.Prelude

data EditView = EditView
    { timesheetEntry        :: TimesheetEntry
    , staffMembers          :: [Staff]
    , shiftTypes            :: [ShiftType]
    , weekOffset            :: Int
    , showApproved          :: Bool
    , showAllStaff          :: Bool
    , selectedStaffFilterId :: Maybe UUID
    , currentViewerStaffId  :: Maybe UUID
    }

instance View EditView where
    html EditView { .. } =
        renderTimesheetEntryModalWithStartButtons
            (timesheetModalTitle timesheetEntry.workedOn)
            (timesheetWeekUrl weekOffset showApproved showAllStaff selectedStaffFilterId)
            editTimesheetFormId
            (renderTimesheetForm (overlayActionByMarker @UpdateTimesheetEntryOverlay) timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff selectedStaffFilterId currentViewerStaffId (pathTo (UpdateTimesheetEntryAction (get #id timesheetEntry))) editTimesheetFormId PageOverlayForm)
            (deleteButtonsFor timesheetEntry weekOffset showApproved showAllStaff selectedStaffFilterId)

editTimesheetFormId :: Text
editTimesheetFormId = "timesheet-entry-edit-form"

renderEditTimesheetDialog :: TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Bool -> Bool -> Maybe UUID -> Maybe UUID -> Html
renderEditTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff selectedStaffFilterId currentViewerStaffId =
    renderTimesheetEntryDialogWithStartButtons
        (timesheetModalTitle timesheetEntry.workedOn)
        editTimesheetFormId
        (renderTimesheetForm (overlayActionByMarker @UpdateTimesheetEntryOverlay) timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff selectedStaffFilterId currentViewerStaffId (pathTo (UpdateTimesheetEntryAction (get #id timesheetEntry))) editTimesheetFormId HtmxOverlayForm)
        (deleteButtonsFor timesheetEntry weekOffset showApproved showAllStaff selectedStaffFilterId)

deleteButtonsFor :: TimesheetEntry -> Int -> Bool -> Bool -> Maybe UUID -> [OverlayButton]
deleteButtonsFor timesheetEntry weekOffset showApproved showAllStaff selectedStaffFilterId =
    [ OverlayButton
        { overlayButtonLabel = "Delete"
        , overlayButtonClass = "btn btn-outline-danger"
        , overlayButtonAction =
            OverlayFormAction
                "DELETE"
                deleteUrl
                [ ("weekOffset", tshow weekOffset)
                , ("showApproved", boolParam showApproved)
                , ("showAllStaff", boolParam showAllStaff)
                , ("staffFilterId", maybe "" tshow selectedStaffFilterId)
                ]
                ("#" <> dialogOverlayMountId)
                (Just "Delete this timesheet entry? This cannot be undone.")
        }
    ]
    where
        deleteUrl = appendQueryParams (pathTo (DeleteTimesheetEntryAction (get #id timesheetEntry))) [("weekOffset", tshow weekOffset), ("staffFilterId", maybe "" tshow selectedStaffFilterId)]
