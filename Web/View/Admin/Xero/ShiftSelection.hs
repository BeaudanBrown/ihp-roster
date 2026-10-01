module Web.View.Admin.Xero.ShiftSelection (renderSelection, shiftSelectionBackButton) where

import qualified Application.Helper.FrontendContract.AppShell as Shell
import Application.Helper.FrontendContract.AppShell.Request
import Application.Helper.FrontendContract.AppShell.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Web.View.Prelude
import Web.View.TimesheetSelection

renderSelection :: XeroTimesheetPreparationRun -> [TimesheetSelectionRow] -> [Text] -> Maybe Text -> Html
renderSelection run rows selected message = renderTimesheetSelectionDialog TimesheetSelectionDialog
    { selectionDialogTitle = "Choose shifts for Xero"
    , selectionDialogBody = renderAppShellActionForm
        (appShellActionByMarker @Shell.SubmitXeroShiftSelection)
        ((defaultAppShellActionRoute (pathTo (SubmitXeroShiftSelectionAction run.id))) { appShellActionRouteExtraAttrs = timesheetSelectionFormAttributes })
        [hsx|
            {maybe mempty renderError message}
            <input type="hidden" name={surfaceFieldNameFrom @Shell.SelectionRunUpdatedAtField fields} value={tshow run.updatedAt} />
            {renderTimesheetSelectionChecklist (surfaceFieldNameFrom @Shell.SelectedTimesheetEntriesField fields) rows selected}
        |]
    , selectionDialogSubmitLabel = "Confirm and submit"
    , selectionDialogLoadingLabel = "Submitting to Xero…"
    , selectionDialogHasSelection = not (null selected)
    }
  where
    renderError text = [hsx|<p class="alert alert-warning" role="alert">{text}</p>|]
    fields = appShellActionFields @Shell.RefreshXeroShiftSelection
        (surfaceField @Shell.SelectionRunUpdatedAtField (tshow run.updatedAt))
        (surfaceField @Shell.SelectedTimesheetEntriesField selected &: noSurfaceFields)

shiftSelectionBackButton :: Id XeroTimesheetPreparationRun -> OverlayButton
shiftSelectionBackButton runId = OverlayButton
    { overlayButtonLabel = "Back"
    , overlayButtonClass = "btn btn-outline-secondary"
    , overlayButtonAction = GeneratedDialogButtonAction
        (appShellActionByMarker @Shell.OpenXeroShiftSelection)
        (defaultAppShellActionRoute (pathTo (OpenXeroShiftSelectionAction runId)))
        True
    }
