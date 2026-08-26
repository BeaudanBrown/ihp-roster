module Application.RosterPublication
    ( rosterDaysArePublished
    ) where

import Data.List (nub)
import Generated.Types
import IHP.Prelude

rosterDaysArePublished :: [RosterDay] -> Bool
rosterDaysArePublished rosterDays =
    length rosterDays == 7
        && length (nub (map (.operationalDate) rosterDays)) == 7
        && all ((== Published) . (.publicationState)) rosterDays
