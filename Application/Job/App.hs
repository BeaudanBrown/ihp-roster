module Application.Job.App where

import Application.Async.Registry (dispatchAppJob)
import Generated.Types
import IHP.Job.Types
import IHP.Prelude

instance Job AppJob where
    perform = dispatchAppJob

    maxConcurrency = 4
    timeoutInMicroseconds = Just (5 * 60 * 1000000)
