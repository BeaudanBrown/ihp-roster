module Application.Async.Registry
    ( dispatchAppJob
    ) where

import Application.Async.Boundary (runAppJobBoundary, throwAppJobError)
import Application.Async.Error (AppJobError (JobUnknownKind))
import Application.Async.Queue (appJobMaxAttempts)
import Application.Billing.Notifications
import Application.Billing.Reconciliation
import Application.EmailDelivery
import Application.FwcMapd.Job
import Application.Helper.Telemetry (withJobTelemetrySpan)
import Application.PublicHolidays.Job
import Application.WageSourceAlert.Job
import Application.Xero.Keepalive
import Application.Xero.ReferenceSyncJob
import qualified Control.Exception.Safe as Exception
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude

dispatchAppJob ::
    (?modelContext :: ModelContext, ?context :: FrameworkConfig) =>
    AppJob ->
    IO ()
dispatchAppJob appJob =
    withJobTelemetrySpan
        (registeredJobKindForTelemetry appJob.jobKind)
        appJob.attemptsCount
        (jobMaximumAttempts appJob.jobKind)
        $ runAppJobBoundary
        $ dispatchAppJobByKind appJob
            `Exception.onException` do
                when (isBillingOperationalJob appJob) (void (enqueueBillingSupportNotificationAfterFinalAttempt appJob))
                when (isWageSourceRefreshJob appJob) (void (handleWageSourceRefreshFailureAfterFinalAttempt appJob))
                handleEmailDeliveryFailureAfterFinalAttempt appJob

registeredJobKindForTelemetry :: Text -> Text
registeredJobKindForTelemetry kind
    | kind `elem` registeredJobKinds = kind
    | otherwise = "unknown"

jobMaximumAttempts :: Text -> Int
jobMaximumAttempts kind
    | kind == xeroReferenceSyncJobKind = 1
    | otherwise = appJobMaxAttempts

registeredJobKinds :: [Text]
registeredJobKinds =
    [ emailDeliveryJobKind
    , fwcMapdRefreshJobKind
    , publicHolidayRefreshJobKind
    , wageSourceHealthCheckJobKind
    , retiredRosterTimesheetCreationJobKind
    , xeroConnectionKeepaliveJobKind
    , xeroReferenceSyncJobKind
    , billingReconciliationJobKind
    ]

dispatchAppJobByKind ::
    (?modelContext :: ModelContext, ?context :: FrameworkConfig) =>
    AppJob ->
    IO ()
dispatchAppJobByKind appJob =
    case appJob.jobKind of
        kind | kind == emailDeliveryJobKind -> performEmailDeliveryJob appJob
        kind | kind == fwcMapdRefreshJobKind -> performFwcMapdRefreshJob appJob
        kind | kind == publicHolidayRefreshJobKind -> performPublicHolidayRefreshJob appJob
        kind | kind == wageSourceHealthCheckJobKind -> performWageSourceHealthCheckJob appJob
        kind | kind == retiredRosterTimesheetCreationJobKind -> retireRosterTimesheetCreationJob appJob
        kind | kind == xeroConnectionKeepaliveJobKind -> performXeroConnectionKeepaliveJob appJob
        kind | kind == xeroReferenceSyncJobKind -> performXeroReferenceSyncJob appJob
        kind | kind == billingReconciliationJobKind -> performBillingReconciliationJob appJob
        _ -> throwAppJobError JobUnknownKind

isWageSourceRefreshJob :: AppJob -> Bool
isWageSourceRefreshJob appJob =
    appJob.jobKind == fwcMapdRefreshJobKind
        || appJob.jobKind == publicHolidayRefreshJobKind

isBillingOperationalJob :: AppJob -> Bool
isBillingOperationalJob appJob =
    appJob.jobKind == billingReconciliationJobKind

retiredRosterTimesheetCreationJobKind :: Text
retiredRosterTimesheetCreationJobKind = "roster_timesheet_creation"

-- Deploys may encounter a job claimed just before the retirement migration ran.
-- Completing it as retired guarantees the new runtime can never create a row.
retireRosterTimesheetCreationJob :: (?modelContext :: ModelContext) => AppJob -> IO ()
retireRosterTimesheetCreationJob appJob =
    void
        ( appJob
            |> set #status JobStatusSucceeded
            |> set #result
                ( Aeson.object
                    [ "status" Aeson..= ("retired" :: Text)
                    , "reason" Aeson..= ("replaced_by_roster_timesheet_suggestions" :: Text)
                    ]
                )
            |> set #lastError Nothing
            |> set #lockedAt Nothing
            |> set #lockedBy Nothing
            |> updateRecord
        )
