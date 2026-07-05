{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.RosterValues
    ( RosterStaffSortKey (..)
    , rosterStaffSortKeyAttribute
    , rosterStaffSortKeyValues
    ) where

import qualified Application.Helper.FrontendContract.Roster as Roster
import Application.Helper.FrontendContract.Values
import GHC.Generics (Generic)
import IHP.Prelude

data RosterStaffSortKey
    = RosterStaffSortByName
    | RosterStaffSortByRole
    | RosterStaffSortByShifts
    deriving (Eq, Show, Generic)

rosterStaffSortKeyValues :: [(RosterStaffSortKey, Text)]
rosterStaffSortKeyValues =
    [ (RosterStaffSortByName, enumLiteralValue @Roster.RosterStaffSortKey @Roster.Name)
    , (RosterStaffSortByRole, enumLiteralValue @Roster.RosterStaffSortKey @Roster.Role)
    , (RosterStaffSortByShifts, enumLiteralValue @Roster.RosterStaffSortKey @Roster.Shifts)
    ]

rosterStaffSortKeyAttribute :: RosterStaffSortKey -> Text
rosterStaffSortKeyAttribute key =
    fromMaybe (error "Unknown roster staff sort key") (lookup key rosterStaffSortKeyValues)
