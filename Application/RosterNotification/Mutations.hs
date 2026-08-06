module Application.RosterNotification.Mutations
    ( CreateRosterNotificationRunResult (..)
    , createRosterNotificationRunUnlessActive
    ) where

import Application.Async.Queue (activeAppJobStatuses)
import qualified Application.RosterNotification as Notification
import qualified Database.PostgreSQL.Simple as PG
import Generated.Types hiding (createRosterNotificationRun)
import IHP.ControllerPrelude
import IHP.ModelSupport (sqlQuery, withTransaction)

data CreateRosterNotificationRunResult
    = RosterNotificationRunCreated !RosterNotificationRun
    | RosterNotificationRunAlreadyActive
    | RosterNotificationRunHasNoEligibleRecipients
    deriving (Eq, Show)

createRosterNotificationRunUnlessActive ::
    (?modelContext :: ModelContext) =>
    User ->
    RosterWeek ->
    IO CreateRosterNotificationRunResult
createRosterNotificationRunUnlessActive actor rosterWeek =
    withTransaction do
        lockRosterNotificationWeek rosterWeek.id
        runs <- query @RosterNotificationRun
            |> filterWhere (#rosterWeekId, unpackId rosterWeek.id)
            |> fetch
        let runIds = map (Just . unpackId . (.id)) runs
        activeDeliveryExists <-
            if null runIds
                then pure False
                else query @AppJob
                    |> filterWhere (#relatedTable, Just "roster_notification_runs")
                    |> filterWhereIn (#relatedId, runIds)
                    |> filterWhereIn (#status, activeAppJobStatuses)
                    |> fetchExists
        if activeDeliveryExists
            then pure RosterNotificationRunAlreadyActive
            else do
                venue <- fetch (Id rosterWeek.venueId :: Id Venue)
                rosterGroup <- fetch (Id rosterWeek.rosterGroupId :: Id RosterGroup)
                audience <- Notification.fetchRosterNotificationAudience venue rosterGroup
                if null audience.audienceRecipients
                    then pure RosterNotificationRunHasNoEligibleRecipients
                    else RosterNotificationRunCreated <$> Notification.createRosterNotificationRunInCurrentTransaction actor rosterWeek

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
