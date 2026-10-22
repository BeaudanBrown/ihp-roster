module Web.Exports.PayrollReports
    ( openPayrollReports, savePayrollReports, previewPayrollReport, sendPayrollReport ) where

import Application.Helper.Export.PayrollWorkbookConfiguration
import qualified Application.Helper.FrontendContract.AppShell as Shell
import Application.Helper.FrontendContract.AppShell.Request (parseAppShellActionParams)
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.PayrollReports.Generation (validCompletedReportWeek)
import Application.PayrollReports.History
import Application.PayrollReports.Job (nextScheduledPayrollReport)
import Application.PayrollReports.Manual
import Application.PayrollReports.Settings
import qualified Application.PayrollReports.Settings as Settings
import Application.VenueTime
import qualified Data.Text as Text
import qualified Data.UUID.V4 as UUID
import Web.Controller.Prelude
import Web.View.Admin.PayrollReportsDialog

openPayrollReports :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IO ResponseReceived
openPayrollReports = respondReports Nothing Nothing

respondReports :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Maybe ReportDraft -> Maybe Text -> IO ResponseReceived
respondReports submitted message = do
    settings <- fetchPayrollReportSettings
    templates <- listSavedPayrollWorkbookConfigurations
    history <- fetchPayrollReportHistory
    config <- query @VenueConfig |> filterWhere (#venueId, unpackId currentVenueId) |> fetchOne
    now <- getCurrentTime
    let current = either (const Nothing) (\value -> value) settings
    next <- maybe (pure Nothing) nextScheduledPayrollReport current
    let today = localDay (resolvedInstantLocalTime (resolvedInstantFromUTC now))
    respondHtml (renderPayrollReportsDialog (fromMaybe (reportDraft current) submitted) (either (const []) (\value -> value) templates) (either (const []) (\value -> value) history) next (addDays (-7) (startOfWeekFor config.rosterWeekStartsOn today)) now message)

savePayrollReports :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IO ResponseReceived
savePayrollReports = do
    ensureVenueWritable
    case parseAppShellActionParams @Shell.SavePayrollReports of
        Left errors -> respondReports Nothing (Just (surfaceRequestFieldErrorsMessage errors))
        Right fields -> do
            let draft = ReportDraft
                    { recipientsText = surfaceFieldValue @Shell.ReportRecipientsField fields
                    , templateId = surfaceFieldValue @Shell.ReportTemplateField fields
                    , enabled = fromMaybe False (surfaceFieldValue @Shell.ReportEnabledField fields)
                    , weekday = surfaceFieldValue @Shell.ReportWeekdayField fields
                    , timeText = surfaceFieldValue @Shell.ReportMinuteField fields
                    , revision = surfaceFieldValue @Shell.ReportRevisionField fields
                    , consent = fromMaybe False (surfaceFieldValue @Shell.ReportConsentField fields)
                    }
            case parseTimeM True defaultTimeLocale "%H:%M" (Text.unpack draft.timeText) :: Maybe TimeOfDay of
                Nothing -> respondReports (Just draft) (Just "Choose a valid local time.")
                Just time -> do
                    outcome <- savePayrollReportSettings PayrollReportSettingsInput
                        { recipients = filter (not . Text.null) (map Text.strip (Text.lines draft.recipientsText))
                        , configurationId = draft.templateId
                        , Settings.enabled = draft.enabled
                        , Settings.weekday = draft.weekday
                        , minuteOfDay = time.todHour * 60 + time.todMin
                        , expectedRevision = draft.revision
                        , sharingConfirmed = draft.consent
                        }
                    case outcome of
                        Left failure -> respondReports (Just draft) (Just (settingsError failure))
                        Right _ -> respondReports Nothing (Just "Payroll report settings saved. The next automatic reporting period is shown below.")

settingsError :: PayrollReportSettingsError -> Text
settingsError = \case
    PayrollReportAccessDenied -> "Payroll report access denied."
    PayrollReportInvalidSettings message -> message
    PayrollReportStaleSettings -> "Settings changed while this form was open. Refresh saved settings, review the changes, and try again."
    PayrollReportTemplateUnavailable -> "That template is no longer available. Choose a current template."
    PayrollReportSharingConfirmationRequired -> "Confirm your authority to share payroll data and the visibility of all recipients."

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
                Right (Just setting) | valid && not (null setting.recipients) && isJust setting.configurationId -> do
                    confirmation <- UUID.nextRandom
                    next <- nextScheduledPayrollReport setting
                    respondHtml (renderPayrollReportConfirmation setting week previous confirmation next)
                _ -> respondReports Nothing (Just "Choose a completed reporting week and save a current template and recipients before sending.")

sendPayrollReport :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IO ResponseReceived
sendPayrollReport = do
    ensureVenueWritable
    case parseAppShellActionParams @Shell.SendPayrollReport of
        Left errors -> respondReports Nothing (Just (surfaceRequestFieldErrorsMessage errors))
        Right fields -> do
            outcome <- requestManualPayrollReport
                (surfaceFieldValue @Shell.ReportConfirmationField fields)
                (surfaceFieldValue @Shell.ReportRevisionField fields)
                (surfaceFieldValue @Shell.ReportWeekField fields)
                (surfaceFieldValue @Shell.ReportPreviousRunField fields)
            case outcome of
                Left message -> respondReports Nothing (Just message)
                Right _ -> respondReports Nothing (Just "Report prepared for delivery. Review its status below; provider acceptance does not confirm inbox delivery.")
