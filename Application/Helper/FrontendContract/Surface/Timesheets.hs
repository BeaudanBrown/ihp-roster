{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.Timesheets
    ( OperationalDate
    , HideApproved
    , ShowTimesheetSuggestions
    , StaffFilterId
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
    , ToggleTimesheetHideApproved
    , ToggleTimesheetShowSuggestions
    , UpdateTimesheetFilters
    , ApproveTimesheetEntry
    , CreateTimesheetEntryFromSuggestion
    , UnapproveTimesheetEntry
    , TimesheetWeek
    , TimesheetsMountState
    , TimesheetsSurface
    , VenueId
    , AnchorDate
    , WindowStartDate
    , WindowEndDate
    , RosterCalendarRevision
    ) where

import Application.Helper.FrontendContract.Surface.DSL

data Timesheets

data TimesheetWeek
data VenueId
data AnchorDate
data WindowStartDate
data WindowEndDate
data RosterCalendarRevision

data TimesheetsMountState
data HideApproved
data ShowTimesheetSuggestions
data StaffFilterId

data TimesheetToolbar
data TimesheetWeekToolbar
data TimesheetDayColumns
data TimesheetDaySection
data TimesheetSidePanelContent
data OperationalDate

data TimesheetDay
data TimesheetWeekBoundaryConfig

data NavigateTimesheetWeek
data UpdateTimesheetFilters
data ToggleTimesheetHideApproved
data ToggleTimesheetShowSuggestions
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

type TimesheetDayResource = Resource TimesheetDay '[ Field VenueId 'WireUUID, Field OperationalDate 'WireDay ]
type TimesheetWeekResource = Resource TimesheetWeek '[ Field VenueId 'WireUUID, Field WindowStartDate 'WireDay, Field WindowEndDate 'WireDay ]
data TimePickerConfig

type TimesheetWeekBoundaryConfigResource = Resource TimesheetWeekBoundaryConfig '[ Field VenueId 'WireUUID ]
type TimePickerConfigResource = Resource TimePickerConfig '[ Field VenueId 'WireUUID ]

type TimesheetScopeBundle =
    '[ Scope TimesheetWeek
        '[ Field VenueId 'WireUUID
         , Field WindowStartDate 'WireDay
         , Field WindowEndDate 'WireDay
         , Field RosterCalendarRevision 'WireInt
         ]
        '[ 'Authorize 'CurrentVenue '[ VenueId ] ]
     , MountState TimesheetsMountState
        '[ Field StaffFilterId ('WireOptional 'WireUUID) ]
     ]

type TimesheetActionBundle =
    '[ BrowserDomToken TimesheetWeekShell
     , Action NavigateTimesheetWeek
        '[ Field AnchorDate 'WireDay
         , OptionalField StaffFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxGet
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlTrue
         , 'HtmxSync ('HtmxSyncOn ('HtmxClosest ('HtmxId TimesheetWeekShell)) 'HtmxSyncReplace)
         ]
     , Action UpdateTimesheetFilters
        '[ Field AnchorDate 'WireDay
         , OptionalField StaffFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxGet
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlTrue
         , 'HtmxSync ('HtmxSyncOn ('HtmxClosest ('HtmxId TimesheetWeekShell)) 'HtmxSyncReplace)
         ]
     , Action ToggleTimesheetHideApproved
        '[ Field AnchorDate 'WireDay
         , Field RosterCalendarRevision 'WireInt
         , Field HideApproved 'WireBool
         , OptionalField StaffFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         ]
     , Action ToggleTimesheetShowSuggestions
        '[ Field AnchorDate 'WireDay
         , Field RosterCalendarRevision 'WireInt
         , Field ShowTimesheetSuggestions 'WireBool
         , OptionalField StaffFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         ]
     , Action CreateTimesheetEntryFromSuggestion
        '[ Field AnchorDate 'WireDay
         , Field RosterCalendarRevision 'WireInt
         , OptionalField StaffFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         ]
     , Action ApproveTimesheetEntry
        '[ Field AnchorDate 'WireDay
         , Field RosterCalendarRevision 'WireInt
         , OptionalField StaffFilterId 'WireUUID
         ]
        '[ 'HtmxMethod 'HtmxPost
         , 'HtmxSwap 'HtmxNoSwap
         , 'HtmxPushUrl 'HtmxPushUrlFalse
         ]
     , Action UnapproveTimesheetEntry
        '[ Field AnchorDate 'WireDay
         , Field RosterCalendarRevision 'WireInt
         , OptionalField StaffFilterId 'WireUUID
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
         , 'DependsOn TimesheetWeekResource '[ 'FromScope VenueId, 'FromScope WindowStartDate, 'FromScope WindowEndDate ]
         , 'DependsOn TimesheetWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         , 'DependsOn TimePickerConfigResource '[ 'FromScope VenueId ]
         ]
     , Fragment TimesheetDayColumns
        '[]
        '[ 'MountTarget TimesheetDayColumns '[]
         , 'Eager
         , 'Live
         , 'DependsOn TimesheetWeekResource '[ 'FromScope VenueId, 'FromScope WindowStartDate, 'FromScope WindowEndDate ]
         , 'DependsOn TimesheetWeekBoundaryConfigResource '[ 'FromScope VenueId ]
         , 'DependsOn TimePickerConfigResource '[ 'FromScope VenueId ]
         ]
     , Fragment TimesheetSidePanelContent
        '[]
        '[ 'MountTarget TimesheetSidePanelContent '[]
         , 'Eager
         , 'Live
         , 'DependsOn TimesheetWeekResource '[ 'FromScope VenueId, 'FromScope WindowStartDate, 'FromScope WindowEndDate ]
         ]
     , Fragment TimesheetDaySection
        '[ Field OperationalDate 'WireDay ]
        '[ 'MountTarget TimesheetDaySection '[ Field OperationalDate 'WireDay ]
         , 'Lazy '[ 'DependsOnFragment TimesheetDayColumns ]
         , 'Live
         , 'DependsOn TimesheetDayResource '[ 'FromScope VenueId, 'FromFragment OperationalDate ]
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
