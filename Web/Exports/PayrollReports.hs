module Web.Exports.PayrollReports
    ( openPayrollReports, savePayrollReports, previewPayrollReport, sendPayrollReport ) where

import Application.Helper.Export.PayrollWorkbookConfiguration
import qualified Application.Helper.FrontendContract.AppShell as Shell
import Application.Helper.FrontendContract.AppShell.Request (parseAppShellActionParams)
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.PayrollReports.Generation (validCompletedReportWeek)
import Application.PayrollReports.Job (nextScheduledPayrollReport)
import Application.PayrollReports.Manual
import Application.PayrollReports.Settings
import qualified Application.PayrollReports.Settings as Settings
import Application.VenueTime
import Application.RecipientGroups (listRecipientGroups)
import qualified Data.UUID.V4 as UUID
import Web.Controller.Prelude
import Web.View.Admin.PayrollReportsDialog

openPayrollReports :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IO ResponseReceived
openPayrollReports = respondReports Nothing Nothing

respondReports :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Maybe ReportDraft -> Maybe Text -> IO ResponseReceived
respondReports submitted message = do
    settings <- fetchPayrollReportSettings
    templates <- listSavedPayrollWorkbookConfigurations
    groups <- listRecipientGroups
    now <- getCurrentTime
    let current = either (const Nothing) (\value -> value) settings
    next <- maybe (pure Nothing) nextScheduledPayrollReport current
    let draft = fromMaybe (reportDraft current) submitted
    let retained = if draft.enabled then draft else draft
            { templateId = current >>= (.configurationId), groupId = current >>= (.recipientGroupId) }
    respondHtml (renderPayrollReportsDialog retained
        (either (const []) (\value -> value) templates) (either (const []) (\value -> value) groups) next now message)

savePayrollReports :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IO ResponseReceived
savePayrollReports = do
    ensureVenueWritable
    case parseAppShellActionParams @Shell.SavePayrollReports of
        Left errors -> respondReports Nothing (Just (surfaceRequestFieldErrorsMessage errors))
        Right fields -> do
            let draft = ReportDraft
                    { templateId = surfaceFieldValue @Shell.ReportTemplateField fields
                    , groupId = surfaceFieldValue @Shell.ReportGroupField fields
                    , enabled = fromMaybe False (surfaceFieldValue @Shell.ReportEnabledField fields)
                    , revision = surfaceFieldValue @Shell.ReportRevisionField fields
                    }
            outcome <- savePayrollReportSettings PayrollReportSettingsInput
                { configurationId = draft.templateId, recipientGroupId = draft.groupId
                , Settings.enabled = draft.enabled, expectedRevision = draft.revision }
            case outcome of
                Left failure -> respondReports (Just draft) (Just (settingsError failure))
                Right _ -> respondReports Nothing (Just "Payroll report settings saved.")

settingsError :: PayrollReportSettingsError -> Text
settingsError = \case
    PayrollReportAccessDenied -> "Payroll report access denied."
    PayrollReportInvalidSettings message -> message
    PayrollReportStaleSettings -> "Settings changed while this form was open. Close and reopen this dialog to review current settings, then try again."
    PayrollReportTemplateUnavailable -> "Choose an available export template before enabling scheduled reports."
    PayrollReportRecipientGroupUnavailable -> "Choose an available recipient group before enabling scheduled reports."

previewPayrollReport :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IO ResponseReceived
previewPayrollReport = do
    ensureVenueWritable
    case parseAppShellActionParams @Shell.PreviewPayrollReport of
        Left errors -> respondReports Nothing (Just (surfaceRequestFieldErrorsMessage errors))
        Right fields -> do
            let week = surfaceFieldValue @Shell.ReportWeekField fields
            let previous = surfaceFieldValue @Shell.ReportPreviousRunField fields
            config <- query @VenueConfig |> filterWhere (#venueId, unpackId currentVenueId) |> fetchOne
            now <- getCurrentTime
            let today = localDay (resolvedInstantLocalTime (resolvedInstantFromUTC now))
            valid <- case previous of
                Nothing -> pure (validCompletedReportWeek config.rosterWeekStartsOn today week)
                Just runId -> do
                    run <- query @PayrollReportRun |> filterWhere (#id, Id runId) |> filterWhere (#venueId, unpackId currentVenueId) |> fetchOneOrNothing
                    pure (maybe False (\r -> r.reportingWeek == week && r.rangeEnd == addDays 6 week && r.rangeEnd < today) run)
            settings <- fetchPayrollReportSettings
            case settings of
                Right (Just setting) | valid && isNothing setting.recipientGroupId && not (null setting.recipients) && isJust setting.configurationId -> do
                    confirmation <- UUID.nextRandom
                    next <- nextScheduledPayrollReport setting
                    respondHtml (renderPayrollReportConfirmation setting week previous confirmation next)
                _ -> respondReports Nothing (Just "Choose a completed reporting week and save a current template and recipients before sending.")

sendPayrollReport :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IO ResponseReceived
sendPayrollReport = do
    ensureVenueWritable
    settings <- fetchPayrollReportSettings
    case settings of
        Right (Just setting) | isJust setting.recipientGroupId ->
            respondReports Nothing (Just "Group-based manual emails require a fresh export-template confirmation.")
        _ -> case parseAppShellActionParams @Shell.SendPayrollReport of
            Left errors -> respondReports Nothing (Just (surfaceRequestFieldErrorsMessage errors))
            Right fields -> do
                outcome <- requestManualPayrollReport
                    (surfaceFieldValue @Shell.ReportConfirmationField fields)
                    (surfaceFieldValue @Shell.ReportRevisionField fields)
                    (surfaceFieldValue @Shell.ReportWeekField fields)
                    (surfaceFieldValue @Shell.ReportPreviousRunField fields)
                case outcome of
                    Left message -> respondReports Nothing (Just message)
                    Right _ -> respondReports Nothing (Just "Report prepared for delivery. This does not confirm inbox delivery.")
