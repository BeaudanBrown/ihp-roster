module Web.View.Admin.Xero.ShiftSelection (renderSelection, renderChooseXeroShiftsButton) where

import qualified Application.Helper.FrontendContract.AppShell as Shell
import Application.Helper.FrontendContract.AppShell.Request
import Application.Helper.FrontendContract.AppShell.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.View.Overlay
import Web.View.Prelude
import Web.View.TimesheetSelection

renderSelection :: XeroTimesheetPreparationRun -> [TimesheetSelectionRow] -> [Text] -> Maybe Text -> Html
renderSelection run rows selected message = renderDialogOverlay DialogOverlayConfig
    { dialogOverlayTitle = "Choose shifts for Xero"
    , dialogOverlayBody = renderAppShellActionForm
        (appShellActionByMarker @Shell.RefreshXeroShiftSelection)
        ((defaultAppShellActionRoute (pathTo (RefreshXeroShiftSelectionAction run.id))) { appShellActionRouteExtraAttrs = [("id", "timesheet-selection-form")] })
        [hsx|
            {maybe mempty renderError message}
            <p>Only selected shifts contribute to pay-item preparation, preview and upload.</p>
            <input type="hidden" name={surfaceFieldNameFrom @Shell.SelectionRunUpdatedAtField fields} value={tshow run.updatedAt} />
            {renderTimesheetSelectionChecklist (surfaceFieldNameFrom @Shell.SelectedTimesheetEntriesField fields) rows selected groupControl}
            <button {...saveAttrs} disabled={null selected}>Use selected shifts</button>
        |]
    , dialogOverlayStartButtons = []
    , dialogOverlayButtons = [dialogOverlayCloseButton "Cancel"]
    , dialogOverlayDialogClass = "modal-lg"
    }
  where
    renderError text = [hsx|<p class="alert alert-warning" role="alert">{text}</p>|]
    fields = appShellActionFields @Shell.RefreshXeroShiftSelection
        (surfaceField @Shell.SelectionRunUpdatedAtField (tshow run.updatedAt))
        (surfaceField @Shell.SelectedTimesheetEntriesField selected &: noSurfaceFields)
    buttonRoute url = (defaultAppShellActionRoute url) { appShellActionRouteExtraAttrs = [("type", "button"), ("class", "btn btn-outline-primary")] }
    saveAttrs = appShellActionAttrs (appShellActionByMarker @Shell.SaveXeroShiftSelection) (buttonRoute (pathTo (SaveXeroShiftSelectionAction run.id)))
    groupControl day select = [hsx|<button {...attributes}>{label}</button>|]
      where
        attributes = appShellActionAttrs (appShellActionByMarker @Shell.ChangeXeroShiftSelectionGroup) (buttonRoute (pathTo (ChangeXeroShiftSelectionGroupAction run.id (tshow <$> day) select)))
        label = (if select then "Select " else "Clear ") <> (if isNothing day then "all" else "day") :: Text

renderChooseXeroShiftsButton :: Id XeroTimesheetPreparationRun -> Html
renderChooseXeroShiftsButton runId = [hsx|<button {...attributes}>Choose shifts…</button>|]
  where
    attributes = appShellActionAttrs (appShellActionByMarker @Shell.OpenXeroShiftSelection)
        ((defaultAppShellActionRoute (pathTo (OpenXeroShiftSelectionAction runId)))
            { appShellActionRouteExtraAttrs = [("type", "button"), ("class", "btn btn-outline-primary")] })
