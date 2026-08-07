{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Web.View.Admin.Xero.TimesheetPreparation.Review
    ( renderPreparationPreview
    , renderPreparationReview
    , renderReconciliationNotices
    , renderReconciliationReview
    ) where

import Application.Helper.XeroAdminTypes
import Data.Scientific (FPFormat (Fixed), Scientific, formatScientific,
                        scientific)
import qualified Data.Text as Text
import qualified Text.Blaze.Html as Blaze
import Web.View.Prelude

renderPreparationReview :: XeroTimesheetPreparationView -> Html
renderPreparationReview view = [hsx|
    {renderFinalSummaryCards view}
    {renderReviewReadiness view}
    {renderReviewSummary view}
|]

renderReconciliationReview :: XeroTimesheetPreparationView -> Html
renderReconciliationReview = renderReconciliationNotices . (.preparationReconciliationNotices)

renderReconciliationNotices :: [XeroTimesheetIssueView] -> Blaze.Html
renderReconciliationNotices notices
    | null notices = [hsx|
        <div class="alert alert-info mb-0">Xero was checked again. Bepis will create missing drafts and update only confirmed Xero drafts.</div>
    |]
    | otherwise = [hsx|
        <section>
            <h6 class="mb-2">Latest Xero check</h6>
            <div class="d-flex flex-column gap-2">{forEach notices renderReconciliationNotice}</div>
        </section>
    |]

renderReconciliationNotice :: XeroTimesheetIssueView -> Blaze.Html
renderReconciliationNotice notice = [hsx|
    <div class={classes [("alert mb-0", True), ("alert-danger", notice.timesheetIssueSeverity == "blocker"), ("alert-warning", notice.timesheetIssueSeverity /= "blocker")]}>
        {notice.timesheetIssueMessage}
    </div>
|]

renderFinalSummaryCards :: XeroTimesheetPreparationView -> Html
renderFinalSummaryCards view = [hsx|
    <div class="row g-2">
        {renderSummaryCard "Employees" (tshow (length view.preparationReviewRows))}
        {renderSummaryCard "Approved shifts" (tshow (sum (map (.reviewRowEntryCount) view.preparationReviewRows)))}
        {renderSummaryCard "Total hours" (formatPreparationUnits (sum (map (.reviewRowTotalUnits) view.preparationReviewRows)))}
        {renderSummaryCard "Estimated wages" (formatMoney (sum (map (.reviewRowTotalAmount) view.preparationReviewRows)))}
    </div>
|]

renderSummaryCard :: Text -> Text -> Html
renderSummaryCard label value = [hsx|
    <div class="col-6 col-lg-3">
        <div class={appSurfaceClasses "p-3 h-100"}>
            <div class="small app-muted">{label}</div>
            <div class="fs-5 fw-semibold">{value}</div>
        </div>
    </div>
|]

renderReviewSummary :: XeroTimesheetPreparationView -> Html
renderReviewSummary view
    | null view.preparationReviewRows = [hsx|
        <section>
            <h6 class="mb-2">Timesheet summary</h6>
            <div class={appSurfaceClasses "p-3 small app-muted"}>
                No Xero-paid staff with approved shifts were found for this pay period.
            </div>
        </section>
    |]
    | otherwise = [hsx|
        <section>
            <h6 class="mb-2">Timesheet summary</h6>
            <div class="table-responsive">
                <table class="table table-sm align-middle mb-0">
                    <thead>
                        <tr>
                            <th>Staff member</th>
                            <th class="text-end">Approved shifts</th>
                            <th class="text-end">Hours</th>
                            <th class="text-end">Estimated wages</th>
                        </tr>
                    </thead>
                    <tbody>{forEach view.preparationReviewRows renderReviewRow}</tbody>
                </table>
            </div>
        </section>
    |]

renderReviewRow :: XeroPreparationReviewRow -> Html
renderReviewRow row = [hsx|
    <tr>
        <td><div class="fw-semibold">{staffName row.reviewRowStaff}</div></td>
        <td class="text-end">{tshow row.reviewRowEntryCount}</td>
        <td class="text-end">{formatPreparationUnits row.reviewRowTotalUnits}</td>
        <td class="text-end">{formatMoney row.reviewRowTotalAmount}</td>
    </tr>
|]

renderReviewReadiness :: XeroTimesheetPreparationView -> Html
renderReviewReadiness view
    | null actionableBlockers = mempty
    | otherwise = [hsx|
        <section>
            <h6 class="mb-2">Needs attention</h6>
            {renderIssues "Blockers" actionableBlockers}
        </section>
    |]
    where
        actionableBlockers = filter reviewActionableBlocker view.preparationReadiness.timesheetReadinessBlockers

reviewActionableBlocker :: XeroTimesheetIssueView -> Bool
reviewActionableBlocker issue =
    issue.timesheetIssueCode /= "managed_pay_item_not_ready"

renderIssues :: Text -> [XeroTimesheetIssueView] -> Html
renderIssues title [] = [hsx|<div class="small app-muted">{title}: none</div>|]
renderIssues title issues = [hsx|
    <div class="small mb-2">
        <div class="fw-semibold mb-1">{title}</div>
        <div class="d-flex flex-wrap gap-2">{forEach issues renderIssue}</div>
    </div>
|]

renderIssue :: XeroTimesheetIssueView -> Html
renderIssue issue = [hsx|
    <span class={classes [("badge text-wrap text-start lh-base", True), ("text-bg-danger", issue.timesheetIssueSeverity == "blocker"), ("text-bg-warning", issue.timesheetIssueSeverity /= "blocker")]}>
        {issue.timesheetIssueMessage}
    </span>
|]

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

formatPreparationUnits :: Rational -> Text
formatPreparationUnits = formatUnits . rationalToScientificAt 2

rationalToScientificAt :: Int -> Rational -> Scientific
rationalToScientificAt decimalPlaces value =
    scientific (round (value * fromInteger scale)) (negate decimalPlaces)
    where
        scale :: Integer
        scale = 10 ^ decimalPlaces

formatMoney :: Scientific -> Text
formatMoney value = "$" <> cs (formatScientific Fixed (Just 2) value)
staffName :: Staff -> Text
staffName staff = Text.strip (staff.firstName <> " " <> staff.lastName)
