{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.RosterValues
    ( RosterStaffSortKey (..)
    , rosterStaffSortKeyAttribute
    , rosterStaffSortKeyValues
    ) where

import qualified Application.Helper.FrontendContract.App as App
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
    [ (RosterStaffSortByName, enumLiteralValue @App.RosterStaffSortKey @App.Name)
    , (RosterStaffSortByRole, enumLiteralValue @App.RosterStaffSortKey @App.Role)
    , (RosterStaffSortByShifts, enumLiteralValue @App.RosterStaffSortKey @App.Shifts)
    ]

rosterStaffSortKeyAttribute :: RosterStaffSortKey -> Text
rosterStaffSortKeyAttribute key =
    fromMaybe (error "Unknown roster staff sort key") (lookup key rosterStaffSortKeyValues)
