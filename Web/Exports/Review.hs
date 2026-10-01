module Web.Exports.Review (withExportReview, renderExportReviewForm) where

import Application.Helper.Export.Types (ExportJobType, exportJobTypeToText)
import qualified Application.Helper.FrontendContract.AppShell as Shell
import Application.Helper.FrontendContract.AppShell.Request
import Application.Helper.FrontendContract.AppShell.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.TimesheetReview
import Application.Helper.View.Overlay (dialogOverlayMountId)
import Application.Helper.View.TimesheetReview
import IHP.ViewPrelude (Html)
import Web.Controller.Prelude

-- No export writes occur until the caller's continuation is submitted. Native
-- forms work too; HTMX downloads normally use swap=none, so retarget the warning.
withExportReview :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Day -> Day -> Html -> IO ResponseReceived -> IO ResponseReceived
withExportReview start end confirmationForm continue = do
    rows <- fetchUnapprovedTimesheets currentVenueId start end
    if null rows then continue else do
        when isHtmxRequest do
            setHeader ("HX-Retarget", cs ("#" <> dialogOverlayMountId))
            setHeader ("HX-Reswap", "innerHTML")
        respondHtml (renderUnapprovedTimesheetsConfirmation
            "Unapproved timesheets in this export period"
            "These timesheets are unapproved and will not be included in the export. Continue with the approved timesheets only?"
            rows "confirm-export-unapproved-timesheets-form" confirmationForm)

-- Keep continuation fields nominal to their own operation, even though both
-- adapters submit the same period/type/configuration values.
renderExportReviewForm :: Bool -> Day -> Day -> ExportJobType -> Maybe UUID -> Html
renderExportReviewForm filtered start end exportType configurationId
    | filtered = renderAppShellActionForm (appShellActionFor selectionFields)
        (route (pathTo ConfirmTimesheetExportSelectionAction)) [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Shell.SelectionRangeStartField selectionFields} value={tshow start} />
            <input type="hidden" name={surfaceFieldNameFrom @Shell.SelectionRangeEndField selectionFields} value={tshow end} />
            <input type="hidden" name={surfaceFieldNameFrom @Shell.SelectionExportTypeField selectionFields} value={exportJobTypeToText exportType} />
            <input type="hidden" name={surfaceFieldNameFrom @Shell.PayrollWorkbookConfigurationIdField selectionFields} value={maybe "" tshow configurationId} />
            <input type="hidden" name={surfaceFieldNameFrom @Shell.SelectedTimesheetEntriesField selectionFields} value="[]" />
        |]
    | otherwise = renderAppShellActionForm (appShellActionFor downloadFields)
        (route (pathTo ConfirmTimesheetExportDownloadAction)) [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Shell.SelectionRangeStartField downloadFields} value={tshow start} />
            <input type="hidden" name={surfaceFieldNameFrom @Shell.SelectionRangeEndField downloadFields} value={tshow end} />
            <input type="hidden" name={surfaceFieldNameFrom @Shell.SelectionExportTypeField downloadFields} value={exportJobTypeToText exportType} />
            <input type="hidden" name={surfaceFieldNameFrom @Shell.PayrollWorkbookConfigurationIdField downloadFields} value={maybe "" tshow configurationId} />
            <input type="hidden" name={surfaceFieldNameFrom @Shell.SelectedTimesheetEntriesField downloadFields} value="[]" />
        |]
  where
    selectionFields = appShellActionFields @Shell.ConfirmTimesheetExportSelection
        (surfaceField @Shell.SelectionRangeStartField start) remainingFields
    downloadFields = appShellActionFields @Shell.ConfirmTimesheetExportDownload
        (surfaceField @Shell.SelectionRangeStartField start) remainingFields
    remainingFields = surfaceField @Shell.SelectionRangeEndField end
        &: surfaceField @Shell.SelectionExportTypeField exportType
        &: surfaceOptionalField @Shell.PayrollWorkbookConfigurationIdField configurationId
        &: surfaceField @Shell.SelectedTimesheetEntriesField ([] :: [Text])
        &: noSurfaceFields
    route url = (defaultAppShellActionRoute url)
        { appShellActionRouteExtraAttrs = [("id", "confirm-export-unapproved-timesheets-form")] }
