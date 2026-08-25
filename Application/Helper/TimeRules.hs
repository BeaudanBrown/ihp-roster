module Application.Helper.TimeRules where

import Application.VenueTime.Model (AuthoritativeBoundaries, BoundaryModelError,
                                    authoritativeEndLocalTime,
                                    authoritativeStartLocalTime,
                                    repeatedEndpointPairCanShareDate,
                                    storedInstantLocalTime)
import Control.Monad (guard)
import Data.Fixed (Pico)
import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (UTCTime (..), getCurrentTime)
import Data.Time.Format (defaultTimeLocale, formatTime, parseTimeM)
import Data.Time.LocalTime (LocalTime (..), TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude

import Application.Helper.ControllerAccess (fetchVenueConfig, hasRole)

parseTimeParam :: Text -> Maybe TimeOfDay
parseTimeParam value = parseTimeM True defaultTimeLocale "%H:%M" (cs value)

isQuarterHourTime :: TimeOfDay -> Bool
isQuarterHourTime tod = todMin tod `mod` 15 == 0 && todSec tod == 0

isQuarterHourMinutes :: Int -> Bool
isQuarterHourMinutes mins = mins >= 0 && mins `mod` 15 == 0

isQuarterHourMinuteOfDay :: Int -> Bool
isQuarterHourMinuteOfDay mins = mins >= 0 && mins < 24 * 60 && mins `mod` 15 == 0

isTimeOnMinuteInterval :: Int -> TimeOfDay -> Bool
isTimeOnMinuteInterval intervalMinutes tod =
    intervalMinutes > 0 && todMin tod `mod` intervalMinutes == 0 && todSec tod == 0

venueShiftTimeIntervalMinutes :: VenueConfig -> Int
venueShiftTimeIntervalMinutes venueConfig =
    if venueConfig.minutePrecisionShiftTimesEnabled then 1 else 15

venueShiftTimeAllows :: VenueConfig -> TimeOfDay -> Bool
venueShiftTimeAllows venueConfig = isTimeOnMinuteInterval (venueShiftTimeIntervalMinutes venueConfig)

venueShiftTimeValidationMessage :: VenueConfig -> Text
venueShiftTimeValidationMessage venueConfig
    | venueConfig.minutePrecisionShiftTimesEnabled = "Choose a whole-minute time"
    | otherwise = "Choose a time on a 15-minute increment"

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

rosterShiftStartDate :: Day -> TimeOfDay -> Day
rosterShiftStartDate rosterDate startTime
    | timeOfDayToMinutes startTime < rosterOperationalStartMinuteOfDay = addDays 1 rosterDate
    | otherwise = rosterDate

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



normalizeWindowEndMinute :: Int -> Int -> Int
normalizeWindowEndMinute startMinute endMinute =
    if endMinute <= startMinute then endMinute + 24 * 60 else endMinute


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
isValidRosterShiftTimePair start end =
    startSecond >= operationalStartSecond
        && startSecond <= operationalEndSecond
        && endSecond >= operationalStartSecond
        && endSecond <= operationalEndSecond
        && endSecond > startSecond
  where
    startSecond = normalizeRosterOperationalSecond start
    endSecond = normalizeRosterOperationalSecond end
    operationalStartSecond = fromIntegral (rosterOperationalStartMinuteOfDay * 60)
    operationalEndSecond = fromIntegral (rosterOperationalFinalSelectableMinute * 60)

authoritativeRosterIntervalIsOperationallyValid :: AuthoritativeBoundaries -> Bool
authoritativeRosterIntervalIsOperationallyValid boundaries =
    isValidRosterShiftTimePair startLocal.localTimeOfDay endLocal.localTimeOfDay
        || ( startLocal.localDay == endLocal.localDay
             && repeatedEndpointPairCanShareDate startLocal.localDay startLocal.localTimeOfDay endLocal.localTimeOfDay
           )
  where
    startLocal = authoritativeStartLocalTime boundaries
    endLocal = authoritativeEndLocalTime boundaries

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

normalizeRosterOperationalSecond :: TimeOfDay -> Pico
normalizeRosterOperationalSecond TimeOfDay { todHour, todMin, todSec } =
    let secondOfDay = fromIntegral ((todHour * 60 + todMin) * 60) + todSec
        operationalStartSecond = fromIntegral (rosterOperationalStartMinuteOfDay * 60)
     in if secondOfDay < operationalStartSecond then secondOfDay + 24 * 60 * 60 else secondOfDay

isWithinEditWindow :: Day -> Day -> Int -> Bool
isWithinEditWindow today workedOn windowDays =
    diffDays today workedOn <= fromIntegral windowDays

operationalDayForLocalTime :: LocalTime -> Day
operationalDayForLocalTime LocalTime { localDay, localTimeOfDay }
    | localTimeOfDay < rosterOperationalStartTime = addDays (-1) localDay
    | otherwise = localDay

calendarDayForOperationalClock :: Day -> TimeOfDay -> Day
calendarDayForOperationalClock operationalDate clock
    | clock < rosterOperationalStartTime = addDays 1 operationalDate
    | otherwise = operationalDate

currentOperationalDayForVenueOutcome :: VenueConfig -> UTCTime -> Either BoundaryModelError Day
currentOperationalDayForVenueOutcome venueConfig utcTime =
    operationalDayForLocalTime <$> storedInstantLocalTime venueConfig.timezone utcTime

-- Invalid configuration cannot define an Operational day. UTC day is used only
-- as a stable navigation anchor so existing pages remain reachable; creation
-- and timing-sensitive workflows validate the configured timezone separately.
currentOperationalDayForVenue :: (?modelContext :: ModelContext) => VenueConfig -> IO Day
currentOperationalDayForVenue venueConfig = do
    now <- getCurrentTime
    pure (either (const (utctDay now)) (\day -> day) (currentOperationalDayForVenueOutcome venueConfig now))

operationalDayForUtcTime :: (?modelContext :: ModelContext) => VenueConfig -> UTCTime -> IO Day
operationalDayForUtcTime venueConfig utcTime =
    pure (either (const (utctDay utcTime)) (\day -> day) (currentOperationalDayForVenueOutcome venueConfig utcTime))

ensureEditWindowOrManager :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Day -> IO ()
ensureEditWindowOrManager workedOn =
    unless (hasRole Manager) do
        config <- fetchVenueConfig
        today <- currentOperationalDayForVenue config
        accessDeniedUnless (isWithinEditWindow today workedOn config.staffTimesheetEditWindowDays)

isLeaveDateRangeValid :: Day -> Day -> Bool
isLeaveDateRangeValid startDate endDate = endDate > startDate
