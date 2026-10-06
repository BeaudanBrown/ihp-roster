{-# LANGUAGE RankNTypes #-}
module Application.Daysheet.ReportStorage
    ( captureManualReport, captureScheduledReports
    ) where

import Application.Daysheet.Authority (withAuthority)
import qualified Application.Daysheet.Contract as D
import qualified Application.Daysheet.Cutoff as Cutoff
import Application.Daysheet.CutoffCapture (CutoffClock)
import Application.Daysheet.DailyStorage
import Application.Daysheet.EmailContract
import qualified Application.Daysheet.Evaluation as E
import Application.Daysheet.Recipients (activeReportRecipients, recipientIdentity)
import Application.Daysheet.Report (projectReport)
import Application.Daysheet.ReportCodec
import Application.Daysheet.ReportError
import qualified Application.Daysheet.Saved as Saved
import Application.EmailDelivery.Envelope
import Application.EmailDelivery.Enqueue (enqueueExternalEmailDeliveryWithStatus)
import Application.Error.Domain (projectDomainError)
import Application.Error.Types
import Application.Helper.Audit (recordAuditEvent)
import Application.Helper.Audit.Vocabulary
import Control.Monad.Trans.Except (ExceptT (..), runExceptT, throwE)
import qualified Data.Aeson as Aeson
import qualified Data.UUID.V4 as UUID
import Generated.Types
import IHP.ControllerPrelude

failure :: ReportStorageError -> ExceptT AppError IO value
failure = throwE . projectDomainError

-- The nonce belongs to one deliberate confirmation. Request retries preserve
-- the old run even after later live corrections or recipient additions.
captureManualReport :: (?modelContext :: ModelContext) => VenueMembership -> Id Daysheet -> D.ReportId -> UUID -> IO (AppResult DaysheetReportSnapshot)
captureManualReport member key report@(D.ReportId reportId) requestKey = withAuthority member [Manager, VenueAdmin, VenueOwner] do
    existing <- liftIO (query @DaysheetReportSnapshot
        |> filterWhere (#venueId, Id member.venueId) |> filterWhere (#requestKey, requestKey) |> fetchOneOrNothing)
    case existing of
        Just snapshot
            | snapshot.daysheetId == key && snapshot.reportId == reportId
              && snapshot.origin == DaysheetManual && snapshot.senderId == Just (Id member.userId) -> pure snapshot
            | otherwise -> failure ReportRequestConflict
        Nothing -> do
            state <- ExceptT (readDailySheet member key)
            unless (isJust state.daysheet.submittedAt) (failure ReportRequiresSubmission)
            now <- liftIO getCurrentTime
            snapshot <- persistReport state report requestKey (Just member.userId) Nothing now
            _ <- liftIO (recordAuditEvent member.venueId member.userId DaysheetReportCapturedAudit
                daysheetReportReferenceTable (unpackId snapshot.id)
                (Aeson.object ["daysheetId" Aeson..= unpackId key, "reportId" Aeson..= reportId, "sourceRevision" Aeson..= state.daysheet.revision]) ApplicationAuditSource)
            pure snapshot

-- One task captures all formatted reports in one transaction. A failed report
-- rolls back every snapshot/job from this cutoff; a late retry never rebuilds.
captureScheduledReports :: (?modelContext :: ModelContext) => CutoffClock -> UUID -> Cutoff.CutoffPlan -> IO (AppResult (Maybe [DaysheetReportSnapshot]))
captureScheduledReports clock venueId plan = withScheduledDaily clock venueId plan \state capturedAt -> runExceptT do
    forM [key | D.Report key _ _ outputs <- D.reports state.definition, D.FormattedReport `elem` outputs] \report@(D.ReportId reportId) -> do
        existing <- liftIO (query @DaysheetReportSnapshot
            |> filterWhere (#daysheetId, state.daysheet.id) |> filterWhere (#reportId, reportId)
            |> filterWhere (#cutoffAt, Just (Cutoff.cutoffAt plan)) |> fetchOneOrNothing)
        case existing of
            Just snapshot -> pure snapshot
            Nothing -> do
                requestKey <- liftIO UUID.nextRandom
                persistReport state report requestKey Nothing (Just (Cutoff.cutoffAt plan)) capturedAt

-- Private: both callers already own the venue serialization transaction. The
-- immutable selected-content record and its permanently deduplicated jobs commit
-- together. No email is transported here, and no existing business data changes.
persistReport :: (?modelContext :: ModelContext) => DailyState -> D.ReportId -> UUID -> Maybe UUID -> Maybe UTCTime -> UTCTime -> ExceptT AppError IO DaysheetReportSnapshot
persistReport state report@(D.ReportId reportId) requestKey sender cutoff capturedAt = do
    unless (any (\(D.Report key _ _ outputs) -> key == report && D.FormattedReport `elem` outputs) (D.reports state.definition)) (failure ReportNotEnabled)
    saved <- either (const (failure ReportCaptureInvalid)) pure
        (Saved.prepareSaved state.definition state.references (E.SnapshotKey (unpackId state.daysheet.venueId) (unpackId state.daysheet.id)) state.content)
    selected <- either (const (failure ReportCaptureInvalid)) pure (projectReport saved report)
    content <- either (\case ReportPayloadTooLarge -> failure ReportCaptureTooLarge; InvalidReportPayload -> failure ReportCaptureInvalid) pure (encodeReportContent selected)
    recipients <- liftIO (activeReportRecipients (unpackId state.daysheet.venueId) report)
    when (length recipients > 10000) (failure ReportCaptureTooLarge)
    snapshot <- liftIO (newRecord @DaysheetReportSnapshot
        |> set #venueId state.daysheet.venueId |> set #daysheetId state.daysheet.id
        |> set #definitionCaptureId state.daysheet.definitionCaptureId |> set #reportId reportId
        |> set #requestKey requestKey |> set #origin (if isJust cutoff then DaysheetScheduled else DaysheetManual)
        |> set #senderId (Id <$> sender) |> set #cutoffAt cutoff |> set #capturedAt capturedAt
        |> set #sourceRevision state.daysheet.revision |> set #content content
        |> set #recipientIds (Aeson.toJSON (map (unpackId . (.id)) recipients)) |> createRecord)
    forM_ recipients \recipient -> liftIO do
        _ <- enqueueExternalEmailDeliveryWithStatus ExternalEmailPayload
            { externalMailKind = daysheetReportMailKind
            , externalRecipient = recipientIdentity recipient
            , externalRecipientAddress = recipient.address
            , externalDomainReferenceId = unpackId snapshot.id
            } sender
        pure ()
    pure snapshot
