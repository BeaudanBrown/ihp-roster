module Web.View.Admin.PayrollReportsDialog where

import Application.Helper.Export.PayrollWorkbookConfiguration
import qualified Application.Helper.FrontendContract.AppShell as Shell
import Application.Helper.FrontendContract.AppShell.Request (appShellActionFields)
import Application.Helper.FrontendContract.AppShell.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.View.Overlay
import Application.Helper.View.ToggleButton
import Web.View.Prelude

data ReportDraft = ReportDraft
    { templateId :: !(Maybe UUID)
    , groupId :: !(Maybe UUID)
    , enabled :: !Bool
    , revision :: !(Maybe Int)
    }

reportDraft :: Maybe PayrollReportSetting -> ReportDraft
reportDraft setting = ReportDraft
    { templateId = setting >>= (.configurationId)
    , groupId = setting >>= (.recipientGroupId)
    , enabled = maybe False (.enabled) setting
    , revision = (.revision) <$> setting
    }

renderPayrollReportsDialog :: ReportDraft -> [SavedPayrollWorkbookConfiguration] -> [RecipientGroup] -> Maybe Day -> Maybe Text -> Html
renderPayrollReportsDialog draft templates groups anchorWeek message =
    renderDialogOverlay DialogOverlayConfig
        { dialogOverlayTitle = "Scheduled reports"
        , dialogOverlayBody = body
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = defaultOverlayButtons "payroll-report-settings-form"
        , dialogOverlayDialogClass = "modal-lg"
        , dialogOverlayDismissalGuard = Nothing
        }
  where
    fields = appShellActionFields @Shell.SavePayrollReports
        (surfaceOptionalField @Shell.ReportTemplateField draft.templateId)
        ( surfaceOptionalField @Shell.ReportGroupField draft.groupId
        &: surfaceOptionalField @Shell.ReportEnabledField (Just draft.enabled)
        &: surfaceOptionalField @Shell.ReportRevisionField draft.revision
        &: surfaceOptionalField @Shell.ReportWeekField anchorWeek
        &: noSurfaceFields )
    selectionRegion = toggleBreakRegion "payroll-report-selections"
    enableControl = renderAppToggleButton
        ((defaultAppToggleButtonConfig "report-enabled" (surfaceToggleScalarField @Shell.ReportEnabledField fields True False) draft.enabled "Enable automatic weekly reports")
            { appToggleBreakRegion = Just selectionRegion, appToggleButtonClass = "mb-3" })
    body = [hsx|
        {forEach message renderMessage}
        {renderAppShellActionForm (appShellActionByMarker @Shell.SavePayrollReports)
            ((defaultAppShellActionRoute (pathTo SavePayrollReportsAction)) { appShellActionRouteExtraAttrs = [("id", "payroll-report-settings-form")] }) settingsFields}
    |]
    renderMessage text = [hsx|<p role="status" class="alert alert-info">{text}</p>|]
    renderTemplate template = let record = template.savedPayrollWorkbookConfigurationRecord in [hsx|<option value={tshow record.id} selected={draft.templateId == Just (unpackId record.id)}>{record.name}</option>|]
    renderGroup group = [hsx|<option value={tshow group.id} selected={draft.groupId == Just (unpackId group.id)}>{group.name}</option>|]
    renderRevision revision = [hsx|<input type="hidden" name={surfaceFieldNameFrom @Shell.ReportRevisionField fields} value={tshow revision}/>|]
    renderAnchorWeek week = [hsx|<input type="hidden" name={surfaceFieldNameFrom @Shell.ReportWeekField fields} value={tshow week}/>|]
    settingsFields = [hsx|
        {enableControl}
        {renderAppToggleBreakRegion selectionRegion draft.enabled "" selectionFields}
        {forEach draft.revision renderRevision}
        {forEach anchorWeek renderAnchorWeek}
    |]
    selectionFields = [hsx|
        <label class="form-label" for="report-template">Export template</label>
        <select id="report-template" class="form-select mb-3" name={surfaceFieldNameFrom @Shell.ReportTemplateField fields}>
            <option value="" selected={isNothing draft.templateId}>Choose an export template</option>
            {forEach templates renderTemplate}
        </select>
        <label class="form-label" for="report-group">Recipient group</label>
        <select id="report-group" class="form-select mb-3" name={surfaceFieldNameFrom @Shell.ReportGroupField fields}>
            <option value="" selected={isNothing draft.groupId}>Choose a recipient group</option>
            {forEach groups renderGroup}
        </select>
    |]
