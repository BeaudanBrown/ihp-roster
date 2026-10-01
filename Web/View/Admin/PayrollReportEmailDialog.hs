module Web.View.Admin.PayrollReportEmailDialog where

import Application.Helper.Export.PayrollWorkbookConfiguration
import qualified Application.Helper.FrontendContract.AppShell as Shell
import Application.Helper.FrontendContract.AppShell.Request (appShellActionFields)
import Application.Helper.FrontendContract.AppShell.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.View.Overlay
import Application.PayrollReports.Manual (ManualPayrollReportPreview (..))
import Application.PayrollReports.Selection
import Web.View.Prelude

renderEmailNotice :: Text -> Html
renderEmailNotice message = renderDialogOverlay DialogOverlayConfig
    { dialogOverlayTitle = "Email export", dialogOverlayBody = [hsx|<p role="status">{message}</p>|]
    , dialogOverlayStartButtons = [], dialogOverlayButtons = [], dialogOverlayDialogClass = "modal-lg"
    , dialogOverlayDismissalGuard = Nothing }

renderEmailGroupChooser :: SavedPayrollWorkbookConfiguration -> Day -> [RecipientGroup] -> Maybe UUID -> Maybe Text -> Html
renderEmailGroupChooser template week groups selected message = renderConfirmationDialog
    ((defaultConfirmationDialogConfig "Email export" description "payroll-email-review-form" form)
        { confirmationDialogApproveLabel = "Review recipients", confirmationDialogLoadingLabel = "Reviewing…", confirmationDialogClass = "modal-lg" })
  where
    record = template.savedPayrollWorkbookConfigurationRecord
    fields = appShellActionFields @Shell.PreviewPayrollReport (surfaceField @Shell.ReportWeekField week)
        (surfaceField @Shell.ReportTemplateField (unpackId record.id) &: surfaceOptionalField @Shell.ReportGroupField selected &: noSurfaceFields)
    description = [hsx|
        {forEach message renderEmailMessage}
        <p>Export template: <strong class="text-break">{record.name}</strong></p>
        <p>{tshow week} – {tshow (addDays 6 week)}</p>
        {when (null groups) noGroups}
    |]
    noGroups = [hsx|<p>Create a recipient group before emailing this export.</p>|]
    form = renderAppShellActionForm (appShellActionByMarker @Shell.PreviewPayrollReport)
        ((defaultAppShellActionRoute (pathTo PreviewPayrollReportAction)) { appShellActionRouteExtraAttrs = [("id", "payroll-email-review-form")] }) [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Shell.ReportWeekField fields} value={tshow week}/>
            <input type="hidden" name={surfaceFieldNameFrom @Shell.ReportTemplateField fields} value={tshow record.id}/>
            <label for="email-recipient-group" class="form-label">Recipient group</label>
            <select id="email-recipient-group" class="form-select" name={surfaceFieldNameFrom @Shell.ReportGroupField fields} required="required">
                <option value="" selected={isNothing selected}>Choose a recipient group</option>
                {forEach groups renderGroup}
            </select>
        |]
    renderGroup group = [hsx|<option value={tshow group.id} selected={selected == Just (unpackId group.id)}>{group.name}</option>|]

renderEmailConfirmation :: ManualPayrollReportPreview -> UUID -> Maybe Text -> Html
renderEmailConfirmation preview confirmation message = renderConfirmationDialog
    ((defaultConfirmationDialogConfig "Confirm payroll email" description "payroll-email-send-form" form)
        { confirmationDialogApproveLabel = if preview.repeatWarning then "Send again" else "Send email"
        , confirmationDialogRejectButton = backButton
        , confirmationDialogLoadingLabel = "Preparing report…", confirmationDialogClass = "modal-lg" })
  where
    selection = preview.selection
    record = preview.selected.template.savedPayrollWorkbookConfigurationRecord
    group = preview.selected.group
    fields = appShellActionFields @Shell.SendPayrollReport (surfaceField @Shell.ReportWeekField preview.reportingWeek)
        (surfaceField @Shell.ReportTemplateField selection.configurationId
        &: surfaceField @Shell.ReportGroupField selection.recipientGroupId
        &: surfaceField @Shell.ReportConfigurationRevisionField selection.configurationRevision
        &: surfaceField @Shell.ReportGroupRevisionField selection.recipientGroupRevision
        &: surfaceField @Shell.ReportRosterStartField selection.rosterWeekStartsOn
        &: surfaceField @Shell.ReportTimezoneField selection.timezone
        &: surfaceOptionalField @Shell.ReportRepeatField (Just preview.repeatWarning)
        &: surfaceField @Shell.ReportConfirmationField confirmation &: noSurfaceFields)
    description = [hsx|
        {forEach message renderEmailMessage}
        <dl class="row mb-0">
            <dt class="col-sm-3">Export</dt><dd class="col-sm-9 text-break">{record.name}</dd>
            <dt class="col-sm-3">Week</dt><dd class="col-sm-9">{tshow preview.reportingWeek} – {tshow (addDays 6 preview.reportingWeek)}</dd>
            <dt class="col-sm-3">Group</dt><dd class="col-sm-9 text-break">{group.name}</dd>
            <dt class="col-sm-3">To / Reply-To</dt><dd class="col-sm-9"><ul class="list-unstyled mb-0">{forEach group.recipients renderAddress}</ul></dd>
        </dl>
    |]
    backFields = appShellActionFields @Shell.OpenPayrollReportEmail
        (surfaceOptionalField @Shell.ReportGroupField (Just selection.recipientGroupId)) noSurfaceFields
    backButton = OverlayButton
        { overlayButtonLabel = "Back", overlayButtonClass = "btn btn-outline-secondary"
        , overlayButtonAction = GeneratedDialogButtonAction (appShellActionByMarker @Shell.OpenPayrollReportEmail)
            (defaultAppShellActionRoute (appendQueryParams
                (pathTo (EmailPayrollReportAction record.id (tshow preview.reportingWeek))) (surfaceFieldsText backFields))) True }
    renderAddress address = [hsx|<li class="text-break">{address}</li>|]
    form = renderAppShellActionForm (appShellActionByMarker @Shell.SendPayrollReport)
        ((defaultAppShellActionRoute (pathTo SendPayrollReportAction)) { appShellActionRouteExtraAttrs = [("id", "payroll-email-send-form")] }) [hsx|
            {forEach (surfaceFieldsText fields) renderEmailHidden}
            {when preview.repeatWarning repeatWarning}
        |]
    repeatWarning = [hsx|
        <p role="alert" class="alert alert-warning">A report for this template and week already exists. This sends a new copy to this group.</p>
    |]

renderEmailMessage :: Text -> Html
renderEmailMessage message = [hsx|<p role="status" class="alert alert-info">{message}</p>|]

renderEmailHidden :: (Text, Text) -> Html
renderEmailHidden (name, value) = [hsx|<input type="hidden" name={name} value={value}/>|]
