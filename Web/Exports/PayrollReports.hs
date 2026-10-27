module Web.Exports.PayrollReports
    ( openPayrollReports, savePayrollReports, openPayrollReportEmail, previewPayrollReport, sendPayrollReport ) where

import Application.Helper.Export.PayrollWorkbookConfiguration
import qualified Application.Helper.FrontendContract.AppShell as Shell
import Application.Helper.FrontendContract.AppShell.Request (parseAppShellActionParams)
import Application.Helper.FrontendContract.Surface.Request (surfaceRequestFieldErrorsMessage)
import Application.Helper.FrontendContract.Surface.Values (surfaceFieldValue)
import Application.PayrollReports.Job (nextScheduledPayrollReport)
import Application.PayrollReports.Manual
import Application.PayrollReports.Selection
import Application.PayrollReports.Settings
import qualified Application.PayrollReports.Settings as Settings
import Application.RecipientGroups (listRecipientGroups)
import qualified Data.UUID.V4 as UUID
import Text.Read (readMaybe)
import Web.Controller.Prelude
import Web.View.Admin.PayrollReportsDialog
import Web.View.Admin.PayrollReportEmailDialog

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

openPayrollReportEmail :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => Id PayrollWorkbookConfiguration -> Text -> IO ResponseReceived
openPayrollReportEmail templateId anchorDate = do
    ensureVenueWritable
    case readMaybe (cs anchorDate) of
        Nothing -> respondHtml (renderEmailNotice "Choose a completed roster week from Exports.")
        Just week -> respondEmailChoices (unpackId templateId) week Nothing Nothing

respondEmailChoices :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => UUID -> Day -> Maybe UUID -> Maybe Text -> IO ResponseReceived
respondEmailChoices templateId week preferred message = do
    template <- fetchSavedPayrollWorkbookConfigurationForVenue currentVenueId (Id templateId)
    config <- query @VenueConfig |> filterWhere (#venueId, unpackId currentVenueId) |> fetchOne
    now <- getCurrentTime
    case template of
        Left _ -> respondHtml (renderEmailNotice "The selected export template is unavailable.")
        Right _ | not (isCompletedPayrollReportWeek config now week) -> respondHtml (renderEmailNotice "Choose a completed roster week from Exports.")
        Right template -> do
            groups <- listRecipientGroups
            settings <- fetchPayrollReportSettings
            let available = either (const []) (\values -> values) groups
            let savedGroup = either (const Nothing) (>>= (.recipientGroupId)) settings
            let chosen = preferred <|> savedGroup
            let activeChoice = chosen >>= \identifier -> if any (\group -> unpackId group.id == identifier) available then Just identifier else Nothing
            respondHtml (renderEmailGroupChooser template week available activeChoice message)

previewPayrollReport :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IO ResponseReceived
previewPayrollReport = do
    ensureVenueWritable
    case parseAppShellActionParams @Shell.PreviewPayrollReport of
        Left errors -> respondHtml (renderEmailNotice (surfaceRequestFieldErrorsMessage errors))
        Right fields -> do
            let week = surfaceFieldValue @Shell.ReportWeekField fields
            let templateId = surfaceFieldValue @Shell.ReportTemplateField fields
            case surfaceFieldValue @Shell.ReportGroupField fields of
                Nothing -> respondEmailChoices templateId week Nothing (Just "Choose an available recipient group.")
                Just groupId -> respondEmailReview templateId groupId week Nothing

respondEmailReview :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => UUID -> UUID -> Day -> Maybe Text -> IO ResponseReceived
respondEmailReview templateId groupId week message = do
    preview <- previewManualPayrollReport templateId groupId week
    case preview of
        Left failure -> respondEmailChoices templateId week (Just groupId) (Just failure)
        Right preview -> do
            confirmation <- UUID.nextRandom
            respondHtml (renderEmailConfirmation preview confirmation message)

sendPayrollReport :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request, ?respond :: Respond) => IO ResponseReceived
sendPayrollReport = do
    ensureVenueWritable
    case parseAppShellActionParams @Shell.SendPayrollReport of
        Left errors -> respondHtml (renderEmailNotice (surfaceRequestFieldErrorsMessage errors))
        Right fields -> do
            let week = surfaceFieldValue @Shell.ReportWeekField fields
            let selection = ManualReportSelection
                    { configurationId = surfaceFieldValue @Shell.ReportTemplateField fields
                    , configurationRevision = surfaceFieldValue @Shell.ReportConfigurationRevisionField fields
                    , recipientGroupId = surfaceFieldValue @Shell.ReportGroupField fields
                    , recipientGroupRevision = surfaceFieldValue @Shell.ReportGroupRevisionField fields
                    , rosterWeekStartsOn = surfaceFieldValue @Shell.ReportRosterStartField fields
                    , timezone = surfaceFieldValue @Shell.ReportTimezoneField fields
                    , repeatSendConfirmed = fromMaybe False (surfaceFieldValue @Shell.ReportRepeatField fields) }
            outcome <- requestSelectedManualPayrollReport (surfaceFieldValue @Shell.ReportConfirmationField fields) selection week
            case outcome of
                Left failure -> respondEmailReview selection.configurationId selection.recipientGroupId week
                    (Just failure)
                Right _ -> respondHtml (renderEmailNotice "Report prepared for delivery. This does not confirm inbox delivery. Do not send another copy merely because delivery has not yet been confirmed.")
