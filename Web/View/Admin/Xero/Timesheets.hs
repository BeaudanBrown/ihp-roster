module Web.View.Admin.Xero.Timesheets
    ( renderXeroTimesheetPanel
    ) where

import Application.Helper.XeroAdminTypes
import qualified Data.Text as Text
import Web.View.Prelude

renderXeroTimesheetPanel :: XeroTimesheetPanelData -> Html
renderXeroTimesheetPanel panel = [hsx|
    <div id="xero-timesheets-data" class="d-flex flex-column gap-3">
        <div>
            <h3 class="h6 mb-1">Draft timesheet submission</h3>
            <div class="small app-muted">Prepare Xero Payroll AU draft timesheets. Bepis will first confirm staff Xero mappings, then let you choose an eligible Xero payroll period.</div>
        </div>
        {renderPeriodNotice panel}
        {maybe mempty renderReadiness panel.xeroTimesheetReadiness}
    </div>
|]

renderEmptyPeriodOption :: XeroTimesheetPanelData -> Html
renderEmptyPeriodOption panel
    | null panel.xeroTimesheetPeriodOptions = [hsx|<option value="">No synced Xero pay periods available</option>|]
    | otherwise = mempty

renderPeriodOption :: XeroTimesheetPeriodOption -> Html
renderPeriodOption option = [hsx|
    <option value={option.periodOptionKey} disabled={option.periodOptionBlocked}>{periodOptionLabel option}</option>
|]

periodOptionLabel :: XeroTimesheetPeriodOption -> Text
periodOptionLabel option =
    option.periodOptionPayrollCalendarName
        <> " · "
        <> formatDateDisplay option.periodOptionStart
        <> " to "
        <> formatDateDisplay option.periodOptionEnd
        <> maybe "" (\status -> " · " <> Text.toUpper status) option.periodOptionXeroPayRunStatus
        <> periodSubmissionStatusLabel option.periodOptionLatestSubmissionStatus
        <> maybe "" (" · blocked: " <>) option.periodOptionBlockReason

periodSubmissionStatusLabel :: Maybe Text -> Text
periodSubmissionStatusLabel status =
    case Text.toCaseFold . Text.strip <$> status of
        Just "submitted"        -> " · submitted already"
        Just "partially_failed" -> " · partially submitted"
        Just "failed"           -> " · failed previously"
        Just "previewed"        -> " · previewed previously"
        Just "pending"          -> " · submission pending"
        Just "blocked"          -> " · blocked previously"
        _                       -> ""

renderPeriodNotice :: XeroTimesheetPanelData -> Html
renderPeriodNotice panel =
    case panel.xeroTimesheetPeriodMessage of
        Just message -> [hsx|<div class="alert alert-secondary mb-0 small">{message}</div>|]
        Nothing ->
            case panel.xeroTimesheetReadiness of
                Nothing -> mempty
                Just readiness -> [hsx|
                    <div class={appSurfaceClasses "p-3 small"}>
                        <span class="fw-semibold">Selected Xero payroll period:</span>
                        {formatDateDisplay readiness.timesheetReadinessPeriodStart} to {formatDateDisplay readiness.timesheetReadinessPeriodEnd}
                        <span class="app-muted ms-2">{tshow readiness.timesheetReadinessEntryCount} approved shifts, {tshow readiness.timesheetReadinessStaffCount} staff, {tshow readiness.timesheetReadinessBucketCount} earnings buckets</span>
                    </div>
                |]

renderReadiness :: XeroTimesheetReadinessView -> Html
renderReadiness readiness = [hsx|
    <div class={appSurfaceClasses "p-3"}>
        <div class="d-flex align-items-center justify-content-between gap-2 mb-2">
            <h4 class="h6 mb-0">Readiness</h4>
            {renderReadinessBadge readiness.timesheetReadinessReady}
        </div>
        {renderIssues "Blockers" "No blockers for this period." "danger" readiness.timesheetReadinessBlockers}
        {renderIssues "Warnings" "No warnings for this period." "warning" readiness.timesheetReadinessWarnings}
    </div>
|]

renderReadinessBadge :: Bool -> Html
renderReadinessBadge True  = renderAppStatusBadge AppStatusSuccess "ready"
renderReadinessBadge False = renderAppStatusBadge AppStatusDanger "blocked"

renderIssues :: Text -> Text -> Text -> [XeroTimesheetIssueView] -> Html
renderIssues title emptyText tone issues = [hsx|
    <div class="small mb-2">
        <div class="fw-semibold mb-1">{title}</div>
        {renderIssueList emptyText tone issues}
    </div>
|]

renderIssueList :: Text -> Text -> [XeroTimesheetIssueView] -> Html
renderIssueList emptyText _ [] = [hsx|<div class="app-muted">{emptyText}</div>|]
renderIssueList _ tone issues = [hsx|<div class="d-flex flex-wrap gap-2">{forEach issues (renderIssue tone)}</div>|]

renderIssue :: Text -> XeroTimesheetIssueView -> Html
renderIssue tone issue = [hsx|
    <span class={"badge text-bg-" <> tone <> " text-wrap text-start lh-base"}>{issue.timesheetIssueMessage}</span>
    {renderIssueHint issue.timesheetIssueHint}
|]

renderIssueHint :: Maybe Text -> Html
renderIssueHint Nothing     = mempty
renderIssueHint (Just hint) = [hsx|<span class="app-muted">{hint}</span>|]

