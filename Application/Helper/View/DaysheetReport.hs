-- | Render only selected report content; never load or reevaluate source data.
module Application.Helper.View.DaysheetReport (renderReportContent, reportPlainText) where

import Application.Daysheet.Report
import IHP.ViewPrelude
import qualified IHP.HSX.Markup as Markup
import qualified Data.Text as Text

-- All author/manager text goes through ordinary HSX escaping.
renderReportContent :: ReportContent -> Markup.Html
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

reportPlainText :: ReportContent -> Text
reportPlainText (ReportContent title sections) = Text.unlines (title : concatMap section sections)
  where
    section (ReportSection label blocks) = "" : label : concatMap block blocks
    block = \case
        ReportInstructions text -> [text]
        ReportField label value -> [label <> ": " <> cell value]
        ReportAdvisory status -> [check status]
        ReportRowAdvisories label rows -> label : [name <> ": " <> check status | (name, status) <- rows]
        ReportTable label columns grouping groups -> label : concatMap (group columns grouping) groups
            <> ["No rows." | all (\(ReportGroup _ rows) -> null rows) groups]
    group columns grouping (ReportGroup value rows) = heading <> map row rows
      where
        heading = case (grouping, value) of
            (Just label, Just value) -> [label <> ": " <> cell value]
            _ -> []
        row cells = Text.intercalate "; " [label <> ": " <> cell value | (label, value) <- zip columns cells]
    cell = \case
        ReportValue _ display -> display
        ReportUnavailable reason -> "Unavailable: " <> reason
    check = \case
        ReportPassed message -> "Passed: " <> message
        ReportConcern message -> "Concern: " <> message
        ReportNotEvaluated reason -> "Not evaluated: " <> reason
