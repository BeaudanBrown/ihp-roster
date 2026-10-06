module Application.Job.DaysheetCapture where

import Application.Async.Boundary (runAppJobBoundary)
import Application.Async.Queue (appJobMaxAttempts)
import Application.Daysheet.CutoffJob (cutoffJobKind)
import Application.Daysheet.CutoffWorker (performCutoffCaptureJob)
import Application.Helper.Telemetry (withJobTelemetrySpan)
import Generated.Types
import IHP.Job.Types
import IHP.Prelude

-- Capture waits have their own bounded IHP pool. Mail and all other AppJobs keep
-- their existing four slots. The limit is per worker process, not per deployment.
instance Job DaysheetCaptureJob where
    perform job = withJobTelemetrySpan cutoffJobKind job.attemptsCount appJobMaxAttempts
        (runAppJobBoundary (performCutoffCaptureJob job))
    maxConcurrency = 8
    maxAttempts = appJobMaxAttempts
    timeoutInMicroseconds = Just (5 * 60 * 1000000)
