{-# LANGUAGE TypeApplications #-}

module Web.View.Timesheets.SuggestedNew where

import Application.Helper.FrontendContract.AppShell (CreateTimesheetEntryOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (appShellActionByMarker)
import Application.VenueTime.Model (timesheetEntryOperationalDate)
import Web.Timesheets.Paths (timesheetWindowUrl)
import Web.View.Prelude

data SuggestedNewView = SuggestedNewView
    { rosterSlotId          :: Id RosterSlot
    , timesheetEntry        :: TimesheetEntry
    , staffMembers          :: [Staff]
    , shiftTypes            :: [ShiftType]
    , calendarRevision      :: Int
    , selectedStaffFilterId :: Maybe UUID
    , currentViewerStaffId  :: Maybe UUID
    , pickerStart           :: Text
    , pickerEnd             :: Text
    , pickerStep            :: Int
    }

instance View SuggestedNewView where
    html SuggestedNewView { .. } =
        renderTimesheetEntryModal
            ("Rostered " <> timesheetModalTitle (timesheetEntryOperationalDate timesheetEntry))
            (timesheetWindowUrl (timesheetEntryOperationalDate timesheetEntry) selectedStaffFilterId)
            suggestedTimesheetFormId
            (renderSuggestedTimesheetForm PageOverlayForm rosterSlotId timesheetEntry staffMembers shiftTypes calendarRevision selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep)

suggestedTimesheetFormId :: Text
suggestedTimesheetFormId = "timesheet-suggestion-create-form"

renderSuggestedTimesheetDialog :: Id RosterSlot -> TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Maybe UUID -> Maybe UUID -> Text -> Text -> Int -> Html
renderSuggestedTimesheetDialog rosterSlotId timesheetEntry staffMembers shiftTypes calendarRevision selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep =
    renderTimesheetEntryDialog
        ("Rostered " <> timesheetModalTitle (timesheetEntryOperationalDate timesheetEntry))
        suggestedTimesheetFormId
        (renderSuggestedTimesheetForm HtmxOverlayForm rosterSlotId timesheetEntry staffMembers shiftTypes calendarRevision selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep)

renderSuggestedTimesheetForm :: (?context :: ControllerContext) => OverlayFormMode -> Id RosterSlot -> TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Maybe UUID -> Maybe UUID -> Text -> Text -> Int -> Html
renderSuggestedTimesheetForm formMode rosterSlotId timesheetEntry staffMembers shiftTypes calendarRevision selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep =
    renderTimesheetForm
        (appShellActionByMarker @CreateTimesheetEntryOverlay)
        RosteredTimesheetForm
        timesheetEntry
        staffMembers
        shiftTypes
        calendarRevision
        selectedStaffFilterId
        currentViewerStaffId
        pickerStart
        pickerEnd
        pickerStep
        (pathTo CreateTimesheetEntryFromSuggestionAction { rosterSlotId })
        suggestedTimesheetFormId
        formMode
