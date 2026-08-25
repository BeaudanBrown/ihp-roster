{-# LANGUAGE DataKinds #-}

module Application.Helper.FrontendContract.Error
    ( AppErrorContract
    , AppErrorRegistry
    ) where

import Application.Async.Error (AppJobError)
import Application.Error.Foundation (FoundationError)
import Application.Helper.FrontendContract.DSL
import Application.TimesheetApproval.Error (TimesheetApprovalError)
import Application.Xero.Timesheets.Error (XeroPreparationError)

-- Browser-visible operation failures are registered here. Domain error types
-- join this list as their request/workflow-facing slices are introduced.
data AppErrorRegistry

type AppErrorContract =
    Global AppErrorRegistry
        '[ ErrorCodes '[AppJobError, FoundationError, TimesheetApprovalError, XeroPreparationError]
         ]
