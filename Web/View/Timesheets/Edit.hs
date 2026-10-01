{-# LANGUAGE TypeApplications #-}

module Web.View.Timesheets.Edit where

import Application.Helper.FrontendContract.AppShell (AnchorDateField,
                                                     DeleteTimesheetEntryOverlay,
                                                     EditTimesheetEntryDialog,
                                                     OpenTimesheetDeleteConfirmationDialog,
                                                     RosterCalendarRevisionField,
                                                     StaffFilterIdField,
                                                     UpdateTimesheetEntryOverlay)
import Application.Helper.FrontendContract.AppShell.Request (appShellActionFields)
import Application.Helper.FrontendContract.AppShell.Runtime (AppShellActionRoute (..),
                                                             AppShellFieldValue (..),
                                                             appShellActionByMarker,
                                                             defaultAppShellActionRoute,
                                                             renderAppShellActionForm)
import Application.Helper.FrontendContract.Surface.Values (noSurfaceFields,
                                                           surfaceField,
                                                           surfaceFieldsText,
                                                           surfaceOptionalField,
                                                           (&:))
import Application.VenueTime.Model (timesheetEntryOperationalDate)
import Web.Timesheets.Filters (TimesheetViewFilters)
import Web.Timesheets.Paths (timesheetWindowStateQueryParamsWithFilters,
                             timesheetWindowUrlWithFilters)
import Web.View.Prelude

newtype EditView = EditView
    { timesheetFormInputs :: TimesheetFormInputs
    }

instance View EditView where
    html EditView { timesheetFormInputs } =
        renderTimesheetEntryModalWithStartButtons
            GuardChangedTimesheet
            (timesheetModalTitle operationalDate)
            (timesheetWindowUrlWithFilters operationalDate timesheetFormInputs.viewFilters)
            editTimesheetFormId
            (renderTimesheetForm (editTimesheetFormRenderModel PageOverlayForm timesheetFormInputs))
            (deleteButtonsFor timesheetFormInputs.timesheetEntry timesheetFormInputs.calendarRevision timesheetFormInputs.viewFilters)
      where
        operationalDate = timesheetEntryOperationalDate timesheetFormInputs.timesheetEntry

editTimesheetFormId :: Text
editTimesheetFormId = "timesheet-entry-edit-form"

renderEditTimesheetDialog :: TimesheetFormInputs -> Html
renderEditTimesheetDialog timesheetFormInputs =
    renderTimesheetEntryDialogWithStartButtons
        GuardChangedTimesheet
        (timesheetModalTitle (timesheetEntryOperationalDate timesheetFormInputs.timesheetEntry))
        editTimesheetFormId
        (renderTimesheetForm (editTimesheetFormRenderModel HtmxOverlayForm timesheetFormInputs))
        (deleteButtonsFor timesheetFormInputs.timesheetEntry timesheetFormInputs.calendarRevision timesheetFormInputs.viewFilters)

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
                , formSurfaceAction = Nothing
                }
        }

timesheetEntryFormOrigin :: TimesheetEntry -> TimesheetFormOrigin
timesheetEntryFormOrigin timesheetEntry
    | isJust timesheetEntry.sourceRosterSlotId = RosteredTimesheetEntryForm
    | otherwise = AdHocTimesheetForm

deleteButtonsFor :: TimesheetEntry -> Int -> TimesheetViewFilters -> [OverlayButton]
deleteButtonsFor timesheetEntry calendarRevision selectedStaffFilterId =
    [ OverlayButton
        { overlayButtonLabel = "Delete"
        , overlayButtonClass = "btn btn-outline-danger"
        , overlayButtonAction =
            GeneratedDialogFormAction
                (appShellActionByMarker @OpenTimesheetDeleteConfirmationDialog)
                (defaultAppShellActionRoute confirmationUrl)
                requestParams
        }
    ]
    where
        requestParams = timesheetDeleteRequestParams timesheetEntry calendarRevision selectedStaffFilterId
        -- The form submits calendar/filter fields; the GET URL must not duplicate them.
        confirmationUrl = pathTo (ShowTimesheetEntryDeleteConfirmationAction (get #id timesheetEntry))

renderTimesheetDeleteConfirmation :: (?context :: ControllerContext) => TimesheetEntry -> Int -> TimesheetViewFilters -> Html
renderTimesheetDeleteConfirmation timesheetEntry calendarRevision selectedStaffFilterId =
    renderConfirmationDialog
        (defaultConfirmationDialogConfig
            "Delete timesheet entry?"
            [hsx|<p class="mb-0">Delete this timesheet entry? This cannot be undone.</p>|]
            formId
            deleteForm)
            { confirmationDialogApproveLabel = "Delete"
            , confirmationDialogApproveTone = ConfirmationDanger
            , confirmationDialogLoadingLabel = "Deleting…"
            , confirmationDialogRejectButton = reopenEditButton
            }
  where
    formId = "delete-timesheet-entry-confirmation-form"
    requestParams = filter (not . null . snd) (timesheetWindowStateQueryParamsWithFilters (timesheetEntryOperationalDate timesheetEntry) selectedStaffFilterId) <> [("rosterCalendarRevision", tshow calendarRevision)]
    -- Retain DELETE's query-based calendar context; Cancel's GET form submits
    -- hidden fields. Neither request duplicates scalars across URL and form.
    deleteUrl = appendQueryParams (pathTo (DeleteTimesheetEntryAction (get #id timesheetEntry))) requestParams
    editUrl = pathTo (EditTimesheetEntryAction (get #id timesheetEntry))
    deleteForm =
        renderAppShellActionForm
            (appShellActionByMarker @DeleteTimesheetEntryOverlay)
            ((defaultAppShellActionRoute deleteUrl)
                { appShellActionRouteFields = [AppShellFieldValue ("_method", "DELETE")]
                , appShellActionRouteExtraAttrs = [("id", formId)]
                })
            mempty
    reopenEditButton = OverlayButton
        { overlayButtonLabel = "Cancel"
        , overlayButtonClass = "btn btn-outline-secondary"
        , overlayButtonAction = GeneratedDialogFormAction
            (appShellActionByMarker @EditTimesheetEntryDialog)
            (defaultAppShellActionRoute editUrl)
            requestParams
        }

timesheetDeleteRequestParams :: TimesheetEntry -> Int -> TimesheetViewFilters -> [(Text, Text)]
timesheetDeleteRequestParams timesheetEntry calendarRevision filters =
    filter (not . null . snd) (timesheetWindowStateQueryParamsWithFilters (timesheetEntryOperationalDate timesheetEntry) filters)
        <> [("rosterCalendarRevision", tshow calendarRevision)]
