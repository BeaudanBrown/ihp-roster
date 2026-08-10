{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.Timesheets
    ( DayOffset
    , ShowApproved
    , ShowTimesheetSuggestions
    , ShowTimesheetWageEstimates
    , StaffFilterId
    , RosterGroupFilterId
    , TimesheetDay
    , TimesheetDayColumns
    , TimesheetDaySection
    , TimesheetSidePanelContent
    , TimesheetWeekBoundaryConfig
    , TimesheetStaffCardsHighlight
    , TimesheetStaffHighlightSourceRole
    , TimesheetStaffHighlightMemberRole
    , TimesheetStaffHighlightPinRole
    , TimesheetStaffPanelSort
    , TimesheetStaffPanelSortRootRole
    , TimesheetStaffPanelSortRowRole
    , TimesheetStaffPanelSortControlRole
    , TimesheetStaffPanelSortRow
    , StaffRowKey
    , StaffName
    , StaffRole
    , EntryCount
    , ApprovedCount
    , NameSortKey
    , RoleSortKey
    , CountSortKey
    , TimesheetSidePanelTabs
    , TimesheetSidePanelTabRole
    , StaffTabKey
    , SettingsTabKey
    , TimesheetSidePanel
    , TimesheetSidePanelRootRole
    , TimesheetSidePanelMainRole
    , TimesheetSidePanelPanelRole
    , TimesheetSidePanelToggleRole
    , TimesheetSidePanelLabelRole
    , TimesheetSidePanelState
    , Collapsed
    , Expanded
    , TimePickerConfig
    , TimesheetWeekShell
    , TimesheetToolbar
    , NavigateTimesheetWeek
    , ToggleTimesheetShowApproved
    , ToggleTimesheetShowSuggestions
    , ToggleTimesheetWageEstimates
    , UpdateTimesheetFilters
    , ApproveTimesheetEntry
    , CreateTimesheetEntryFromSuggestion
    , UnapproveTimesheetEntry
    , TimesheetWeek
    , TimesheetsMountState
    , TimesheetsSurface
    , VenueId
    , WeekOffset
    ) where

import Application.Helper.FrontendContract.Surface.DSL

data Timesheets

data TimesheetWeek
data VenueId
data WeekOffset

data TimesheetsMountState
data ShowApproved
data ShowTimesheetSuggestions
data ShowTimesheetWageEstimates
data StaffFilterId
data RosterGroupFilterId

data TimesheetToolbar
data TimesheetWeekToolbar
data TimesheetDayColumns
data TimesheetDaySection
data TimesheetSidePanelContent
data DayOffset

data TimesheetDay
data TimesheetWeekBoundaryConfig

data NavigateTimesheetWeek
data UpdateTimesheetFilters
data ToggleTimesheetShowApproved
data ToggleTimesheetShowSuggestions
data ToggleTimesheetWageEstimates
data ApproveTimesheetEntry
data CreateTimesheetEntryFromSuggestion
data UnapproveTimesheetEntry
data TimesheetWeekShell

data TimesheetStaffCardsHighlight
data TimesheetStaffHighlightSourceRole
data TimesheetStaffHighlightMemberRole
data TimesheetStaffHighlightPinRole

data TimesheetStaffPanelSort
data TimesheetStaffPanelSortRootRole
data TimesheetStaffPanelSortRowRole
data TimesheetStaffPanelSortControlRole
data TimesheetStaffPanelSortRow
data StaffRowKey
data StaffName
data StaffRole
data EntryCount
data ApprovedCount
data NameSortKey
data RoleSortKey
data CountSortKey

data TimesheetSidePanelTabs
data TimesheetSidePanelTabRole
data StaffTabKey
data SettingsTabKey

data TimesheetSidePanel
data TimesheetSidePanelRootRole
data TimesheetSidePanelMainRole
data TimesheetSidePanelPanelRole
data TimesheetSidePanelToggleRole
data TimesheetSidePanelLabelRole
data TimesheetSidePanelState
data Collapsed
data Expanded

type TimesheetDayResource = Resource TimesheetDay '[ Field VenueId 'WireUUID, Field WeekOffset 'WireInt, Field DayOffset 'WireInt ]
type TimesheetWeekResource = Resource TimesheetWeek '[ Field VenueId 'WireUUID, Field WeekOffset 'WireInt ]
data TimePickerConfig

type TimesheetWeekBoundaryConfigResource = Resource TimesheetWeekBoundaryConfig '[ Field VenueId 'WireUUID ]
type TimePickerConfigResource = Resource TimePickerConfig '[ Field VenueId 'WireUUID ]

type TimesheetScopeBundle =
    '[ Scope TimesheetWeek
        '[ Field VenueId 'WireUUID
         , Field WeekOffset 'WireInt
         ]
        '[ 'Authorize 'CurrentVenue '[ VenueId ] ]
     , MountState TimesheetsMountState
        '[ Field StaffFilterId ('WireOptional 'WireUUID)
         , Field RosterGroupFilterId ('WireOptional 'WireUUID)
         ]
     ]

type TimesheetActionBundle =
    '[ BrowserDomToken TimesheetWeekShell
     , Action NavigateTimesheetWeek
        '[ Field WeekOffset 'WireInt
         , OptionalField StaffFilterId 'WireUUID
         , OptionalField RosterGroupFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxGet
         , 'HtmxTarget ('HtmxId TimesheetWeekShell)
         , 'HtmxSwap 'HtmxOuterHTML
         , 'HtmxPushUrl 'HtmxPushUrlTrue
         , 'HtmxSync ('HtmxSyncOn ('HtmxClosest ('HtmxId TimesheetWeekShell)) 'HtmxSyncReplace)
         ]
     , Action UpdateTimesheetFilters
        '[ Field WeekOffset 'WireInt
         , OptionalField StaffFilterId 'WireUUID
         , OptionalField RosterGroupFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxGet
         , 'HtmxTarget ('HtmxId TimesheetWeekShell)
         , 'HtmxSwap 'HtmxOuterHTML
         , 'HtmxPushUrl 'HtmxPushUrlTrue
         , 'HtmxSync ('HtmxSyncOn ('HtmxClosest ('HtmxId TimesheetWeekShell)) 'HtmxSyncReplace)
         ]
     , Action ToggleTimesheetShowApproved
        '[ Field WeekOffset 'WireInt
         , Field ShowApproved 'WireBool
         , OptionalField StaffFilterId 'WireUUID
         , OptionalField RosterGroupFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         ]
     , Action ToggleTimesheetShowSuggestions
        '[ Field WeekOffset 'WireInt
         , Field ShowTimesheetSuggestions 'WireBool
         , OptionalField StaffFilterId 'WireUUID
         , OptionalField RosterGroupFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         ]
     , Action ToggleTimesheetWageEstimates
        '[ Field WeekOffset 'WireInt
         , Field ShowTimesheetWageEstimates 'WireBool
         , OptionalField StaffFilterId 'WireUUID
         , OptionalField RosterGroupFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         ]
     , Action CreateTimesheetEntryFromSuggestion
        '[ Field WeekOffset 'WireInt
         , OptionalField StaffFilterId 'WireUUID
         , OptionalField RosterGroupFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         ]
     , Action ApproveTimesheetEntry
        '[ Field WeekOffset 'WireInt
         , OptionalField StaffFilterId 'WireUUID
         , OptionalField RosterGroupFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         ]
     , Action UnapproveTimesheetEntry
        '[ Field WeekOffset 'WireInt
         , OptionalField StaffFilterId 'WireUUID
         , OptionalField RosterGroupFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         ]
     ]

type TimesheetFragmentBundle =
    '[ Fragment TimesheetToolbar
        '[]
        '[ 'MountTarget TimesheetWeekToolbar '[]
         , 'Eager
         , 'Live
         , 'DependsOn TimesheetWeekResource '[ 'FromScope VenueId, 'FromScope WeekOffset ]
         , 'DependsOn TimesheetWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         , 'DependsOn TimePickerConfigResource '[ 'FromScope VenueId ]
         ]
     , Fragment TimesheetDayColumns
        '[]
        '[ 'MountTarget TimesheetDayColumns '[]
         , 'Eager
         , 'Live
         , 'DependsOn TimesheetWeekResource '[ 'FromScope VenueId, 'FromScope WeekOffset ]
         , 'DependsOn TimesheetWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         , 'DependsOn TimePickerConfigResource '[ 'FromScope VenueId ]
         ]
     , Fragment TimesheetSidePanelContent
        '[]
        '[ 'MountTarget TimesheetSidePanelContent '[]
         , 'Eager
         , 'Live
         , 'DependsOn TimesheetWeekResource '[ 'FromScope VenueId, 'FromScope WeekOffset ]
         ]
     , Fragment TimesheetDaySection
        '[ Field DayOffset 'WireInt ]
        '[ 'MountTarget TimesheetDaySection '[ Field DayOffset 'WireInt ]
         , 'Lazy '[ 'DependsOnFragment TimesheetDayColumns ]
         , 'Live
         , 'DependsOn TimesheetDayResource '[ 'FromScope VenueId, 'FromScope WeekOffset, 'FromFragment DayOffset ]
         , 'DependsOn TimesheetWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         , 'DependsOn TimePickerConfigResource '[ 'FromScope VenueId ]
         ]
     ]

type TimesheetSidePanelBrowserBundle =
    '[ BrowserInboundDto TimesheetStaffPanelSortRow
        '[ Field StaffRowKey 'WireText
         , Field StaffName 'WireText
         , Field StaffRole 'WireText
         , Field EntryCount 'WireInt
         , Field ApprovedCount 'WireInt
         ]
     , BrowserRole TimesheetStaffPanelSortRootRole
     , BrowserRole TimesheetStaffPanelSortRowRole
     , BrowserRole TimesheetStaffPanelSortControlRole
     , CompleteSetSort TimesheetStaffPanelSort TimesheetStaffPanelSortRootRole TimesheetStaffPanelSortRowRole TimesheetStaffPanelSortControlRole TimesheetStaffPanelSortRow
        '[ SortKey NameSortKey
            '[ SortComparator StaffName 'SortText 'FollowSortDirection
             , SortComparator StaffRowKey 'SortOpaque 'AlwaysAscending
             ]
         , SortKey RoleSortKey
            '[ SortComparator StaffRole 'SortText 'FollowSortDirection
             , SortComparator StaffName 'SortText 'AlwaysAscending
             , SortComparator StaffRowKey 'SortOpaque 'AlwaysAscending
             ]
         , SortKey CountSortKey
            '[ SortComparator EntryCount 'SortInteger 'FollowSortDirection
             , SortComparator ApprovedCount 'SortInteger 'FollowSortDirection
             , SortComparator StaffName 'SortText 'AlwaysAscending
             , SortComparator StaffRowKey 'SortOpaque 'AlwaysAscending
             ]
         ]
        NameSortKey
        'SortAscending
     , BrowserRole TimesheetSidePanelTabRole
     , TabSet TimesheetSidePanelTabs TimesheetSidePanelTabRole '[ StaffTabKey, SettingsTabKey ] StaffTabKey
     , BrowserRole TimesheetSidePanelRootRole
     , BrowserRole TimesheetSidePanelMainRole
     , BrowserRole TimesheetSidePanelPanelRole
     , BrowserRole TimesheetSidePanelToggleRole
     , BrowserRole TimesheetSidePanelLabelRole
     , BrowserClosedState TimesheetSidePanelState '[ Collapsed, Expanded ]
     , SidePanel TimesheetSidePanel TimesheetSidePanelRootRole TimesheetSidePanelMainRole TimesheetSidePanelPanelRole TimesheetSidePanelToggleRole TimesheetSidePanelLabelRole TimesheetSidePanelState Collapsed Expanded
     , BrowserRole TimesheetStaffHighlightSourceRole
     , BrowserRole TimesheetStaffHighlightMemberRole
     , BrowserRole TimesheetStaffHighlightPinRole
     , LinkedHighlight TimesheetStaffCardsHighlight TimesheetStaffHighlightSourceRole TimesheetStaffHighlightMemberRole
        '[ 'ActivateOnHover
         , 'ActivateOnFocus
         , 'ActivateOnKeyboard
         , 'ActivateWithPin TimesheetStaffHighlightPinRole
         ]
        '[ 'HighlightMatchingSource
         , 'HighlightMatchingMember
         ]
     ]

type TimesheetsSurface =
    Surface Timesheets (Concat '[ TimesheetScopeBundle, TimesheetFragmentBundle, TimesheetActionBundle, TimesheetSidePanelBrowserBundle ])
