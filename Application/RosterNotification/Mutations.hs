module Application.RosterNotification.Mutations
    ( lockRosterNotificationWeek
    ) where

import qualified Database.PostgreSQL.Simple as PG
import Generated.Types
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlQuery)

lockRosterNotificationWeek ::
    (?modelContext :: ModelContext) =>
    Id RosterWeek ->
    IO ()
lockRosterNotificationWeek rosterWeekId = do
    lockedRows <- sqlQuery
        "SELECT id FROM roster_weeks WHERE id = ? FOR UPDATE"
        (PG.Only (unpackId rosterWeekId))
        :: IO [PG.Only UUID]
    unless (length lockedRows == 1) (fail "Roster notification week no longer exists")
