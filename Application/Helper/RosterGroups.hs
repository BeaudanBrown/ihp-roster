{-# LANGUAGE LambdaCase          #-}
{-# LANGUAGE OverloadedRecordDot #-}

module Application.Helper.RosterGroups where

import Application.Helper.Controller (currentUserIsUnimpersonatedSuperAdmin,
                                      currentVenueId, fetchCurrentUserStaff,
                                      hasRole)
import Application.Helper.Staff (sortStaffForDisplay)
import Application.Helper.WeekBoundaries (defaultRosterWeekStartsOn,
                                          sortDayNamesForVenueWeek)
import qualified Data.Set as Set
import Generated.Types
import IHP.ControllerPrelude

defaultRosterGroupName :: Text
defaultRosterGroupName = "Main"

defaultRosterSlotNames :: [Text]
defaultRosterSlotNames = ["Early", "Mid", "Late"]

defaultVenueDayNames :: [(Int, Text)]
defaultVenueDayNames =
    [ (1, "Monday")
    , (2, "Tuesday")
    , (3, "Wednesday")
    , (4, "Thursday")
    , (5, "Friday")
    , (6, "Saturday")
    , (0, "Sunday")
    ]

ensureVenueRosterDefaults :: (?modelContext :: ModelContext) => Venue -> IO RosterGroup
ensureVenueRosterDefaults venue =
    do
        _ <- ensureVenueConfigRecord venue
        _ <- ensureVenueDayNames venue
        rosterGroup <- ensureVenueDefaultRosterGroup venue
        _ <- ensureDefaultRosterSlots venue rosterGroup
        pure rosterGroup

createVenueRosterGroupWithDefaults :: (?modelContext :: ModelContext) => Venue -> Text -> Int -> Bool -> IO RosterGroup
createVenueRosterGroupWithDefaults venue name sortOrder isActive = do
    rosterGroup <-
        newRecord @RosterGroup
            |> set #venueId (unpackId venue.id)
            |> set #name name
            |> set #sortOrder sortOrder
            |> set #isActive isActive
            |> set #isDefault False
            |> createRecord
    when isActive do
        _ <- ensureDefaultRosterSlots venue rosterGroup
        pure ()
    pure rosterGroup

syncVenueDefaultRosterGroupToTopActive :: (?modelContext :: ModelContext) => Id Venue -> IO ()
syncVenueDefaultRosterGroupToTopActive venueId = do
    rosterGroups <-
        query @RosterGroup
            |> filterWhere (#venueId, unpackId venueId)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> orderByAsc #sortOrder
            |> orderByAsc #createdAt
            |> fetch
    forM_ (find (.isActive) rosterGroups) \topActiveGroup -> do
        _ <- setVenueDefaultRosterGroup venueId topActiveGroup.id
        pure ()

fetchCurrentVenueDefaultRosterGroup :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO RosterGroup
fetchCurrentVenueDefaultRosterGroup = do
    venue <- fetch currentVenueId
    ensureVenueRosterDefaults venue

fetchCurrentVenueRosterGroups :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [RosterGroup]
fetchCurrentVenueRosterGroups =
    query @RosterGroup
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch

setVenueDefaultRosterGroup :: (?modelContext :: ModelContext) => Id Venue -> Id RosterGroup -> IO RosterGroup
setVenueDefaultRosterGroup venueId rosterGroupId = do
    rosterGroups <-
        query @RosterGroup
            |> filterWhere (#venueId, unpackId venueId)
            |> filterWhere (#archivedAt, Nothing)
            |> fetch
    forM_ rosterGroups \rosterGroup ->
        when (rosterGroup.id /= rosterGroupId && rosterGroup.isDefault) do
            _ <-
                rosterGroup
                    |> set #isDefault False
                    |> updateRecord
            pure ()
    forM_ (find (\rosterGroup -> rosterGroup.id == rosterGroupId && not rosterGroup.isDefault) rosterGroups) \rosterGroup -> do
        _ <-
            rosterGroup
                |> set #isDefault True
                |> updateRecord
        pure ()
    fetch rosterGroupId

fetchCurrentVenueRosterGroupOrDefault :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Maybe (Id RosterGroup) -> IO RosterGroup
fetchCurrentVenueRosterGroupOrDefault maybeRosterGroupId = do
    defaultRosterGroup <- fetchCurrentVenueDefaultRosterGroup
    case maybeRosterGroupId of
        Nothing -> pure defaultRosterGroup
        Just rosterGroupId -> do
            rosterGroupOrNothing <-
                query @RosterGroup
                    |> filterWhere (#id, rosterGroupId)
                    |> filterWhere (#venueId, unpackId currentVenueId)
                    |> filterWhere (#isActive, True)
                    |> filterWhere (#archivedAt, Nothing)
                    |> fetchOneOrNothing
            pure (fromMaybe defaultRosterGroup rosterGroupOrNothing)

-- | Roster groups the effective viewer may open on the roster page.
-- Managers and unimpersonated support retain venue-wide access. Ordinary staff
-- are limited to explicit active assignments; this read intentionally does not
-- call 'ensureStaffDefaultRosterGroupAssignment'.
fetchViewableRosterGroups :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [RosterGroup]
fetchViewableRosterGroups = do
    activeGroups <- filter (.isActive) <$> fetchCurrentVenueRosterGroups
    if hasRole Manager || currentUserIsUnimpersonatedSuperAdmin
        then pure activeGroups
        else do
            maybeStaff <- fetchCurrentUserStaff
            case maybeStaff of
                Nothing -> pure []
                Just staff -> do
                    assignments <-
                        query @StaffRosterGroup
                            |> filterWhere (#staffId, unpackId staff.id)
                            |> filterWhere (#deletedAt, Nothing)
                            |> fetch
                    let assignedGroupIds = Set.fromList (map (.rosterGroupId) assignments)
                    pure (filter (\group -> unpackId group.id `Set.member` assignedGroupIds) activeGroups)

fetchViewableRosterGroup :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> IO (Maybe RosterGroup)
fetchViewableRosterGroup rosterGroupId =
    find ((== rosterGroupId) . (.id)) <$> fetchViewableRosterGroups

fetchRosterGroupSlotNames :: (?modelContext :: ModelContext) => Id RosterGroup -> IO [SlotName]
fetchRosterGroupSlotNames rosterGroupId =
    query @SlotName
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch

fetchActiveRosterGroupSlotNames :: (?modelContext :: ModelContext) => Id RosterGroup -> IO [SlotName]
fetchActiveRosterGroupSlotNames rosterGroupId =
    query @SlotName
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch

ensureStaffDefaultRosterGroupAssignment :: (?modelContext :: ModelContext) => Staff -> IO ()
ensureStaffDefaultRosterGroupAssignment staff = do
    existingAssignment <-
        query @StaffRosterGroup
            |> filterWhere (#staffId, unpackId staff.id)
            |> filterWhere (#deletedAt, Nothing)
            |> fetchOneOrNothing
    case existingAssignment of
        Just _ -> pure ()
        Nothing -> do
            venue <- fetch (Id staff.venueId :: Id Venue)
            rosterGroup <- ensureVenueDefaultRosterGroup venue
            _ <-
                newRecord @StaffRosterGroup
                    |> set #staffId (unpackId staff.id)
                    |> set #rosterGroupId (unpackId rosterGroup.id)
                    |> createRecord
            pure ()

fetchStaffRosterGroupIds :: (?modelContext :: ModelContext) => Staff -> IO [Id RosterGroup]
fetchStaffRosterGroupIds staff = do
    ensureStaffDefaultRosterGroupAssignment staff
    assignments <-
        query @StaffRosterGroup
            |> filterWhere (#staffId, unpackId staff.id)
            |> filterWhere (#deletedAt, Nothing)
            |> orderByAsc #createdAt
            |> fetch
    pure (map (Id . (.rosterGroupId)) assignments)

syncStaffRosterGroupAssignments :: (?modelContext :: ModelContext) => Staff -> [Id RosterGroup] -> IO ()
syncStaffRosterGroupAssignments staff desiredRosterGroupIds = do
    now <- getCurrentTime
    existingAssignments <-
        query @StaffRosterGroup
            |> filterWhere (#staffId, unpackId staff.id)
            |> filterWhere (#deletedAt, Nothing)
            |> fetch
    let desiredRosterGroupUuidSet = Set.fromList (map unpackId desiredRosterGroupIds)
    let existingRosterGroupUuidSet = Set.fromList (map (.rosterGroupId) existingAssignments)
    forM_ existingAssignments \assignment ->
        when (assignment.rosterGroupId `Set.notMember` desiredRosterGroupUuidSet) do
            _ <- assignment
                |> set #deletedAt (Just now)
                |> set #deleteReason (Just "staff_roster_group_removed")
                |> updateRecord
            pure ()
    forM_ desiredRosterGroupIds \rosterGroupId ->
        when (unpackId rosterGroupId `Set.notMember` existingRosterGroupUuidSet) do
            _ <-
                newRecord @StaffRosterGroup
                    |> set #staffId (unpackId staff.id)
                |> set #rosterGroupId (unpackId rosterGroupId)
                    |> createRecord
            pure ()

staffIsEligibleForRosterGroup :: (?modelContext :: ModelContext) => Id Staff -> Id RosterGroup -> IO Bool
staffIsEligibleForRosterGroup staffId rosterGroupId = do
    staff <- fetch staffId
    applicableRosterGroupIds <- fetchStaffRosterGroupIds staff
    pure (rosterGroupId `elem` applicableRosterGroupIds)

fetchEligibleRosterGroupStaff :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Id RosterGroup -> IO [Staff]
fetchEligibleRosterGroupStaff rosterGroupId = do
    staffRosterGroups <-
        query @StaffRosterGroup
            |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
            |> filterWhere (#deletedAt, Nothing)
            |> fetch
    let staffIds = map (.staffId) staffRosterGroups
    if null staffIds
        then pure []
        else
            sortStaffForDisplay <$> (query @Staff
                |> filterWhere (#venueId, unpackId currentVenueId)
                |> filterWhere (#isActive, True)
                |> filterWhere (#archivedAt, Nothing)
                |> filterWhereIn (#id, map Id staffIds)
                |> fetch)

fetchCurrentVenueActiveStaff :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [Staff]
fetchCurrentVenueActiveStaff =
    sortStaffForDisplay <$> (query @Staff
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> filterWhere (#archivedAt, Nothing)
        |> fetch)

fetchVenueDayNames :: (?modelContext :: ModelContext) => Venue -> IO [DayName]
fetchVenueDayNames venue = do
    venueConfig <- ensureVenueConfigRecord venue
    dayNames <-
        query @DayName
            |> filterWhere (#venueId, unpackId venue.id)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> fetch
    pure (sortDayNamesForVenueWeek venueConfig dayNames)

ensureVenueConfigRecord :: (?modelContext :: ModelContext) => Venue -> IO VenueConfig
ensureVenueConfigRecord venue =
    query @VenueConfig
        |> filterWhere (#venueId, unpackId venue.id)
        |> fetchOneOrNothing
        >>= \case
            Just venueConfig -> pure venueConfig
            Nothing ->
                newRecord @VenueConfig
                    |> set #venueId (unpackId venue.id)
                    |> set #timezone "Australia/Melbourne"
                    |> set #rosterWeekStartsOn defaultRosterWeekStartsOn
                    |> set #rosterLayoutMode DayColumns
                    |> set #defaultStaffPayAssignmentMode RosterOnly
                    |> set #defaultStaffAwardLevelId Nothing
                    |> set #lateToEarlyMinStartGapMinutes 600
                    |> set #staffTimesheetEditWindowDays 7
                    |> createRecord

ensureVenueDayNames :: (?modelContext :: ModelContext) => Venue -> IO [DayName]
ensureVenueDayNames venue = do
    existingDayNames <- fetchVenueDayNames venue
    let existingWeekdayIndexes = map (.weekdayIndex) existingDayNames

    forM_ defaultVenueDayNames \(weekdayIndex, dayName) ->
        unless (weekdayIndex `elem` existingWeekdayIndexes) do
            _ <- newRecord @DayName
                |> set #venueId (unpackId venue.id)
                |> set #weekdayIndex weekdayIndex
                |> set #name dayName
                |> set #isActive True
                |> createRecord
            pure ()

    fetchVenueDayNames venue

ensureVenueDefaultRosterGroup :: (?modelContext :: ModelContext) => Venue -> IO RosterGroup
ensureVenueDefaultRosterGroup venue = do
    activeGroupOrNothing <-
        query @RosterGroup
            |> filterWhere (#venueId, unpackId venue.id)
            |> filterWhere (#isActive, True)
            |> filterWhere (#archivedAt, Nothing)
            |> orderByAsc #sortOrder
            |> orderByAsc #createdAt
            |> fetchOneOrNothing

    case activeGroupOrNothing of
        Just rosterGroup -> do
            syncVenueDefaultRosterGroupToTopActive venue.id
            fetch rosterGroup.id
        Nothing ->
            newRecord @RosterGroup
                |> set #venueId (unpackId venue.id)
                |> set #name defaultRosterGroupName
                |> set #sortOrder 0
                |> set #isActive True
                |> set #isDefault True
                |> createRecord

ensureDefaultRosterSlots :: (?modelContext :: ModelContext) => Venue -> RosterGroup -> IO [SlotName]
ensureDefaultRosterSlots venue rosterGroup = do
    existingSlotNames <- fetchRosterGroupSlotNames rosterGroup.id
    if null existingSlotNames
        then
            forM (zip [0 :: Int ..] defaultRosterSlotNames) \(sortOrder, slotName) ->
                newRecord @SlotName
                    |> set #venueId (unpackId venue.id)
                    |> set #rosterGroupId (unpackId rosterGroup.id)
                    |> set #name slotName
                    |> set #sortOrder sortOrder
                    |> set #isActive True
                    |> createRecord
        else pure existingSlotNames
