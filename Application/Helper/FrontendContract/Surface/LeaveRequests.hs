{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.LeaveRequests
    ( LeaveRequestsContent
    , UnavailabilityBlackouts
    , UnavailabilityBlackoutsResource
    , LeaveAvailabilityWarnings
    , LeaveAvailabilityWarningsResource
    , LeaveSection
    , LeaveSectionValue (..)
    , LeaveSectionCount
    , LeaveSectionList
    , LeaveTargetSuffix
    , LeaveRequestsSection
    , LeaveRequestsSectionResource
    , LeaveRequestsSurface
    , LeaveRequestsScope
    , LeaveSidePanelContent
    , LeaveStaffPeriodsHighlight
    , LeaveStaffHighlightSourceRole
    , LeaveStaffHighlightMemberRole
    , LeaveStaffHighlightPinRole
    , LeaveStaffPanelSort
    , LeaveStaffPanelSortRootRole
    , LeaveStaffPanelSortRowRole
    , LeaveStaffPanelSortControlRole
    , LeaveStaffPanelSortRow
    , StaffRowKey
    , StaffName
    , StaffRole
    , PeriodCount
    , PendingCount
    , NameSortKey
    , RoleSortKey
    , CountSortKey
    , LeaveSidePanelTabs
    , LeaveSidePanelTabRole
    , StaffTabKey
    , SettingsTabKey
    , LeaveSidePanel
    , LeaveSidePanelRootRole
    , LeaveSidePanelMainRole
    , LeaveSidePanelPanelRole
    , LeaveSidePanelToggleRole
    , LeaveSidePanelLabelRole
    , LeaveSidePanelState
    , Collapsed
    , Expanded
    , ArchiveLeaveRequestsPage
    , ArchivePage
    , ApproveLeaveRequest
    , DenyLeaveRequest
    , CreateUnavailabilityBlackout
    , UpdateUnavailabilityBlackout
    , DeleteUnavailabilityBlackout
    , StartDate
    , EndDate
    , Reason
    , VenueId
    ) where

import Application.Helper.FrontendContract.Surface.DSL hiding (Enum)
import IHP.ModelSupport (InputValue (..))
import IHP.Prelude

data LeaveSectionValue
    = LeavePendingSection
    | LeaveApprovedSection
    | LeaveDeniedSection
    | LeaveArchiveSection
    deriving (Eq, Show, Enum, Bounded)

instance InputValue LeaveSectionValue where
    inputValue LeavePendingSection  = "pending"
    inputValue LeaveApprovedSection = "approved"
    inputValue LeaveDeniedSection   = "denied"
    inputValue LeaveArchiveSection  = "archive"

data LeaveRequests

data LeaveRequestsScope
data VenueId

data LeaveRequestsContent
data LeaveSidePanelContent
data UnavailabilityBlackouts
data LeaveAvailabilityWarnings
data LeaveSection
data LeaveSectionCount
data LeaveSectionList
data Leave
data LeaveTargetSuffix
data ArchiveLeaveRequestsPage
data ApproveLeaveRequest
data DenyLeaveRequest
data CreateUnavailabilityBlackout
data UpdateUnavailabilityBlackout
data DeleteUnavailabilityBlackout
data StartDate
data EndDate
data Reason
data ArchivePage
data None
data LeaveArchivePageContent

data LeaveStaffPeriodsHighlight
data LeaveStaffHighlightSourceRole
data LeaveStaffHighlightMemberRole
data LeaveStaffHighlightPinRole

data LeaveStaffPanelSort
data LeaveStaffPanelSortRootRole
data LeaveStaffPanelSortRowRole
data LeaveStaffPanelSortControlRole
data LeaveStaffPanelSortRow
data StaffRowKey
data StaffName
data StaffRole
data PeriodCount
data PendingCount
data NameSortKey
data RoleSortKey
data CountSortKey

data LeaveSidePanelTabs
data LeaveSidePanelTabRole
data StaffTabKey
data SettingsTabKey

data LeaveSidePanel
data LeaveSidePanelRootRole
data LeaveSidePanelMainRole
data LeaveSidePanelPanelRole
data LeaveSidePanelToggleRole
data LeaveSidePanelLabelRole
data LeaveSidePanelState
data Collapsed
data Expanded

type UnavailabilityBlackoutsResource = Resource UnavailabilityBlackouts '[ Field VenueId 'WireUUID ]
type LeaveAvailabilityWarningsResource = Resource LeaveAvailabilityWarnings '[ Field VenueId 'WireUUID ]
type LeaveRequestsSectionResource = Resource LeaveRequestsSection '[ Field VenueId 'WireUUID, Field LeaveSection ('WireClosed LeaveSectionValue) ]
data LeaveRequestsSection

type LeaveRequestsSurface =
    Surface LeaveRequests
        '[ Scope LeaveRequestsScope
            '[ Field VenueId 'WireUUID
             ]
            '[ 'Authorize 'CurrentVenueManager '[ VenueId ] ]
         , Fragment UnavailabilityBlackouts
            '[]
            '[ 'MountTarget UnavailabilityBlackouts '[]
             , 'Eager
             , 'Live
             , 'DependsOn UnavailabilityBlackoutsResource '[ 'FromScope VenueId ]
             ]
         , Fragment LeaveSidePanelContent
            '[]
            '[ 'MountTarget LeaveSidePanelContent '[]
             , 'Eager
             , 'Live
             , 'Contains UnavailabilityBlackouts
             , 'DependsOn LeaveAvailabilityWarningsResource '[ 'FromScope VenueId ]
             ]
         , Fragment LeaveAvailabilityWarnings
            '[]
            '[ 'MountTarget LeaveAvailabilityWarnings '[]
             , 'Eager
             , 'Live
             , 'DependsOn LeaveAvailabilityWarningsResource '[ 'FromScope VenueId ]
             ]
         , Fragment LeaveSectionCount
            '[ Field LeaveSection ('WireClosed LeaveSectionValue) ]
            '[ 'MountTarget Leave '[ Field LeaveSection ('WireClosed LeaveSectionValue), Field LeaveTargetSuffix 'WireText ]
             , 'Eager
             , 'Live
             , 'DependsOn LeaveRequestsSectionResource '[ 'FromScope VenueId, 'FromFragment LeaveSection ]
             ]
         , Fragment LeaveSectionList
            '[ Field LeaveSection ('WireClosed LeaveSectionValue) ]
            '[ 'MountTarget Leave '[ Field LeaveSection ('WireClosed LeaveSectionValue), Field LeaveTargetSuffix 'WireText ]
             , 'Eager
             , 'Live
             , 'DependsOn LeaveRequestsSectionResource '[ 'FromScope VenueId, 'FromFragment LeaveSection ]
             ]
         , Action ArchiveLeaveRequestsPage
            '[ Field ArchivePage 'WireInt ]
            '[ 'HtmxMethod 'HtmxGet
             , 'HtmxTarget ('HtmxId LeaveArchivePageContent)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlTrue
             ]
         , Action ApproveLeaveRequest
            '[]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId LeaveRequestsContent)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , Action DenyLeaveRequest
            '[]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId LeaveRequestsContent)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , Action CreateUnavailabilityBlackout
            '[ Field StartDate 'WireDay, Field EndDate 'WireDay, Field Reason 'WireText ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId UnavailabilityBlackouts)
             , 'HtmxSwap 'HtmxOuterHTML
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , Action UpdateUnavailabilityBlackout
            '[ Field StartDate 'WireDay, Field EndDate 'WireDay, Field Reason 'WireText ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId UnavailabilityBlackouts)
             , 'HtmxSwap 'HtmxOuterHTML
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , Action DeleteUnavailabilityBlackout
            '[]
            '[ 'HtmxMethod 'HtmxDelete
             , 'HtmxTarget ('HtmxId UnavailabilityBlackouts)
             , 'HtmxSwap 'HtmxNoSwap
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , BrowserInboundDto LeaveStaffPanelSortRow
            '[ Field StaffRowKey 'WireText
             , Field StaffName 'WireText
             , Field StaffRole 'WireText
             , Field PeriodCount 'WireInt
             , Field PendingCount 'WireInt
             ]
         , BrowserRole LeaveStaffPanelSortRootRole
         , BrowserRole LeaveStaffPanelSortRowRole
         , BrowserRole LeaveStaffPanelSortControlRole
         , CompleteSetSort LeaveStaffPanelSort LeaveStaffPanelSortRootRole LeaveStaffPanelSortRowRole LeaveStaffPanelSortControlRole LeaveStaffPanelSortRow
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
                '[ SortComparator PeriodCount 'SortInteger 'FollowSortDirection
                 , SortComparator PendingCount 'SortInteger 'FollowSortDirection
                 , SortComparator StaffName 'SortText 'AlwaysAscending
                 , SortComparator StaffRowKey 'SortOpaque 'AlwaysAscending
                 ]
             ]
            NameSortKey
            'SortAscending
         , BrowserRole LeaveSidePanelTabRole
         , TabSet LeaveSidePanelTabs LeaveSidePanelTabRole '[ StaffTabKey, SettingsTabKey ] StaffTabKey
         , BrowserRole LeaveSidePanelRootRole
         , BrowserRole LeaveSidePanelMainRole
         , BrowserRole LeaveSidePanelPanelRole
         , BrowserRole LeaveSidePanelToggleRole
         , BrowserRole LeaveSidePanelLabelRole
         , BrowserClosedState LeaveSidePanelState '[ Collapsed, Expanded ]
         , SidePanel LeaveSidePanel LeaveSidePanelRootRole LeaveSidePanelMainRole LeaveSidePanelPanelRole LeaveSidePanelToggleRole LeaveSidePanelLabelRole LeaveSidePanelState Collapsed Expanded
         , BrowserRole LeaveStaffHighlightSourceRole
         , BrowserRole LeaveStaffHighlightMemberRole
         , BrowserRole LeaveStaffHighlightPinRole
         , LinkedHighlight LeaveStaffPeriodsHighlight LeaveStaffHighlightSourceRole LeaveStaffHighlightMemberRole
            '[ 'ActivateOnHover
             , 'ActivateOnFocus
             , 'ActivateOnKeyboard
             , 'ActivateWithPin LeaveStaffHighlightPinRole
             ]
            '[ 'HighlightMatchingSource
             , 'HighlightMatchingMember
             ]
         , DomToken LeaveRequestsContent
         , DomToken LeaveArchivePageContent
         ]
