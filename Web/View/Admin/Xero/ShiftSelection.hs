module Web.View.Admin.Xero.ShiftSelection (renderSelection, renderChooseXeroShiftsButton) where

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
        (appShellActionByMarker @Shell.SaveXeroShiftSelection)
        ((defaultAppShellActionRoute (pathTo (SaveXeroShiftSelectionAction run.id))) { appShellActionRouteExtraAttrs = timesheetSelectionFormAttributes })
        [hsx|
            {maybe mempty renderError message}
            <input type="hidden" name={surfaceFieldNameFrom @Shell.SelectionRunUpdatedAtField fields} value={tshow run.updatedAt} />
            {renderTimesheetSelectionChecklist (surfaceFieldNameFrom @Shell.SelectedTimesheetEntriesField fields) rows selected}
        |]
    , selectionDialogSubmitLabel = "Use selected shifts"
    , selectionDialogSubmitAction = appShellActionByMarker @Shell.SaveXeroShiftSelection
    , selectionDialogSubmitRoute = defaultAppShellActionRoute (pathTo (SaveXeroShiftSelectionAction run.id))
    , selectionDialogHasSelection = not (null selected)
    }
  where
    renderError text = [hsx|<p class="alert alert-warning" role="alert">{text}</p>|]
    fields = appShellActionFields @Shell.RefreshXeroShiftSelection
        (surfaceField @Shell.SelectionRunUpdatedAtField (tshow run.updatedAt))
        (surfaceField @Shell.SelectedTimesheetEntriesField selected &: noSurfaceFields)

renderChooseXeroShiftsButton :: Id XeroTimesheetPreparationRun -> Html
renderChooseXeroShiftsButton runId = [hsx|<button {...attributes}>Choose shifts…</button>|]
  where
    attributes = appShellActionAttrs (appShellActionByMarker @Shell.OpenXeroShiftSelection)
        ((defaultAppShellActionRoute (pathTo (OpenXeroShiftSelectionAction runId)))
            { appShellActionRouteExtraAttrs = [("type", "button"), ("class", "btn btn-outline-primary")] })
