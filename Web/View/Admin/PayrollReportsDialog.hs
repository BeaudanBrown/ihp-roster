module Web.View.Admin.PayrollReportsDialog where

import Application.Helper.Export.PayrollWorkbookConfiguration
import qualified Application.Helper.FrontendContract.AppShell as Shell
import Application.Helper.FrontendContract.AppShell.Request (appShellActionFields)
import Application.Helper.FrontendContract.AppShell.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.View.Overlay
import Application.VenueTime
import qualified Data.Text as Text
import Web.View.Prelude

data ReportDraft = ReportDraft
    { recipientsText :: !Text
    , templateId :: !(Maybe UUID)
    , enabled :: !Bool
    , recipientEntry :: !Text
    , timeText :: !Text
    , revision :: !(Maybe Int)
    }

reportDraft :: Maybe PayrollReportSetting -> ReportDraft
reportDraft setting = ReportDraft
    { recipientsText = maybe "" (Text.intercalate "\n" . (.recipients)) setting
    , templateId = setting >>= (.configurationId)
    , enabled = maybe False (.enabled) setting
    , recipientEntry = ""
    , timeText = maybe "09:00" (\s -> pad (s.minuteOfDay `div` 60) <> ":" <> pad (s.minuteOfDay `mod` 60)) setting
    , revision = (.revision) <$> setting
    }
  where
    pad n = Text.justifyRight 2 '0' (tshow n)

reportLocalTimestamp :: UTCTime -> Text
reportLocalTimestamp = tshow . resolvedInstantLocalTime . resolvedInstantFromUTC

renderPayrollReportsDialog :: ReportDraft -> [SavedPayrollWorkbookConfiguration] -> Maybe (UTCTime, Day) -> [Day] -> UTCTime -> Maybe Text -> Html
renderPayrollReportsDialog draft templates next weeks now message =
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
        &: surfaceField @Shell.ReportMinuteField draft.timeText
        &: surfaceOptionalField @Shell.ReportRevisionField draft.revision
        &: surfaceOptionalField @Shell.ReportRecipientEntryField (Just draft.recipientEntry)
        &: surfaceOptionalField @Shell.ReportRecipientAddField Nothing
        &: surfaceOptionalField @Shell.ReportRecipientRemoveField Nothing
        &: noSurfaceFields )
    body = [hsx|
        {forEach message renderMessage}
        {renderAppShellActionForm (appShellActionByMarker @Shell.SavePayrollReports)
            ((defaultAppShellActionRoute (pathTo SavePayrollReportsAction)) { appShellActionRouteExtraAttrs = [("id", "payroll-report-settings-form")] }) settingsFields}
        <hr/>
        <h3 class="h6">Next automatic report</h3>
        {nextDescription}
        <h3 class="h6">Send a completed week</h3>
        <p>Save settings first. Manual sends work with automation off. Unapproved entries are excluded.</p>
        {manualForm weeks}
    |]
    renderMessage text = [hsx|<p role="status" class="alert alert-info">{text}</p>|]
    renderTemplate template = let record = template.savedPayrollWorkbookConfigurationRecord in [hsx|<option value={tshow record.id} selected={draft.templateId == Just (unpackId record.id)}>{record.name}</option>|]
    renderRecipient address = [hsx|
        <li class="list-group-item d-flex align-items-center justify-content-between gap-2">
            <span class="text-break">{address}</span>
            <button type="submit" class="btn btn-outline-secondary btn-sm" formnovalidate="formnovalidate" name={surfaceFieldNameFrom @Shell.ReportRecipientRemoveField fields} value={address} aria-label={"Remove " <> address}>Remove</button>
        </li>
    |]
    renderRevision revision = [hsx|<input type="hidden" name={surfaceFieldNameFrom @Shell.ReportRevisionField fields} value={tshow revision}/>|]
    settingsFields = [hsx|
        <input type="hidden" name={surfaceFieldNameFrom @Shell.ReportRecipientsField fields} value={draft.recipientsText}/>
        <label class="form-label" for="report-recipient-entry">Recipients</label>
        <div class="input-group mb-2">
            <input id="report-recipient-entry" class="form-control" type="email" autocomplete="email" placeholder="Email address" name={surfaceFieldNameFrom @Shell.ReportRecipientEntryField fields} value={draft.recipientEntry}/>
            <button type="submit" class="btn btn-outline-primary" formnovalidate="formnovalidate" name={surfaceFieldNameFrom @Shell.ReportRecipientAddField fields} value="true">Add</button>
        </div>
        <ul class="list-group mb-3" aria-label="Report recipients">{forEach (filter (not . Text.null) (Text.lines draft.recipientsText)) renderRecipient}</ul>
        <label class="form-label" for="report-template">Saved payroll template</label>
        <select id="report-template" class="form-select mb-3" name={surfaceFieldNameFrom @Shell.ReportTemplateField fields}>
            <option value="" selected={isNothing draft.templateId}>Choose a template</option>
            {forEach templates renderTemplate}
        </select>
        <label class="form-label" for="report-time">Send time on the first day of each roster week</label>
        <input id="report-time" class="form-control mb-3" type="time" required="required" name={surfaceFieldNameFrom @Shell.ReportMinuteField fields} value={draft.timeText}/>
        <div class="form-check mb-3"><input id="report-enabled" class="form-check-input" type="checkbox" name={surfaceFieldNameFrom @Shell.ReportEnabledField fields} value="true" checked={draft.enabled}/><label class="form-check-label" for="report-enabled">Enable automatic weekly reports</label></div>
        {forEach draft.revision renderRevision}
    |]
    nextDescription = case next of
        Nothing -> [hsx|<p>Automation is off or a usable schedule is unavailable. Choose a template and recipients before sending.</p>|]
        Just (due, week) -> [hsx|<p>Scheduled for <strong>{reportLocalTimestamp due}</strong>, reporting {tshow week} – {tshow (addDays 6 week)}.</p>{overdue due}|]
    overdue due = if due <= now then [hsx|<p>Awaiting scheduler processing. Catch-up is permitted for 24 hours; older occurrences are marked missed.</p>|] else mempty

manualForm :: [Day] -> Html
manualForm [] = mempty
manualForm weeks@(latest : _) = renderAppShellActionForm (appShellActionByMarker @Shell.PreviewPayrollReport)
    (defaultAppShellActionRoute (pathTo PreviewPayrollReportAction)) [hsx|
        <label class="form-label" for="report-manual-week">Reporting week</label>
        <select id="report-manual-week" class="form-select mb-3" required="required" name={surfaceFieldNameFrom @Shell.ReportWeekField fields}>
            {forEach weeks renderWeek}
        </select>
        <button type="submit" class="btn btn-outline-primary">Review and send</button>
    |]
  where
    renderWeek week = [hsx|<option value={tshow week} selected={week == latest}>{weekLabel week}</option>|]
    weekLabel week = formatTime defaultTimeLocale "%d %b %Y" week <> " – " <> formatTime defaultTimeLocale "%d %b %Y" (addDays 6 week)
    fields = appShellActionFields @Shell.PreviewPayrollReport (surfaceField @Shell.ReportWeekField latest)
        (surfaceOptionalField @Shell.ReportPreviousRunField Nothing &: noSurfaceFields)

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
