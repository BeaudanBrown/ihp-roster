{-# LANGUAGE OverloadedRecordDot #-}

-- | Roster-only creation defaults. Timesheets retain their independent policy.
module Web.RosterWeeks.DefaultDuration
    ( RosterCreationDefaults (..)
    , rosterCreationDefaults
    , validDefaultRosterDuration
    , defaultRosterStart
    , defaultRosterEnd
    ) where

import Application.Helper.TimeRules
import Application.VenueTime (MelbourneCivilTime (..),
                              RepeatedTimeOccurrence (..), VenueTimeError (..),
                              resolveCivilTime, resolvedInstantFromUTC,
                              resolvedInstantLocalTime, resolvedInstantUTC)
import Data.Time (addDays, addUTCTime, diffDays, localDay, localTimeOfDay)
import Generated.Types (VenueConfig, defaultRosterShiftDurationMinutes)
import IHP.Prelude

data RosterCreationDefaults = RosterCreationDefaults
    { creationDefaultMinutes    :: !Int
    , creationWindowStartMinute :: !Int
    , creationWindowEndMinute   :: !Int
    } deriving (Eq, Show)

rosterCreationDefaults :: VenueConfig -> RosterCreationDefaults
rosterCreationDefaults config = RosterCreationDefaults
    config.defaultRosterShiftDurationMinutes
    (venueTimePickerStartMinuteOfDay config)
    (venueTimePickerFinalSelectableMinuteOfDay config)

validDefaultRosterDuration :: Int -> Bool
validDefaultRosterDuration minutes = minutes >= 15 && minutes <= 1440 && minutes `mod` 15 == 0

defaultRosterStart :: RosterCreationDefaults -> Day -> Maybe UTCTime
defaultRosterStart config day =
    case resolveCivilTime civil of
        Right resolved -> Just (resolvedInstantUTC resolved)
        Left (RepeatedCivilTimeRequiresOccurrence _) ->
            either (const Nothing) (Just . resolvedInstantUTC) (resolveCivilTime civil { repeatedTimeOccurrence = Just FirstOccurrence })
        Left _ -> Nothing
  where
    minute = config.creationWindowStartMinute
    startDay = if minute < rosterOperationalStartMinuteOfDay then addDays 1 day else day
    civil = MelbourneCivilTime startDay (minuteOfDayToTimeOfDay minute) Nothing

-- | Search real elapsed instants, retaining the editor's precision. Clipping
-- uses the configured civil window, so DST gaps are never invented and repeated
-- endpoints retain their actual occurrence. The bounded search is at most 288
-- candidates for timeline creation (96 for ordinary quarter-hour creation).
defaultRosterEnd :: RosterCreationDefaults -> Day -> UTCTime -> Int -> Maybe UTCTime
defaultRosterEnd config day start stepMinutes = headMay candidates
  where
    configuredStart = config.creationWindowStartMinute
    dayOffset = if configuredStart < rosterOperationalStartMinuteOfDay then 1440 else 0
    windowStart = configuredStart + dayOffset
    windowEnd = normalizeWindowEndMinute configuredStart config.creationWindowEndMinute + dayOffset
    minuteOf instant =
        let local = resolvedInstantLocalTime (resolvedInstantFromUTC instant)
         in fromInteger (diffDays local.localDay day) * 1440 + timeOfDayToMinutes local.localTimeOfDay
    step = max 1 stepMinutes
    candidates =
        [ instant
        | minutes <- [config.creationDefaultMinutes, config.creationDefaultMinutes - step .. step]
        , let instant = addUTCTime (fromIntegral (minutes * 60)) start
        , minuteOf start >= windowStart
        , minuteOf instant >= windowStart
        , minuteOf instant <= windowEnd
        ]
