-- Group-envelope orchestration. The only SMTP call remains in EmailDelivery.
module Application.EmailDelivery.Group
    ( GroupDeliveryRuntime (..)
    , payrollReportMailKind
    , enqueuePayrollReportOutcome
    , performGroupEmailDeliveryWith
    , recordPayrollReportProviderFailure
    , handleGroupEmailFinalFailure
    , notifyInterruptedGroupEmail
    ) where

import Application.Async.Boundary (throwAppJobError, trySynchronousAppJobAction)
import Application.Async.Error (AppJobError (..))
import Application.EmailDelivery.Correlation
import Application.EmailDelivery.Persistence
import Application.PayrollReports.Email
import Application.PayrollReports.Notifications
import Application.PayrollReports.Settings
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude
import Network.Mail.Mime (Mail (..))

payrollReportMailKind :: Text
payrollReportMailKind = "payroll_report_group_v1"

data GroupDeliveryRuntime = GroupDeliveryRuntime
    { groupDeliveryDisabled :: !(IO Bool)
    , deliverGroupMail :: !(Mail -> IO ())
    }

data GroupEnvelope = GroupEnvelope !Text !UUID
instance Aeson.FromJSON GroupEnvelope where
    parseJSON = Aeson.withObject "GroupEnvelope" \value ->
        GroupEnvelope <$> value Aeson..: "mailKind" <*> value Aeson..: "domainReferenceId"

-- A version-2 group envelope references the immutable recipient snapshot. It
-- cannot impersonate an account or squeeze multiple addresses into one Address.
enqueuePayrollReportOutcome :: (?modelContext :: ModelContext) => PayrollReportRun -> IO ()
enqueuePayrollReportOutcome submitted = do
    notifyPayrollReportFailure submitted
    withTransaction do
        withPayrollReportVenueLock submitted.venueId
        run <- fetch submitted.id
        when (run.status `elem` [PayrollReportReady, PayrollReportNoData, PayrollReportQueued]) do
            void $ insertPermanentlyDeduplicatedEmailJob EmailDeliveryInsert
                { payloadSchemaVersion = 2
                , payload = Aeson.object ["mailKind" Aeson..= payrollReportMailKind, "domainReferenceId" Aeson..= unpackId run.id]
                , requestedByUserId = Just run.requestedByUserId
                , venueId = Just run.venueId
                , relatedTable = "payroll_report_runs"
                , relatedId = unpackId run.id
                , dedupeKey = "email-delivery/payroll-report/" <> tshow run.id
                }
            run |> set #status PayrollReportQueued |> updateRecord |> void

performGroupEmailDeliveryWith :: (?modelContext :: ModelContext) => GroupDeliveryRuntime -> AppJob -> IO ()
performGroupEmailDeliveryWith runtime job = do
    runId <- case Aeson.fromJSON job.payload of
        Aeson.Success (GroupEnvelope kind runId)
            | job.payloadSchemaVersion == 2 && kind == payrollReportMailKind
            && job.relatedTable == Just "payroll_report_runs" && job.relatedId == Just runId -> pure runId
        _ -> throwAppJobError JobInvalidProvenance
    disabled <- runtime.groupDeliveryDisabled
    prepared <- withTransaction do
        run <- fetch (Id runId :: Id PayrollReportRun)
        unless (job.venueId == Just run.venueId) (throwAppJobError JobInvalidProvenance)
        withPayrollReportVenueLock run.venueId
        current <- fetch run.id
        setting <- case current.settingsId of
            Nothing -> pure Nothing
            Just settingId -> fetchOneOrNothing (Id settingId :: Id PayrollReportSetting)
        if current.status `notElem` [PayrollReportReady, PayrollReportNoData, PayrollReportQueued]
            then completeGroupJob job current >> pure Nothing
        else if not (payrollReportRunIsCurrent setting current)
            then terminal current PayrollReportCancelled
        else if disabled
            then terminal current PayrollReportDisabled
        else do
            now <- getCurrentTime
            export <- case current.exportJobId of
                Nothing -> pure Nothing
                Just exportId -> fetchOneOrNothing (Id exportId :: Id ExportJob)
            venue <- fetch (Id current.venueId :: Id Venue)
            let artifactValid = case export of
                    Nothing -> current.approvedEntryCount == 0 && isNothing current.exportJobId
                    Just artifact -> artifact.venueId == current.venueId && artifact.expiresAt > now && isJust artifact.fileContents && artifact.fileEncoding == "base64"
            if not artifactValid then terminal current PayrollReportFailed else
                case (validatePayrollReportRecipients current.recipients, buildPayrollReportMail venue.name current export) of
                    (Right _, Right mail) -> do
                        correlation <- prepareProviderCorrelation job
                        -- Commit uncertainty BEFORE any transport call. A crash here
                        -- may lose a send, but can never blindly replay payroll to
                        -- recipients who might already have received it.
                        sending <- current |> set #status PayrollReportAmbiguous |> set #updatedAt now |> updateRecord
                        let correlated = mail { mailHeaders = mail.mailHeaders <> [("Message-ID", correlation.messageId), ("Resend-Idempotency-Key", "app-job/" <> tshow job.id)] }
                        pure (Just (sending, correlated, correlation))
                    _ -> terminal current PayrollReportFailed
    forM_ prepared \(run, mail, correlation) -> do
        outcome <- trySynchronousAppJobAction (runtime.deliverGroupMail mail)
        withTransaction do
            withPayrollReportVenueLock run.venueId
            current <- fetch run.id
            now <- getCurrentTime
            final <- case outcome of
                Left _ -> pure current
                Right () -> do
                    void (markSmtpAccepted correlation now)
                    if current.status == PayrollReportBounced then pure current else
                        current |> set #status PayrollReportAccepted |> set #updatedAt now |> updateRecord
            completeGroupJob job final
    current <- fetch (Id runId :: Id PayrollReportRun)
    notifyPayrollReportFailure current
  where
    terminal :: (?modelContext :: ModelContext) => PayrollReportRun -> PayrollReportStatusEnum -> IO (Maybe (PayrollReportRun, Mail, EmailDeliveryProviderState))
    terminal current status = do
        now <- getCurrentTime
        final <- current |> set #status status |> set #updatedAt now |> updateRecord
        completeGroupJob job final
        pure Nothing

completeGroupJob :: (?modelContext :: ModelContext) => AppJob -> PayrollReportRun -> IO ()
completeGroupJob job run = void $ job
    |> set #status JobStatusSucceeded |> set #lastError Nothing |> set #lockedAt Nothing |> set #lockedBy Nothing
    |> set #result (Aeson.object ["mailKind" Aeson..= payrollReportMailKind, "domainReferenceId" Aeson..= unpackId run.id, "deliveryStatus" Aeson..= deliveryStatus run.status])
    |> updateRecord
  where
    deliveryStatus = \case
        PayrollReportAccepted -> "sent" :: Text
        PayrollReportDisabled -> "delivery_disabled"
        PayrollReportCancelled -> "delivery_skipped"
        PayrollReportAmbiguous -> "acceptance_unknown"
        PayrollReportBounced -> "recipient_failure"
        PayrollReportFailed -> "delivery_failed"
        PayrollReportMissed -> "delivery_skipped"
        PayrollReportReady -> "delivery_skipped"
        PayrollReportNoData -> "delivery_skipped"
        PayrollReportQueued -> "delivery_skipped"

-- A later delivered event for another recipient must never erase a group bounce.
-- Correlation uses the shared Message-ID/provider ID, not addresses or timing.
recordPayrollReportProviderFailure :: (?modelContext :: ModelContext) => AppJob -> Text -> IO ()
recordPayrollReportProviderFailure job providerStatus =
    when (job.payloadSchemaVersion == 2 && job.relatedTable == Just "payroll_report_runs" && providerStatus `elem` ["bounced", "complained", "failed", "suppressed"]) $
        forM_ job.relatedId \runId -> do
            maybeRun <- withTransaction do
                run <- fetchOneOrNothing (Id runId :: Id PayrollReportRun)
                forM run \run -> do
                    withPayrollReportVenueLock run.venueId
                    current <- fetch run.id
                    now <- getCurrentTime
                    current |> set #status PayrollReportBounced |> set #updatedAt now |> updateRecord
            mapM_ notifyPayrollReportFailure maybeRun

-- Registry invokes this on interrupted attempts too: a timed-out transport may
-- never reach the ordinary completion path, but its uncertainty is durable.
notifyInterruptedGroupEmail :: (?modelContext :: ModelContext) => AppJob -> IO ()
notifyInterruptedGroupEmail job = when (job.payloadSchemaVersion == 2 && job.relatedTable == Just "payroll_report_runs") $
    forM_ job.relatedId \runId -> do
        run <- fetchOneOrNothing (Id runId :: Id PayrollReportRun)
        mapM_ notifyPayrollReportFailure run

handleGroupEmailFinalFailure :: (?modelContext :: ModelContext) => AppJob -> IO ()
handleGroupEmailFinalFailure job = when (job.payloadSchemaVersion == 2 && job.relatedTable == Just "payroll_report_runs") $
    forM_ job.relatedId \runId -> do
        final <- withTransaction do
            run <- fetch (Id runId :: Id PayrollReportRun)
            withPayrollReportVenueLock run.venueId
            current <- fetch run.id
            if current.status `elem` [PayrollReportReady, PayrollReportNoData, PayrollReportQueued]
                then current |> set #status PayrollReportFailed |> updateRecord
                else pure current
        notifyPayrollReportFailure final
