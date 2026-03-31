{-# LANGUAGE LambdaCase #-}
{-# LANGUAGE OverloadedRecordDot #-}

module Application.Helper.RosterGroups where

import Application.Helper.Controller (currentVenueId)
import Data.Time.Calendar (fromGregorian)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude

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

fetchCurrentVenueDefaultRosterGroup :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO RosterGroup
fetchCurrentVenueDefaultRosterGroup = do
    venue <- fetch currentVenueId
    ensureVenueRosterDefaults venue

fetchCurrentVenueRosterGroups :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [RosterGroup]
fetchCurrentVenueRosterGroups =
    query @RosterGroup
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> orderByAsc #sortOrder
        |> orderByAsc #createdAt
        |> fetch

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
                    |> fetchOneOrNothing
            pure (fromMaybe defaultRosterGroup rosterGroupOrNothing)

fetchRosterGroupSlotNames :: (?modelContext :: ModelContext) => Id RosterGroup -> IO [SlotName]
fetchRosterGroupSlotNames rosterGroupId =
    query @SlotName
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
        |> orderByAsc #createdAt
        |> fetch

fetchActiveRosterGroupSlotNames :: (?modelContext :: ModelContext) => Id RosterGroup -> IO [SlotName]
fetchActiveRosterGroupSlotNames rosterGroupId =
    query @SlotName
        |> filterWhere (#rosterGroupId, unpackId rosterGroupId)
        |> filterWhere (#isActive, True)
        |> orderByAsc #createdAt
        |> fetch

fetchVenueDayNames :: (?modelContext :: ModelContext) => Venue -> IO [DayName]
fetchVenueDayNames venue =
    query @DayName
        |> filterWhere (#venueId, unpackId venue.id)
        |> orderByAsc #weekdayIndex
        |> fetch

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
                    |> set #timezone "UTC"
                    |> set #weekOffsetEpoch (fromGregorian 2025 1 6)
                    |> set #lateToEarlyMinStartGapMinutes 600
                    |> set #staffTimesheetEditWindowDays 7
                    |> createRecord

ensureVenueDayNames :: (?modelContext :: ModelContext) => Venue -> IO [DayName]
ensureVenueDayNames venue = do
    existingDayNames <- fetchVenueDayNames venue
    let existingWeekdayIndexes = map (.weekdayIndex) existingDayNames

    forM_ defaultVenueDayNames \(weekdayIndex, dayName) ->
        when (weekdayIndex `notElem` existingWeekdayIndexes) do
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
    defaultGroupOrNothing <-
        query @RosterGroup
            |> filterWhere (#venueId, unpackId venue.id)
            |> filterWhere (#isActive, True)
            |> filterWhere (#isDefault, True)
            |> orderByAsc #sortOrder
            |> orderByAsc #createdAt
            |> fetchOneOrNothing

    activeGroupOrNothing <-
        query @RosterGroup
            |> filterWhere (#venueId, unpackId venue.id)
            |> filterWhere (#isActive, True)
            |> orderByAsc #sortOrder
            |> orderByAsc #createdAt
            |> fetchOneOrNothing

    case defaultGroupOrNothing <|> activeGroupOrNothing of
        Just rosterGroup
            | rosterGroup.isDefault -> pure rosterGroup
            | otherwise ->
                rosterGroup
                    |> set #isDefault True
                    |> updateRecord
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
            forM defaultRosterSlotNames \slotName ->
                newRecord @SlotName
                    |> set #venueId (unpackId venue.id)
                    |> set #rosterGroupId (unpackId rosterGroup.id)
                    |> set #name slotName
                    |> set #isActive True
                    |> createRecord
        else pure existingSlotNames
