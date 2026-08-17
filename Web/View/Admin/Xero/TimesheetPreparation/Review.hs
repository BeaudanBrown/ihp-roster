{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.Xero.TimesheetPreparation.Review
    ( renderPreparationPreview
    ) where

import Application.Helper.XeroAdminTypes
import Data.Scientific (FPFormat (Fixed), Scientific, formatScientific)
import qualified Data.Text as Text
import Web.View.Prelude

renderPreparationPreview :: XeroTimesheetPreparationView -> Html
renderPreparationPreview view
    | null view.preparationPreviewRows = mempty
    | otherwise = [hsx|
        <section>
            <h6 class="mb-2">Preview</h6>
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <thead>
                        <tr>
                            <th>Employee</th>
                            <th>Action</th>
                            <th class="text-end">Units</th>
                            <th>Earnings lines</th>
                        </tr>
                    </thead>
                    <tbody>{forEach view.preparationPreviewRows renderPreviewRow}</tbody>
                </table>
            </div>
        </section>
    |]

renderPreviewRow :: XeroTimesheetPreviewRowView -> Html
renderPreviewRow row = [hsx|
    <tr>
        <td>
            <div class="fw-semibold">{row.previewRowEmployeeName}</div>
            <div class="small app-muted">{row.previewRowXeroEmployeeId}</div>
        </td>
        <td>{renderPreviewOperation row}</td>
        <td class="text-end">{formatUnits row.previewRowTotalUnits}</td>
        <td>{Text.intercalate ", " (map lineSummary row.previewRowLines)}</td>
    </tr>
|]

renderPreviewOperation :: XeroTimesheetPreviewRowView -> Html
renderPreviewOperation row
    | row.previewRowOperation == "update" = [hsx|
        <div>
            <span class="badge text-bg-info">Update existing draft</span>
            {renderPreviewXeroTimesheetId row.previewRowXeroTimesheetId}
        </div>
    |]
    | otherwise = [hsx|<span class="badge text-bg-success">Create new draft</span>|]

renderPreviewXeroTimesheetId :: Maybe Text -> Html
renderPreviewXeroTimesheetId Nothing = mempty
renderPreviewXeroTimesheetId (Just timesheetId) = [hsx|<div class="small app-muted">{timesheetId}</div>|]

lineSummary :: XeroTimesheetPreviewLineView -> Text
lineSummary line =
    line.previewLineViewEarningsRateName <> " (" <> formatUnits line.previewLineViewTotalUnits <> ")"

formatUnits :: Scientific -> Text
formatUnits value = cs (formatScientific Fixed (Just 2) value)
