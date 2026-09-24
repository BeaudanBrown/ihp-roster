{-# LANGUAGE TypeApplications #-}

module Web.View.Timesheets.RosterPrefillNew where

import Application.Helper.FrontendContract.AppShell (CreateTimesheetEntryOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (appShellActionByMarker)
import Application.VenueTime.Model (timesheetEntryOperationalDate)
import Web.Timesheets.Paths (timesheetWindowUrl)
import Web.View.Prelude

data RosterPrefillTimesheetRenderModel = RosterPrefillTimesheetRenderModel
    { rosterSlotId        :: Id RosterSlot
    , timesheetFormInputs :: TimesheetFormInputs
    }

newtype RosterPrefillNewView = RosterPrefillNewView
    { rosterPrefillTimesheetRenderModel :: RosterPrefillTimesheetRenderModel
    }

instance View RosterPrefillNewView where
    html RosterPrefillNewView { rosterPrefillTimesheetRenderModel } =
        renderTimesheetEntryModal
            ("Rostered " <> timesheetModalTitle operationalDate)
            (timesheetWindowUrl operationalDate inputs.selectedStaffFilterId)
            rosterPrefillTimesheetFormId
            (renderRosterPrefillTimesheetForm PageOverlayForm rosterPrefillTimesheetRenderModel)
      where
        inputs = rosterPrefillTimesheetRenderModel.timesheetFormInputs
        operationalDate = timesheetEntryOperationalDate inputs.timesheetEntry

rosterPrefillTimesheetFormId :: Text
rosterPrefillTimesheetFormId = "timesheet-roster-prefill-create-form"

renderRosterPrefillTimesheetDialog :: RosterPrefillTimesheetRenderModel -> Html
renderRosterPrefillTimesheetDialog rosterPrefillTimesheetRenderModel =
    renderTimesheetEntryDialog
        GuardNewTimesheet
        ("Rostered " <> timesheetModalTitle operationalDate)
        rosterPrefillTimesheetFormId
        (renderRosterPrefillTimesheetForm HtmxOverlayForm rosterPrefillTimesheetRenderModel)
  where
    operationalDate = timesheetEntryOperationalDate rosterPrefillTimesheetRenderModel.timesheetFormInputs.timesheetEntry

renderRosterPrefillTimesheetForm :: (?context :: ControllerContext) => OverlayFormMode -> RosterPrefillTimesheetRenderModel -> Html
renderRosterPrefillTimesheetForm formMode RosterPrefillTimesheetRenderModel { rosterSlotId, timesheetFormInputs } =
    renderTimesheetForm
        TimesheetFormRenderModel
            { timesheetFormInputs
            , timesheetFormPresentation =
                TimesheetFormPresentation
                    { appShellAction = appShellActionByMarker @CreateTimesheetEntryOverlay
                    , formOrigin = RosteredTimesheetForm
                    , actionUrl = pathTo CreateTimesheetEntryFromRosterShiftAction { rosterSlotId }
                    , formId = rosterPrefillTimesheetFormId
                    , formMode
                    }
            }
