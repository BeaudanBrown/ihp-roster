{-# LANGUAGE TypeApplications #-}

module Web.View.Timesheets.Edit where

import Application.Helper.FrontendContract.AppShell (DeleteTimesheetEntryOverlay,
                                                     UpdateTimesheetEntryOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             appShellActionByMarker)
import Application.VenueTime.Model (timesheetEntryOperationalDate)
import Web.Timesheets.Paths (timesheetWindowStateQueryParams,
                             timesheetWindowUrl)
import Web.View.Prelude

data EditView = EditView
    { timesheetEntry        :: TimesheetEntry
    , staffMembers          :: [Staff]
    , shiftTypes            :: [ShiftType]
    , weekOffset            :: Int
    , calendarRevision      :: Int
    , selectedStaffFilterId :: Maybe UUID
    , currentViewerStaffId  :: Maybe UUID
    , pickerStart           :: Text
    , pickerEnd             :: Text
    , pickerStep            :: Int
    }

instance View EditView where
    html EditView { .. } =
        renderTimesheetEntryModalWithStartButtons
            (timesheetModalTitle (timesheetEntryOperationalDate timesheetEntry))
            (timesheetWindowUrl (timesheetEntryOperationalDate timesheetEntry) selectedStaffFilterId)
            editTimesheetFormId
            (renderTimesheetForm (appShellActionByMarker @UpdateTimesheetEntryOverlay) formOrigin timesheetEntry staffMembers shiftTypes weekOffset calendarRevision selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep (pathTo (UpdateTimesheetEntryAction (get #id timesheetEntry))) editTimesheetFormId PageOverlayForm)
            (deleteButtonsFor timesheetEntry calendarRevision selectedStaffFilterId)
      where
        formOrigin = timesheetEntryFormOrigin timesheetEntry

editTimesheetFormId :: Text
editTimesheetFormId = "timesheet-entry-edit-form"

renderEditTimesheetDialog :: TimesheetEntry -> [Staff] -> [ShiftType] -> Int -> Int -> Maybe UUID -> Maybe UUID -> Text -> Text -> Int -> Html
renderEditTimesheetDialog timesheetEntry staffMembers shiftTypes weekOffset calendarRevision selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep =
    renderTimesheetEntryDialogWithStartButtons
        (timesheetModalTitle (timesheetEntryOperationalDate timesheetEntry))
        editTimesheetFormId
        (renderTimesheetForm (appShellActionByMarker @UpdateTimesheetEntryOverlay) formOrigin timesheetEntry staffMembers shiftTypes weekOffset calendarRevision selectedStaffFilterId currentViewerStaffId pickerStart pickerEnd pickerStep (pathTo (UpdateTimesheetEntryAction (get #id timesheetEntry))) editTimesheetFormId HtmxOverlayForm)
        (deleteButtonsFor timesheetEntry calendarRevision selectedStaffFilterId)
  where
    formOrigin = timesheetEntryFormOrigin timesheetEntry

timesheetEntryFormOrigin :: TimesheetEntry -> TimesheetFormOrigin
timesheetEntryFormOrigin timesheetEntry
    | isJust timesheetEntry.sourceRosterSlotId = RosteredTimesheetEntryForm
    | otherwise = AdHocTimesheetForm

deleteButtonsFor :: TimesheetEntry -> Int -> Maybe UUID -> [OverlayButton]
deleteButtonsFor timesheetEntry calendarRevision selectedStaffFilterId =
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
                (("_method", "DELETE") : requestParams)
                (Just "Delete this timesheet entry? This cannot be undone.")
        }
    ]
    where
        requestParams = timesheetWindowStateQueryParams (timesheetEntryOperationalDate timesheetEntry) selectedStaffFilterId <> [("rosterCalendarRevision", tshow calendarRevision)]
        deleteUrl = appendQueryParams (pathTo (DeleteTimesheetEntryAction (get #id timesheetEntry))) requestParams
