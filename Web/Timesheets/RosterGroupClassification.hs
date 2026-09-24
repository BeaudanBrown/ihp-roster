module Web.Timesheets.RosterGroupClassification
    ( TimesheetRosterGroupClassification (..)
    , applyTimesheetRosterGroupClassification
    , resolveTimesheetRosterGroupForStaff
    , staffMatchesTimesheetRosterGroup
    , timesheetRosterGroupClassification
    ) where

import Generated.Types
import Web.Controller.Prelude

-- Closed application projection of the database discriminator plus conditional FK.
data TimesheetRosterGroupClassification
    = TimesheetInRosterGroup !UUID
    | TimesheetNoRosterGroup
    deriving (Eq, Show)

timesheetRosterGroupClassification :: TimesheetEntry -> TimesheetRosterGroupClassification
timesheetRosterGroupClassification entry = case (entry.rosterGroupClassification, entry.rosterGroupId) of
    (InRosterGroup, Just rosterGroupId) -> TimesheetInRosterGroup rosterGroupId
    (NoRosterGroup, Nothing) -> TimesheetNoRosterGroup
    _ -> error "Database violated Timesheet roster-group classification constraint"

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

-- Nothing means multiple memberships and therefore requires the pre-form chooser.
resolveTimesheetRosterGroupForStaff :: (?modelContext :: ModelContext) => UUID -> UUID -> IO (Maybe TimesheetRosterGroupClassification)
resolveTimesheetRosterGroupForStaff venueId staffId = do
    groupIds <- activeRosterGroupIdsForStaff venueId staffId
    pure case groupIds of
        [] -> Just TimesheetNoRosterGroup
        [groupId] -> Just (TimesheetInRosterGroup groupId)
        _ -> Nothing

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
