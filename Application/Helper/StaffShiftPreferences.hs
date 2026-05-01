{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.StaffShiftPreferences where

import Application.Helper.Controller (currentVenueId)
import Application.Helper.WeekBoundaries (orderedWeekdayIndexes,
                                          weekdayIndexLabel)
import qualified Data.Text as Text
import qualified Data.Text.Encoding as Text
import Data.Time.Clock (getCurrentTime)
import Generated.Types
import IHP.ControllerPrelude
import IHP.Prelude
import Text.Read (readMaybe)

data ShiftPreferenceSelection = ShiftPreferenceSelection
    { weekdayIndex :: Int
    , startHour    :: Int
    , endHour      :: Int
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

fetchStaffShiftPreferenceSelections :: (?modelContext :: ModelContext) => Staff -> IO [ShiftPreferenceSelection]
fetchStaffShiftPreferenceSelections staff = do
    preferences <- fetchStaffShiftPreferences staff
    pure (map staffShiftPreferenceSelection preferences)

fetchStaffShiftPreferences :: (?modelContext :: ModelContext) => Staff -> IO [StaffShiftPreference]
fetchStaffShiftPreferences staff =
    query @StaffShiftPreference
        |> filterWhere (#staffId, unpackId staff.id)
        |> filterWhere (#deletedAt, Nothing)
        |> fetch

replaceStaffShiftPreferences :: (?modelContext :: ModelContext) => Staff -> [ShiftPreferenceSelection] -> IO ()
replaceStaffShiftPreferences staff selections = do
    now <- getCurrentTime
    existingPreferences <-
        query @StaffShiftPreference
            |> filterWhere (#staffId, unpackId staff.id)
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
                |> set #weekdayIndex selection.weekdayIndex
                |> set #preferredStartHour selection.startHour
                |> set #preferredEndHour selection.endHour
                |> createRecord
        pure ()

parseShiftPreferenceSelections :: (?request :: Request) => [PreferenceWeekday] -> [Text] -> Either Text [ShiftPreferenceSelection]
parseShiftPreferenceSelections weekdays rawKeys =
    forM (nub rawKeys) decodeAndValidate
    where
        allowedWeekdayIndexes = map (.weekdayIndex) weekdays

        decodeAndValidate rawKey =
            case decodeShiftPreferenceKey rawKey of
                Nothing -> Left "One or more submitted shift preferences could not be understood."
                Just weekdayIndex
                    | weekdayIndex `notElem` allowedWeekdayIndexes ->
                        Left "One or more submitted shift preferences used an invalid weekday."
                    | otherwise -> do
                        startHour <- parseHourParam (shiftPreferenceStartHourParamName rawKey)
                        endHour <- parseHourParam (shiftPreferenceEndHourParamName rawKey)
                        if startHour <= endHour
                            then Right ShiftPreferenceSelection { weekdayIndex, startHour, endHour }
                            else Left "One or more submitted shift preferences used an invalid time window."

        parseHourParam paramName =
            case requestParamText paramName >>= readMaybe . cs of
                Just hour | hour >= preferenceMinimumHour && hour <= preferenceMaximumHour -> Right hour
                _ -> Left "One or more submitted shift preferences used an invalid hour."

encodeStaffShiftPreferenceKey :: StaffShiftPreference -> Text
encodeStaffShiftPreferenceKey preference =
    encodeShiftPreferenceKey preference.weekdayIndex

staffShiftPreferenceSelection :: StaffShiftPreference -> ShiftPreferenceSelection
staffShiftPreferenceSelection preference =
    ShiftPreferenceSelection
        { weekdayIndex = preference.weekdayIndex
        , startHour = preference.preferredStartHour
        , endHour = preference.preferredEndHour
        }

encodeShiftPreferenceKey :: Int -> Text
encodeShiftPreferenceKey = tshow

shiftPreferenceStartHourParamName :: Text -> Text
shiftPreferenceStartHourParamName key = "shiftPreferenceStartHour:" <> key

shiftPreferenceEndHourParamName :: Text -> Text
shiftPreferenceEndHourParamName key = "shiftPreferenceEndHour:" <> key

defaultPreferenceStartHour :: Int
defaultPreferenceStartHour = 9

defaultPreferenceEndHour :: Int
defaultPreferenceEndHour = 17

preferenceMinimumHour :: Int
preferenceMinimumHour = 5

preferenceMaximumHour :: Int
preferenceMaximumHour = 23

preferenceHourOptions :: [Int]
preferenceHourOptions = [preferenceMinimumHour .. preferenceMaximumHour]

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

decodeShiftPreferenceKey :: Text -> Maybe Int
decodeShiftPreferenceKey rawKey =
    readMaybe (cs rawKey)
