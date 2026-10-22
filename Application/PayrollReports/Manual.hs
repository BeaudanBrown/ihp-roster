module Application.PayrollReports.Manual (requestManualPayrollReport) where

import Application.Helper.ControllerAccess (hasRole)
import Application.Helper.ControllerContext (authenticatedCurrentUser, currentVenueId, currentVenueOrNothing)
import Application.PayrollReports.Generation
import Generated.Types
import IHP.ControllerPrelude

-- One server-issued confirmation UUID is reused on double submission/retry.
-- A historical reference preserves its original dates even after calendar edits.
requestManualPayrollReport :: (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    UUID -> Int -> Day -> Maybe UUID -> IO (Either Text PayrollReportRun)
requestManualPayrollReport confirmationId revision week previousRunId
    | isNothing currentVenueOrNothing || not (hasRole VenueAdmin) = pure (Left "Payroll report access denied.")
    | otherwise = do
        now <- getCurrentTime
        generatePayrollReportRequest ReportGenerationRequest
            { runId = confirmationId
            , venueId = currentVenueId
            , actorId = unpackId authenticatedCurrentUser.id
            , origin = if isJust previousRunId then PayrollReportUpdated else PayrollReportManual
            , scheduledAt = Nothing
            , week
            , now
            , expectedRevision = Just revision
            , previousRunId
            }
