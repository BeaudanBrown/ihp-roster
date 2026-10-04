-- | An elapsed-time axis. Civil clocks are labels, never coordinates.
module Web.RosterWeeks.TimelineScale
    ( TimelineScale (..)
    , timelineScaleForDay
    , timelineOffsetMinutes
    , timelineInstantAt
    , timelineClockLabel
    , timelineOperationalMinute
    , timelineSnapInstants
    , timelineCreateInstants
    , timelineMoveChoices
    , timelineCoordinate
    ) where

import Application.Helper.TimeRules (normalizeWindowEndMinute,
                                      rosterOperationalStartMinuteOfDay,
                                      rosterOperationalFinalSelectableMinute,
                                      authoritativeRosterIntervalIsOperationallyValid,
                                      operationalDayForLocalTime)
import Application.VenueTime.Model
import Application.VenueTime
import qualified Data.Text as Text
import Data.Time.Clock.POSIX (posixSecondsToUTCTime, utcTimeToPOSIXSeconds)
import IHP.Prelude

data TimelineScale = TimelineScale
    { scaleStartsAt :: !UTCTime
    , scaleEndsAt :: !UTCTime
    , scaleMinutes :: !Double
    } deriving (Eq, Show)

timelineScaleForDay :: Day -> Int -> Int -> [(UTCTime, UTCTime)] -> Either VenueTimeError TimelineScale
timelineScaleForDay day configuredStart configuredFinal shifts = do
    start <- resolveDisplayBoundary FirstOccurrence day startMinute
    end <- resolveDisplayBoundary SecondOccurrence day endMinute
    let startsAt = foldl' min start (map fst shifts)
        endsAt = foldl' max end (map snd shifts)
    pure TimelineScale
        { scaleStartsAt = startsAt
        , scaleEndsAt = endsAt
        , scaleMinutes = realToFrac (diffUTCTime endsAt startsAt) / 60
        }
  where
    dayOffset = if configuredStart < rosterOperationalStartMinuteOfDay then 1440 else 0
    startMinute = configuredStart + dayOffset
    endMinute = normalizeWindowEndMinute configuredStart configuredFinal + dayOffset + 15

-- Configured display edges are not saved shift endpoints. A gap edge advances
-- to the first real minute, and a repeated edge includes both occurrences.
resolveDisplayBoundary :: RepeatedTimeOccurrence -> Day -> Int -> Either VenueTimeError UTCTime
resolveDisplayBoundary occurrence day minute =
    case resolveCivilTime civil of
        Right value -> Right (resolvedInstantUTC value)
        Left (RepeatedCivilTimeRequiresOccurrence _) ->
            resolvedInstantUTC <$> resolveCivilTime civil { repeatedTimeOccurrence = Just occurrence }
        Left (NonexistentCivilTime _) -> resolveDisplayBoundary occurrence day (minute + 1)
        Left failure -> Left failure
  where
    (days, clockMinute) = minute `divMod` 1440
    (hours, minutes) = clockMinute `divMod` 60
    civil = MelbourneCivilTime (addDays (toInteger days) day) (TimeOfDay hours minutes 0) Nothing

-- | Snap to real five-minute boundaries, not offsets from the expanded range
-- origin: a saved boundary may include seconds (or fractions of a second).
-- Epoch alignment also gives both occurrences of an autumn clock unique keys.
timelineSnapInstants :: TimelineScale -> [UTCTime]
timelineSnapInstants scale =
    [ posixSecondsToUTCTime (fromInteger (tick * 300))
    | tick <- [ceiling (utcTimeToPOSIXSeconds scale.scaleStartsAt / 300) .. floor (utcTimeToPOSIXSeconds scale.scaleEndsAt / 300)]
    ]

-- New shifts need a selectable start and room for a later end in the editor.
timelineCreateInstants :: TimelineScale -> Day -> [UTCTime]
timelineCreateInstants scale day =
    [ instant
    | instant <- timelineSnapInstants scale
    , let minute = timelineOperationalMinute day instant
    , minute >= rosterOperationalStartMinuteOfDay
    , minute < rosterOperationalFinalSelectableMinute
    ]

-- Microsecond coordinates stay within JavaScript's exact integer range for a
-- roster day. They are display geometry only; saved durations remain exact.
timelineCoordinate :: TimelineScale -> UTCTime -> Int
timelineCoordinate scale instant = round (diffUTCTime instant scale.scaleStartsAt * 1000000)

timelineMoveChoices :: TimelineScale -> Day -> AuthoritativeBoundaries -> [(UTCTime, Text)]
timelineMoveChoices scale day source =
    [ (start, timelineClockLabel start <> "–" <> timelineClockLabel end)
    | start <- timelineSnapInstants scale
    , let end = addUTCTime (authoritativeElapsedSeconds source) start
    , end <= scale.scaleEndsAt
    , Right boundaries <- [authoritativeBoundariesFromInstants (authoritativeTimezone source) start end Nothing Nothing]
    , operationalDayForLocalTime (authoritativeStartLocalTime boundaries) == day
    , authoritativeRosterIntervalIsOperationallyValid boundaries
    ]

timelineOffsetMinutes :: TimelineScale -> UTCTime -> Double
timelineOffsetMinutes scale instant = realToFrac (diffUTCTime instant scale.scaleStartsAt) / 60

timelineInstantAt :: TimelineScale -> Double -> UTCTime
timelineInstantAt scale minutes = addUTCTime (realToFrac (minutes * 60)) scale.scaleStartsAt

timelineClockLabel :: UTCTime -> Text
timelineClockLabel instant = Text.pack (formatTime defaultTimeLocale clockFormat local.localTimeOfDay) <> suffix
  where
    resolved = resolvedInstantFromUTC instant
    local = resolvedInstantLocalTime resolved
    clockFormat = if local.localTimeOfDay.todSec == 0 then "%H:%M" else "%H:%M:%S%Q"
    suffix = case resolvedInstantOccurrence resolved of
        Nothing -> ""
        Just FirstOccurrence -> " (first)"
        Just SecondOccurrence -> " (second)"

timelineOperationalMinute :: Day -> UTCTime -> Int
timelineOperationalMinute day instant = fromInteger (diffDays local.localDay day) * 1440 + clock.todHour * 60 + clock.todMin
  where
    local = resolvedInstantLocalTime (resolvedInstantFromUTC instant)
    clock = local.localTimeOfDay
