{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.Roster
    ( RosterContent
    , RosterLayout
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
    , RosterWeekStructure
    , RosterSlotsStructure
    , RosterSlotsContent
    , RosterWeekBoundaryConfig
    , TimePickerConfig
    , RosterWeekOverview
    , MoveRosterShiftToSlot
    , ShiftDragSource
    , StaffDragSource
    , ShiftSlotDropzone
    , StaffCreateDropzone
    , DayColumnDropzone
    , ExistingShiftDropzone
    , DeleteShiftDropzone
    , StaffShiftsHighlight
    , StaffHighlightSourceRole
    , StaffHighlightMemberRole
    , StaffHighlightPinRole
    , StaffHighlightOrderState
    , RosterStaffPanelSort
    , StaffPanelSortRootRole
    , StaffPanelSortRowRole
    , StaffPanelSortControlRole
    , RosterStaffPanelSortRow
    , StaffRowKey
    , StaffName
    , StaffRole
    , AssignedShifts
    , IdealShifts
    , NameSortKey
    , RoleSortKey
    , ShiftsSortKey
    , RosterStaffPanelTabs
    , StaffPanelTabRole
    , StaffTabKey
    , SettingsTabKey
    , FullscreenRootRole
    , FullscreenToggleRole
    , FullscreenLabelRole
    , FullscreenState
    , Collapsed
    , Expanded
    , ColumnEditorRole
    , ColumnEditStartRole
    , ColumnEditDoneRole
    , ColumnEditingState
    , Inactive
    , Active
    , ImageExportTriggerRole
    , ImageExportConfigRole
    , ImageExportProjectionRole
    , ImageExportRowRole
    , ImageExportCellRole
    , ImageExportFormat
    , Jpg
    , RosterImageExportConfig
    , RosterImageExportCell
    , ImageExportFilename
    , ImageExportMimeType
    , ImageExportQualityPercent
    , ImageExportPixelRatio
    , ImageExportMinimumWidth
    , ImageExportMaximumWidth
    , ImageExportIdleLabel
    , ImageExportPreparingLabel
    , ImageExportDownloadedLabel
    , ImageExportFailedLabel
    , ImageExportFailureMessage
    , ImageExportMissingProjectionMessage
    , ImageExportCloneFailureMessage
    , ImageExportRenderFailureMessage
    , ImageExportCanvasFailureMessage
    , ImageExportEncodingFailureMessage
    , ImageExportText
    , WeekOverviewPanelRole
    , WeekOverviewDayRole
    , WeekOverviewTodayRole
    , WeekOverviewDetailsRole
    , WeekOverviewSelectedLabelRole
    , WeekOverviewLeaveValueRole
    , WeekOverviewAssignedValueRole
    , WeekOverviewHoursValueRole
    , WeekOverviewSummaryRole
    , WeekOverviewWeekLabelRole
    , WeekOverviewGoLinkRole
    , WeekOverviewAvailability
    , Loaded
    , Unloaded
    , WeekOverviewClosure
    , Open
    , Closed
    , WeekOverviewCalendarDay
    , Today
    , OtherDay
    , RosterWeekOverviewPanelConfig
    , RosterWeekOverviewDayConfig
    , WeekOverviewCurrentDate
    , WeekOverviewDate
    , WeekOverviewSelectedLabel
    , WeekOverviewLeaveDisplay
    , WeekOverviewAssignedDisplay
    , WeekOverviewHoursDisplay
    , WeekOverviewSummaryText
    , WeekOverviewWeekLabel
    , WeekOverviewNavigationUrl
    , WeekOverviewAvailabilityField
    , WeekOverviewClosureField
    , ShiftGroupHighlight
    , ShiftGroupHighlightSourceRole
    , ShiftGroupHighlightMemberRole
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
    , ShowRosterWarnings
    , IsLive
    , ShowWageEstimates
    , HideStaffAtIdealShifts
    , HideStaffUnavailable
    , HideStaffOnApprovedLeave
    , HideStaffAlreadyAssignedToday
    , StaffScope
    ) where

import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Interaction
import qualified Application.Helper.FrontendContract.Surface.SelfServiceLeave as SelfServiceLeave

data Roster
data RosterDayTimeline

data RosterWeek
data RosterWeekStructure
data RosterSlotsStructure
data RosterSlotsContent
data VenueId
data RosterGroupId
data WeekOffset

data RosterLayout
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

data StaffShiftsHighlight
data StaffHighlightSourceRole
data StaffHighlightMemberRole
data StaffHighlightPinRole
data StaffHighlightOrderState

data RosterStaffPanelSort
data StaffPanelSortRootRole
data StaffPanelSortRowRole
data StaffPanelSortControlRole
data RosterStaffPanelSortRow
data StaffRowKey
data StaffName
data StaffRole
data AssignedShifts
data IdealShifts
data NameSortKey
data RoleSortKey
data ShiftsSortKey

data RosterStaffPanelTabs
data StaffPanelTabRole
data StaffTabKey
data SettingsTabKey

data FullscreenRootRole
data FullscreenToggleRole
data FullscreenLabelRole
data FullscreenState
data Collapsed
data Expanded

data ColumnEditorRole
data ColumnEditStartRole
data ColumnEditDoneRole
data ColumnEditingState
data Inactive
data Active

data ImageExportTriggerRole
data ImageExportConfigRole
data ImageExportProjectionRole
data ImageExportRowRole
data ImageExportCellRole
data ImageExportFormat
data Jpg
data RosterImageExportConfig
data RosterImageExportCell
data ImageExportFilename
data ImageExportMimeType
data ImageExportQualityPercent
data ImageExportPixelRatio
data ImageExportMinimumWidth
data ImageExportMaximumWidth
data ImageExportIdleLabel
data ImageExportPreparingLabel
data ImageExportDownloadedLabel
data ImageExportFailedLabel
data ImageExportFailureMessage
data ImageExportMissingProjectionMessage
data ImageExportCloneFailureMessage
data ImageExportRenderFailureMessage
data ImageExportCanvasFailureMessage
data ImageExportEncodingFailureMessage
data ImageExportText

data WeekOverviewPanelRole
data WeekOverviewDayRole
data WeekOverviewTodayRole
data WeekOverviewDetailsRole
data WeekOverviewSelectedLabelRole
data WeekOverviewLeaveValueRole
data WeekOverviewAssignedValueRole
data WeekOverviewHoursValueRole
data WeekOverviewSummaryRole
data WeekOverviewWeekLabelRole
data WeekOverviewGoLinkRole
data WeekOverviewAvailability
data Loaded
data Unloaded
data WeekOverviewClosure
data Open
data Closed
data WeekOverviewCalendarDay
data Today
data OtherDay
data RosterWeekOverviewPanelConfig
data RosterWeekOverviewDayConfig
data WeekOverviewCurrentDate
data WeekOverviewDate
data WeekOverviewSelectedLabel
data WeekOverviewLeaveDisplay
data WeekOverviewAssignedDisplay
data WeekOverviewHoursDisplay
data WeekOverviewSummaryText
data WeekOverviewWeekLabel
data WeekOverviewNavigationUrl
data WeekOverviewAvailabilityField
data WeekOverviewClosureField

data ShiftGroupHighlight
data ShiftGroupHighlightSourceRole
data ShiftGroupHighlightMemberRole

data NavigateRosterWeek
data ToggleRosterWarnings
data ToggleRosterWageEstimates
data SortRosterWeek
data ToggleRosterWeekLiveStatus
data ToggleRosterAssignmentFilters
data CopyRosterWeek
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
data RosterStaffPanelFragment
data RosterWeekOverviewMount

type RosterWeekResource = Resource RosterWeek '[ Field RosterGroupId 'WireUUID, Field WeekOffset 'WireInt ]
type RosterWeekStructureResource = Resource RosterWeekStructure '[ Field RosterGroupId 'WireUUID, Field WeekOffset 'WireInt ]
type RosterSlotsStructureResource = Resource RosterSlotsStructure '[ Field RosterGroupId 'WireUUID, Field WeekOffset 'WireInt ]
type RosterSlotsContentResource = Resource RosterSlotsContent '[ Field RosterGroupId 'WireUUID, Field WeekOffset 'WireInt ]
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
    '[ Fragment RosterLayout
        '[]
        '[ 'MountTarget RosterLayout '[]
         , 'Eager
         , 'Contains RosterContent
         , 'Contains RosterStaffPanel
         , ContainsSurface SelfServiceLeave.SelfServiceLeave
         ]
     , Fragment RosterContent
        '[]
        '[ 'MountTarget RosterContent '[]
         , 'Eager
         , 'Live
         , 'DependsOn RosterWeekStructureResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ]
         , 'Contains RosterGridToolbar
         , 'Contains RosterGridFrame
         ]
     , Fragment RosterGridToolbar
        '[]
        '[ 'MountTarget RosterGridToolbar '[]
         , 'Eager
         , 'Live
         , 'DependsOn RosterWeekResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ]
         , 'DependsOn RosterEndTimesConfigResource '[ 'FromScope VenueId ]
         , 'DependsOn RosterWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         ]
     , Fragment RosterGridFrame
        '[]
        '[ 'MountTarget RosterGridFrame '[]
         , 'Eager
         , 'Live
         , 'DependsOn RosterWeekStructureResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ]
         , 'DependsOn RosterEndTimesConfigResource '[ 'FromScope VenueId ]
         , 'DependsOn RosterWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         , 'Contains RosterDayColumns
         , 'Contains RosterDayRail
         , 'Contains RosterWageRail
         , 'Contains RosterSlotsGrid
         , 'Contains RosterDaySection
         ]
     , Fragment RosterDayColumns '[] '[ 'MountTarget RosterDayColumns '[], 'Eager, 'Live, 'DependsOn RosterWeekResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ], 'DependsOn RosterEndTimesConfigResource '[ 'FromScope VenueId ], 'DependsOn RosterWeekBoundaryConfigResource '[ 'FromScope VenueId ] ]
     , Fragment RosterDayRail '[] '[ 'MountTarget RosterDayRail '[], 'Eager, 'Live, 'DependsOn RosterWeekResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ], 'DependsOn RosterEndTimesConfigResource '[ 'FromScope VenueId ], 'DependsOn RosterWeekBoundaryConfigResource '[ 'FromScope VenueId ] ]
     , Fragment RosterWageRail '[] '[ 'MountTarget RosterWageRail '[], 'Eager, 'Live, 'DependsOn RosterWeekResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ], 'DependsOn RosterEndTimesConfigResource '[ 'FromScope VenueId ], 'DependsOn RosterWeekBoundaryConfigResource '[ 'FromScope VenueId ] ]
     , Fragment RosterSlotsGrid '[] '[ 'MountTarget RosterSlotsGrid '[], 'Eager, 'Live, 'DependsOn RosterSlotsStructureResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ], 'DependsOn RosterSlotsContentResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ], 'DependsOn RosterEndTimesConfigResource '[ 'FromScope VenueId ], 'DependsOn RosterWeekBoundaryConfigResource '[ 'FromScope VenueId ] ]
     , Fragment RosterStaffPanel '[] '[ 'MountTarget RosterStaffPanelFragment '[], 'Lazy '[ 'DependsOnFragment RosterContent ], 'Live, 'DependsOn RosterWeekResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ] ]
     , Fragment RosterWeekOverview '[] '[ 'MountTarget RosterWeekOverviewMount '[ Field RosterGroupId 'WireUUID, Field WeekOffset 'WireInt ], 'Lazy '[ 'DependsOnFragment RosterContent ], 'DependsOn RosterWeekResource '[ 'FromScope RosterGroupId, 'FromScope WeekOffset ] ]
     , Fragment RosterDaySection
        '[ Field RosterDayId 'WireUUID ]
        '[ 'MountTarget RosterDaySection '[ Field RosterDayId 'WireUUID ]
         , 'Lazy '[ 'DependsOnFragment RosterGridFrame, 'Contains RosterRow ]
         , 'Live
         , 'DependsOn RosterDayResource '[ 'FromFragment RosterDayId ]
         , 'DependsOn RosterEndTimesConfigResource '[ 'FromScope VenueId ]
         , 'DependsOn RosterWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         ]
     , Fragment RosterRow
        '[ Field RosterDayId 'WireUUID
         , Field RowIndex 'WireInt
         ]
        '[ 'MountTarget RosterRow '[ Field RosterDayId 'WireUUID, Field RowIndex 'WireInt ]
         , 'Lazy '[ 'DependsOnFragment RosterDaySection ]
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
         , 'HtmxSwap 'HtmxOuterHTML
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
         , 'HtmxTarget ('HtmxId RosterStaffPanelFragment)
         , 'HtmxSwap 'HtmxOuterHTML
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         ]
     , DomToken RosterContent
     , DomToken RosterWeekShell
     , DomToken RosterDaySection
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
                 , 'ModifierVariant Copy DuplicateRosterShiftToDay '[ CloneShadowCopy DragPreviewLayer, DropzoneHighlight ]
                 ]
            , SourceRef StaffDragSource
                '[ 'SessionOption DragSession
                 , 'Submits DropRosterStaff
                 , 'SourceField SourceItemKey
                 , 'CompatibleDropzone ExistingShiftDropzone
                 , 'CompatibleDropzone ShiftSlotDropzone
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

type RosterStaffPanelBrowserBundle =
    '[ BrowserInboundDto RosterStaffPanelSortRow
        '[ Field StaffRowKey 'WireText
         , Field StaffName 'WireText
         , Field StaffRole 'WireText
         , Field AssignedShifts 'WireInt
         , Field IdealShifts 'WireInt
         ]
     , BrowserRole StaffPanelSortRootRole
     , BrowserRole StaffPanelSortRowRole
     , BrowserRole StaffPanelSortControlRole
     , CompleteSetSort RosterStaffPanelSort StaffPanelSortRootRole StaffPanelSortRowRole StaffPanelSortControlRole RosterStaffPanelSortRow
        '[ SortKey NameSortKey
            '[ SortComparator StaffName 'SortText 'FollowSortDirection
             , SortComparator StaffRowKey 'SortOpaque 'AlwaysAscending
             ]
         , SortKey RoleSortKey
            '[ SortComparator StaffRole 'SortText 'FollowSortDirection
             , SortComparator StaffName 'SortText 'AlwaysAscending
             , SortComparator StaffRowKey 'SortOpaque 'AlwaysAscending
             ]
         , SortKey ShiftsSortKey
            '[ SortComparator AssignedShifts 'SortInteger 'FollowSortDirection
             , SortComparator IdealShifts 'SortInteger 'FollowSortDirection
             , SortComparator StaffName 'SortText 'AlwaysAscending
             , SortComparator StaffRowKey 'SortOpaque 'AlwaysAscending
             ]
         ]
        NameSortKey
        'SortAscending
     , BrowserRole StaffPanelTabRole
     , TabSet RosterStaffPanelTabs StaffPanelTabRole '[ StaffTabKey, SettingsTabKey ] StaffTabKey
     ]

type RosterChromeBrowserBundle =
    '[ BrowserRole FullscreenRootRole
     , BrowserRole FullscreenToggleRole
     , BrowserRole FullscreenLabelRole
     , BrowserClosedState FullscreenState '[ Collapsed, Expanded ]
     , BrowserRole ColumnEditorRole
     , BrowserRole ColumnEditStartRole
     , BrowserRole ColumnEditDoneRole
     , BrowserClosedState ColumnEditingState '[ Inactive, Active ]
     ]

type RosterImageExportBrowserBundle =
    '[ BrowserRole ImageExportTriggerRole
     , BrowserRole ImageExportConfigRole
     , BrowserRole ImageExportProjectionRole
     , BrowserRole ImageExportRowRole
     , BrowserRole ImageExportCellRole
     , BrowserClosedState ImageExportFormat '[ Jpg ]
     , BrowserInboundDto RosterImageExportConfig
        '[ Field ImageExportFilename 'WireText
         , Field ImageExportMimeType 'WireText
         , Field ImageExportQualityPercent 'WireInt
         , Field ImageExportPixelRatio 'WireInt
         , Field ImageExportMinimumWidth 'WireInt
         , Field ImageExportMaximumWidth 'WireInt
         , Field ImageExportIdleLabel 'WireText
         , Field ImageExportPreparingLabel 'WireText
         , Field ImageExportDownloadedLabel 'WireText
         , Field ImageExportFailedLabel 'WireText
         , Field ImageExportFailureMessage 'WireText
         , Field ImageExportMissingProjectionMessage 'WireText
         , Field ImageExportCloneFailureMessage 'WireText
         , Field ImageExportRenderFailureMessage 'WireText
         , Field ImageExportCanvasFailureMessage 'WireText
         , Field ImageExportEncodingFailureMessage 'WireText
         ]
     , BrowserInboundDto RosterImageExportCell
        '[ Field ImageExportText 'WireText ]
     ]

type RosterWeekOverviewBrowserBundle =
    '[ BrowserRole WeekOverviewPanelRole
     , BrowserRole WeekOverviewDayRole
     , BrowserRole WeekOverviewTodayRole
     , BrowserRole WeekOverviewDetailsRole
     , BrowserRole WeekOverviewSelectedLabelRole
     , BrowserRole WeekOverviewLeaveValueRole
     , BrowserRole WeekOverviewAssignedValueRole
     , BrowserRole WeekOverviewHoursValueRole
     , BrowserRole WeekOverviewSummaryRole
     , BrowserRole WeekOverviewWeekLabelRole
     , BrowserRole WeekOverviewGoLinkRole
     , BrowserClosedState WeekOverviewAvailability '[ Loaded, Unloaded ]
     , BrowserClosedState WeekOverviewClosure '[ Open, Closed ]
     , BrowserClosedState WeekOverviewCalendarDay '[ Today, OtherDay ]
     , BrowserInboundDto RosterWeekOverviewPanelConfig
        '[ Field WeekOverviewCurrentDate 'WireDay ]
     , BrowserInboundDto RosterWeekOverviewDayConfig
        '[ Field WeekOverviewDate 'WireDay
         , Field WeekOverviewSelectedLabel 'WireText
         , Field WeekOverviewLeaveDisplay 'WireText
         , Field WeekOverviewAssignedDisplay 'WireText
         , Field WeekOverviewHoursDisplay 'WireText
         , Field WeekOverviewSummaryText 'WireText
         , Field WeekOverviewWeekLabel 'WireText
         , Field WeekOverviewNavigationUrl 'WireText
         , Field WeekOverviewAvailabilityField 'WireText
         , Field WeekOverviewClosureField 'WireText
         ]
     ]

type RosterLinkedHighlightBundle =
    '[ BrowserRole StaffHighlightSourceRole
     , BrowserRole StaffHighlightMemberRole
     , BrowserRole StaffHighlightPinRole
     , BrowserState StaffHighlightOrderState
     , LinkedHighlight StaffShiftsHighlight StaffHighlightSourceRole StaffHighlightMemberRole
        '[ 'ActivateOnHover
         , 'ActivateOnFocus
         , 'ActivateOnKeyboard
         , 'ActivateWithPin StaffHighlightPinRole
         ]
        '[ 'HighlightMatchingSource
         , 'HighlightMatchingMember
         , 'HighlightOrderedMemberBounds StaffHighlightOrderState
         ]
     , BrowserRole ShiftGroupHighlightSourceRole
     , BrowserRole ShiftGroupHighlightMemberRole
     , LinkedHighlight ShiftGroupHighlight ShiftGroupHighlightSourceRole ShiftGroupHighlightMemberRole
        '[ 'ActivateOnHover
         , 'ActivateOnFocus
         , 'ActivateOnKeyboard
         ]
        '[ 'HighlightMatchingMember ]
     ]

type RosterSurface =
    Surface Roster (Concat '[ RosterScopeBundle, RosterFragmentBundle, RosterActionBundle, RosterInteractionBundle, RosterStaffPanelBrowserBundle, RosterChromeBrowserBundle, RosterImageExportBrowserBundle, RosterWeekOverviewBrowserBundle, RosterLinkedHighlightBundle ])

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
        '[ 'MountTarget RosterDayTimelineContent '[ Field RosterDayId 'WireUUID ]
         , 'Eager
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

type RosterDayTimelineLinkedHighlightBundle =
    '[ BrowserRole ShiftGroupHighlightSourceRole
     , BrowserRole ShiftGroupHighlightMemberRole
     , LinkedHighlight ShiftGroupHighlight ShiftGroupHighlightSourceRole ShiftGroupHighlightMemberRole
        '[ 'ActivateOnHover
         , 'ActivateOnFocus
         , 'ActivateOnKeyboard
         ]
        '[ 'HighlightMatchingMember ]
     ]

type RosterDayTimelineSurface =
    Surface RosterDayTimeline (Concat '[ RosterDayTimelineScopeBundle, RosterDayTimelineFragmentBundle, RosterDayTimelineActionBundle, RosterDayTimelineInteractionBundle, RosterDayTimelineLinkedHighlightBundle ])
