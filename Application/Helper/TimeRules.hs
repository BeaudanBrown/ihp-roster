module Application.Helper.TimeRules where

import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (UTCTime (..), getCurrentTime)
import Data.Time.Format (defaultTimeLocale, parseTimeM)
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

shiftDurationMinutes :: TimeOfDay -> TimeOfDay -> Int
shiftDurationMinutes start end =
    normalizeShiftMinuteOfDay end - normalizeShiftMinuteOfDay start

timeOfDayToMinutes :: TimeOfDay -> Int
timeOfDayToMinutes tod = todHour tod * 60 + todMin tod

normalizeShiftMinuteOfDay :: TimeOfDay -> Int
normalizeShiftMinuteOfDay tod =
    let minuteOfDay = timeOfDayToMinutes tod
    in if minuteOfDay < 360 then minuteOfDay + 1440 else minuteOfDay

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
