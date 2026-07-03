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
    , RosterEndTimesConfig
    , RosterRow
    , RosterSlotsGrid
    , RosterStaffPanel
    , RosterSurface
    , RosterWageRail
    , RosterWeek
    , RosterWeekBoundaryConfig
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

data RosterDay
data RosterEndTimesConfig
data RosterWeekBoundaryConfig

type RosterWeekResource = Resource RosterWeek '[ Field RosterGroupId 'WireUUID, Field WeekOffset 'WireInt ]
type RosterDayResource = Resource RosterDay '[ Field RosterDayId 'WireUUID ]
type RosterEndTimesConfigResource = Resource RosterEndTimesConfig '[ Field VenueId 'WireUUID ]
type RosterWeekBoundaryConfigResource = Resource RosterWeekBoundaryConfig '[ Field VenueId 'WireUUID ]

type RosterScopeBundle =
    '[ Scope RosterWeek
        '[ Field VenueId 'WireUUID
         , Field RosterGroupId 'WireUUID
         , Field WeekOffset 'WireInt
         ]
        '[ 'Authorize 'CurrentVenueRosterGroup '[ VenueId, RosterGroupId ] ]
     ]

type RosterFragmentBundle =
    '[ Fragment RosterContent
        '[]
        '[ 'Eager
         , 'Live
         , 'DependsOn RosterWeekResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ]
         , 'DependsOn RosterEndTimesConfigResource '[ 'FromScope VenueId ]
         , 'DependsOn RosterWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         , 'Contains RosterGridToolbar
         , 'Contains RosterGridFrame
         ]
     , Fragment RosterGridToolbar
        '[]
        '[ 'Eager
         , 'Live
         , 'DependsOn RosterWeekResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ]
         , 'DependsOn RosterEndTimesConfigResource '[ 'FromScope VenueId ]
         , 'DependsOn RosterWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         ]
     , Fragment RosterGridFrame
        '[]
        '[ 'Eager
         , 'Live
         , 'DependsOn RosterWeekResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ]
         , 'DependsOn RosterEndTimesConfigResource '[ 'FromScope VenueId ]
         , 'DependsOn RosterWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         , 'Contains RosterDayColumns
         , 'Contains RosterDayRail
         , 'Contains RosterWageRail
         , 'Contains RosterSlotsGrid
         , 'Contains RosterDaySection
         ]
     , Fragment RosterDayColumns '[] '[ 'Eager, 'Live, 'DependsOn RosterWeekResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ], 'DependsOn RosterEndTimesConfigResource '[ 'FromScope VenueId ], 'DependsOn RosterWeekBoundaryConfigResource '[ 'FromScope VenueId ] ]
     , Fragment RosterDayRail '[] '[ 'Eager, 'Live, 'DependsOn RosterWeekResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ], 'DependsOn RosterEndTimesConfigResource '[ 'FromScope VenueId ], 'DependsOn RosterWeekBoundaryConfigResource '[ 'FromScope VenueId ] ]
     , Fragment RosterWageRail '[] '[ 'Eager, 'Live, 'DependsOn RosterWeekResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ], 'DependsOn RosterEndTimesConfigResource '[ 'FromScope VenueId ], 'DependsOn RosterWeekBoundaryConfigResource '[ 'FromScope VenueId ] ]
     , Fragment RosterSlotsGrid '[] '[ 'Eager, 'Live, 'DependsOn RosterWeekResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ], 'DependsOn RosterEndTimesConfigResource '[ 'FromScope VenueId ], 'DependsOn RosterWeekBoundaryConfigResource '[ 'FromScope VenueId ] ]
     , Fragment RosterStaffPanel '[] '[ 'Lazy '[ 'DependsOnFragment RosterContent ], 'Live, 'DependsOn RosterWeekResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ] ]
     , Fragment RosterDaySection
        '[ Field RosterDayId 'WireUUID ]
        '[ 'Lazy '[ 'DependsOnFragment RosterGridFrame, 'Contains RosterRow ]
         , 'Live
         , 'DependsOn RosterDayResource '[ 'FromFragment RosterDayId ]
         , 'DependsOn RosterEndTimesConfigResource '[ 'FromScope VenueId ]
         , 'DependsOn RosterWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         ]
     , Fragment RosterRow
        '[ Field RosterDayId 'WireUUID
         , Field RowIndex 'WireInt
         ]
        '[ 'Lazy '[ 'DependsOnFragment RosterDaySection ]
         , 'Live
         , 'DependsOn RosterDayResource '[ 'FromFragment RosterDayId ]
         , 'DependsOn RosterEndTimesConfigResource '[ 'FromScope VenueId ]
         , 'DependsOn RosterWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         ]
     ]

type RosterInteractionBundle =
    Concat
        '[ LayoutModeInteraction SetRosterLayoutMode RosterContent RosterLayoutMode
         , DragDropInteraction MoveRosterShiftToSlot RosterContent
         ]

type RosterSurface =
    Surface Roster (Concat '[ RosterScopeBundle, RosterFragmentBundle, RosterInteractionBundle ])
