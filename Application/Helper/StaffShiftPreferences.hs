{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications #-}

module Application.Helper.StaffShiftPreferences where

import Application.Helper.Controller (currentVenueId)
import Application.Helper.RosterGroups (fetchStaffRosterGroupIds)
import qualified Data.Text as Text
import Text.Read (readMaybe)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude

data StaffPreferenceGroupSection = StaffPreferenceGroupSection
    { rosterGroup :: RosterGroup
    , slotNames   :: [SlotName]
    }

data ShiftPreferenceSelection = ShiftPreferenceSelection
    { rosterGroupId :: Id RosterGroup
    , weekdayIndex  :: Int
    , slotNameId    :: Id SlotName
    }
    deriving (Eq, Show)

fetchCurrentVenueActiveDayNames :: (?context :: ControllerContext, ?modelContext :: ModelContext) => IO [DayName]
fetchCurrentVenueActiveDayNames =
    query @DayName
        |> filterWhere (#venueId, unpackId currentVenueId)
        |> filterWhere (#isActive, True)
        |> fetch
        >>= pure . sortOn (displayWeekdayOrder . (.weekdayIndex))

fetchStaffPreferenceGroupSections :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Staff -> IO [StaffPreferenceGroupSection]
fetchStaffPreferenceGroupSections staff = do
    rosterGroupIds <- fetchStaffRosterGroupIds staff
    fetchPreferenceSectionsForRosterGroups rosterGroupIds

fetchPreferenceSectionsForRosterGroups :: (?context :: ControllerContext, ?modelContext :: ModelContext) => [Id RosterGroup] -> IO [StaffPreferenceGroupSection]
fetchPreferenceSectionsForRosterGroups rosterGroupIds = do
    rosterGroups <-
        query @RosterGroup
            |> filterWhere (#venueId, unpackId currentVenueId)
            |> filterWhereIn (#id, rosterGroupIds)
            |> filterWhere (#isActive, True)
            |> orderByAsc #sortOrder
            |> orderByAsc #createdAt
            |> fetch
    forM rosterGroups \rosterGroup -> do
        slotNames <-
            query @SlotName
                |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                |> filterWhere (#isActive, True)
                |> orderByAsc #createdAt
                |> fetch
        pure StaffPreferenceGroupSection { rosterGroup, slotNames }

fetchStaffShiftPreferenceKeyTexts :: (?modelContext :: ModelContext) => Staff -> [Id RosterGroup] -> IO [Text]
fetchStaffShiftPreferenceKeyTexts staff rosterGroupIds = do
    preferences <- fetchStaffShiftPreferences staff rosterGroupIds
    pure (map encodeStaffShiftPreferenceKey preferences)

fetchStaffShiftPreferences :: (?modelContext :: ModelContext) => Staff -> [Id RosterGroup] -> IO [StaffShiftPreference]
fetchStaffShiftPreferences staff rosterGroupIds
    | null rosterGroupIds = pure []
    | otherwise =
        query @StaffShiftPreference
            |> filterWhere (#staffId, unpackId staff.id)
            |> filterWhereIn (#rosterGroupId, map unpackId rosterGroupIds)
            |> fetch

replaceStaffShiftPreferences :: (?modelContext :: ModelContext) => Staff -> [Id RosterGroup] -> [ShiftPreferenceSelection] -> IO ()
replaceStaffShiftPreferences staff rosterGroupIds selections = do
    when (not (null rosterGroupIds)) do
        existingPreferences <-
            query @StaffShiftPreference
                |> filterWhere (#staffId, unpackId staff.id)
                |> filterWhereIn (#rosterGroupId, map unpackId rosterGroupIds)
                |> fetch
        deleteRecords existingPreferences
    forM_ (nub selections) \selection -> do
        _ <-
            newRecord @StaffShiftPreference
                |> set #venueId staff.venueId
                |> set #staffId (unpackId staff.id)
                |> set #rosterGroupId (unpackId selection.rosterGroupId)
                |> set #slotNameId (unpackId selection.slotNameId)
                |> set #weekdayIndex selection.weekdayIndex
                |> createRecord
        pure ()

parseShiftPreferenceSelections :: [StaffPreferenceGroupSection] -> [DayName] -> [Text] -> Either Text [ShiftPreferenceSelection]
parseShiftPreferenceSelections sections dayNames rawKeys =
    forM (nub rawKeys) decodeAndValidate
    where
        allowedWeekdayIndexes = map (.weekdayIndex) dayNames
        allowedSlotPairs =
            [ (rosterGroup.id, slotName.id)
            | section <- sections
            , let rosterGroup = section.rosterGroup
            , slotName <- section.slotNames
            ]

        decodeAndValidate rawKey =
            case decodeShiftPreferenceKey rawKey of
                Nothing -> Left "One or more submitted shift preferences could not be understood."
                Just selection
                    | selection.weekdayIndex `notElem` allowedWeekdayIndexes ->
                        Left "One or more submitted shift preferences used an invalid weekday."
                    | (selection.rosterGroupId, selection.slotNameId) `notElem` allowedSlotPairs ->
                        Left "One or more submitted shift preferences used an invalid roster-group slot."
                    | otherwise ->
                        Right selection

encodeShiftPreferenceKey :: ShiftPreferenceSelection -> Text
encodeShiftPreferenceKey selection =
    tshow selection.rosterGroupId <> "|" <> tshow selection.weekdayIndex <> "|" <> tshow selection.slotNameId

encodeStaffShiftPreferenceKey :: StaffShiftPreference -> Text
encodeStaffShiftPreferenceKey preference =
    encodeShiftPreferenceKey
        ShiftPreferenceSelection
            { rosterGroupId = Id preference.rosterGroupId
            , weekdayIndex = preference.weekdayIndex
            , slotNameId = Id preference.slotNameId
            }

decodeShiftPreferenceKey :: Text -> Maybe ShiftPreferenceSelection
decodeShiftPreferenceKey rawKey =
    case Text.splitOn "|" rawKey of
        [rosterGroupIdText, weekdayIndexText, slotNameIdText] -> do
            let rosterGroupId = textToId rosterGroupIdText :: Id RosterGroup
            let slotNameId = textToId slotNameIdText :: Id SlotName
            weekdayIndex <- readMaybe (cs weekdayIndexText)
            pure ShiftPreferenceSelection { rosterGroupId, weekdayIndex, slotNameId }
        _ -> Nothing

displayWeekdayOrder :: Int -> Int
displayWeekdayOrder weekdayIndex
    | weekdayIndex == 0 = 7
    | otherwise = weekdayIndex
