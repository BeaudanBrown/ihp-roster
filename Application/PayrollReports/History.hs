{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

-- | Venue-authorised history, grouped by reporting period rather than execution
-- count. Dates are the immutable historical dates, not today's roster calendar.
module Application.PayrollReports.History
    ( PayrollReportWeek (..)
    , fetchPayrollReportHistory
    , groupPayrollReportHistory
    , payrollReportStatusLabel
    , payrollReportOriginLabel
    ) where

import Application.Helper.ControllerAccess (hasRole)
import Application.Helper.ControllerContext (currentVenueId, currentVenueOrNothing)
import Application.PayrollReports.Settings (PayrollReportSettingsError (..))
import qualified Data.List as List
import Generated.Types
import IHP.ControllerPrelude

data PayrollReportWeek = PayrollReportWeek
    { reportingWeek :: !Day
    , executions :: ![PayrollReportRun]
    }

fetchPayrollReportHistory :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO (Either PayrollReportSettingsError [PayrollReportWeek])
fetchPayrollReportHistory
    | isNothing currentVenueOrNothing || not (hasRole VenueAdmin) = pure (Left PayrollReportAccessDenied)
    | otherwise = do
        -- Limit periods, never executions: repeated manual sends must not hide
        -- earlier weeks. Both queries are scoped before any rows are returned.
        periods <- query @PayrollReportRun
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> distinctOn #reportingWeek
            |> orderByDesc #reportingWeek
            |> limit 4
            |> fetch
        runs <- query @PayrollReportRun
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhereIn (#reportingWeek, map (.reportingWeek) periods)
            |> orderByDesc #createdAt
            |> fetch
        pure (Right (groupPayrollReportHistory runs))

groupPayrollReportHistory :: [PayrollReportRun] -> [PayrollReportWeek]
groupPayrollReportHistory = take 4 . mapMaybe toWeek . List.groupBy sameWeek . List.sortOn ordering
  where
    ordering run = (Down run.reportingWeek, Down run.createdAt, Down run.id)
    sameWeek left right = left.reportingWeek == right.reportingWeek
    toWeek [] = Nothing
    toWeek runs@(first : _) = Just PayrollReportWeek { reportingWeek = first.reportingWeek, executions = runs }

-- Provider acceptance is not evidence of inbox delivery. Uncertain transport
-- results require an explicit whole-list resend, never an automatic replay.
payrollReportStatusLabel :: PayrollReportStatusEnum -> Text
payrollReportStatusLabel = \case
    PayrollReportReady -> "Preparing delivery"
    PayrollReportNoData -> "Preparing no-data email"
    PayrollReportQueued -> "Queued"
    PayrollReportAccepted -> "Accepted by email provider — inbox delivery not confirmed"
    PayrollReportBounced -> "Delivery problem — some recipients may have received the email"
    PayrollReportAmbiguous -> "Delivery uncertain — some recipients may have received the email"
    PayrollReportFailed -> "Failed"
    PayrollReportMissed -> "Missed — outside the 24-hour catch-up window"
    PayrollReportCancelled -> "Cancelled"
    PayrollReportDisabled -> "Not sent — email delivery disabled"

payrollReportOriginLabel :: PayrollReportOriginEnum -> Text
payrollReportOriginLabel = \case
    PayrollReportScheduled -> "Automatic"
    PayrollReportManual -> "Manual"
    PayrollReportUpdated -> "Updated resend"
