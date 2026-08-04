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
    , selectedStaffFilterId :: Maybe UUID
    , currentViewerStaffId  :: Maybe UUID
    , pickerStart           :: Text
    , pickerEnd             :: Text
    , pickerStep            :: Int
    }

instance View EditView where
    html EditView { .. } =
        renderTimesheetEntryModalWithStartButtons
            (timesheetModalTitle (timesheetEntryWorkedOn timesheetEntry))
            (timesheetWeekUrl weekOffset selectedStaffFilterId)
            editTimesheetFormId
            (renderTimesheetForm (appShellActionByMarker @UpdateTimesheetEntryOverlay) formOrigin timesheetEntry staffMembers shiftTypes weekOffset selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep (pathTo (UpdateTimesheetEntryAction (get #id timesheetEntry))) editTimesheetFormId PageOverlayForm)
            (deleteButtonsFor timesheetEntry weekOffset selectedStaffFilterId)
      where
        formOrigin = timesheetEntryFormOrigin timesheetEntry

editTimesheetFormId :: Text
editTimesheetFormId = "timesheet-entry-edit-form"

renderEditTimesheetDialog :: TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Maybe UUID -> Maybe UUID -> Text -> Text -> Int -> Html
renderEditTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep =
    renderTimesheetEntryDialogWithStartButtons
        (timesheetModalTitle (timesheetEntryWorkedOn timesheetEntry))
        editTimesheetFormId
        (renderTimesheetForm (appShellActionByMarker @UpdateTimesheetEntryOverlay) formOrigin timesheetEntry staffMembers shiftTypes weekOffset selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep (pathTo (UpdateTimesheetEntryAction (get #id timesheetEntry))) editTimesheetFormId HtmxOverlayForm)
        (deleteButtonsFor timesheetEntry weekOffset selectedStaffFilterId)
  where
    formOrigin = timesheetEntryFormOrigin timesheetEntry

timesheetEntryFormOrigin :: TimesheetEntry -> TimesheetFormOrigin
timesheetEntryFormOrigin timesheetEntry
    | isJust timesheetEntry.sourceRosterSlotId = RosteredTimesheetEntryForm
    | otherwise = AdHocTimesheetForm

deleteButtonsFor :: TimesheetEntry -> Int -> Maybe UUID -> [OverlayButton]
deleteButtonsFor timesheetEntry weekOffset selectedStaffFilterId =
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
                (("_method", "DELETE") : timesheetStateQueryParams weekOffset selectedStaffFilterId)
                (Just "Delete this timesheet entry? This cannot be undone.")
        }
    ]
    where
        deleteUrl = appendQueryParams (pathTo (DeleteTimesheetEntryAction (get #id timesheetEntry))) (timesheetStateQueryParams weekOffset selectedStaffFilterId)
