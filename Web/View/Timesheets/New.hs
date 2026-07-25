{-# LANGUAGE TypeApplications #-}

module Web.View.Timesheets.New where

import Application.Helper.FrontendContract.AppShell (CreateTimesheetEntryOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (appShellActionByMarker)
import Application.VenueTime.Model (timesheetEntryWorkedOn)
import Web.Timesheets.Paths (timesheetWeekUrl)
import Web.View.Prelude

data NewView = NewView
    { timesheetEntry            :: TimesheetEntry
    , staffMembers              :: [Staff]
    , shiftTypes                :: [ShiftType]
    , weekOffset                :: Int
    , showApproved              :: Bool
    , showAllStaff              :: Bool
    , showSuggestions           :: Bool
    , hasRosterSuggestionForDay :: Bool
    , selectedStaffFilterId     :: Maybe UUID
    , currentViewerStaffId      :: Maybe UUID
    , pickerStart               :: Text
    , pickerEnd                 :: Text
    }

instance View NewView where
    html NewView { .. } =
        renderTimesheetEntryModal
            (timesheetModalTitle (timesheetEntryWorkedOn timesheetEntry))
            (timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)
            newTimesheetFormId
            (renderTimesheetForm (appShellActionByMarker @CreateTimesheetEntryOverlay) formOrigin timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd (pathTo CreateTimesheetEntryAction) newTimesheetFormId PageOverlayForm)
      where
        formOrigin = if hasRosterSuggestionForDay then AdHocTimesheetFormWithSuggestion else AdHocTimesheetForm

newTimesheetFormId :: Text
newTimesheetFormId = "timesheet-entry-create-form"

renderNewTimesheetDialog :: TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Bool -> Bool -> Bool -> Bool -> Maybe UUID -> Maybe UUID -> Text -> Text -> Html
renderNewTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions hasRosterSuggestionForDay selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd =
    renderTimesheetEntryDialog
        (timesheetModalTitle (timesheetEntryWorkedOn timesheetEntry))
        newTimesheetFormId
        (renderTimesheetForm (appShellActionByMarker @CreateTimesheetEntryOverlay) formOrigin timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd (pathTo CreateTimesheetEntryAction) newTimesheetFormId HtmxOverlayForm)
  where
    formOrigin = if hasRosterSuggestionForDay then AdHocTimesheetFormWithSuggestion else AdHocTimesheetForm
