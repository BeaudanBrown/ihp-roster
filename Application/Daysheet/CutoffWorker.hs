module Application.Daysheet.CutoffWorker
    ( performCutoffCaptureJob, performCutoffCaptureJobWith
    ) where

import Application.Async.Boundary (throwAppJobError)
import Application.Async.Error (AppJobError (..))
import Application.Async.Payload (decodeAppJobPayloadV1)
import qualified Application.Daysheet.Cutoff as Cutoff
import Application.Daysheet.CutoffCapture (CutoffClock, systemCutoffClock)
import Application.Daysheet.CutoffJob
import Application.Daysheet.ReportStorage (captureScheduledReports)
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude

performCutoffCaptureJob :: (?modelContext :: ModelContext) => AppJob -> IO ()
performCutoffCaptureJob = performCutoffCaptureJobWith systemCutoffClock

performCutoffCaptureJobWith :: (?modelContext :: ModelContext) => CutoffClock -> AppJob -> IO ()
performCutoffCaptureJobWith clock job = do
    payload <- decodeAppJobPayloadV1 job :: IO CutoffJobPayload
    unless (job.jobKind == cutoffJobKind && job.relatedTable == Just "daysheets"
        && job.relatedId == Just payload.daysheetId && isNothing job.requestedByUserId)
        (throwAppJobError JobInvalidProvenance)
    venueId <- maybe (throwAppJobError JobInvalidProvenance) pure job.venueId
    source <- query @Daysheet |> filterWhere (#id, Id payload.daysheetId)
        |> filterWhere (#venueId, Id venueId) |> filterWhere (#operationalDate, payload.operationalDate) |> fetchOneOrNothing
    case source of
        Nothing -> complete 0
        Just record -> do
            meaning <- query @DaysheetDefinitionCapture |> filterWhere (#id, record.definitionCaptureId)
                |> filterWhere (#venueId, venueId) |> filterWhere (#operationalDate, payload.operationalDate) |> fetchOneOrNothing
            captured <- maybe (throwAppJobError JobInvalidProvenance) pure meaning
            plan <- either (const (throwAppJobError JobValidationRejected)) pure (Cutoff.planCutoff captured.timezone payload.operationalDate)
            unless (Cutoff.cutoffAt plan == payload.cutoffAt) (throwAppJobError JobInvalidProvenance)
            -- A committed capture survives a crash before queue acknowledgement.
            -- Retrying may acknowledge it but must never rebuild from newer data.
            previous <- countSnapshots record plan
            when (previous == 0) do
                result <- captureScheduledReports clock venueId plan
                either (const (throwAppJobError JobValidationRejected)) (const (pure ())) result
            countSnapshots record plan >>= complete
  where
    countSnapshots record plan = query @DaysheetReportSnapshot
        |> filterWhere (#venueId, record.venueId) |> filterWhere (#daysheetId, record.id)
        |> filterWhere (#origin, DaysheetScheduled) |> filterWhere (#cutoffAt, Just (Cutoff.cutoffAt plan)) |> fetchCount
    complete count = do
        _ <- job |> set #status JobStatusSucceeded |> set #lastError Nothing
            |> set #lockedAt Nothing |> set #lockedBy Nothing
            |> set #result (Aeson.object ["status" Aeson..= (if count == 0 then "skipped" :: Text else "captured"), "snapshotCount" Aeson..= count])
            |> updateRecord
        pure ()
