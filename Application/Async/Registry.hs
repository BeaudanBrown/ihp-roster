module Application.Async.Registry
    ( dispatchAppJob
    ) where

import Application.Billing.Notifications
import Application.Billing.Reconciliation
import Application.EmailDelivery
import Application.FwcMapd.Job
import Application.InvitationDelivery.Job
import Application.PublicHolidays.Job
import Application.WageSourceAlert.Job
import Application.Xero.Keepalive
import Application.Xero.ReferenceSyncJob
import qualified Control.Exception as Exception
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import qualified Data.Text as Text
import Generated.Types
import IHP.ControllerPrelude
import IHP.FrameworkConfig (FrameworkConfig)
import IHP.Job.Types (JobStatus (JobStatusSucceeded))

dispatchAppJob ::
    (?modelContext :: ModelContext, ?context :: FrameworkConfig) =>
    AppJob ->
    IO ()
dispatchAppJob appJob =
    dispatchAppJobByKind appJob
        `Exception.onException` do
            when (isBillingOperationalJob appJob) (void (enqueueBillingSupportNotificationAfterFinalAttempt appJob))
            when (isWageSourceRefreshJob appJob) (void (handleWageSourceRefreshFailureAfterFinalAttempt appJob))

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
        kind | kind == venueInvitationDeliveryJobKind -> performVenueInvitationDeliveryJob appJob
        kind | kind == venueOnboardingInvitationDeliveryJobKind -> performVenueOnboardingInvitationDeliveryJob appJob
        _ -> fail ("Unknown app job kind: " <> Text.unpack appJob.jobKind)

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
