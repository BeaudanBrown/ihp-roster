module Web.Timesheets.RosterGroupClassification
    ( TimesheetRosterGroupClassification (..)
    , applyTimesheetRosterGroupClassification
    , staffMatchesTimesheetRosterGroup
    , validTimesheetRosterGroupClassificationsForStaff
    , timesheetRosterGroupClassification
    ) where

import Generated.Types
import Web.Controller.Prelude

-- Closed application projection of the database discriminator plus conditional FK.
data TimesheetRosterGroupClassification
    = TimesheetInRosterGroup !UUID
    | TimesheetNoRosterGroup
    deriving (Eq, Ord, Show)

timesheetRosterGroupClassification :: TimesheetEntry -> Maybe TimesheetRosterGroupClassification
timesheetRosterGroupClassification entry = case (entry.rosterGroupClassification, entry.rosterGroupId) of
    (InRosterGroup, Just rosterGroupId) -> Just (TimesheetInRosterGroup rosterGroupId)
    (NoRosterGroup, Nothing) -> Just TimesheetNoRosterGroup
    _ -> Nothing

applyTimesheetRosterGroupClassification :: TimesheetRosterGroupClassification -> TimesheetEntry -> TimesheetEntry
applyTimesheetRosterGroupClassification classification entry = case classification of
    TimesheetInRosterGroup rosterGroupId ->
        entry
            |> set #rosterGroupClassification InRosterGroup
            |> set #rosterGroupId (Just rosterGroupId)
    TimesheetNoRosterGroup ->
        entry
            |> set #rosterGroupClassification NoRosterGroup
            |> set #rosterGroupId Nothing

validTimesheetRosterGroupClassificationsForStaff :: (?modelContext :: ModelContext) => UUID -> UUID -> IO [TimesheetRosterGroupClassification]
validTimesheetRosterGroupClassificationsForStaff venueId staffId = do
    groupIds <- activeRosterGroupIdsForStaff venueId staffId
    pure case groupIds of
        [] -> [TimesheetNoRosterGroup]
        _ -> map TimesheetInRosterGroup groupIds

staffMatchesTimesheetRosterGroup :: (?modelContext :: ModelContext) => UUID -> UUID -> TimesheetRosterGroupClassification -> IO Bool
staffMatchesTimesheetRosterGroup venueId staffId classification = do
    groupIds <- activeRosterGroupIdsForStaff venueId staffId
    pure case classification of
        TimesheetInRosterGroup groupId -> groupId `elem` groupIds
        TimesheetNoRosterGroup -> null groupIds

activeRosterGroupIdsForStaff :: (?modelContext :: ModelContext) => UUID -> UUID -> IO [UUID]
activeRosterGroupIdsForStaff venueId staffId = do
    memberships <-
        query @StaffRosterGroup
            |> filterWhere (#staffId, staffId)
            |> filterWhere (#deletedAt, Nothing)
            |> fetch
    let membershipGroupIds = map (.rosterGroupId) memberships
    if null membershipGroupIds
        then pure []
        else do
            groups <-
                query @RosterGroup
                    |> filterWhere (#venueId, venueId)
                    |> filterWhereIn (#id, map Id membershipGroupIds)
                    |> filterWhere (#isActive, True)
                    |> filterWhere (#archivedAt, Nothing)
                    |> orderByAsc #sortOrder
                    |> orderByAsc #id
                    |> fetch
            pure (map (unpackId . (.id)) groups)
