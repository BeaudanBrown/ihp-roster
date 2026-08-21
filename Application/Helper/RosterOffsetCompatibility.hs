module Application.Helper.RosterOffsetCompatibility
    ( applyLegacyRosterDayOffset
    , applyLegacyRosterWeekOffset
    , applyLegacyWeekOffsetEpoch
    , applyLegacyWeekOffsetEpochDate
    , defaultWeekOffsetEpochForStartDay
    , legacyRosterWeekStartForRecord
    , legacyWeekOffsetForEpoch
    , venueWeekOffsetForDay
    , venueWeekStartDate
    ) where

import Application.Helper.WeekBoundaries (WeekdayIndex)
import qualified Data.List as List
import Data.Time.Calendar (Day, addDays, diffDays, fromGregorian)
import Generated.Types
import IHP.Prelude

-- | Rollback compatibility for the retained offset schema. Runtime roster and
-- Timesheet authority must use explicit Operational dates instead.
defaultWeekOffsetEpochForStartDay :: WeekdayIndex -> Day
defaultWeekOffsetEpochForStartDay startsOn =
    addDays (toInteger (weekdayOrderOffset startsOn)) mondayEpoch
  where
    mondayEpoch = fromGregorian 2025 1 6

-- | Populate the retained VenueConfig rollback column from explicit calendar
-- configuration. Do not read this field outside this compatibility module.
applyLegacyWeekOffsetEpoch :: WeekdayIndex -> VenueConfig -> VenueConfig
applyLegacyWeekOffsetEpoch startsOn =
    applyLegacyWeekOffsetEpochDate (defaultWeekOffsetEpochForStartDay startsOn)

-- | Test/fixture-only rollback epoch override. Production calendar changes must
-- use 'applyLegacyWeekOffsetEpoch' so the retained value matches the start day.
applyLegacyWeekOffsetEpochDate :: Day -> VenueConfig -> VenueConfig
applyLegacyWeekOffsetEpochDate = set #weekOffsetEpoch

-- | Derive the retained RosterWeek rollback key for a date-native window.
venueWeekOffsetForDay :: VenueConfig -> Day -> Int
venueWeekOffsetForDay venueConfig =
    legacyWeekOffsetForEpoch venueConfig.weekOffsetEpoch

legacyWeekOffsetForEpoch :: Day -> Day -> Int
legacyWeekOffsetForEpoch compatibilityEpoch operationalDate =
    fromInteger (diffDays operationalDate compatibilityEpoch `div` 7)

-- | Decode retained rollback identity only at an explicit compatibility seam.
venueWeekStartDate :: VenueConfig -> Int -> Day
venueWeekStartDate venueConfig compatibilityOffset =
    addDays (toInteger (compatibilityOffset * 7)) venueConfig.weekOffsetEpoch

-- | Decode the retained identity of one compatibility RosterWeek record.
legacyRosterWeekStartForRecord :: VenueConfig -> RosterWeek -> Day
legacyRosterWeekStartForRecord venueConfig rosterWeek =
    venueWeekStartDate venueConfig rosterWeek.weekOffset

-- | Populate retained RosterWeek rollback identity from an explicit window.
applyLegacyRosterWeekOffset :: VenueConfig -> Day -> RosterWeek -> RosterWeek
applyLegacyRosterWeekOffset venueConfig windowStart =
    set #weekOffset (venueWeekOffsetForDay venueConfig windowStart)

-- | Populate retained RosterDay rollback identity from its Operational date.
applyLegacyRosterDayOffset :: Day -> RosterDay -> RosterDay
applyLegacyRosterDayOffset windowStart rosterDay =
    rosterDay
        |> set #dayOffset (fromInteger (diffDays rosterDay.operationalDate windowStart))

weekdayOrderOffset :: WeekdayIndex -> Int
weekdayOrderOffset weekdayIndex =
    fromMaybe 0 (List.elemIndex weekdayIndex [1, 2, 3, 4, 5, 6, 0])
