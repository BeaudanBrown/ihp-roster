{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.StaffShiftPreferences where

import Application.Helper.Controller (currentVenueId)
import Application.Helper.RosterGroups (fetchStaffRosterGroupIds)
import Application.Helper.WeekBoundaries (orderedWeekdayIndexes,
                                          weekdayIndexLabel)
import qualified Data.Text as Text
import Data.Time.Clock (getCurrentTime)
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude
import Text.Read (readMaybe)

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

data PreferenceWeekday = PreferenceWeekday
    { weekdayIndex :: Int
    , label        :: Text
    }
    deriving (Eq, Show)

allPreferenceWeekdays :: VenueConfig -> [PreferenceWeekday]
allPreferenceWeekdays venueConfig =
    map
        (\weekdayIndex ->
            PreferenceWeekday
                { weekdayIndex
                , label = weekdayIndexLabel weekdayIndex
                }
        )
        (orderedWeekdayIndexes venueConfig.rosterWeekStartsOn)

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
            |> filterWhere (#archivedAt, Nothing)
            |> orderByAsc #sortOrder
            |> orderByAsc #createdAt
            |> fetch
    forM rosterGroups \rosterGroup -> do
        slotNames <-
            query @SlotName
                |> filterWhere (#rosterGroupId, unpackId rosterGroup.id)
                |> filterWhere (#isActive, True)
                |> filterWhere (#archivedAt, Nothing)
                |> orderByAsc #sortOrder
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
            |> filterWhere (#deletedAt, Nothing)
            |> fetch

replaceStaffShiftPreferences :: (?modelContext :: ModelContext) => Staff -> [Id RosterGroup] -> [ShiftPreferenceSelection] -> IO ()
replaceStaffShiftPreferences staff rosterGroupIds selections = do
    unless (null rosterGroupIds) do
        now <- getCurrentTime
        existingPreferences <-
            query @StaffShiftPreference
                |> filterWhere (#staffId, unpackId staff.id)
                |> filterWhereIn (#rosterGroupId, map unpackId rosterGroupIds)
                |> filterWhere (#deletedAt, Nothing)
                |> fetch
        forM_ existingPreferences \preference -> do
            _ <- preference
                |> set #deletedAt (Just now)
                |> set #deleteReason (Just "staff_shift_preferences_replaced")
                |> updateRecord
            pure ()
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

parseShiftPreferenceSelections :: [StaffPreferenceGroupSection] -> [PreferenceWeekday] -> [Text] -> Either Text [ShiftPreferenceSelection]
parseShiftPreferenceSelections sections weekdays rawKeys =
    forM (nub rawKeys) decodeAndValidate
    where
        allowedWeekdayIndexes = map (.weekdayIndex) weekdays
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
            rosterGroupId <- Id <$> UUID.fromText rosterGroupIdText
            slotNameId <- Id <$> UUID.fromText slotNameIdText
            weekdayIndex <- readMaybe (cs weekdayIndexText)
            pure ShiftPreferenceSelection { rosterGroupId, weekdayIndex, slotNameId }
        _ -> Nothing
