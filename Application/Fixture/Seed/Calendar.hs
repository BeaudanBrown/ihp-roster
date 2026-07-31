module Application.Fixture.Seed.Calendar
    ( currentWeekOffsetForDay
    , weekOffsetForDay
    , weekStartForOffset
    ) where

import Application.Fixture (defaultWeekEpoch)
import Data.Time.Calendar (Day, addDays, diffDays)
import IHP.Prelude

weekStartForOffset :: Int -> Day
weekStartForOffset weekOffset =
    addDays (toInteger (weekOffset * 7)) defaultWeekEpoch

currentWeekOffsetForDay :: Day -> Int
currentWeekOffsetForDay = weekOffsetForDay

weekOffsetForDay :: Day -> Int
weekOffsetForDay day =
    fromInteger (diffDays day defaultWeekEpoch `div` 7)
