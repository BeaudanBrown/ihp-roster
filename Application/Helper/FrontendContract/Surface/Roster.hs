{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.Roster
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
    , RosterWeekOverview
    , RosterStaffSelfServiceLeaveFormFragment
    , MoveRosterShiftToSlot
    , NavigateRosterWeek
    , ToggleRosterWarnings
    , ToggleRosterWageEstimates
    , SortRosterWeek
    , ToggleRosterWeekLiveStatus
    , ToggleRosterAssignmentFilters
    , CopyRosterWeek
    , CreateRosterSelfServiceLeaveRequest
    , CreateRosterWeekSlotDefinition
    , DeleteRosterWeekSlotDefinition
    , ToggleRosterDayClosed
    , AddRosterRow
    , RemoveRosterRow
    , ToggleRosterStaffScope
    , RosterLayoutMode
    , RowIndex
    , SetRosterLayoutMode
    , VenueId
    , WeekOffset
    ) where

import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Interaction

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
data NavigateRosterWeek
data ToggleRosterWarnings
data ToggleRosterWageEstimates
data SortRosterWeek
data ToggleRosterWeekLiveStatus
data ToggleRosterAssignmentFilters
data CopyRosterWeek
data CreateRosterSelfServiceLeaveRequest
data CreateRosterWeekSlotDefinition
data DeleteRosterWeekSlotDefinition
data ToggleRosterDayClosed
data AddRosterRow
data RemoveRosterRow
data ToggleRosterStaffScope
data RosterLayoutMode

data RosterDayId
data RowIndex
data None
data OuterHTML
data ShowRosterWarnings
data IsLive
data ShowWageEstimates
data ShowUnavailableStaff
data ShowIdealShiftMatches
data StaffScope
data RosterWeekShellSyncCustomHtmx
data CopyRosterWeekCustomHtmx

data RosterDay
data RosterWeekOverview
data RosterEndTimesConfig
data RosterWeekBoundaryConfig
data RosterStaffSelfServiceLeaveFormFragment
data StartDate
data EndDate
data Reason

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
     , Fragment RosterWeekOverview '[] '[ 'Lazy '[ 'DependsOnFragment RosterContent ], 'DependsOn RosterWeekResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ] ]
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

type RosterActionBundle =
    '[ Action NavigateRosterWeek
        '[ Field WeekOffset 'WireInt
         , Field RosterGroupId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxGet
         , 'HtmxTarget RosterContent
         , 'HtmxSwap OuterHTML
         , 'HtmxPushUrl 'HtmxPushUrlTrue
         , 'CustomHtmx RosterWeekShellSyncCustomHtmx "roster week navigation serializes through the stable roster week shell"
         ]
     , Action ToggleRosterWarnings
        '[ Field ShowRosterWarnings 'WireBool ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap None
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'CustomHtmx RosterWeekShellSyncCustomHtmx "preference toggles serialize through the stable roster week shell"
         ]
     , Action ToggleRosterWageEstimates
        '[ Field ShowWageEstimates 'WireBool ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap None
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'CustomHtmx RosterWeekShellSyncCustomHtmx "preference toggles serialize through the stable roster week shell"
         ]
     , Action SortRosterWeek
        '[]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxTarget RosterContent
         , 'HtmxSwap None
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'CustomHtmx RosterWeekShellSyncCustomHtmx "sort mutations serialize through the stable roster week shell"
         ]
     , Action ToggleRosterWeekLiveStatus
        '[ Field IsLive 'WireBool ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxTarget RosterContent
         , 'HtmxSwap OuterHTML
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'CustomHtmx RosterWeekShellSyncCustomHtmx "live toggle serializes through the stable roster week shell"
         ]
     , Action ToggleRosterAssignmentFilters
        '[ Field ShowUnavailableStaff 'WireBool
         , Field ShowIdealShiftMatches 'WireBool
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap None
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'CustomHtmx RosterWeekShellSyncCustomHtmx "assignment filter toggles serialize through the stable roster week shell"
         ]
     , Action CopyRosterWeek
        '[]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxTarget RosterContent
         , 'HtmxSwap OuterHTML
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'CustomHtmx RosterWeekShellSyncCustomHtmx "copy mutations serialize through the stable roster week shell"
         , 'CustomHtmx CopyRosterWeekCustomHtmx "copy previous week requires a destructive overwrite confirmation"
         ]
     , Action CreateRosterSelfServiceLeaveRequest
        '[ Field StartDate 'WireDay
         , Field EndDate 'WireDay
         , Field Reason 'WireText
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxTarget RosterStaffSelfServiceLeaveFormFragment
         , 'HtmxSwap OuterHTML
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         ]
     , Action CreateRosterWeekSlotDefinition
        '[]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxTarget RosterContent
         , 'HtmxSwap None
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'CustomHtmx RosterWeekShellSyncCustomHtmx "slot-definition mutations serialize through the stable roster week shell"
         ]
     , Action DeleteRosterWeekSlotDefinition
        '[]
        '[ 'HtmxMethod 'HtmxDelete
         , 'HtmxTarget RosterContent
         , 'HtmxSwap None
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'CustomHtmx RosterWeekShellSyncCustomHtmx "slot-definition mutations serialize through the stable roster week shell"
         ]
     , Action ToggleRosterDayClosed
        '[]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxTarget RosterDaySection
         , 'HtmxSwap None
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'CustomHtmx RosterWeekShellSyncCustomHtmx "day row mutations serialize through the stable roster week shell"
         ]
     , Action AddRosterRow
        '[]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxTarget RosterDaySection
         , 'HtmxSwap None
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'CustomHtmx RosterWeekShellSyncCustomHtmx "day row mutations serialize through the stable roster week shell"
         ]
     , Action RemoveRosterRow
        '[]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxTarget RosterDaySection
         , 'HtmxSwap None
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'CustomHtmx RosterWeekShellSyncCustomHtmx "day row mutations serialize through the stable roster week shell"
         ]
     , Action ToggleRosterStaffScope
        '[ Field StaffScope 'WireText ]
        '[ 'HtmxMethod 'HtmxGet
         , 'HtmxTarget RosterStaffPanel
         , 'HtmxSwap OuterHTML
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         ]
     , DomToken RosterContent
     , DomToken RosterDaySection
     , DomToken RosterStaffPanel
     , DomToken RosterStaffSelfServiceLeaveFormFragment
     ]

type RosterInteractionBundle =
    Concat
        '[ LayoutModeInteraction SetRosterLayoutMode RosterContent RosterLayoutMode
         , DragDropInteraction MoveRosterShiftToSlot RosterContent
         ]

type RosterSurface =
    Surface Roster (Concat '[ RosterScopeBundle, RosterFragmentBundle, RosterActionBundle, RosterInteractionBundle ])
