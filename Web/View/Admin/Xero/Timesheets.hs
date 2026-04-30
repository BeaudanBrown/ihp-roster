module Web.View.Admin.Xero.Timesheets
    ( renderXeroTimesheetPanel
    ) where

import Application.Helper.XeroAdminTypes
import qualified Data.List as List
import Data.Scientific (FPFormat (Fixed), Scientific, formatScientific)
import qualified Data.Text as Text
import Web.View.Admin.Common (formatTimestamp)
import Web.View.Prelude

renderXeroTimesheetPanel :: XeroTimesheetPanelData -> Html
renderXeroTimesheetPanel panel = [hsx|
    <div class="d-flex flex-column gap-3">
        <div class="d-flex flex-column flex-lg-row justify-content-between gap-3">
            <div>
                <h3 class="h6 mb-1">Draft timesheet submission</h3>
                <div class="small app-muted">Create Xero Payroll AU draft timesheets from approved IHP timesheets for the selected payroll calendar period.</div>
            </div>
            <div class="d-flex flex-wrap gap-2 align-items-start">
                {renderPreviewButton panel}
                {renderSubmitButton panel}
            </div>
        </div>
        {renderPeriodNotice panel}
        {maybe mempty renderReadiness panel.xeroTimesheetReadiness}
        {maybe renderEmptyLatestRun renderLatestRun panel.xeroTimesheetLatestRun}
    </div>
|]

renderPreviewButton :: XeroTimesheetPanelData -> Html
renderPreviewButton panel = [hsx|
    <form method="POST" action={PreviewXeroDraftTimesheetsAction}>
        <button type="submit"
                class="btn btn-sm btn-outline-primary"
                disabled={not (canPreview panel)}
                hx-post={pathTo PreviewXeroDraftTimesheetsAction}
                hx-target="#admin-xero-fragment"
                hx-swap="outerHTML">
            Preview draft timesheets
        </button>
    </form>
|]

renderSubmitButton :: XeroTimesheetPanelData -> Html
renderSubmitButton panel = [hsx|
    <form method="POST" action={SubmitXeroDraftTimesheetsAction}>
        <button type="submit"
                class="btn btn-sm btn-primary"
                disabled={not (canPreview panel)}
                hx-post={pathTo SubmitXeroDraftTimesheetsAction}
                hx-target="#admin-xero-fragment"
                hx-swap="outerHTML">
            Submit drafts to Xero
        </button>
    </form>
|]

canPreview :: XeroTimesheetPanelData -> Bool
canPreview panel =
    panel.xeroTimesheetActionsAllowed
        && maybe False (.timesheetReadinessReady) panel.xeroTimesheetReadiness

renderPeriodNotice :: XeroTimesheetPanelData -> Html
renderPeriodNotice panel =
    case panel.xeroTimesheetPeriodMessage of
        Just message -> [hsx|<div class="alert alert-secondary mb-0 small">{message}</div>|]
        Nothing ->
            case panel.xeroTimesheetReadiness of
                Nothing -> mempty
                Just readiness -> [hsx|
                    <div class="border rounded p-3 small">
                        <span class="fw-semibold">Selected Xero payroll period:</span>
                        {formatDateDisplay readiness.timesheetReadinessPeriodStart} to {formatDateDisplay readiness.timesheetReadinessPeriodEnd}
                        <span class="app-muted ms-2">{tshow readiness.timesheetReadinessEntryCount} approved entries, {tshow readiness.timesheetReadinessStaffCount} staff, {tshow readiness.timesheetReadinessBucketCount} earnings buckets</span>
                    </div>
                |]

renderReadiness :: XeroTimesheetReadinessView -> Html
renderReadiness readiness = [hsx|
    <div class="border rounded p-3">
        <div class="d-flex align-items-center justify-content-between gap-2 mb-2">
            <h4 class="h6 mb-0">Readiness</h4>
            {renderReadinessBadge readiness.timesheetReadinessReady}
        </div>
        {renderIssues "Blockers" "No blockers for this period." "danger" readiness.timesheetReadinessBlockers}
        {renderIssues "Warnings" "No warnings for this period." "warning" readiness.timesheetReadinessWarnings}
    </div>
|]

renderReadinessBadge :: Bool -> Html
renderReadinessBadge True = [hsx|<span class="badge text-bg-success">ready</span>|]
renderReadinessBadge False = [hsx|<span class="badge text-bg-danger">blocked</span>|]

renderIssues :: Text -> Text -> Text -> [XeroTimesheetIssueView] -> Html
renderIssues title emptyText tone issues = [hsx|
    <div class="small mb-2">
        <div class="fw-semibold mb-1">{title}</div>
        {renderIssueList emptyText tone issues}
    </div>
|]

renderIssueList :: Text -> Text -> [XeroTimesheetIssueView] -> Html
renderIssueList emptyText _ [] = [hsx|<div class="app-muted">{emptyText}</div>|]
renderIssueList _ tone issues = [hsx|<div class="d-flex flex-column gap-2">{forEach issues (renderIssue tone)}</div>|]

renderIssue :: Text -> XeroTimesheetIssueView -> Html
renderIssue tone issue = [hsx|
    <div class={"alert alert-" <> tone <> " py-2 px-3 mb-0"}>
        <div>{issue.timesheetIssueMessage}</div>
        {renderIssueHint issue.timesheetIssueHint}
    </div>
|]

renderIssueHint :: Maybe Text -> Html
renderIssueHint Nothing     = mempty
renderIssueHint (Just hint) = [hsx|<div class="small mt-1">{hint}</div>|]

renderEmptyLatestRun :: Html
renderEmptyLatestRun = [hsx|
    <div class="border rounded p-3 small app-muted">
        No Xero draft-timesheet preview has been prepared yet.
    </div>
|]

renderLatestRun :: XeroTimesheetRunView -> Html
renderLatestRun runView = [hsx|
    <div class="border rounded p-3">
        <div class="d-flex flex-column flex-lg-row justify-content-between gap-2 mb-3">
            <div>
                <h4 class="h6 mb-1">Latest run</h4>
                <div class="small app-muted">
                    {formatDateDisplay run.payPeriodStart} to {formatDateDisplay run.payPeriodEnd}
                    {renderSubmittedBy runView.timesheetRunSubmittedBy}
                </div>
            </div>
            <div class="text-lg-end">
                {renderRunStatus run.status}
                <div class="small app-muted mt-1">Created {formatTimestamp run.createdAt}</div>
            </div>
        </div>
        {renderRunError run.errorSummary}
        {renderPreviewRows runView.timesheetRunPreviewRows}
        {renderSubmissionRows runView.timesheetRunSubmissionRows}
        {renderHistoricalRunNotice runView.timesheetRunHasHistoricalSib}
    </div>
|]
    where
        run = runView.timesheetRun

renderHistoricalRunNotice :: Bool -> Html
renderHistoricalRunNotice False = mempty
renderHistoricalRunNotice True = [hsx|<div class="small app-muted mt-3">Only the latest Xero submission run is shown.</div>|]

renderSubmittedBy :: Maybe User -> Html
renderSubmittedBy Nothing     = mempty
renderSubmittedBy (Just user) = [hsx|<span> by {user.email}</span>|]

renderRunStatus :: Text -> Html
renderRunStatus status = [hsx|<span class={"badge " <> statusBadgeClass status}>{statusLabel status}</span>|]

renderRunError :: Maybe Text -> Html
renderRunError Nothing = mempty
renderRunError (Just message) = [hsx|<div class="alert alert-danger small">{message}</div>|]

renderPreviewRows :: [XeroTimesheetPreviewRowView] -> Html
renderPreviewRows [] = [hsx|<div class="small app-muted">No preview rows were generated for the latest run.</div>|]
renderPreviewRows rows = [hsx|
    <div class="table-responsive">
        <table class="table table-sm align-middle mb-0">
            <thead>
                <tr>
                    <th>Employee</th>
                    <th>Period</th>
                    <th class="text-end">Units</th>
                    <th>Earnings lines</th>
                    <th class="text-end">Source entries</th>
                </tr>
            </thead>
            <tbody>{forEach rows renderPreviewRow}</tbody>
        </table>
    </div>
|]

renderPreviewRow :: XeroTimesheetPreviewRowView -> Html
renderPreviewRow row = [hsx|
    <tr>
        <td>
            <div class="fw-semibold">{row.previewRowEmployeeName}</div>
            <div class="small app-muted">{row.previewRowXeroEmployeeId}</div>
        </td>
        <td>{formatDateDisplay row.previewRowPeriodStart} to {formatDateDisplay row.previewRowPeriodEnd}</td>
        <td class="text-end">{formatUnits row.previewRowTotalUnits}</td>
        <td>{earningsSummary row.previewRowLines}</td>
        <td class="text-end">{row.previewRowSourceCount}</td>
    </tr>
|]

renderSubmissionRows :: [XeroTimesheetSubmissionRowView] -> Html
renderSubmissionRows [] = mempty
renderSubmissionRows rows = [hsx|
    <div class="mt-3">
        <h5 class="h6 mb-2">Submission status</h5>
        <div class="table-responsive">
            <table class="table table-sm align-middle mb-0">
                <thead>
                    <tr>
                        <th>Employee</th>
                        <th>Status</th>
                        <th>Xero timesheet</th>
                        <th>Error</th>
                        <th class="text-end">Attempts</th>
                        <th></th>
                    </tr>
                </thead>
                <tbody>{forEach rows renderSubmissionRow}</tbody>
            </table>
        </div>
    </div>
|]

renderSubmissionRow :: XeroTimesheetSubmissionRowView -> Html
renderSubmissionRow rowView = [hsx|
    <tr>
        <td>
            <div class="fw-semibold">{employeeLabel rowView}</div>
            <div class="small app-muted">{submission.xeroEmployeeId}</div>
        </td>
        <td>{renderRunStatus submission.status}</td>
        <td>{fromMaybe "-" (submission.xeroTimesheetId <|> submission.xeroTimesheetStatus)}</td>
        <td class="small">{fromMaybe "" submission.lastError}</td>
        <td class="text-end">{submission.attemptCount}</td>
        <td class="text-end">{renderRetryButton submission}</td>
    </tr>
|]
    where
        submission = rowView.submissionRowSubmission

renderRetryButton :: XeroTimesheetSubmission -> Html
renderRetryButton submission
    | submission.status `elem` ["failed", "blocked"] = [hsx|
        <form method="POST" action={RetryXeroDraftTimesheetSubmissionAction submission.id}>
            <button type="submit"
                    class="btn btn-sm btn-outline-secondary"
                    hx-post={pathTo (RetryXeroDraftTimesheetSubmissionAction submission.id)}
                    hx-target="#admin-xero-fragment"
                    hx-swap="outerHTML">
                Retry
            </button>
        </form>
    |]
    | otherwise = mempty

employeeLabel :: XeroTimesheetSubmissionRowView -> Text
employeeLabel rowView =
    case rowView.submissionRowEmployee of
        Just employee -> employee.displayName
        Nothing ->
            case rowView.submissionRowStaff of
                Just staff -> staff.firstName <> " " <> staff.lastName
                Nothing    -> rowView.submissionRowSubmission.xeroEmployeeId

earningsSummary :: [XeroTimesheetPreviewLineView] -> Text
earningsSummary [] = "-"
earningsSummary lines =
    lines
        |> map (\line -> line.previewLineViewEarningsRateName <> " (" <> formatUnits line.previewLineViewTotalUnits <> ")")
        |> Text.intercalate ", "

formatUnits :: Scientific -> Text
formatUnits value = cs (formatScientific Fixed (Just 2) value)

statusLabel :: Text -> Text
statusLabel "partially_failed" = "partially failed"
statusLabel value              = Text.replace "_" " " value

statusBadgeClass :: Text -> Text
statusBadgeClass "submitted"        = "text-bg-success"
statusBadgeClass "previewed"        = "text-bg-info"
statusBadgeClass "pending"          = "text-bg-secondary"
statusBadgeClass "blocked"          = "text-bg-danger"
statusBadgeClass "failed"           = "text-bg-danger"
statusBadgeClass "partially_failed" = "text-bg-warning"
statusBadgeClass _                  = "text-bg-secondary"
