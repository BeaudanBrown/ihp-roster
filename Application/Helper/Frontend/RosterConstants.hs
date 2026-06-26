module Application.Helper.Frontend.RosterConstants
    ( RosterStaffSortKey (..)
    , rosterStaffSortKeyAttribute
    , rosterStaffSortKeyValues
    ) where

import IHP.Prelude

data RosterStaffSortKey
    = RosterStaffSortByName
    | RosterStaffSortByRole
    | RosterStaffSortByShifts
    deriving (Eq, Show)

rosterStaffSortKeyValues :: [(RosterStaffSortKey, Text)]
rosterStaffSortKeyValues =
    [ (RosterStaffSortByName, "name")
    , (RosterStaffSortByRole, "role")
    , (RosterStaffSortByShifts, "shifts")
    ]

rosterStaffSortKeyAttribute :: RosterStaffSortKey -> Text
rosterStaffSortKeyAttribute key =
    fromMaybe (error "Unknown roster staff sort key") (lookup key rosterStaffSortKeyValues)
