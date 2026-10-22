module Application.PayrollReports.Job
    ( payrollReportJobKind
    , enqueuePayrollReportSweep
    , performPayrollReportJob
    , nextScheduledPayrollReport
    ) where

import Application.Async.Payload (decodeAppJobPayloadV1)
import Application.Async.Queue
import Application.EmailDelivery.Group (enqueuePayrollReportOutcome)
import Application.PayrollReports.Generation
import Application.PayrollReports.Schedule
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude

payrollReportJobKind :: Text
payrollReportJobKind = "payroll_report_generate"

data ScheduledReportPayload = ScheduledReportPayload
    { dueAt :: !UTCTime
    , reportingWeek :: !Day
    , settingsRevision :: !Int
    }

instance Aeson.FromJSON ScheduledReportPayload where
    parseJSON = Aeson.withObject "ScheduledReportPayload" \value ->
        ScheduledReportPayload <$> value Aeson..: "dueAt" <*> value Aeson..: "reportingWeek" <*> value Aeson..: "settingsRevision"

-- The deployment timer only enqueues work. IHP's existing worker owns execution,
-- concurrency, sanitized errors and retries. No parallel application scheduler.
enqueuePayrollReportSweep :: (?modelContext :: ModelContext) => IO Int
enqueuePayrollReportSweep = do
    settings <- query @PayrollReportSetting |> filterWhere (#enabled, True) |> fetch
    results <- forM settings \setting -> nextScheduledPayrollReport setting >>= \case
        Nothing -> pure 0
        Just (dueAt, week) -> do
            void $ enqueueAppJob AppJobRequest
                { jobKind = payrollReportJobKind
                , payload = Aeson.object ["dueAt" Aeson..= dueAt, "reportingWeek" Aeson..= week, "settingsRevision" Aeson..= setting.revision]
                , payloadSchemaVersion = 1
                , requestedByUserId = Just setting.updatedByUserId
                , venueId = Just setting.venueId
                , relatedTable = Just "payroll_report_settings"
                , relatedId = Just (unpackId setting.id)
                , dedupeKey = Just ("payroll-report/" <> tshow setting.id <> "/" <> tshow setting.revision <> "/" <> tshow dueAt)
                , runAt = Just dueAt
                }
            pure 1
    pure (sum results)

nextScheduledPayrollReport :: (?modelContext :: ModelContext) => PayrollReportSetting -> IO (Maybe (UTCTime, Day))
nextScheduledPayrollReport setting
    | not setting.enabled = pure Nothing
    | otherwise = do
        config <- query @VenueConfig |> filterWhere (#venueId, setting.venueId) |> fetchOneOrNothing
        previous <- query @PayrollReportRun |> filterWhere (#venueId, setting.venueId)
            |> filterWhere (#origin, PayrollReportScheduled) |> orderByDesc #scheduledAt |> fetchOneOrNothing
        case config of
            Nothing -> pure Nothing
            Just config -> seek config 0 (max setting.scheduleActivatedAt (fromMaybe setting.scheduleActivatedAt (previous >>= (.scheduledAt))))
  where
    -- At most one already-processed period can overlap a changed weekly time;
    -- the bounded loop also fails closed on malformed historical state.
    seek :: (?modelContext :: ModelContext) => VenueConfig -> Int -> UTCTime -> IO (Maybe (UTCTime, Day))
    seek config attempts after
        | attempts >= 8 = pure Nothing
        | otherwise = case nextReportOccurrence config.timezone setting.weekday setting.minuteOfDay after of
            Left _ -> pure Nothing
            Right due -> do
                let week = reportWeekForOccurrence config.rosterWeekStartsOn due
                exists <- query @PayrollReportRun |> filterWhere (#venueId, setting.venueId)
                    |> filterWhere (#origin, PayrollReportScheduled) |> filterWhere (#reportingWeek, week) |> fetchExists
                if exists then seek config (attempts + 1) due else pure (Just (due, week))

performPayrollReportJob :: (?modelContext :: ModelContext) => AppJob -> IO ()
performPayrollReportJob job = do
    payload :: ScheduledReportPayload <- decodeAppJobPayloadV1 job
    settings <- case job.relatedId of
        Nothing -> pure Nothing
        Just settingId -> query @PayrollReportSetting |> filterWhere (#id, Id settingId) |> fetchOneOrNothing
    case settings of
        Just setting | Just setting.venueId == job.venueId && setting.enabled && setting.revision == payload.settingsRevision -> do
            now <- getCurrentTime
            outcome <- generatePayrollReportRequest ReportGenerationRequest
                { runId = unpackId job.id
                , venueId = Id setting.venueId
                , actorId = setting.updatedByUserId
                , origin = PayrollReportScheduled
                , scheduledAt = Just payload.dueAt
                , week = payload.reportingWeek
                , now
                , expectedRevision = Just setting.revision
                , previousRunId = Nothing
                }
            case outcome of
                Left _ -> finish "obsolete_or_invalid"
                Right run -> enqueuePayrollReportOutcome run >> finish "generated"
        _ -> finish "obsolete"
  where
    finish status = void $ job |> set #status JobStatusSucceeded
        |> set #result (Aeson.object ["reportGeneration" Aeson..= (status :: Text)])
        |> set #lastError Nothing |> set #lockedAt Nothing |> set #lockedBy Nothing |> updateRecord
