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
    , MoveRosterShiftToSlot
    , RosterLayoutMode
    , RowIndex
    , SetRosterLayoutMode
    , VenueId
    , WeekOffset
    ) where

import Application.Helper.FrontendSurface.DSL
import Application.Helper.FrontendSurface.Interaction

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

data SetRosterLayoutMode
data MoveRosterShiftToSlot
data RosterLayoutMode

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
         , 'Live
         , 'Contains RosterGridToolbar
         , 'Contains RosterGridFrame
         ]
     , Fragment RosterGridToolbar '[] '[ 'Eager, 'Live ]
     , Fragment RosterGridFrame
        '[]
        '[ 'Eager
         , 'Live
         , 'Contains RosterDayColumns
         , 'Contains RosterDayRail
         , 'Contains RosterWageRail
         , 'Contains RosterSlotsGrid
         , 'Contains RosterDaySection
         ]
     , Fragment RosterDayColumns '[] '[ 'Eager, 'Live ]
     , Fragment RosterDayRail '[] '[ 'Eager, 'Live ]
     , Fragment RosterWageRail '[] '[ 'Eager, 'Live ]
     , Fragment RosterSlotsGrid '[] '[ 'Eager, 'Live ]
     , Fragment RosterStaffPanel '[] '[ 'Lazy '[ 'DependsOn RosterContent ], 'Live ]
     , Fragment RosterDaySection
        '[ Field RosterDayId 'WireUUID ]
        '[ 'Lazy '[ 'DependsOn RosterGridFrame, 'Contains RosterRow ], 'Live ]
     , Fragment RosterRow
        '[ Field RosterDayId 'WireUUID
         , Field RowIndex 'WireInt
         ]
        '[ 'Lazy '[ 'DependsOn RosterDaySection ], 'Live ]
     ]

type RosterInteractionBundle =
    Concat
        '[ LayoutModeInteraction SetRosterLayoutMode RosterContent RosterLayoutMode
         , DragDropInteraction MoveRosterShiftToSlot RosterContent
         ]

type RosterSurface =
    Surface Roster (Concat '[ RosterScopeBundle, RosterFragmentBundle, RosterInteractionBundle ])
