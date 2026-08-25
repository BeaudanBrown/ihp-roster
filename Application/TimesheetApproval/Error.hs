{-# LANGUAGE DeriveGeneric #-}

module Application.TimesheetApproval.Error
    ( TimesheetApprovalError (..)
    ) where

import Application.Error.Domain (AppErrorProjection (..), DomainError (..))
import Application.Error.Types
import GHC.Generics (Generic)
import IHP.Prelude

data TimesheetApprovalError
    = ApprovalStillBlocked
    | ApprovalControlStale
    | ApprovalProviderWriteActive
    | ApprovalRefreshLockTimedOut
    | ApprovalEntryUnavailable
    deriving (Eq, Generic, Show)

instance DomainError TimesheetApprovalError where
    appErrorProjection ApprovalStillBlocked = AppErrorProjection
        { safeMessage = "This Timesheet approval is still blocked by current pay facts or Xero mappings. Resolve the blocker and try again."
        , severity = Blocking
        , recovery = UserActionRequired
        , retryDirective = DoNotRetry
        }
    appErrorProjection ApprovalControlStale = AppErrorProjection
        { safeMessage = "This Timesheet approval changed after the preparation page loaded. Refresh the preparation and review it again."
        , severity = Blocking
        , recovery = UserActionRequired
        , retryDirective = DoNotRetry
        }
    appErrorProjection ApprovalProviderWriteActive = AppErrorProjection
        { safeMessage = "Xero is currently writing this Timesheet. Wait for reconciliation to finish before refreshing its approval."
        , severity = Blocking
        , recovery = Retryable
        , retryDirective = RetryAfter 5
        }
    appErrorProjection ApprovalRefreshLockTimedOut = AppErrorProjection
        { safeMessage = "This Timesheet is busy. Refresh the preparation and try again."
        , severity = Blocking
        , recovery = Retryable
        , retryDirective = RetryAfter 1
        }
    appErrorProjection ApprovalEntryUnavailable = AppErrorProjection
        { safeMessage = "This Timesheet is no longer available for approval refresh."
        , severity = Blocking
        , recovery = UserActionRequired
        , retryDirective = DoNotRetry
        }
