{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.Helper.JobStatus
    ( jobStatusHasDiagnostic
    , jobStatusLabel
    ) where

import IHP.Job.Types (JobStatus (..))
import IHP.Prelude

jobStatusLabel :: JobStatus -> Text
jobStatusLabel JobStatusNotStarted = "queued"
jobStatusLabel JobStatusRunning    = "running"
jobStatusLabel JobStatusRetry      = "retrying"
jobStatusLabel JobStatusSucceeded  = "succeeded"
jobStatusLabel JobStatusFailed     = "failed"
jobStatusLabel JobStatusTimedOut   = "timed out"

jobStatusHasDiagnostic :: JobStatus -> Bool
jobStatusHasDiagnostic JobStatusNotStarted = False
jobStatusHasDiagnostic JobStatusRunning    = False
jobStatusHasDiagnostic JobStatusRetry      = True
jobStatusHasDiagnostic JobStatusSucceeded  = False
jobStatusHasDiagnostic JobStatusFailed     = True
jobStatusHasDiagnostic JobStatusTimedOut   = True
