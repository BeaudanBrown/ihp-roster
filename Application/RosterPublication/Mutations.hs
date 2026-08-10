module Application.RosterPublication.Mutations
    ( normalizePublishedRosterWindows
    , withRosterCalendarLock
    , withRosterWindowDateLock
    , withRosterWindowLock
    ) where

import qualified Database.PostgreSQL.Simple as PG
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (ModelContext, sqlExecDiscardResult, sqlQueryScalar,
                         unpackId, withTransaction)
import IHP.Prelude

-- QueryBuilder cannot express this window-function update. Keep the unavoidable
-- set-based normalization beside the publication locks that serialize it.
normalizePublishedRosterWindows :: (?modelContext :: ModelContext) => Id Venue -> Int -> IO ()
normalizePublishedRosterWindows venueId rosterWeekStartsOn =
    sqlExecDiscardResult
        "WITH published_groups AS ( \
        \    SELECT id, COUNT(*) OVER ( \
        \        PARTITION BY roster_group_id, \
        \        operational_date - (((EXTRACT(DOW FROM operational_date)::int - ? + 7) % 7)::int) \
        \    ) AS published_day_count \
        \    FROM roster_days \
        \    WHERE venue_id = ? AND publication_state = 'published' \
        \) \
        \UPDATE roster_days \
        \SET publication_state = 'draft' \
        \FROM published_groups \
        \WHERE roster_days.id = published_groups.id \
        \AND published_groups.published_day_count < 7"
        (rosterWeekStartsOn, unpackId venueId)

withRosterCalendarLock :: (?modelContext :: ModelContext) => Id Venue -> IO value -> IO value
withRosterCalendarLock venueId action =
    withTransaction do
        let lockKey = "roster-calendar:" <> tshow venueId
        _ :: Bool <- sqlQueryScalar
            "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS roster_calendar_lock"
            (PG.Only lockKey)
        action

withRosterWindowDateLock :: (?modelContext :: ModelContext) => Id Venue -> Id RosterGroup -> Day -> Day -> IO value -> IO value
withRosterWindowDateLock venueId rosterGroupId windowStart windowEnd action =
    withRosterCalendarLock venueId do
        let lockKey = "roster-window-date:" <> tshow venueId <> ":" <> tshow rosterGroupId <> ":" <> tshow windowStart <> ":" <> tshow windowEnd
        _ :: Bool <- sqlQueryScalar
            "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS roster_window_date_lock"
            (PG.Only lockKey)
        action

withRosterWindowLock :: (?modelContext :: ModelContext) => Id Venue -> Id RosterGroup -> Int -> IO value -> IO value
withRosterWindowLock venueId rosterGroupId weekOffset action =
    withRosterCalendarLock venueId do
        let lockKey = "roster-window:" <> tshow venueId <> ":" <> tshow rosterGroupId <> ":" <> tshow weekOffset
        _ :: Bool <- sqlQueryScalar
            "SELECT TRUE FROM (SELECT pg_advisory_xact_lock(hashtext(?))) AS roster_window_lock"
            (PG.Only lockKey)
        action
