module Application.Helper.LiveResource
    ( LiveMutationResult (..)
    , LiveResource (..)
    , liveMutationResult
    ) where

import qualified Data.Set as Set
import Data.UUID (UUID)
import IHP.Prelude

data LiveResource
    = LeaveRequestsResource !UUID
    | StaffLeaveRequestsResource !UUID
    | LeaveCalendarResource !UUID !Int
    | TimesheetWeekResource !UUID !Int
    | StaffTimesheetResource !UUID
    | StaffProfileResource !UUID
    | StaffPreferencesResource !UUID
    deriving (Eq, Ord, Show)

data LiveMutationResult a = LiveMutationResult
    { liveMutationValue            :: !a
    , liveMutationTouchedResources :: !(Set.Set LiveResource)
    }
    deriving (Eq, Show)

liveMutationResult :: a -> [LiveResource] -> LiveMutationResult a
liveMutationResult value resources =
    LiveMutationResult
        { liveMutationValue = value
        , liveMutationTouchedResources = Set.fromList resources
        }
