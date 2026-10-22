module Application.PayrollReports.Notifications (notifyPayrollReportFailure) where

import Application.OperationalIncident
import Control.Monad (void)
import qualified Data.Aeson as Aeson
import Generated.Types
import IHP.ControllerPrelude

notifyPayrollReportFailure :: (?modelContext :: ModelContext) => PayrollReportRun -> IO ()
notifyPayrollReportFailure run = forM_ failureCategory \category -> do
    now <- getCurrentTime
    void $ reconcileOperationalIncident IncidentObservation
        { category = "payroll_report"
        , scopeKey = tshow run.venueId
        , stableIdentity = tshow run.id
        , affectedSource = "payroll_reporting"
        , venueId = Just run.venueId
        , observedAt = now
        , isActive = True
        , severity = IncidentWarning
        , impactKey = category
        , impactRank = 20
        , symptomCodes = [category]
        , safeMetadata = Aeson.object
            [ "venueId" Aeson..= run.venueId
            , "reportingWeek" Aeson..= run.reportingWeek
            , "reportRunId" Aeson..= unpackId run.id
            , "failureCategory" Aeson..= category
            ]
        }
  where
    failureCategory = case run.status of
        PayrollReportFailed -> Just "generation_or_delivery_failed"
        PayrollReportMissed -> Just "scheduled_window_missed"
        PayrollReportBounced -> Just "recipient_delivery_failure"
        PayrollReportAmbiguous -> Just "delivery_acceptance_unknown"
        PayrollReportReady -> Nothing
        PayrollReportNoData -> Nothing
        PayrollReportCancelled -> Nothing
        PayrollReportQueued -> Nothing
        PayrollReportAccepted -> Nothing
        PayrollReportDisabled -> Nothing
