module Web.View.Admin.PayrollReportEmailDialog where

import Application.Helper.Export.PayrollWorkbookConfiguration
import qualified Application.Helper.FrontendContract.AppShell as Shell
import Application.Helper.FrontendContract.AppShell.Request (appShellActionFields)
import Application.Helper.FrontendContract.AppShell.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.View.Overlay
import Application.Helper.Url (appendQueryParams)
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
        <p>Reporting {tshow week} – {tshow (addDays 6 week)}. The full template is emailed; download filters do not apply.</p>
        {when (null groups) noGroups}
        <a href={appendQueryParams (pathTo AdminAction) [("showRecipientGroups", "true")] <> "#recipient-groups"}>Manage recipient groups</a>
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
        { confirmationDialogApproveLabel = "Send to entire group", confirmationDialogLoadingLabel = "Preparing report…", confirmationDialogClass = "modal-lg" })
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
        &: surfaceOptionalField @Shell.ReportRepeatField Nothing
        &: surfaceField @Shell.ReportConfirmationField confirmation &: noSurfaceFields)
    description = [hsx|
        {forEach message renderEmailMessage}
        <p>Export template: <strong class="text-break">{record.name}</strong></p>
        <p>Reporting {tshow preview.reportingWeek} – {tshow (addDays 6 preview.reportingWeek)} using current approved data and the full template.</p>
        <p>Recipient group: <strong class="text-break">{group.name}</strong></p>
        <p>To and Reply-To:</p>
        <ul>{forEach group.recipients renderAddress}</ul>
        <p>All recipients can see each other and reply directly to the group.</p>
        <p>Only approved entries are included. If none qualify, a status email explains whether approvals are pending; no attachment is sent. Unrecorded work cannot be detected.</p>
        <p>Manual email does not suppress automation. Acceptance is not inbox delivery; investigate uncertain delivery before sending again.</p>
        <button type="button" class="btn btn-outline-secondary" {...changeGroupAttrs}>Change recipient group</button>
    |]
    changeGroupAttrs = appShellActionAttrs (appShellActionByMarker @Shell.OpenPayrollReportEmail)
        (defaultAppShellActionRoute (pathTo (EmailPayrollReportAction record.id (tshow preview.reportingWeek))))
    renderAddress address = [hsx|<li class="text-break">{address}</li>|]
    form = renderAppShellActionForm (appShellActionByMarker @Shell.SendPayrollReport)
        ((defaultAppShellActionRoute (pathTo SendPayrollReportAction)) { appShellActionRouteExtraAttrs = [("id", "payroll-email-send-form")] }) [hsx|
            {forEach (surfaceFieldsText fields) renderEmailHidden}
            {when preview.repeatWarning repeatAcknowledgement}
        |]
    repeatAcknowledgement = [hsx|
        <p class="alert alert-warning">This template and reporting week already has a prepared, sent or uncertain report, possibly for another group. This creates a new report for the entire selected group, not a replay or a retry only to missed recipients.</p>
        <label class="form-check-label">
            <input type="checkbox" class="form-check-input" name={surfaceFieldNameFrom @Shell.ReportRepeatField fields} value="true" required="required"/>
            I confirm sending another report to the entire group.
        </label>
    |]

renderEmailMessage :: Text -> Html
renderEmailMessage message = [hsx|<p role="status" class="alert alert-info">{message}</p>|]

renderEmailHidden :: (Text, Text) -> Html
renderEmailHidden (name, value) = [hsx|<input type="hidden" name={name} value={value}/>|]
