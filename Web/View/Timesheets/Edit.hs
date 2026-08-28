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

newtype EditView = EditView
    { timesheetFormInputs :: TimesheetFormInputs
    }

instance View EditView where
    html EditView { timesheetFormInputs } =
        renderTimesheetEntryModalWithStartButtons
            (timesheetModalTitle operationalDate)
            (timesheetWindowUrl operationalDate timesheetFormInputs.selectedStaffFilterId)
            editTimesheetFormId
            (renderTimesheetForm (editTimesheetFormRenderModel PageOverlayForm timesheetFormInputs))
            (deleteButtonsFor timesheetFormInputs.timesheetEntry timesheetFormInputs.calendarRevision timesheetFormInputs.selectedStaffFilterId)
      where
        operationalDate = timesheetEntryOperationalDate timesheetFormInputs.timesheetEntry

editTimesheetFormId :: Text
editTimesheetFormId = "timesheet-entry-edit-form"

renderEditTimesheetDialog :: TimesheetFormInputs -> Html
renderEditTimesheetDialog timesheetFormInputs =
    renderTimesheetEntryDialogWithStartButtons
        (timesheetModalTitle (timesheetEntryOperationalDate timesheetFormInputs.timesheetEntry))
        editTimesheetFormId
        (renderTimesheetForm (editTimesheetFormRenderModel HtmxOverlayForm timesheetFormInputs))
        (deleteButtonsFor timesheetFormInputs.timesheetEntry timesheetFormInputs.calendarRevision timesheetFormInputs.selectedStaffFilterId)

editTimesheetFormRenderModel :: OverlayFormMode -> TimesheetFormInputs -> TimesheetFormRenderModel
editTimesheetFormRenderModel formMode timesheetFormInputs =
    TimesheetFormRenderModel
        { timesheetFormInputs
        , timesheetFormPresentation =
            TimesheetFormPresentation
                { appShellAction = appShellActionByMarker @UpdateTimesheetEntryOverlay
                , formOrigin = timesheetEntryFormOrigin timesheetFormInputs.timesheetEntry
                , actionUrl = pathTo (UpdateTimesheetEntryAction (get #id timesheetFormInputs.timesheetEntry))
                , formId = editTimesheetFormId
                , formMode
                }
        }

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
