{-# LANGUAGE TypeApplications #-}

module Web.View.Timesheets.Edit where

import Application.Helper.FrontendContract.AppShell (DeleteTimesheetEntryOverlay,
                                                     UpdateTimesheetEntryOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker)
import Application.VenueTime.Model (timesheetEntryWorkedOn)
import Web.Timesheets.Paths (timesheetStateQueryParams, timesheetWeekUrl)
import Web.View.Prelude

data EditView = EditView
    { timesheetEntry        :: TimesheetEntry
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

instance View EditView where
    html EditView { .. } =
        renderTimesheetEntryModalWithStartButtons
            (timesheetModalTitle (timesheetEntryWorkedOn timesheetEntry))
            (timesheetWeekUrl weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)
            editTimesheetFormId
            (renderTimesheetForm (appShellActionByMarker @UpdateTimesheetEntryOverlay) formOrigin timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd (pathTo (UpdateTimesheetEntryAction (get #id timesheetEntry))) editTimesheetFormId PageOverlayForm)
            (deleteButtonsFor timesheetEntry weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)
      where
        formOrigin = timesheetEntryFormOrigin timesheetEntry

editTimesheetFormId :: Text
editTimesheetFormId = "timesheet-entry-edit-form"

renderEditTimesheetDialog :: TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Bool -> Bool -> Bool -> Maybe UUID -> Maybe UUID -> Text -> Text -> Html
renderEditTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd =
    renderTimesheetEntryDialogWithStartButtons
        (timesheetModalTitle (timesheetEntryWorkedOn timesheetEntry))
        editTimesheetFormId
        (renderTimesheetForm (appShellActionByMarker @UpdateTimesheetEntryOverlay) formOrigin timesheetEntry staffMembers shiftTypes weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd (pathTo (UpdateTimesheetEntryAction (get #id timesheetEntry))) editTimesheetFormId HtmxOverlayForm)
        (deleteButtonsFor timesheetEntry weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)
  where
    formOrigin = timesheetEntryFormOrigin timesheetEntry

timesheetEntryFormOrigin :: TimesheetEntry -> TimesheetFormOrigin
timesheetEntryFormOrigin timesheetEntry
    | isJust timesheetEntry.sourceRosterSlotId = RosteredTimesheetEntryForm
    | otherwise = AdHocTimesheetForm

deleteButtonsFor :: TimesheetEntry -> Int -> Bool -> Bool -> Bool -> Maybe UUID -> [OverlayButton]
deleteButtonsFor timesheetEntry weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId =
    [ OverlayButton
        { overlayButtonLabel = "Delete"
        , overlayButtonClass = "btn btn-outline-danger"
        , overlayButtonAction =
            GeneratedDialogFormAction
                (appShellActionByMarker @DeleteTimesheetEntryOverlay)
                AppShellActionRoute
                    { appShellActionRouteUrl = deleteUrl
                    , appShellActionRouteFields = []
                    , appShellActionRouteCustomHtmx = []
                    , appShellActionRouteStandardUrl = Nothing
                    , appShellActionRouteExtraAttrs = []
                    }
                (("_method", "DELETE") : timesheetStateQueryParams weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)
                (Just "Delete this timesheet entry? This cannot be undone.")
        }
    ]
    where
        deleteUrl = appendQueryParams (pathTo (DeleteTimesheetEntryAction (get #id timesheetEntry))) (timesheetStateQueryParams weekOffset showApproved showAllStaff showSuggestions selectedStaffFilterId)
