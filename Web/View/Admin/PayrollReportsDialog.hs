module Web.View.Admin.PayrollReportsDialog where

import Application.Helper.Export.PayrollWorkbookConfiguration
import qualified Application.Helper.FrontendContract.AppShell as Shell
import Application.Helper.FrontendContract.AppShell.Request (appShellActionFields)
import Application.Helper.FrontendContract.AppShell.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.View.Overlay
import Application.PayrollReports.History
import Application.VenueTime
import qualified Data.Text as Text
import Web.View.Prelude

data ReportDraft = ReportDraft
    { recipientsText :: !Text
    , templateId :: !(Maybe UUID)
    , enabled :: !Bool
    , weekday :: !Int
    , timeText :: !Text
    , revision :: !(Maybe Int)
    , consent :: !Bool
    }

reportDraft :: Maybe PayrollReportSetting -> ReportDraft
reportDraft setting = ReportDraft
    { recipientsText = maybe "" (Text.intercalate "\n" . (.recipients)) setting
    , templateId = setting >>= (.configurationId)
    , enabled = maybe False (.enabled) setting
    , weekday = maybe 1 (.weekday) setting
    , timeText = maybe "09:00" (\s -> pad (s.minuteOfDay `div` 60) <> ":" <> pad (s.minuteOfDay `mod` 60)) setting
    , revision = (.revision) <$> setting
    , consent = False
    }
  where
    pad n = Text.justifyRight 2 '0' (tshow n)

reportLocalTimestamp :: UTCTime -> Text
reportLocalTimestamp = tshow . resolvedInstantLocalTime . resolvedInstantFromUTC

renderPayrollReportsDialog :: ReportDraft -> [SavedPayrollWorkbookConfiguration] -> [PayrollReportWeek] -> Maybe (UTCTime, Day) -> Day -> UTCTime -> Maybe Text -> Html
renderPayrollReportsDialog draft templates history next defaultWeek now message =
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
        (surfaceField @Shell.ReportRecipientsField draft.recipientsText)
        ( surfaceOptionalField @Shell.ReportTemplateField draft.templateId
        &: surfaceOptionalField @Shell.ReportEnabledField (Just draft.enabled)
        &: surfaceField @Shell.ReportWeekdayField draft.weekday
        &: surfaceField @Shell.ReportMinuteField draft.timeText
        &: surfaceOptionalField @Shell.ReportRevisionField draft.revision
        &: surfaceOptionalField @Shell.ReportConsentField (Just draft.consent)
        &: noSurfaceFields )
    body = [hsx|
        {forEach message renderMessage}
        <p>Weekly payroll emails use approved entries only. Times are Australia/Melbourne, including daylight saving.</p>
        {renderAppShellActionForm (appShellActionByMarker @Shell.SavePayrollReports)
            ((defaultAppShellActionRoute (pathTo SavePayrollReportsAction)) { appShellActionRouteExtraAttrs = [("id", "payroll-report-settings-form")] }) settingsFields}
        <hr/>
        <h3 class="h6">Next automatic report</h3>
        {nextDescription}
        <h3 class="h6">Send a completed week</h3>
        <p>Save settings first. Manual sends work with automation off. Unapproved entries are excluded.</p>
        {manualForm defaultWeek Nothing "Review send"}
        <hr/>
        <h3 class="h6">Last four reporting weeks</h3>
        <p>Snapshot at {reportLocalTimestamp now}. Provider acceptance does not confirm inbox delivery.</p>
        <button type="button" class="btn btn-outline-secondary btn-sm" {...appShellActionAttrs (appShellActionByMarker @Shell.OpenPayrollReports) (defaultAppShellActionRoute (pathTo PayrollReportsAction))}>Refresh saved settings and history</button>
        <p class="small text-muted">Refreshing discards unsaved edits.</p>
        {historyBody}
    |]
    renderMessage text = [hsx|<p role="status" class="alert alert-info">{text}</p>|]
    historyBody = if null history then [hsx|<p>No report executions yet.</p>|] else forEach history renderWeek
    renderTemplate template = let record = template.savedPayrollWorkbookConfigurationRecord in [hsx|<option value={tshow record.id} selected={draft.templateId == Just (unpackId record.id)}>{record.name}</option>|]
    renderDay (day, label) = [hsx|<option value={tshow day} selected={draft.weekday == day}>{label}</option>|]
    days = zip [0..6] (["Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday"] :: [Text])
    renderRevision revision = [hsx|<input type="hidden" name={surfaceFieldNameFrom @Shell.ReportRevisionField fields} value={tshow revision}/>|]
    settingsFields = [hsx|
        <label class="form-label" for="report-recipients">Recipients (one email address per line, maximum 50)</label>
        <textarea id="report-recipients" class="form-control mb-3" rows="4" name={surfaceFieldNameFrom @Shell.ReportRecipientsField fields}>{draft.recipientsText}</textarea>
        <label class="form-label" for="report-template">Saved payroll template</label>
        <select id="report-template" class="form-select mb-3" name={surfaceFieldNameFrom @Shell.ReportTemplateField fields}>
            <option value="" selected={isNothing draft.templateId}>Choose a template</option>
            {forEach templates renderTemplate}
        </select>
        <label class="form-label" for="report-weekday">Send day</label>
        <select id="report-weekday" class="form-select mb-3" name={surfaceFieldNameFrom @Shell.ReportWeekdayField fields}>
            {forEach days renderDay}
        </select>
        <label class="form-label" for="report-time">Local send time</label>
        <input id="report-time" class="form-control mb-3" type="time" required="required" name={surfaceFieldNameFrom @Shell.ReportMinuteField fields} value={draft.timeText}/>
        <div class="form-check mb-3"><input id="report-enabled" class="form-check-input" type="checkbox" name={surfaceFieldNameFrom @Shell.ReportEnabledField fields} value="true" checked={draft.enabled}/><label class="form-check-label" for="report-enabled">Enable automatic weekly reports</label></div>
        <div class="form-check mb-3"><input id="report-consent" class="form-check-input" type="checkbox" name={surfaceFieldNameFrom @Shell.ReportConsentField fields} value="true" checked={draft.consent}/><label class="form-check-label" for="report-consent">I am authorised to share payroll data with this list. Everyone sees all recipients in To and Reply-To; replies go directly to the group. External addresses are allowed and are not verified.</label></div>
        <p class="small text-muted">Confirmation is required when enabling or changing recipients. Disabling stops unstarted automatic sends, not explicit manual sends. Schedule edits start at the next future occurrence without backfill.</p>
        {forEach draft.revision renderRevision}
    |]
    nextDescription = case next of
        Nothing -> [hsx|<p>Automation is off or a usable schedule is unavailable. Choose a template and recipients before sending.</p>|]
        Just (due, week) -> [hsx|<p>Scheduled for <strong>{reportLocalTimestamp due}</strong>, reporting {tshow week} – {tshow (addDays 6 week)}.</p>{overdue due}|]
    overdue due = if due <= now then [hsx|<p>Awaiting scheduler processing. Catch-up is permitted for 24 hours; older occurrences are marked missed.</p>|] else mempty
    renderRun run = [hsx|<p>{payrollReportOriginLabel run.origin} · {reportLocalTimestamp run.createdAt} · {payrollReportStatusLabel run.status}</p>|]
    resendForm group = case group.executions of
        [] -> mempty
        run : _ -> manualForm group.reportingWeek (Just (unpackId run.id)) "Review updated resend"
    renderWeek group = [hsx|
        <section class="mt-3"><h4 class="h6">{tshow group.reportingWeek} – {tshow (addDays 6 group.reportingWeek)}</h4>
        {forEach group.executions renderRun}
        {resendForm group}
        </section>
    |]

manualForm :: Day -> Maybe UUID -> Text -> Html
manualForm week previous label = renderAppShellActionForm (appShellActionByMarker @Shell.PreviewPayrollReport)
    (defaultAppShellActionRoute (pathTo PreviewPayrollReportAction)) [hsx|
        {weekField}
        {forEach previous renderPrevious}
        <button type="submit" class="btn btn-outline-primary">{label}</button>
    |]
  where
    renderPrevious runId = [hsx|<input type="hidden" name={surfaceFieldNameFrom @Shell.ReportPreviousRunField fields} value={tshow runId}/>|]
    weekField = if isJust previous
        then [hsx|<input type="hidden" name={surfaceFieldNameFrom @Shell.ReportWeekField fields} value={tshow week}/>|]
        else [hsx|<label class="form-label">Reporting week start<input class="form-control" type="date" required="required" name={surfaceFieldNameFrom @Shell.ReportWeekField fields} value={tshow week}/></label>|]
    fields = appShellActionFields @Shell.PreviewPayrollReport (surfaceField @Shell.ReportWeekField week)
        (surfaceOptionalField @Shell.ReportPreviousRunField previous &: noSurfaceFields)

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
