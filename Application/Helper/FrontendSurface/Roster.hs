{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.Roster
    ( RosterContent
    , RosterDayColumns
    , RosterDayId
    , RosterDayRail
    , RosterDaySection
    , RosterGridFrame
    , RosterGridToolbar
    , RosterGroupId
    , RosterRow
    , RosterSlotsGrid
    , RosterStaffPanel
    , RosterSurface
    , RosterWageRail
    , RosterWeek
    , RowIndex
    , VenueId
    , WeekOffset
    ) where

import Application.Helper.FrontendSurface.DSL

data Roster

data RosterWeek
data VenueId
data RosterGroupId
data WeekOffset

data RosterContent
data RosterGridToolbar
data RosterGridFrame
data RosterDayColumns
data RosterDayRail
data RosterWageRail
data RosterSlotsGrid
data RosterStaffPanel
data RosterDaySection
data RosterRow

data RosterDayId
data RowIndex

type RosterScopeBundle =
    '[ Scope RosterWeek
        '[ Field VenueId 'WireUUID
         , Field RosterGroupId 'WireUUID
         , Field WeekOffset 'WireInt
         ]
     ]

type RosterFragmentBundle =
    '[ Fragment RosterContent
        '[]
        '[ 'Eager
         , 'Contains RosterGridToolbar
         , 'Contains RosterGridFrame
         ]
     , Fragment RosterGridToolbar '[] '[ 'Eager ]
     , Fragment RosterGridFrame
        '[]
        '[ 'Eager
         , 'Contains RosterDayColumns
         , 'Contains RosterDayRail
         , 'Contains RosterWageRail
         , 'Contains RosterSlotsGrid
         , 'Contains RosterDaySection
         ]
     , Fragment RosterDayColumns '[] '[ 'Eager ]
     , Fragment RosterDayRail '[] '[ 'Eager ]
     , Fragment RosterWageRail '[] '[ 'Eager ]
     , Fragment RosterSlotsGrid '[] '[ 'Eager ]
     , Fragment RosterStaffPanel '[] '[ 'Lazy '[ 'DependsOn RosterContent ] ]
     , Fragment RosterDaySection
        '[ Field RosterDayId 'WireUUID ]
        '[ 'Lazy '[ 'DependsOn RosterGridFrame, 'Contains RosterRow ] ]
     , Fragment RosterRow
        '[ Field RosterDayId 'WireUUID
         , Field RowIndex 'WireInt
         ]
        '[ 'Lazy '[ 'DependsOn RosterDaySection ] ]
     ]

type RosterSurface =
    Surface Roster (Concat '[ RosterScopeBundle, RosterFragmentBundle ])
