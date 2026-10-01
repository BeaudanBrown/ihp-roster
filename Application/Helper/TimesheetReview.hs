module Application.Helper.TimesheetReview
    ( UnapprovedTimesheetView (..)
    , fetchPeriodTimesheetEntries
    , fetchUnapprovedTimesheets
    ) where

import Generated.Types
import IHP.ControllerPrelude

-- Operational-day membership keeps overnight entries whole. Both export and
-- provider review use the same inclusive period and exclude deleted history.
data UnapprovedTimesheetView = UnapprovedTimesheetView
    { unapprovedTimesheetEntry :: TimesheetEntry
    , unapprovedTimesheetStaff :: Maybe Staff
    }
    deriving (Eq, Show)

fetchPeriodTimesheetEntries :: (?modelContext :: ModelContext) => Id Venue -> Day -> Day -> IO [TimesheetEntry]
fetchPeriodTimesheetEntries venueId periodStart periodEnd =
    query @TimesheetEntry
        |> filterWhere (#venueId, unpackId venueId)
        |> filterWhereGreaterThanOrEqualTo (#operationalDate, periodStart)
        |> filterWhereLessThan (#operationalDate, addDays 1 periodEnd)
        |> filterWhere (#deletedAt, Nothing)
        |> orderBy #operationalDate
        |> orderBy #startsAt
        |> fetch

fetchUnapprovedTimesheets :: (?modelContext :: ModelContext) => Id Venue -> Day -> Day -> IO [UnapprovedTimesheetView]
fetchUnapprovedTimesheets venueId periodStart periodEnd = do
    entries <- filter (not . (.isApproved)) <$> fetchPeriodTimesheetEntries venueId periodStart periodEnd
    staff <- if null entries then pure [] else
        query @Staff
            |> filterWhere (#venueId, unpackId venueId)
            |> filterWhereIn (#id, map (Id . (.staffId)) entries)
            |> fetch
    pure (map (\entry -> UnapprovedTimesheetView entry (find ((== entry.staffId) . unpackId . (.id)) staff)) entries)
