module Application.RosterPublication
    ( fetchRosterWeekHasPublishedDay
    , fetchRosterWeekIsPublished
    , rosterDaysArePublished
    ) where

import Application.Helper.WeekBoundaries (venueWeekStartDate)
import Data.List (nub)
import Data.Time.Calendar (addDays)
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (ModelContext)
import IHP.Prelude

rosterDaysArePublished :: [RosterDay] -> Bool
rosterDaysArePublished rosterDays =
    length rosterDays == 7
        && length (nub (map (.operationalDate) rosterDays)) == 7
        && all ((== Published) . (.publicationState)) rosterDays

fetchRosterWeekHasPublishedDay :: (?modelContext :: ModelContext) => RosterWeek -> IO Bool
fetchRosterWeekHasPublishedDay rosterWeek =
    any ((== Published) . (.publicationState)) <$> fetchRosterWeekDays rosterWeek

fetchRosterWeekIsPublished :: (?modelContext :: ModelContext) => RosterWeek -> IO Bool
fetchRosterWeekIsPublished rosterWeek =
    rosterDaysArePublished <$> fetchRosterWeekDays rosterWeek

fetchRosterWeekDays :: (?modelContext :: ModelContext) => RosterWeek -> IO [RosterDay]
fetchRosterWeekDays rosterWeek = do
    venueConfig <- query @VenueConfig
        |> filterWhere (#venueId, rosterWeek.venueId)
        |> fetchOne
    let windowStartDate = venueWeekStartDate venueConfig rosterWeek.weekOffset
        windowEndDate = addDays 6 windowStartDate
    rosterDays <- query @RosterDay
        |> filterWhere (#venueId, rosterWeek.venueId)
        |> filterWhere (#rosterGroupId, rosterWeek.rosterGroupId)
        |> filterWhereGreaterThanOrEqualTo (#operationalDate, windowStartDate)
        |> filterWhereLessThanOrEqualTo (#operationalDate, windowEndDate)
        |> fetch
    pure rosterDays
