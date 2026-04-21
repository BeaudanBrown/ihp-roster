{-# LANGUAGE TypeApplications #-}

module Application.Helper.Controller
    ( module Application.Helper.Controller
    , module Application.Helper.ControllerContext
    , module Application.Helper.ControllerAccess
    , module Application.Helper.ControllerSupport
    , module Application.Helper.Htmx
    , module Application.Helper.Audit
    ) where

import Data.Time.Calendar (Day, addDays, diffDays)
import Data.Time.Clock (UTCTime (..), getCurrentTime)
import Data.Time.Format (defaultTimeLocale, parseTimeM)
import Data.Time.LocalTime (TimeOfDay (..))
import Generated.Types
import IHP.ControllerPrelude

import Application.Helper.Audit
import Application.Helper.ControllerAccess
import Application.Helper.ControllerContext
import Application.Helper.ControllerSupport
import Application.Helper.Htmx

-- Here you can add functions which are available in all your controllers

-- | Parse a HH:MM text value into a TimeOfDay.
parseTimeParam :: Text -> Maybe TimeOfDay
parseTimeParam value = parseTimeM True defaultTimeLocale "%H:%M" (cs value)

-- | True when a TimeOfDay falls on a 15-minute boundary.
isQuarterHourTime :: TimeOfDay -> Bool
isQuarterHourTime tod = todMin tod `mod` 15 == 0 && todSec tod == 0

-- | True when minutes are non-negative and divisible by 15.
isQuarterHourMinutes :: Int -> Bool
isQuarterHourMinutes mins = mins >= 0 && mins `mod` 15 == 0

-- | Compute shift duration in minutes (end - start).
shiftDurationMinutes :: TimeOfDay -> TimeOfDay -> Int
shiftDurationMinutes start end =
    normalizeShiftMinuteOfDay end - normalizeShiftMinuteOfDay start

timeOfDayToMinutes :: TimeOfDay -> Int
timeOfDayToMinutes tod = todHour tod * 60 + todMin tod

-- | Normalize shift-related times onto a linear timeline where 00:00-05:45
-- are treated as next-day continuation of the same working window.
normalizeShiftMinuteOfDay :: TimeOfDay -> Int
normalizeShiftMinuteOfDay tod =
    let minuteOfDay = timeOfDayToMinutes tod
    in if minuteOfDay < 360 then minuteOfDay + 1440 else minuteOfDay

-- | True when the worked-on date is within the staff edit window (inclusive).
-- The window is measured in days from today backwards.
isWithinEditWindow :: Day -> Day -> Int -> Bool
isWithinEditWindow today workedOn windowDays =
    diffDays today workedOn <= fromIntegral windowDays

-- | Guard that denies staff access to entries outside the edit window.
-- Manager/admin roles bypass the restriction entirely.
ensureEditWindowOrManager :: (?context :: ControllerContext, ?modelContext :: ModelContext) => Day -> IO ()
ensureEditWindowOrManager workedOn =
    unless (hasRole ManagerRole') do
        config <- fetchVenueConfig
        today <- utctDay <$> getCurrentTime
        accessDeniedUnless (isWithinEditWindow today workedOn config.staffTimesheetEditWindowDays)

leaveRequestCanBeDeleted :: LeaveRequest -> Bool
leaveRequestCanBeDeleted leaveRequest =
    parseLeaveRequestStatus leaveRequest.status == Just LeavePending

-- | True when leave date range is valid.
-- Start date is first unavailable date, end date is first available date.
isLeaveDateRangeValid :: Day -> Day -> Bool
isLeaveDateRangeValid startDate endDate = endDate > startDate

-- | Returns all week offsets overlapped by an inclusive date range.
affectedWeekOffsetsForDateRange :: Day -> Day -> Day -> [Int]
affectedWeekOffsetsForDateRange epoch startDate endDate
    | not (isLeaveDateRangeValid startDate endDate) = []
    | otherwise = [startOffset .. endOffset]
    where
        toWeekOffset day = fromInteger (diffDays day epoch `div` 7)
        startOffset = toWeekOffset startDate
        leaveLastDate = addDays (-1) endDate
        endOffset = toWeekOffset leaveLastDate
