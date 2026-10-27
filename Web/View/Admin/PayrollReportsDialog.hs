module Web.View.Admin.PayrollReportsDialog where

import Application.Helper.Export.PayrollWorkbookConfiguration
import qualified Application.Helper.FrontendContract.AppShell as Shell
import Application.Helper.FrontendContract.AppShell.Request (appShellActionFields)
import Application.Helper.FrontendContract.AppShell.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.View.Overlay
import Application.Helper.View.ToggleButton
import Application.Helper.Url (appendQueryParams)
import Application.VenueTime
import qualified Data.Text as Text
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

reportLocalTimestamp :: UTCTime -> Text
reportLocalTimestamp = tshow . resolvedInstantLocalTime . resolvedInstantFromUTC

renderPayrollReportsDialog :: ReportDraft -> [SavedPayrollWorkbookConfiguration] -> [RecipientGroup] -> Maybe (UTCTime, Day) -> UTCTime -> Maybe Text -> Html
renderPayrollReportsDialog draft templates groups next now message =
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
        &: noSurfaceFields )
    selectionRegion = toggleBreakRegion "payroll-report-selections"
    enableControl = renderAppToggleButton
        ((defaultAppToggleButtonConfig "report-enabled" (surfaceToggleScalarField @Shell.ReportEnabledField fields True False) draft.enabled "Enable automatic weekly reports")
            { appToggleBreakRegion = Just selectionRegion, appToggleButtonClass = "mb-3" })
    body = [hsx|
        {forEach message renderMessage}
        {renderAppShellActionForm (appShellActionByMarker @Shell.SavePayrollReports)
            ((defaultAppShellActionRoute (pathTo SavePayrollReportsAction)) { appShellActionRouteExtraAttrs = [("id", "payroll-report-settings-form")] }) settingsFields}
        <p>New schedules send at <strong>06:00 venue-local</strong> on the first day of each roster week, reporting the previous completed week.</p>
        <p class="small app-muted">Only approved entries are included. With no eligible entries, a status email is sent without an attachment. This schedule does not control manual emails.</p>
        {when (null groups) noGroups}
        <a href={appendQueryParams (pathTo AdminAction) [("showRecipientGroups", "true")] <> "#recipient-groups"}>Manage recipient groups</a>
        <hr/>
        <h3 class="h6">Next automatic report</h3>
        {nextDescription}
    |]
    renderMessage text = [hsx|<p role="status" class="alert alert-info">{text}</p>|]
    noGroups = [hsx|<p class="alert alert-info">Create a recipient group in Admin before enabling scheduled reports.</p>|]
    renderTemplate template = let record = template.savedPayrollWorkbookConfigurationRecord in [hsx|<option value={tshow record.id} selected={draft.templateId == Just (unpackId record.id)}>{record.name}</option>|]
    renderGroup group = [hsx|<option value={tshow group.id} selected={draft.groupId == Just (unpackId group.id)}>{group.name}</option>|]
    renderRevision revision = [hsx|<input type="hidden" name={surfaceFieldNameFrom @Shell.ReportRevisionField fields} value={tshow revision}/>|]
    settingsFields = [hsx|
        {enableControl}
        {renderAppToggleBreakRegion selectionRegion draft.enabled "" selectionFields}
        {forEach draft.revision renderRevision}
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
    nextDescription = case next of
        Nothing -> [hsx|<p>Automation is off or a usable schedule is unavailable. Saved selections are retained while automation is off.</p>|]
        Just (due, week) -> [hsx|<p>Scheduled for <strong>{reportLocalTimestamp due}</strong>, reporting {tshow week} – {tshow (addDays 6 week)}.</p>{overdue due}|]
    overdue due = if due <= now then [hsx|<p>Awaiting scheduler processing. Catch-up is permitted for 24 hours; older occurrences are marked missed.</p>|] else mempty

renderPayrollReportConfirmation :: PayrollReportSetting -> Day -> Maybe UUID -> UUID -> Maybe (UTCTime, Day) -> Html
renderPayrollReportConfirmation setting week previous confirmation next = renderConfirmationDialog
    ((defaultConfirmationDialogConfig "Confirm payroll email" description "payroll-report-send-form" form)
        { confirmationDialogApproveLabel = "Send to entire list", confirmationDialogLoadingLabel = "Preparing report…" })
  where
    description = [hsx|
        <p>Reporting {tshow week} – {tshow (addDays 6 week)} using the current saved template and approved data at generation.</p>
        <p>To and Reply-To: <strong>{Text.intercalate ", " setting.recipients}</strong>. All recipients can see each other and reply directly to the group.</p>
        <p>Submitted but unapproved entries are excluded. With no approved entries, a no-data email is sent without an attachment.</p>
        {resendWarning}
        {forEach next automaticWarning}
    |]
    resendWarning = if isJust previous then [hsx|<p class="alert alert-warning">This creates an updated report, not a replay. The entire current list receives another copy, including people who previously received the report.</p>|] else mempty
    automaticWarning (due, automaticWeek) = [hsx|<p class="alert alert-warning">Automation remains scheduled for {reportLocalTimestamp due}, reporting {tshow automaticWeek}. This manual send does not suppress it.</p>|]
    renderPrevious runId = [hsx|<input type="hidden" name={surfaceFieldNameFrom @Shell.ReportPreviousRunField fields} value={tshow runId}/>|]
    fields = appShellActionFields @Shell.SendPayrollReport (surfaceField @Shell.ReportWeekField week)
        (surfaceOptionalField @Shell.ReportPreviousRunField previous &: surfaceField @Shell.ReportRevisionField setting.revision &: surfaceField @Shell.ReportConfirmationField confirmation &: noSurfaceFields)
    form = renderAppShellActionForm (appShellActionByMarker @Shell.SendPayrollReport)
        ((defaultAppShellActionRoute (pathTo SendPayrollReportAction)) { appShellActionRouteExtraAttrs = [("id", "payroll-report-send-form")] }) [hsx|
            <input type="hidden" name={surfaceFieldNameFrom @Shell.ReportWeekField fields} value={tshow week}/>
            <input type="hidden" name={surfaceFieldNameFrom @Shell.ReportRevisionField fields} value={tshow setting.revision}/>
            <input type="hidden" name={surfaceFieldNameFrom @Shell.ReportConfirmationField fields} value={tshow confirmation}/>
            {forEach previous renderPrevious}
        |]
