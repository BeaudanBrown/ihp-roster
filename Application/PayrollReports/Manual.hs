module Application.PayrollReports.Manual
    ( requestManualPayrollReport
    , completedPayrollReportWeeks
    , ManualPayrollReportPreview (..)
    , previewManualPayrollReport
    , requestSelectedManualPayrollReport
    ) where

import Application.Helper.ControllerAccess (hasRole)
import Application.Helper.ControllerContext (authenticatedCurrentUser, currentVenueId, currentVenueOrNothing)
import Application.EmailDelivery.Group (enqueuePayrollReportOutcome)
import Application.PayrollReports.Generation
import Application.PayrollReports.Selection
import Application.VenueTime.Model (storedInstantLocalTime)
import Application.Helper.WeekBoundaries (startOfWeekFor)
import Generated.Types
import IHP.ControllerPrelude

-- Latest completed week first, including empty weeks since the venue's first
-- relevant date. A newly created venue still offers the previous complete week.
completedPayrollReportWeeks :: Int -> Day -> Day -> [Day]
completedPayrollReportWeeks startsOn today earliest =
    takeWhile (>= firstWeek) (iterate (addDays (-7)) latestWeek)
  where
    latestWeek = addDays (-7) (startOfWeekFor startsOn today)
    firstWeek = min latestWeek (startOfWeekFor startsOn earliest)

-- One server-issued confirmation UUID is reused on double submission/retry.
-- A historical reference preserves its original dates even after calendar edits.
requestManualPayrollReport :: (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    UUID -> Int -> Day -> Maybe UUID -> IO (Either Text PayrollReportRun)
requestManualPayrollReport confirmationId revision week previousRunId
    | isNothing currentVenueOrNothing || not (hasRole VenueAdmin) = pure (Left "Payroll report access denied.")
    | otherwise = do
        now <- getCurrentTime
        outcome <- generatePayrollReportRequest ReportGenerationRequest
            { runId = confirmationId
            , venueId = currentVenueId
            , actorId = unpackId authenticatedCurrentUser.id
            , origin = if isJust previousRunId then PayrollReportUpdated else PayrollReportManual
            , scheduledAt = Nothing
            , week
            , now
            , expectedRevision = Just revision
            , previousRunId
            , manualSelection = Nothing
            }
        case outcome of
            Left _ -> pure outcome
            Right run -> enqueuePayrollReportOutcome run >> pure outcome

-- Contains private group addresses for rendering only; intentionally no Show.
data ManualPayrollReportPreview = ManualPayrollReportPreview
    { selected :: !SelectedPayrollReport
    , selection :: !ManualReportSelection
    , reportingWeek :: !Day
    , repeatWarning :: !Bool
    }

previewManualPayrollReport :: (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    UUID -> UUID -> Day -> IO (Either Text ManualPayrollReportPreview)
previewManualPayrollReport configurationId groupId week
    | isNothing currentVenueOrNothing || not (hasRole VenueAdmin) = pure (Left "Payroll report access denied.")
    | otherwise = loadSelectedPayrollReport currentVenueId configurationId groupId >>= \case
        Left message -> pure (Left message)
        Right selected -> do
            now <- getCurrentTime
            case storedInstantLocalTime selected.config.timezone now of
                Left _ -> pure (Left "The venue timezone is unavailable.")
                Right localNow
                    | not (validCompletedReportWeek selected.config.rosterWeekStartsOn (localDay localNow) week) -> pure (Left "Choose a completed roster week.")
                    | otherwise -> do
                        repeatWarning <- payrollReportAlreadyPrepared currentVenueId configurationId week
                        pure (Right ManualPayrollReportPreview
                            { selected, selection = selectedReportConfirmation selected, reportingWeek = week, repeatWarning })

requestSelectedManualPayrollReport :: (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    UUID -> ManualReportSelection -> Day -> IO (Either Text PayrollReportRun)
requestSelectedManualPayrollReport confirmationId selection week
    | isNothing currentVenueOrNothing || not (hasRole VenueAdmin) = pure (Left "Payroll report access denied.")
    | otherwise = do
        now <- getCurrentTime
        outcome <- generatePayrollReportRequest ReportGenerationRequest
            { runId = confirmationId
            , venueId = currentVenueId
            , actorId = unpackId authenticatedCurrentUser.id
            , origin = PayrollReportManual
            , scheduledAt = Nothing
            , week, now
            , expectedRevision = Nothing
            , previousRunId = Nothing
            , manualSelection = Just selection
            }
        case outcome of
            Left _ -> pure outcome
            Right run -> enqueuePayrollReportOutcome run >> pure outcome
