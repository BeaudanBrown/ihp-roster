{-# LANGUAGE TypeApplications #-}

module Web.View.Timesheets.SuggestedNew where

import Application.Helper.FrontendContract.AppShell (CreateTimesheetEntryOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (appShellActionByMarker)
import Web.Timesheets.Paths (timesheetWeekUrl)
import Web.View.Prelude

data SuggestedNewView = SuggestedNewView
    { rosterSlotId          :: Id RosterSlot
    , timesheetEntry        :: TimesheetEntry
    , staffMembers          :: [Staff]
    , shiftTypes            :: [ShiftType]
    , weekOffset            :: Int
    , showApproved          :: Bool
    , showAllStaff          :: Bool
    , showSuggestions       :: Bool
    , selectedStaffFilterId :: Maybe UUID
    , currentViewerStaffId  :: Maybe UUID
    , pickerStart           :: Text
    , pickerEnd             :: Text
    }

instance View SuggestedNewView where
    html SuggestedNewView { .. } =
        renderTimesheetEntryModal
            ("Rostered " <> timesheetModalTitle timesheetEntry.workedOn)
            (timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)
            suggestedTimesheetFormId
            (renderSuggestedTimesheetForm PageOverlayForm rosterSlotId timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd)

suggestedTimesheetFormId :: Text
suggestedTimesheetFormId = "timesheet-suggestion-create-form"

renderSuggestedTimesheetDialog :: Id RosterSlot -> TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Bool -> Bool -> Bool -> Maybe UUID -> Maybe UUID -> Text -> Text -> Html
renderSuggestedTimesheetDialog rosterSlotId timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd =
    renderTimesheetEntryDialog
        ("Rostered " <> timesheetModalTitle timesheetEntry.workedOn)
        suggestedTimesheetFormId
        (renderSuggestedTimesheetForm HtmxOverlayForm rosterSlotId timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd)

renderSuggestedTimesheetForm :: (?context :: ControllerContext) => OverlayFormMode -> Id RosterSlot -> TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Bool -> Bool -> Bool -> Maybe UUID -> Maybe UUID -> Text -> Text -> Html
renderSuggestedTimesheetForm formMode rosterSlotId timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd =
    renderTimesheetForm
        (appShellActionByMarker @CreateTimesheetEntryOverlay)
        RosteredTimesheetForm
        timesheetEntry
        staffMembers
        shiftTypes
        weekOffset
        showApproved
        showAllStaff
        showSuggestions
        selectedStaffFilterId
        currentViewerStaffId
        pickerStart
        pickerEnd
        (pathTo CreateTimesheetEntryFromSuggestionAction { rosterSlotId })
        suggestedTimesheetFormId
        formMode
