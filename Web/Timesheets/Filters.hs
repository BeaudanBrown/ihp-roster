module Web.Timesheets.Filters
    ( TimesheetViewFilters (..)
    , emptyTimesheetViewFilters
    , activeTimesheetFilterCount
    , matchesTimesheetFilters
    , canonicalizeTimesheetFilters
    ) where

import qualified Data.Set as Set
import IHP.Prelude

-- Presentation state only; never authorization evidence. Empty means All.
data TimesheetViewFilters = TimesheetViewFilters
    { filterStaffIds       :: ![UUID]
    , filterRosterGroupIds :: ![UUID]
    , filterShiftTypeIds   :: ![UUID]
    }
    deriving (Eq, Show)

emptyTimesheetViewFilters :: TimesheetViewFilters
emptyTimesheetViewFilters = TimesheetViewFilters [] [] []

activeTimesheetFilterCount :: TimesheetViewFilters -> Int
activeTimesheetFilterCount filters =
    length (filter (not . null) [filters.filterStaffIds, filters.filterRosterGroupIds, filters.filterShiftTypeIds])

matchesTimesheetFilters :: TimesheetViewFilters -> UUID -> Maybe UUID -> UUID -> Bool
matchesTimesheetFilters filters staffId groupId shiftTypeId =
    matches filters.filterStaffIds staffId
        && (null filters.filterRosterGroupIds || maybe False (`elem` filters.filterRosterGroupIds) groupId)
        && matches filters.filterShiftTypeIds shiftTypeId
  where
    matches selected value = null selected || value `elem` selected

canonicalizeTimesheetFilters :: Bool -> [UUID] -> [UUID] -> [UUID] -> TimesheetViewFilters -> TimesheetViewFilters
canonicalizeTimesheetFilters management staffIds groupIds shiftTypeIds requested =
    TimesheetViewFilters
        (if management then retain staffIds requested.filterStaffIds else [])
        (if management && length groupIds > 1 then retain groupIds requested.filterRosterGroupIds else [])
        (retain shiftTypeIds requested.filterShiftTypeIds)
  where
    retain available = Set.toAscList . Set.intersection (Set.fromList available) . Set.fromList
