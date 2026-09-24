{-# LANGUAGE TypeApplications #-}

module Web.View.Timesheets.RosterPrefillNew where

import Application.Helper.FrontendContract.AppShell (CreateTimesheetEntryOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (appShellActionByMarker)
import Application.Helper.FrontendContract.LiveUpdateValues (surfaceActionDomAttribute)
import Application.Helper.FrontendContract.Surface.Runtime (defaultFrontendSurfaceActionRoute,
                                                            frontendSurfaceActionAttrs)
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Action as TimesheetsAction
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
            GuardNewTimesheet
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
                    , actionUrl
                    , formId = rosterPrefillTimesheetFormId
                    , formMode
                    , formExtraAttrs = filter ((== surfaceActionDomAttribute) . fst) (frontendSurfaceActionAttrs surfaceAction (defaultFrontendSurfaceActionRoute actionUrl))
                    }
            }
  where
    actionUrl = pathTo CreateTimesheetEntryFromRosterShiftAction { rosterSlotId }
    surfaceAction =
        TimesheetsAction.createTimesheetEntryFromRosterShiftAction
            (TimesheetsAction.createTimesheetEntryFromRosterShiftActionFields timesheetFormInputs.timesheetEntry.operationalDate timesheetFormInputs.calendarRevision timesheetFormInputs.selectedStaffFilterId)
