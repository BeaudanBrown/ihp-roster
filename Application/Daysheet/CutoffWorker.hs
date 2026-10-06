module Application.Daysheet.CutoffWorker
    ( performCutoffCaptureJob, performCutoffCaptureJobWith
    , handoffCutoffCaptureJob, handoffCutoffCaptureJobWith
    ) where

import Application.Async.Boundary (throwAppJobError)
import Application.Async.Error (AppJobError (..))
import Application.Async.Payload (decodeAppJobPayloadV1)
import qualified Application.Daysheet.Cutoff as Cutoff
import Application.Daysheet.CutoffCapture (CutoffClock (..), systemCutoffClock)
import Application.Daysheet.CutoffJob
import Application.Daysheet.Locks (lockDaysheetVenue)
import Application.Daysheet.ReportStorage (captureScheduledReports)
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude

performCutoffCaptureJob :: (?modelContext :: ModelContext) => DaysheetCaptureJob -> IO ()
performCutoffCaptureJob = performCutoffCaptureJobWith systemCutoffClock

performCutoffCaptureJobWith :: (?modelContext :: ModelContext) => CutoffClock -> DaysheetCaptureJob -> IO ()
performCutoffCaptureJobWith clock job = do
    source <- query @Daysheet |> filterWhere (#id, job.daysheetId) |> fetchOneOrNothing
    count <- case source of
        Nothing -> throwAppJobError JobInvalidProvenance
        Just record -> do
            plan <- checkedPlan record job.cutoffAt
            -- A committed capture survives a crash before queue acknowledgement.
            -- Retrying acknowledges it but never rebuilds from newer data.
            previous <- countSnapshots record plan
            when (previous == 0) do
                result <- captureScheduledReports clock (unpackId record.venueId) plan
                either (const (throwAppJobError JobValidationRejected)) (const (pure ())) result
            countSnapshots record plan
    _ <- job |> set #status JobStatusSucceeded |> set #lastError Nothing
        |> set #lockedAt Nothing |> set #lockedBy Nothing
        |> set #result (Aeson.object ["status" Aeson..= (if count == 0 then "skipped" :: Text else "captured"), "snapshotCount" Aeson..= count])
        |> updateRecord
    pure ()
  where
    countSnapshots record plan = query @DaysheetReportSnapshot
        |> filterWhere (#venueId, record.venueId) |> filterWhere (#daysheetId, record.id)
        |> filterWhere (#origin, DaysheetScheduled) |> filterWhere (#cutoffAt, Just (Cutoff.cutoffAt plan)) |> fetchCount

checkedPlan :: (?modelContext :: ModelContext) => Daysheet -> UTCTime -> IO Cutoff.CutoffPlan
checkedPlan record expected = do
    meaning <- query @DaysheetDefinitionCapture |> filterWhere (#id, record.definitionCaptureId)
        |> filterWhere (#venueId, unpackId record.venueId) |> filterWhere (#operationalDate, record.operationalDate) |> fetchOneOrNothing
    captured <- maybe (throwAppJobError JobInvalidProvenance) pure meaning
    plan <- either (const (throwAppJobError JobValidationRejected)) pure (Cutoff.planCutoff captured.timezone record.operationalDate)
    unless (Cutoff.cutoffAt plan == expected) (throwAppJobError JobInvalidProvenance)
    pure plan

-- Compatibility for already-persisted AppJobs. Ordinary worker slots never wait
-- until cutoff: atomically hand off to the dedicated queue, then acknowledge.
-- No migration deletes/reinterprets old jobs, and repeated handoffs converge.
handoffCutoffCaptureJob :: (?modelContext :: ModelContext) => AppJob -> IO ()
handoffCutoffCaptureJob = handoffCutoffCaptureJobWith systemCutoffClock

handoffCutoffCaptureJobWith :: (?modelContext :: ModelContext) => CutoffClock -> AppJob -> IO ()
handoffCutoffCaptureJobWith clock job = do
    payload <- decodeAppJobPayloadV1 job :: IO CutoffJobPayload
    unless (job.jobKind == cutoffJobKind && job.relatedTable == Just "daysheets"
        && job.relatedId == Just payload.daysheetId && isNothing job.requestedByUserId)
        (throwAppJobError JobInvalidProvenance)
    venueId <- maybe (throwAppJobError JobInvalidProvenance) pure job.venueId
    withTransaction do
        locked <- lockDaysheetVenue venueId
        unless locked (throwAppJobError JobInvalidProvenance)
        source <- query @Daysheet |> filterWhere (#id, Id payload.daysheetId)
            |> filterWhere (#venueId, Id venueId) |> filterWhere (#operationalDate, payload.operationalDate) |> fetchOneOrNothing
        outcome <- case source of
            Nothing -> pure "skipped"
            Just record -> do
                plan <- checkedPlan record payload.cutoffAt
                now <- clock.now
                enqueueCutoffCapture now record plan
                pure (if now < Cutoff.cutoffAt plan then "delegated" else "skipped")
        _ <- job |> set #status JobStatusSucceeded |> set #lastError Nothing
            |> set #lockedAt Nothing |> set #lockedBy Nothing
            |> set #result (Aeson.object ["status" Aeson..= (outcome :: Text)]) |> updateRecord
        pure ()
