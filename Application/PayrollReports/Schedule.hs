module Application.PayrollReports.Schedule
    ( nextReportOccurrence
    , reportWeekForOccurrence
    , withinReportCatchUpWindow
    ) where

import Application.Helper.WeekBoundaries (startOfWeekFor, weekdayIndexForDay)
import Application.VenueTime
import Data.Time (addLocalTime, localDay)
import Data.Traversable (traverse)
import IHP.Prelude

-- VenueTime currently supports Melbourne only; fail closed for unsupported
-- persisted zones instead of silently scheduling in UTC or server-local time.
nextReportOccurrence :: Text -> Int -> Int -> UTCTime -> Either Text UTCTime
nextReportOccurrence timezone weekday minute after
    | timezone /= melbourneTimeZoneName = Left "Unsupported venue timezone."
    | weekday < 0 || weekday > 6 || minute < 0 || minute >= 1440 = Left "Invalid report schedule."
    | otherwise = do
        candidates <- traverse resolveDay matchingDays
        maybe (Left "No next report occurrence.") Right (find (> after) candidates)
  where
    today = localDay (resolvedInstantLocalTime (resolvedInstantFromUTC after))
    matchingDays = filter ((== weekday) . weekdayIndexForDay) (map (`addDays` today) [0 .. 14])
    resolveDay day = resolveMinute 0 (LocalTime day (TimeOfDay (minute `div` 60) (minute `mod` 60) 0))
    resolveMinute :: Int -> LocalTime -> Either Text UTCTime
    resolveMinute attempts local
        | attempts > 180 = Left "Unable to resolve scheduled civil time."
        | otherwise = case resolveCivilTime (MelbourneCivilTime local.localDay local.localTimeOfDay Nothing) of
            Right instant -> Right (resolvedInstantUTC instant)
            Left RepeatedCivilTimeRequiresOccurrence {} ->
                either (const (Left "Unable to resolve repeated scheduled time.")) (Right . resolvedInstantUTC)
                    (resolveCivilTime (MelbourneCivilTime local.localDay local.localTimeOfDay (Just FirstOccurrence)))
            Left NonexistentCivilTime {} -> resolveMinute (attempts + 1) (addLocalTime 60 local)
            Left _ -> Left "Invalid scheduled civil time."

reportWeekForOccurrence :: Int -> UTCTime -> Day
reportWeekForOccurrence startsOn = addDays (-7) . startOfWeekFor startsOn . localDay . resolvedInstantLocalTime . resolvedInstantFromUTC

withinReportCatchUpWindow :: UTCTime -> UTCTime -> Bool
withinReportCatchUpWindow now due = now >= due && diffUTCTime now due < 86400
