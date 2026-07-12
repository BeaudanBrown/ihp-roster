{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.Roster
    ( RosterContent
    , RosterDayColumns
    , RosterDay
    , RosterDayId
    , RosterDayTimeline
    , RosterDayTimelineContent
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
    , RosterDayTimelineSurface
    , RosterWeekShell
    , RosterWageRail
    , RosterWeek
    , RosterWeekBoundaryConfig
    , RosterWeekOverview
    , RosterStaffSelfServiceLeaveFormFragment
    , MoveRosterShiftToSlot
    , ShiftDragSource
    , StaffDragSource
    , ShiftSlotDropzone
    , StaffCreateDropzone
    , DayColumnDropzone
    , ExistingShiftDropzone
    , DeleteShiftDropzone
    , MoveRosterTimelineShift
    , DuplicateRosterShiftToDay
    , DropRosterStaff
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
data RosterDayTimeline

data RosterWeek
data VenueId
data RosterGroupId
data WeekOffset

data RosterContent
data RosterWeekShell
data RosterGridToolbar
data RosterGridFrame
data RosterDayColumns
data RosterDayRail
data RosterWageRail
data RosterSlotsGrid
data RosterStaffPanel
data RosterDaySection
data RosterRow
data RosterDayTimelineContent

data SetRosterLayoutMode
data MoveRosterShiftToSlot
data MoveRosterTimelineShift
data DuplicateRosterShiftToDay
data DropRosterStaff

data ShiftDragSource
data StaffDragSource
data ShiftSlotDropzone
data StaffCreateDropzone
data DayColumnDropzone
data ExistingShiftDropzone
data DeleteShiftDropzone
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
data HideStaffAtIdealShifts
data HideStaffUnavailable
data HideStaffOnApprovedLeave
data HideStaffAlreadyAssignedToday
data StaffScope
data CopyRosterWeekCustomHtmx

data RosterDay
data RosterWeekOverview
data RosterEndTimesConfig
data RosterWeekBoundaryConfig
data TimePickerConfig
data RosterStaffSelfServiceLeaveFormFragment
data StartDate
data EndDate
data Reason

type RosterWeekResource = Resource RosterWeek '[ Field RosterGroupId 'WireUUID, Field WeekOffset 'WireInt ]
type RosterDayResource = Resource RosterDay '[ Field RosterDayId 'WireUUID ]
type RosterEndTimesConfigResource = Resource RosterEndTimesConfig '[ Field VenueId 'WireUUID ]
type RosterWeekBoundaryConfigResource = Resource RosterWeekBoundaryConfig '[ Field VenueId 'WireUUID ]
type TimePickerConfigResource = Resource TimePickerConfig '[ Field VenueId 'WireUUID ]

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
     , Fragment RosterStaffSelfServiceLeaveFormFragment '[] '[ 'Eager, 'Live, 'ResyncOnly ]
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
         , 'HtmxTarget ('HtmxId RosterWeekShell)
         , 'HtmxPushUrl 'HtmxPushUrlTrue
         , 'HtmxSync ('HtmxSyncOn ('HtmxId RosterWeekShell) 'HtmxSyncReplace)
         ]
     , Action ToggleRosterWarnings
        '[ Field ShowRosterWarnings 'WireBool ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'HtmxSync ('HtmxSyncOn ('HtmxId RosterWeekShell) 'HtmxSyncReplace)
         ]
     , Action ToggleRosterWageEstimates
        '[ Field ShowWageEstimates 'WireBool ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'HtmxSync ('HtmxSyncOn ('HtmxId RosterWeekShell) 'HtmxSyncReplace)
         ]
     , Action SortRosterWeek
        '[]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxTarget ('HtmxId RosterContent)
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'HtmxSync ('HtmxSyncOn ('HtmxId RosterWeekShell) 'HtmxSyncReplace)
         ]
     , Action ToggleRosterWeekLiveStatus
        '[ Field IsLive 'WireBool ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxTarget ('HtmxId RosterContent)
         , 'HtmxSwap 'HtmxOuterHTML
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'HtmxSync ('HtmxSyncOn ('HtmxId RosterWeekShell) 'HtmxSyncReplace)
         ]
     , Action ToggleRosterAssignmentFilters
        '[ Field HideStaffAtIdealShifts 'WireBool
         , Field HideStaffUnavailable 'WireBool
         , Field HideStaffOnApprovedLeave 'WireBool
         , Field HideStaffAlreadyAssignedToday 'WireBool
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'HtmxSync ('HtmxSyncOn ('HtmxId RosterWeekShell) 'HtmxSyncReplace)
         ]
     , Action CopyRosterWeek
        '[]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxTarget ('HtmxId RosterContent)
         , 'HtmxSwap 'HtmxOuterHTML
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'HtmxSync ('HtmxSyncOn ('HtmxId RosterWeekShell) 'HtmxSyncReplace)
         , 'CustomHtmx CopyRosterWeekCustomHtmx "copy previous week requires a destructive overwrite confirmation"
         ]
     , Action CreateRosterSelfServiceLeaveRequest
        '[ Field StartDate 'WireDay
         , Field EndDate 'WireDay
         , Field Reason 'WireText
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxTarget ('HtmxId RosterStaffSelfServiceLeaveFormFragment)
         , 'HtmxSwap 'HtmxOuterHTML
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         ]
     , Action CreateRosterWeekSlotDefinition
        '[]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxTarget ('HtmxId RosterContent)
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'HtmxSync ('HtmxSyncOn ('HtmxId RosterWeekShell) 'HtmxSyncReplace)
         ]
     , Action DeleteRosterWeekSlotDefinition
        '[]
        '[ 'HtmxMethod 'HtmxDelete
         , 'HtmxTarget ('HtmxId RosterContent)
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'HtmxSync ('HtmxSyncOn ('HtmxId RosterWeekShell) 'HtmxSyncReplace)
         ]
     , Action ToggleRosterDayClosed
        '[]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'HtmxSync ('HtmxSyncOn ('HtmxId RosterWeekShell) 'HtmxSyncReplace)
         ]
     , Action AddRosterRow
        '[]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'HtmxSync ('HtmxSyncOn ('HtmxId RosterWeekShell) 'HtmxSyncReplace)
         ]
     , Action RemoveRosterRow
        '[]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         , 'HtmxSync ('HtmxSyncOn ('HtmxId RosterWeekShell) 'HtmxSyncReplace)
         ]
     , Action ToggleRosterStaffScope
        '[ Field StaffScope 'WireText ]
        '[ 'HtmxMethod 'HtmxGet
         , 'HtmxTarget ('HtmxId RosterStaffPanel)
         , 'HtmxSwap 'HtmxOuterHTML
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         ]
     , DomToken RosterContent
     , DomToken RosterWeekShell
     , DomToken RosterDaySection
     , DomToken RosterStaffPanel
     , DomToken RosterStaffSelfServiceLeaveFormFragment
     ]

type RosterInteractionBundle =
    Concat
        '[ LayoutModeInteraction SetRosterLayoutMode RosterContent RosterLayoutMode
         , '[ DragSessionDefinition
            , SourceRef ShiftDragSource
                '[ 'SessionOption DragSession
                 , 'Submits MoveRosterShiftToSlot
                 , 'SourceField SourceItemKey
                 , 'CompatibleDropzone ShiftSlotDropzone
                 , 'CompatibleDropzone DayColumnDropzone
                 , 'CompatibleDropzone DeleteShiftDropzone
                 , 'ModifierVariant Copy DuplicateRosterShiftToDay '[ 'Effect CloneShadowCopy '[ 'Layer DragPreviewLayer ], 'Effect DropzoneHighlight '[] ]
                 ]
            , SourceRef StaffDragSource
                '[ 'SessionOption DragSession
                 , 'Submits DropRosterStaff
                 , 'SourceField SourceItemKey
                 , 'CompatibleDropzone ExistingShiftDropzone
                 , 'CompatibleDropzone StaffCreateDropzone
                 ]
            , DropzoneRef ShiftSlotDropzone '[ 'SessionOption DragSession, 'TargetField TargetDropzoneKey ]
            , DropzoneRef StaffCreateDropzone '[ 'SessionOption DragSession, 'TargetField TargetDropzoneKey ]
            , DropzoneRef DayColumnDropzone '[ 'SessionOption DragSession, 'TargetField TargetDropzoneKey ]
            , DropzoneRef ExistingShiftDropzone '[ 'SessionOption DragSession, 'TargetField TargetDropzoneKey ]
            , DropzoneRef DeleteShiftDropzone '[ 'SessionOption DragSession, 'TargetField TargetDropzoneKey ]
            ]
         , DragDropIntent MoveRosterShiftToSlot RosterContent
         , '[ Action DuplicateRosterShiftToDay DragDropFields '[ 'Target RosterContent ] ]
         , '[ Intent DuplicateRosterShiftToDay DragDropFields '[ 'SessionOption DragSession, 'BackedBy DuplicateRosterShiftToDay ] ]
         , DragDropIntent DropRosterStaff RosterContent
         ]

type RosterSurface =
    Surface Roster (Concat '[ RosterScopeBundle, RosterFragmentBundle, RosterActionBundle, RosterInteractionBundle ])

type RosterDayTimelineScopeBundle =
    '[ Scope RosterDayTimeline
        '[ Field VenueId 'WireUUID
         , Field RosterGroupId 'WireUUID
         , Field WeekOffset 'WireInt
         , Field RosterDayId 'WireUUID
         ]
        '[ 'Authorize 'CurrentVenueRosterGroup '[ VenueId, RosterGroupId ] ]
     ]

type RosterDayTimelineFragmentBundle =
    '[ Fragment RosterDayTimelineContent
        '[ Field RosterDayId 'WireUUID ]
        '[ 'Eager
         , 'Live
         , 'DependsOn RosterDayResource '[ 'FromFragment RosterDayId ]
         , 'DependsOn RosterEndTimesConfigResource '[ 'FromScope VenueId ]
         , 'DependsOn RosterWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         , 'DependsOn TimePickerConfigResource '[ 'FromScope VenueId ]
         ]
     ]

type RosterDayTimelineActionBundle =
    '[ DomToken RosterDayTimelineContent
     ]

type RosterDayTimelineInteractionBundle =
    DragDropInteraction MoveRosterTimelineShift RosterDayTimelineContent

type RosterDayTimelineSurface =
    Surface RosterDayTimeline (Concat '[ RosterDayTimelineScopeBundle, RosterDayTimelineFragmentBundle, RosterDayTimelineActionBundle, RosterDayTimelineInteractionBundle ])
