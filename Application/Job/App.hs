module Application.Job.App where

import Application.Async.Queue (appJobMaxAttempts)
import Application.Async.Registry (dispatchAppJob)
import Application.Xero.ReferenceSyncJob (xeroReferenceSyncJobKind)
import Generated.Types
import IHP.Job.Types
import IHP.Prelude

instance Job AppJob where
    perform = dispatchAppJob

    maxConcurrency = 4
    maxAttempts
        | ?job.jobKind == xeroReferenceSyncJobKind = 1
        | otherwise = appJobMaxAttempts
    timeoutInMicroseconds = Just (5 * 60 * 1000000)
