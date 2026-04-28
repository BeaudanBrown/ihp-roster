module Web.View.Admin.Exports
    ( renderExportsSection
    ) where

import Application.Helper.Export (ReportWeekSelection (..), VenueReportDefinition (..))
import Web.View.Admin.Common
import Web.View.Prelude

renderExportsSection :: Maybe VenueReportDefinition -> Maybe VenueReportDefinition -> Maybe VenueReportDefinition -> ReportWeekSelection -> Html
renderExportsSection staffPayReportDefinition hourlyBreakdownReportDefinition payrollEarningsReportDefinition reportWeekSelection =
    renderConfigSection
        "exports"
        "Exports"
        ("Generate the built-in payroll exports for the current report week: " <> tshow reportWeekSelection.weekStart <> " to " <> tshow reportWeekSelection.weekEnd <> ".")
        (renderExportSummary [staffPayReportDefinition, hourlyBreakdownReportDefinition, payrollEarningsReportDefinition])
        mempty
        [hsx|
            <div class="d-flex flex-wrap gap-2">
                {renderExportButton staffPayReportDefinition reportWeekSelection "Generate Staff Pay CSV"}
                {renderExportButton hourlyBreakdownReportDefinition reportWeekSelection "Generate Hourly Breakdown ZIP"}
                {renderExportButton payrollEarningsReportDefinition reportWeekSelection "Generate Payroll Earnings CSV"}
                <a href={ExportJobsAction} class="btn btn-outline-secondary">Export History</a>
            </div>
        |]

renderExportSummary :: [Maybe VenueReportDefinition] -> Html
renderExportSummary reportDefinitions = [hsx|
    <div class="small app-muted mb-3">
        {availableCount} of {tshow totalCount} built-in exports are currently available for this venue.
    </div>
|]
    where
        totalCount = length reportDefinitions
        availableCount = length (filter isJust reportDefinitions)

renderExportButton :: Maybe VenueReportDefinition -> ReportWeekSelection -> Text -> Html
renderExportButton maybeReportDefinition reportWeekSelection label =
    case maybeReportDefinition of
        Just reportDefinition -> [hsx|
            <form method="POST" action={CreateExportJobAction} class="d-inline" data-disable-javascript-submission="true">
                <input type="hidden" name="reportSlug" value={reportDefinition.definition.slug} />
                <input type="hidden" name="weekOffset" value={tshow reportWeekSelection.weekOffset} />
                <button class="btn btn-outline-primary" type="submit">{label}</button>
            </form>
        |]
        Nothing -> [hsx|
            <button class="btn btn-outline-secondary" type="button" disabled={True}>{label <> " unavailable"}</button>
        |]
