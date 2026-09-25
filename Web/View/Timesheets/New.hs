{-# LANGUAGE TypeApplications #-}

module Web.View.Timesheets.New where

import Application.Helper.FrontendContract.AppShell (CreateTimesheetEntryOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (appShellActionByMarker)
import Application.VenueTime.Model (timesheetEntryOperationalDate)
import Web.Timesheets.Paths (timesheetWindowUrl)
import Web.View.Prelude

newtype NewTimesheetRenderModel = NewTimesheetRenderModel
    { timesheetFormInputs :: TimesheetFormInputs
    }

newtype NewView = NewView
    { newTimesheetRenderModel :: NewTimesheetRenderModel
    }

instance View NewView where
    html NewView { newTimesheetRenderModel } =
        renderTimesheetEntryModal
            GuardNewTimesheet
            (timesheetModalTitle operationalDate)
            (timesheetWindowUrl operationalDate inputs.selectedStaffFilterId)
            newTimesheetFormId
            (renderTimesheetForm (newTimesheetFormRenderModel PageOverlayForm newTimesheetRenderModel))
      where
        inputs = newTimesheetRenderModel.timesheetFormInputs
        operationalDate = timesheetEntryOperationalDate inputs.timesheetEntry

newTimesheetFormId :: Text
newTimesheetFormId = "timesheet-entry-create-form"

renderNewTimesheetDialog :: NewTimesheetRenderModel -> Html
renderNewTimesheetDialog newTimesheetRenderModel =
    renderTimesheetEntryDialog
        GuardNewTimesheet
        (timesheetModalTitle operationalDate)
        newTimesheetFormId
        (renderTimesheetForm (newTimesheetFormRenderModel HtmxOverlayForm newTimesheetRenderModel))
  where
    operationalDate = timesheetEntryOperationalDate newTimesheetRenderModel.timesheetFormInputs.timesheetEntry

newTimesheetFormRenderModel :: OverlayFormMode -> NewTimesheetRenderModel -> TimesheetFormRenderModel
newTimesheetFormRenderModel formMode NewTimesheetRenderModel { timesheetFormInputs } =
    TimesheetFormRenderModel
        { timesheetFormInputs
        , timesheetFormPresentation =
            TimesheetFormPresentation
                { appShellAction = appShellActionByMarker @CreateTimesheetEntryOverlay
                , formOrigin = AdHocTimesheetForm
                , actionUrl = pathTo CreateTimesheetEntryAction
                , formId = newTimesheetFormId
                , formMode
                , formSurfaceAction = Nothing
                }
        }
