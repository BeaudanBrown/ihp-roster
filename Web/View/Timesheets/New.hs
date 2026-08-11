{-# LANGUAGE TypeApplications #-}

module Web.View.Timesheets.New where

import Application.Helper.FrontendContract.AppShell (CreateTimesheetEntryOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (appShellActionByMarker)
import Application.VenueTime.Model (timesheetEntryOperationalDate)
import Web.Timesheets.Paths (timesheetWindowUrl)
import Web.View.Prelude

data NewView = NewView
    { timesheetEntry            :: TimesheetEntry
    , staffMembers              :: [Staff]
    , shiftTypes                :: [ShiftType]
    , weekOffset                :: Int
    , calendarRevision          :: Int
    , hasRosterSuggestionForDay :: Bool
    , selectedStaffFilterId     :: Maybe UUID
    , currentViewerStaffId      :: Maybe UUID
    , pickerStart               :: Text
    , pickerEnd                 :: Text
    , pickerStep                :: Int
    }

instance View NewView where
    html NewView { .. } =
        renderTimesheetEntryModal
            (timesheetModalTitle (timesheetEntryOperationalDate timesheetEntry))
            (timesheetWindowUrl (timesheetEntryOperationalDate timesheetEntry) selectedStaffFilterId)
            newTimesheetFormId
            (renderTimesheetForm (appShellActionByMarker @CreateTimesheetEntryOverlay) formOrigin timesheetEntry staffMembers shiftTypes weekOffset calendarRevision selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep (pathTo CreateTimesheetEntryAction) newTimesheetFormId PageOverlayForm)
      where
        formOrigin = if hasRosterSuggestionForDay then AdHocTimesheetFormWithSuggestion else AdHocTimesheetForm

newTimesheetFormId :: Text
newTimesheetFormId = "timesheet-entry-create-form"

renderNewTimesheetDialog :: TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Int -> Bool -> Maybe UUID -> Maybe UUID -> Text -> Text -> Int -> Html
renderNewTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset calendarRevision hasRosterSuggestionForDay selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep =
    renderTimesheetEntryDialog
        (timesheetModalTitle (timesheetEntryOperationalDate timesheetEntry))
        newTimesheetFormId
        (renderTimesheetForm (appShellActionByMarker @CreateTimesheetEntryOverlay) formOrigin timesheetEntry staffMembers shiftTypes weekOffset calendarRevision selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep (pathTo CreateTimesheetEntryAction) newTimesheetFormId HtmxOverlayForm)
  where
    formOrigin = if hasRosterSuggestionForDay then AdHocTimesheetFormWithSuggestion else AdHocTimesheetForm
