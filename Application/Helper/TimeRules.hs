module Application.Helper.TimeRules where

import Control.Monad (guard)
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (UTCTime (..), getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime, parseTimeM)
import Data.Time.LocalTime (LocalTime (..), TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude

import Application.Helper.ControllerAccess (fetchVenueConfig, hasRole)
import Application.Helper.ControllerSupport (VenueRole (ManagerRole'))

parseTimeParam :: Text -> Maybe TimeOfDay
parseTimeParam value = parseTimeM True defaultTimeLocale "%H:%M" (cs value)

isQuarterHourTime :: TimeOfDay -> Bool
isQuarterHourTime tod = todMin tod `mod` 15 == 0 && todSec tod == 0

isQuarterHourMinutes :: Int -> Bool
isQuarterHourMinutes mins = mins >= 0 && mins `mod` 15 == 0

isQuarterHourMinuteOfDay :: Int -> Bool
isQuarterHourMinuteOfDay mins = mins >= 0 && mins < 24 * 60 && mins `mod` 15 == 0

automaticMealBreakThresholdMinutes :: Int
automaticMealBreakThresholdMinutes = 6 * 60 + 15

automaticMealBreakStartOffsetMinutes :: Int
automaticMealBreakStartOffsetMinutes = 5 * 60 + 30

automaticMealBreakMinutes :: Int
automaticMealBreakMinutes = 30

rosterOperationalStartMinuteOfDay :: Int
rosterOperationalStartMinuteOfDay = 6 * 60

rosterOperationalFinalSelectableMinuteOfDay :: Int
rosterOperationalFinalSelectableMinuteOfDay = 5 * 60 + 45

rosterOperationalFinalSelectableMinute :: Int
rosterOperationalFinalSelectableMinute = 24 * 60 + rosterOperationalFinalSelectableMinuteOfDay

rosterOperationalStartTime :: TimeOfDay
rosterOperationalStartTime = TimeOfDay 6 0 0

rosterOperationalFinalSelectableTime :: TimeOfDay
rosterOperationalFinalSelectableTime = TimeOfDay 5 45 0

rosterOperationalStartTimeText :: Text
rosterOperationalStartTimeText = "06:00"

rosterOperationalFinalSelectableTimeText :: Text
rosterOperationalFinalSelectableTimeText = "05:45"

defaultNewShiftDurationMinutes :: Int
defaultNewShiftDurationMinutes = 8 * 60

venueTimePickerStartMinuteOfDay :: VenueConfig -> Int
venueTimePickerStartMinuteOfDay = (.timePickerStartMinuteOfDay)

venueTimePickerFinalSelectableMinuteOfDay :: VenueConfig -> Int
venueTimePickerFinalSelectableMinuteOfDay = (.timePickerFinalSelectableMinuteOfDay)

formatMinuteOfDayText :: Int -> Text
formatMinuteOfDayText minuteOfDay = timeOfDayToStorageValue (minuteOfDayToTimeOfDay minuteOfDay)

parseQuarterHourMinuteOfDay :: Text -> Maybe Int
parseQuarterHourMinuteOfDay value = do
    tod <- parseTimeParam value
    let minute = timeOfDayToMinutes tod
    guard (isQuarterHourMinuteOfDay minute)
    pure minute

venueTimePickerStartTimeText :: VenueConfig -> Text
venueTimePickerStartTimeText = formatMinuteOfDayText . venueTimePickerStartMinuteOfDay

venueTimePickerFinalSelectableTimeText :: VenueConfig -> Text
venueTimePickerFinalSelectableTimeText = formatMinuteOfDayText . venueTimePickerFinalSelectableMinuteOfDay

venueTimePickerStartTime :: VenueConfig -> TimeOfDay
venueTimePickerStartTime = minuteOfDayToTimeOfDay . venueTimePickerStartMinuteOfDay

venueTimePickerFinalSelectableTime :: VenueConfig -> TimeOfDay
venueTimePickerFinalSelectableTime = minuteOfDayToTimeOfDay . venueTimePickerFinalSelectableMinuteOfDay

normalizeWindowEndMinute :: Int -> Int -> Int
normalizeWindowEndMinute startMinute endMinute =
    if endMinute <= startMinute then endMinute + 24 * 60 else endMinute

venueTimePickerWindowDurationMinutes :: Int -> Int -> Int
venueTimePickerWindowDurationMinutes startMinute endMinute =
    normalizeWindowEndMinute startMinute endMinute - startMinute

isMinuteWithinTimePickerWindow :: Int -> Int -> Int -> Bool
isMinuteWithinTimePickerWindow startMinute endMinute minuteOfDay =
    let endMinuteNormalized = normalizeWindowEndMinute startMinute endMinute
        minuteNormalized = if minuteOfDay < startMinute then minuteOfDay + 24 * 60 else minuteOfDay
     in minuteNormalized >= startMinute && minuteNormalized <= endMinuteNormalized

defaultShiftTimesForPickerWindow :: Int -> Int -> (TimeOfDay, TimeOfDay)
defaultShiftTimesForPickerWindow startMinute endMinute =
    let endMinuteNormalized = normalizeWindowEndMinute startMinute endMinute
        defaultEndMinute = min (startMinute + defaultNewShiftDurationMinutes) endMinuteNormalized
     in (minuteOfDayToTimeOfDay startMinute, minuteOfDayToTimeOfDay defaultEndMinute)

defaultShiftTimesForVenueConfig :: VenueConfig -> (TimeOfDay, TimeOfDay)
defaultShiftTimesForVenueConfig venueConfig =
    defaultShiftTimesForPickerWindow
        (venueTimePickerStartMinuteOfDay venueConfig)
        (venueTimePickerFinalSelectableMinuteOfDay venueConfig)

timeOfDayToStorageValue :: TimeOfDay -> Text
timeOfDayToStorageValue tod = cs (formatTime defaultTimeLocale "%H:%M" tod)

shiftDurationMinutes :: TimeOfDay -> TimeOfDay -> Int
shiftDurationMinutes start end =
    normalizeShiftMinuteOfDay end - normalizeShiftMinuteOfDay start

automaticMealBreakForShift :: TimeOfDay -> TimeOfDay -> Maybe (TimeOfDay, TimeOfDay, Int)
automaticMealBreakForShift start end
    | shiftDurationMinutes start end >= automaticMealBreakThresholdMinutes =
        let startMinute = timeOfDayToMinutes start
            breakStartMinute = startMinute + automaticMealBreakStartOffsetMinutes
            breakEndMinute = breakStartMinute + automaticMealBreakMinutes
         in Just (minuteOfDayToTimeOfDay breakStartMinute, minuteOfDayToTimeOfDay breakEndMinute, automaticMealBreakMinutes)
    | otherwise = Nothing

automaticMealBreakWindowMinutes :: TimeOfDay -> TimeOfDay -> Maybe (Int, Int)
automaticMealBreakWindowMinutes start end
    | shiftDurationMinutes start end >= automaticMealBreakThresholdMinutes =
        let breakStartMinute = normalizeShiftMinuteOfDay start + automaticMealBreakStartOffsetMinutes
         in Just (breakStartMinute, breakStartMinute + automaticMealBreakMinutes)
    | otherwise = Nothing

validRosterShiftDurationMinutes :: TimeOfDay -> TimeOfDay -> Maybe Int
validRosterShiftDurationMinutes start end =
    let startMinute = normalizeRosterOperationalMinute start
        endMinute = normalizeRosterOperationalMinute end
        duration = endMinute - startMinute
     in if startMinute >= rosterOperationalStartMinuteOfDay
            && startMinute <= rosterOperationalFinalSelectableMinute
            && endMinute >= rosterOperationalStartMinuteOfDay
            && endMinute <= rosterOperationalFinalSelectableMinute
            && duration > 0
            then Just duration
            else Nothing

isValidRosterShiftTimePair :: TimeOfDay -> TimeOfDay -> Bool
isValidRosterShiftTimePair start end = isJust (validRosterShiftDurationMinutes start end)

timeOfDayToMinutes :: TimeOfDay -> Int
timeOfDayToMinutes tod = todHour tod * 60 + todMin tod

minuteOfDayToTimeOfDay :: Int -> TimeOfDay
minuteOfDayToTimeOfDay minute =
    let normalizedMinute = minute `mod` (24 * 60)
        (hour, minuteOfHour) = normalizedMinute `divMod` 60
     in TimeOfDay hour minuteOfHour 0

normalizeShiftMinuteOfDay :: TimeOfDay -> Int
normalizeShiftMinuteOfDay = normalizeRosterOperationalMinute

normalizeRosterOperationalMinute :: TimeOfDay -> Int
normalizeRosterOperationalMinute tod =
    let minuteOfDay = timeOfDayToMinutes tod
    in if minuteOfDay < rosterOperationalStartMinuteOfDay then minuteOfDay + 1440 else minuteOfDay

isWithinEditWindow :: Day -> Day -> Int -> Bool
isWithinEditWindow today workedOn windowDays =
    diffDays today workedOn <= fromIntegral windowDays

operationalDayForLocalTime :: LocalTime -> Day
operationalDayForLocalTime LocalTime { localDay, localTimeOfDay }
    | localTimeOfDay < TimeOfDay 6 0 0 = addDays (-1) localDay
    | otherwise = localDay

currentOperationalDayForVenue :: (?modelContext :: ModelContext) => VenueConfig -> IO Day
currentOperationalDayForVenue venueConfig = do
    now <- getCurrentTime
    operationalDayForUtcTime venueConfig now

operationalDayForUtcTime :: (?modelContext :: ModelContext) => VenueConfig -> UTCTime -> IO Day
operationalDayForUtcTime venueConfig utcTime = do
    localTime <- sqlQueryScalar
        "SELECT (?::timestamptz AT TIME ZONE ?)"
        (utcTime, venueConfig.timezone)
    pure (operationalDayForLocalTime localTime)

ensureEditWindowOrManager :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Day -> IO ()
ensureEditWindowOrManager workedOn =
    unless (hasRole ManagerRole') do
        config <- fetchVenueConfig
        today <- utctDay <$> getCurrentTime
        accessDeniedUnless (isWithinEditWindow today workedOn config.staffTimesheetEditWindowDays)

isLeaveDateRangeValid :: Day -> Day -> Bool
isLeaveDateRangeValid startDate endDate = endDate > startDate
