{-# LANGUAGE TypeApplications #-}

module Web.View.Timesheets.New where

import Application.Helper.FrontendContract.Overlay (CreateTimesheetEntryOverlay)
import Application.Helper.FrontendContract.Overlay.Runtime (overlayActionByMarker)
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
    }

instance View NewView where
    html NewView { .. } =
        renderTimesheetEntryModal
            (timesheetModalTitle timesheetEntry.workedOn)
            (timesheetWeekUrl weekOffset showApproved showAllStaff selectedStaffFilterId)
            newTimesheetFormId
            (renderTimesheetForm (overlayActionByMarker @CreateTimesheetEntryOverlay) timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff selectedStaffFilterId currentViewerStaffId (pathTo CreateTimesheetEntryAction) newTimesheetFormId PageOverlayForm)

newTimesheetFormId :: Text
newTimesheetFormId = "timesheet-entry-create-form"

renderNewTimesheetDialog :: TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Bool -> Bool -> Maybe UUID -> Maybe UUID -> Html
renderNewTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff selectedStaffFilterId currentViewerStaffId =
    renderTimesheetEntryDialog
        (timesheetModalTitle timesheetEntry.workedOn)
        newTimesheetFormId
        (renderTimesheetForm (overlayActionByMarker @CreateTimesheetEntryOverlay) timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff selectedStaffFilterId currentViewerStaffId (pathTo CreateTimesheetEntryAction) newTimesheetFormId HtmxOverlayForm)
