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
                                                           (&:))
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
        GuardChangedTimesheet
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
                (appShellActionByMarker @OpenTimesheetDeleteConfirmationDialog)
                (defaultAppShellActionRoute confirmationUrl)
                requestParams
        }
    ]
    where
        requestParams = timesheetDeleteRequestParams timesheetEntry calendarRevision selectedStaffFilterId
        confirmationUrl = pathTo (ShowTimesheetEntryDeleteConfirmationAction (get #id timesheetEntry))

renderTimesheetDeleteConfirmation :: (?context :: ControllerContext) => TimesheetEntry -> Int -> Maybe UUID -> Html
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
    requestParams = timesheetWindowStateQueryParams (timesheetEntryOperationalDate timesheetEntry) selectedStaffFilterId <> [("rosterCalendarRevision", tshow calendarRevision)]
    deleteUrl = appendQueryParams (pathTo (DeleteTimesheetEntryAction (get #id timesheetEntry))) requestParams
    editUrl = appendQueryParams (pathTo (EditTimesheetEntryAction (get #id timesheetEntry))) requestParams
    deleteForm =
        renderAppShellActionForm
            (appShellActionByMarker @DeleteTimesheetEntryOverlay)
            ((defaultAppShellActionRoute deleteUrl)
                { appShellActionRouteFields = AppShellFieldValue ("_method", "DELETE") : fmap AppShellFieldValue requestParams
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

timesheetDeleteRequestParams :: TimesheetEntry -> Int -> Maybe UUID -> [(Text, Text)]
timesheetDeleteRequestParams timesheetEntry calendarRevision selectedStaffFilterId =
    surfaceFieldsText $
        appShellActionFields @OpenTimesheetDeleteConfirmationDialog
            (surfaceField @AnchorDateField (tshow (timesheetEntryOperationalDate timesheetEntry) :: Text))
            ( surfaceField @RosterCalendarRevisionField (tshow calendarRevision)
                &: surfaceField @StaffFilterIdField (maybe "" tshow selectedStaffFilterId)
                &: noSurfaceFields
            )
