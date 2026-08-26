module Application.RosterNotification.Mutations
    ( lockRosterNotificationWindow
    ) where

import qualified Database.PostgreSQL.Simple as PG
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlQuery)

lockRosterNotificationWindow ::
    (?modelContext :: ModelContext) =>
    Id Venue ->
    Id RosterGroup ->
    Day ->
    Day ->
    IO ()
lockRosterNotificationWindow venueId rosterGroupId windowStart windowEnd = do
    _dayLocks :: [PG.Only UUID] <- sqlQuery
        "SELECT id FROM roster_days WHERE venue_id = ? AND roster_group_id = ? AND operational_date >= ? AND operational_date < ? ORDER BY operational_date FOR UPDATE"
        (unpackId venueId, unpackId rosterGroupId, windowStart, windowEnd)
    _laneLocks :: [PG.Only UUID] <- sqlQuery
        "SELECT roster_lanes.id FROM roster_lanes JOIN roster_days ON roster_days.id = roster_lanes.roster_day_id WHERE roster_days.venue_id = ? AND roster_days.roster_group_id = ? AND roster_days.operational_date >= ? AND roster_days.operational_date < ? ORDER BY roster_lanes.id FOR UPDATE OF roster_lanes"
        (unpackId venueId, unpackId rosterGroupId, windowStart, windowEnd)
    _slotLocks :: [PG.Only UUID] <- sqlQuery
        "SELECT roster_slots.id FROM roster_slots JOIN roster_days ON roster_days.id = roster_slots.roster_day_id WHERE roster_days.venue_id = ? AND roster_days.roster_group_id = ? AND roster_days.operational_date >= ? AND roster_days.operational_date < ? AND roster_slots.deleted_at IS NULL ORDER BY roster_slots.id FOR UPDATE OF roster_slots"
        (unpackId venueId, unpackId rosterGroupId, windowStart, windowEnd)
    pure ()
