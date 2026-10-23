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
    earliestEntry <- query @TimesheetEntry |> filterWhere (#venueId, unpackId currentVenueId)
        |> orderByAsc #operationalDate |> fetchOneOrNothing
    config <- query @VenueConfig |> filterWhere (#venueId, unpackId currentVenueId) |> fetchOne
    now <- getCurrentTime
    let current = either (const Nothing) (\value -> value) settings
    next <- maybe (pure Nothing) nextScheduledPayrollReport current
    let today = localDay (resolvedInstantLocalTime (resolvedInstantFromUTC now))
    let venueCreated = localDay (resolvedInstantLocalTime (resolvedInstantFromUTC currentVenue.createdAt))
    let earliest = maybe venueCreated (min venueCreated . (.operationalDate)) earliestEntry
    let weeks = completedPayrollReportWeeks config.rosterWeekStartsOn today earliest
    respondHtml (renderPayrollReportsDialog (fromMaybe (reportDraft current) submitted) (either (const []) (\value -> value) templates) next weeks now message)

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
                    , recipientEntry = fromMaybe "" (surfaceFieldValue @Shell.ReportRecipientEntryField fields)
                    , timeText = surfaceFieldValue @Shell.ReportMinuteField fields
                    , revision = surfaceFieldValue @Shell.ReportRevisionField fields
                    }
            let addresses = filter (not . Text.null) (map Text.strip (Text.lines draft.recipientsText))
            let adding = fromMaybe False (surfaceFieldValue @Shell.ReportRecipientAddField fields)
            case surfaceFieldValue @Shell.ReportRecipientRemoveField fields of
                Just address -> respondReports (Just (draft { recipientsText = Text.intercalate "\n" (filter (/= address) addresses) })) Nothing
                Nothing -> do
                    let pending = Text.strip draft.recipientEntry
                    let candidates = addresses <> [pending | adding || not (Text.null pending)]
                    case validatePayrollReportRecipients candidates of
                        Left failure -> respondReports (Just draft) (Just (settingsError failure))
                        Right recipients -> do
                            let updatedDraft = draft { recipientsText = Text.intercalate "\n" recipients, recipientEntry = "" }
                            if adding then respondReports (Just updatedDraft) Nothing
                            else case parseTimeM True defaultTimeLocale "%H:%M" (Text.unpack draft.timeText) :: Maybe TimeOfDay of
                                Nothing -> respondReports (Just updatedDraft) (Just "Choose a valid local time.")
                                Just time -> do
                                    outcome <- savePayrollReportSettings PayrollReportSettingsInput
                                        { recipients
                                        , configurationId = draft.templateId
                                        , Settings.enabled = draft.enabled
                                        , minuteOfDay = time.todHour * 60 + time.todMin
                                        , expectedRevision = draft.revision
                                        }
                                    case outcome of
                                        Left failure -> respondReports (Just updatedDraft) (Just (settingsError failure))
                                        Right _ -> respondReports Nothing (Just "Payroll report settings saved. The next automatic reporting period is shown below.")

settingsError :: PayrollReportSettingsError -> Text
settingsError = \case
    PayrollReportAccessDenied -> "Payroll report access denied."
    PayrollReportInvalidSettings message -> message
    PayrollReportStaleSettings -> "Settings changed while this form was open. Close and reopen this dialog to review current settings, then try again."
    PayrollReportTemplateUnavailable -> "That template is no longer available. Choose a current template."

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
                Right _ -> respondReports Nothing (Just "Report prepared for delivery. This does not confirm inbox delivery.")
