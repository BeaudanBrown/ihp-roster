{-# LANGUAGE TypeApplications #-}

module Web.View.Timesheets.SuggestedNew where

import Application.Helper.FrontendContract.AppShell (CreateTimesheetEntryOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime (appShellActionByMarker)
import Application.VenueTime.Model (timesheetEntryOperationalDate)
import Web.Timesheets.Paths (timesheetWindowUrl)
import Web.View.Prelude

data SuggestedTimesheetRenderModel = SuggestedTimesheetRenderModel
    { rosterSlotId        :: Id RosterSlot
    , timesheetFormInputs :: TimesheetFormInputs
    }

newtype SuggestedNewView = SuggestedNewView
    { suggestedTimesheetRenderModel :: SuggestedTimesheetRenderModel
    }

instance View SuggestedNewView where
    html SuggestedNewView { suggestedTimesheetRenderModel } =
        renderTimesheetEntryModal
            ("Rostered " <> timesheetModalTitle operationalDate)
            (timesheetWindowUrl operationalDate inputs.selectedStaffFilterId)
            suggestedTimesheetFormId
            (renderSuggestedTimesheetForm PageOverlayForm suggestedTimesheetRenderModel)
      where
        inputs = suggestedTimesheetRenderModel.timesheetFormInputs
        operationalDate = timesheetEntryOperationalDate inputs.timesheetEntry

suggestedTimesheetFormId :: Text
suggestedTimesheetFormId = "timesheet-suggestion-create-form"

renderSuggestedTimesheetDialog :: SuggestedTimesheetRenderModel -> Html
renderSuggestedTimesheetDialog suggestedTimesheetRenderModel =
    renderTimesheetEntryDialog
        ("Rostered " <> timesheetModalTitle operationalDate)
        suggestedTimesheetFormId
        (renderSuggestedTimesheetForm HtmxOverlayForm suggestedTimesheetRenderModel)
  where
    operationalDate = timesheetEntryOperationalDate suggestedTimesheetRenderModel.timesheetFormInputs.timesheetEntry

renderSuggestedTimesheetForm :: (?context :: ControllerContext) => OverlayFormMode -> SuggestedTimesheetRenderModel -> Html
renderSuggestedTimesheetForm formMode SuggestedTimesheetRenderModel { rosterSlotId, timesheetFormInputs } =
    renderTimesheetForm
        TimesheetFormRenderModel
            { timesheetFormInputs
            , timesheetFormPresentation =
                TimesheetFormPresentation
                    { appShellAction = appShellActionByMarker @CreateTimesheetEntryOverlay
                    , formOrigin = RosteredTimesheetForm
                    , actionUrl = pathTo CreateTimesheetEntryFromSuggestionAction { rosterSlotId }
                    , formId = suggestedTimesheetFormId
                    , formMode
                    }
            }
