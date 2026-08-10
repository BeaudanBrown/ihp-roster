module Web.Timesheets.Filters
    ( TimesheetViewFilters (..)
    , emptyTimesheetViewFilters
    ) where

import qualified Data.UUID as UUID
import Web.Controller.Prelude

-- | Canonical URL-backed presentation state for a Timesheets view.
-- Authorization is evaluated independently against the viewer's full venue scope.
data TimesheetViewFilters = TimesheetViewFilters
    { filterStaffId       :: !(Maybe UUID.UUID)
    , filterRosterGroupId :: !(Maybe UUID.UUID)
    }
    deriving (Eq, Show)

emptyTimesheetViewFilters :: TimesheetViewFilters
emptyTimesheetViewFilters = TimesheetViewFilters Nothing Nothing
