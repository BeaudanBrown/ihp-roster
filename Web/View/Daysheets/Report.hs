module Web.View.Daysheets.Report
    ( ReportView (..), renderReportBody, renderReportContent ) where

import Application.Daysheet.Report
import qualified Application.Helper.FrontendContract.Surface.Daysheet as Surface
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Web.Daysheets.LiveUpdates
import Web.View.Prelude

data ReportView = ReportView
    { record :: Daysheet, report :: UUID, content :: ReportContent }

instance View ReportView where
    html ReportView { .. } = renderReportBody record report content

renderReportBody :: (?context :: ControllerContext) => Daysheet -> UUID -> ReportContent -> Html
renderReportBody record report content@(ReportContent label _) =
    renderFrontendSurfaceFragmentMount @Surface.DaysheetSurface @Surface.DaysheetReport
        (surfaceField @Surface.ConfiguredReportId report &: noSurfaceFields)
        (daysheetReportSurface record report) (renderAppPage AppPageConfig
            { appPageTitle = label
            , appPageDescription = Nothing
            , appPageActions = [hsx|<a href={daysheetDateUrl record.operationalDate} class="btn btn-outline-secondary">Return to Daysheet</a>|]
            , appPageHelpTopic = Nothing, appPageWidthClass = ""
            , appPageBody = [hsx|
                <div class="app-page-stack">
                    <p><strong>{identity}</strong> — Operational date {tshow record.operationalDate}.</p>
                    <p>Current saved values, not a frozen or sent report. Unsaved edits are not included.</p>
                    <p>Last saved: {dateTime record.lastEditedAt}.</p>
                    {renderReportContent content}
                </div>
            |]
            })
  where identity = if isNothing record.submittedAt then "Draft preview" :: Text else "Live preview"

-- The renderer sees only the selected projection, never the saved source model.
-- All author/manager text goes through ordinary HSX escaping.
renderReportContent :: ReportContent -> Html
renderReportContent (ReportContent _ sections) = if null sections
    then [hsx|<p>No sections are selected for this report.</p>|]
    else forEach sections section
  where
    section (ReportSection label blocks) = [hsx|
        <section class="app-panel mb-4"><h2 class="h4 text-break">{label}</h2>{forEach blocks block}</section>
    |]
    block = \case
        ReportInstructions text -> [hsx|<p class="text-break">{text}</p>|]
        ReportField label value -> [hsx|<dl><dt class="text-break">{label}</dt><dd>{cell value}</dd></dl>|]
        ReportAdvisory status -> check status
        ReportRowAdvisories label rows -> [hsx|
            <section><h3 class="h5 text-break">{label}</h3>{forEach rows rowCheck}</section>
        |]
        ReportTable label columns grouping groups -> [hsx|
            <section class="mb-4">
                <h3 class="h5 text-break">{label}</h3>
                <div class="table-responsive" role="region" aria-label={label} tabindex="0">
                    <table class="table"><thead><tr>{forEach columns heading}</tr></thead>{forEach groups (group columns grouping)}</table>
                </div>
                {if all emptyGroup groups then emptyRows else mempty}
            </section>
        |]
    heading label = [hsx|<th scope="col" class="text-break">{label}</th>|]
    group columns grouping (ReportGroup value rows) = [hsx|<tbody>{groupHeading}{forEach rows row}</tbody>|]
      where
        groupHeading = case (grouping, value) of
            (Just label, Just value) -> [hsx|<tr><th scope="rowgroup" colspan={length columns}><span class="text-break">{label}: </span>{cell value}</th></tr>|]
            _ -> mempty
    row values = [hsx|<tr>{forEach values tableCell}</tr>|]
    tableCell value = [hsx|<td>{cell value}</td>|]
    cell = \case
        ReportValue _ text -> [hsx|<span class="text-break">{text}</span>|]
        ReportUnavailable reason -> [hsx|<span class="text-muted text-break">Unavailable: {reason}</span>|]
    rowCheck (label, status) = [hsx|<div><strong class="text-break">{label}</strong>{check status}</div>|]
    check = \case
        ReportPassed text -> [hsx|<p class="small text-muted text-break">Passed: {text}</p>|]
        ReportConcern text -> [hsx|<p class="alert alert-warning text-break">Concern: {text}</p>|]
        ReportNotEvaluated reason -> [hsx|<p class="alert alert-secondary text-break">Not evaluated: {reason}</p>|]
    emptyGroup (ReportGroup _ rows) = null rows
    emptyRows = [hsx|<p class="text-muted">No rows.</p>|]
