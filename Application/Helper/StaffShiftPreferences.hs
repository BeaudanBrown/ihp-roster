{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.StaffShiftPreferences where

import Application.Helper.Controller (currentVenueId)
import Application.Helper.RosterGroups (fetchStaffRosterGroupIds)
import Application.Helper.WeekBoundaries (orderedWeekdayIndexes,
                                          weekdayIndexLabel)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Data.Time.Clock (getCurrentTime)
import qualified Data.UUID as UUID
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude
import Text.Read (readMaybe)

data StaffPreferenceGroupSection = StaffPreferenceGroupSection
    { rosterGroup :: RosterGroup
    }

data ShiftPreferenceSelection = ShiftPreferenceSelection
    { rosterGroupId :: Id RosterGroup
    , weekdayIndex  :: Int
    , startHour     :: Int
    , endHour       :: Int
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
    pure (map (\rosterGroup -> StaffPreferenceGroupSection { rosterGroup }) rosterGroups)

fetchStaffShiftPreferenceSelections :: (?modelContext :: ModelContext) => Staff -> [Id RosterGroup] -> IO [ShiftPreferenceSelection]
fetchStaffShiftPreferenceSelections staff rosterGroupIds = do
    preferences <- fetchStaffShiftPreferences staff rosterGroupIds
    pure (map staffShiftPreferenceSelection preferences)

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
                |> set #weekdayIndex selection.weekdayIndex
                |> set #preferredStartHour selection.startHour
                |> set #preferredEndHour selection.endHour
                |> createRecord
        pure ()

parseShiftPreferenceSelections :: (?request :: Request) => [StaffPreferenceGroupSection] -> [PreferenceWeekday] -> [Text] -> Either Text [ShiftPreferenceSelection]
parseShiftPreferenceSelections sections weekdays rawKeys =
    forM (nub rawKeys) decodeAndValidate
    where
        allowedWeekdayIndexes = map (.weekdayIndex) weekdays
        allowedRosterGroupIds =
            [ rosterGroup.id
            | section <- sections
            , let rosterGroup = section.rosterGroup
            ]

        decodeAndValidate rawKey =
            case decodeShiftPreferenceKey rawKey of
                Nothing -> Left "One or more submitted shift preferences could not be understood."
                Just (rosterGroupId, weekdayIndex)
                    | weekdayIndex `notElem` allowedWeekdayIndexes ->
                        Left "One or more submitted shift preferences used an invalid weekday."
                    | rosterGroupId `notElem` allowedRosterGroupIds ->
                        Left "One or more submitted shift preferences used an invalid roster group."
                    | otherwise -> do
                        startHour <- parseHourParam (shiftPreferenceStartHourParamName rawKey)
                        endHour <- parseHourParam (shiftPreferenceEndHourParamName rawKey)
                        if startHour <= endHour
                            then Right ShiftPreferenceSelection { rosterGroupId, weekdayIndex, startHour, endHour }
                            else Left "One or more submitted shift preferences used an invalid time window."

        parseHourParam paramName =
            case requestParamText paramName >>= readMaybe . cs of
                Just hour | hour >= 0 && hour <= 23 -> Right hour
                _ -> Left "One or more submitted shift preferences used an invalid hour."

encodeStaffShiftPreferenceKey :: StaffShiftPreference -> Text
encodeStaffShiftPreferenceKey preference =
    encodeShiftPreferenceKey (Id preference.rosterGroupId) preference.weekdayIndex

staffShiftPreferenceSelection :: StaffShiftPreference -> ShiftPreferenceSelection
staffShiftPreferenceSelection preference =
    ShiftPreferenceSelection
        { rosterGroupId = Id preference.rosterGroupId
        , weekdayIndex = preference.weekdayIndex
        , startHour = preference.preferredStartHour
        , endHour = preference.preferredEndHour
        }

encodeShiftPreferenceKey :: Id RosterGroup -> Int -> Text
encodeShiftPreferenceKey rosterGroupId weekdayIndex =
    tshow rosterGroupId <> "|" <> tshow weekdayIndex

shiftPreferenceStartHourParamName :: Text -> Text
shiftPreferenceStartHourParamName key = "shiftPreferenceStartHour:" <> key

shiftPreferenceEndHourParamName :: Text -> Text
shiftPreferenceEndHourParamName key = "shiftPreferenceEndHour:" <> key

defaultPreferenceStartHour :: Int
defaultPreferenceStartHour = 9

defaultPreferenceEndHour :: Int
defaultPreferenceEndHour = 17

preferenceHourOptions :: [Int]
preferenceHourOptions = [0 .. 23]

formatPreferenceHour :: Int -> Text
formatPreferenceHour hour
    | hour == 0 = "12 AM"
    | hour < 12 = tshow hour <> " AM"
    | hour == 12 = "12 PM"
    | hour <= 23 = tshow (hour - 12) <> " PM"
    | otherwise = tshow hour <> ":00"

requestParamText :: (?request :: Request) => Text -> Maybe Text
requestParamText paramName =
    listToMaybe
        [ Text.decodeUtf8 rawValue
        | (name, Just rawValue) <- allParams
        , Text.decodeUtf8 name == paramName
        ]

decodeShiftPreferenceKey :: Text -> Maybe (Id RosterGroup, Int)
decodeShiftPreferenceKey rawKey =
    case Text.splitOn "|" rawKey of
        [rosterGroupIdText, weekdayIndexText] -> do
            rosterGroupId <- Id <$> UUID.fromText rosterGroupIdText
            weekdayIndex <- readMaybe (cs weekdayIndexText)
            pure (rosterGroupId, weekdayIndex)
        _ -> Nothing
