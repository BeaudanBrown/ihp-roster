module Web.View.Daysheets.Report
    ( ReportView (..), renderReportBody, renderReportContent ) where

import Application.Daysheet.Report
import Application.Helper.View.DaysheetReport (renderReportContent)
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
