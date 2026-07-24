module Application.Helper.WeekBoundaries
    ( WeekdayIndex
    , defaultRosterWeekStartsOn
    , defaultWeekOffsetEpochForStartDay
    , validRosterWeekStartDays
    , orderedWeekdayIndexes
    , startOfWeekFor
    , venueEffectiveRateDate
    , venueEffectiveRateEndDate
    , sortDayNamesForVenueWeek
    , affectedVenueWeekOffsetsForDateRange
    , weekdayIndexForDay
    , venueWeekOffsetForDay
    , venueWeekStartDate
    , weekdayIndexLabel
    ) where

import qualified Data.List as List
import Data.Time.Calendar (Day, addDays, diffDays, fromGregorian)
import Data.Time.Calendar.WeekDate (toWeekDate)
import Generated.Types
import IHP.Prelude

type WeekdayIndex = Int

defaultRosterWeekStartsOn :: WeekdayIndex
defaultRosterWeekStartsOn = 1

validRosterWeekStartDays :: [WeekdayIndex]
validRosterWeekStartDays = canonicalWeekdayOrder

defaultWeekOffsetEpochForStartDay :: WeekdayIndex -> Day
defaultWeekOffsetEpochForStartDay startsOn =
    addDays (toInteger (weekdayOrderOffset startsOn)) mondayEpoch
    where
        mondayEpoch = fromGregorian 2025 1 6

weekdayOrderOffset :: WeekdayIndex -> Int
weekdayOrderOffset weekdayIndex =
    fromMaybe 0 (List.elemIndex weekdayIndex canonicalWeekdayOrder)

canonicalWeekdayOrder :: [WeekdayIndex]
canonicalWeekdayOrder = [1, 2, 3, 4, 5, 6, 0]

orderedWeekdayIndexes :: WeekdayIndex -> [WeekdayIndex]
orderedWeekdayIndexes startsOn =
    take 7 (dropWhile (/= startsOn) (cycle canonicalWeekdayOrder))

sortDayNamesForVenueWeek :: VenueConfig -> [DayName] -> [DayName]
sortDayNamesForVenueWeek venueConfig =
    List.sortOn (\dayName -> weekdayOrderOffsetFor (orderedWeekdayIndexes venueConfig.rosterWeekStartsOn) dayName.weekdayIndex)

affectedVenueWeekOffsetsForDateRange :: VenueConfig -> Day -> Day -> [Int]
affectedVenueWeekOffsetsForDateRange venueConfig startDate endDate
    | endDate <= startDate = []
    | otherwise = [startOffset .. endOffset]
    where
        startOffset = venueWeekOffsetForDay venueConfig startDate
        leaveLastDate = addDays (-1) endDate
        endOffset = venueWeekOffsetForDay venueConfig leaveLastDate

weekdayIndexForDay :: Day -> WeekdayIndex
weekdayIndexForDay day =
    case toWeekDate day of
        (_, _, 7)            -> 0
        (_, _, weekdayIndex) -> weekdayIndex

startOfWeekFor :: WeekdayIndex -> Day -> Day
startOfWeekFor startsOn day =
    addDays (toInteger (negate dayOffset)) day
    where
        orderedIndexes = orderedWeekdayIndexes startsOn
        dayOffset = weekdayOrderOffsetFor orderedIndexes (weekdayIndexForDay day)

venueEffectiveRateDate :: WeekdayIndex -> Day -> Day
venueEffectiveRateDate weekStartsOn rawOperativeFrom
    | rawOperativeFrom == weekStart = rawOperativeFrom
    | otherwise = addDays 7 weekStart
    where
        weekStart = startOfWeekFor weekStartsOn rawOperativeFrom

venueEffectiveRateEndDate :: WeekdayIndex -> Maybe Day -> Maybe Day
venueEffectiveRateEndDate weekStartsOn rawOperativeTo = do
    operativeTo <- rawOperativeTo
    pure (addDays (-1) (venueEffectiveRateDate weekStartsOn (addDays 1 operativeTo)))

weekdayOrderOffsetFor :: [WeekdayIndex] -> WeekdayIndex -> Int
weekdayOrderOffsetFor orderedIndexes weekdayIndex =
    fromMaybe 0 (List.elemIndex weekdayIndex orderedIndexes)

venueWeekOffsetForDay :: VenueConfig -> Day -> Int
venueWeekOffsetForDay venueConfig day =
    fromInteger (diffDays day venueConfig.weekOffsetEpoch `div` 7)

venueWeekStartDate :: VenueConfig -> Int -> Day
venueWeekStartDate venueConfig weekOffset =
    addDays (toInteger (weekOffset * 7)) venueConfig.weekOffsetEpoch

weekdayIndexLabel :: WeekdayIndex -> Text
weekdayIndexLabel weekdayIndex =
    fromMaybe ("Weekday " <> tshow weekdayIndex) (lookup weekdayIndex weekdayIndexLabels)

weekdayIndexLabels :: [(WeekdayIndex, Text)]
weekdayIndexLabels =
    [ (0, "Sunday")
    , (1, "Monday")
    , (2, "Tuesday")
    , (3, "Wednesday")
    , (4, "Thursday")
    , (5, "Friday")
    , (6, "Saturday")
    ]
