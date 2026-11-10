module Web.View.Admin.ExportFailure
    ( ExportFailureView (..)
    , exportFailureDialog
    ) where

import Application.Helper.Export.Failure
import Application.Helper.View.Overlay
import Web.View.Prelude

data ExportFailureView = ExportFailureView
    { failures :: [ExportEntryFailure]
    }

instance View ExportFailureView where
    html view = renderPageDialogModal (pathTo AdminAction) (exportFailureDialog view.failures)

exportFailureDialog :: [ExportEntryFailure] -> DialogOverlayConfig
exportFailureDialog failures =
    (defaultDialogOverlayConfig "Payroll export blocked" body [dialogOverlayCloseButton "Close"])
        { dialogOverlayDialogClass = "modal-dialog-scrollable" }
  where
    body = [hsx|
        <p>No payroll file was generated. Review these timesheets:</p>
        <ul>{forEach failures renderFailure}</ul>
        <p>If the recorded times are correct, contact support. Do not change valid times to bypass this check.</p>
    |]
    renderFailure failure = [hsx|
        <li>
            <a href={pathTo (EditTimesheetEntryAction failure.entryFailureId)}>{fromMaybe "Timesheet" failure.entryFailureStaffName} — {failure.entryFailureDate}</a>
            {renderInterval failure}
            <p>{failure.entryFailureMessage}</p>
        </li>
    |]
    renderInterval failure = case (failure.entryFailureStart, failure.entryFailureEnd) of
        (Just start, Just end) -> [hsx|<p>{start} to {end}</p>|]
        _ -> mempty
