{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.LeaveRequests
    ( LeaveRequestsContent
    , LeaveAvailabilityWarnings
    , LeaveAvailabilityWarningsResource
    , LeaveSection
    , LeaveSectionCount
    , LeaveSectionList
    , LeaveTargetSuffix
    , LeaveRequestsSection
    , LeaveRequestsSectionResource
    , LeaveRequestsSurface
    , LeaveRequestsScope
    , ArchiveLeaveRequestsPage
    , ArchivePage
    , ApproveLeaveRequest
    , DenyLeaveRequest
    , VenueId
    ) where

import Application.Helper.FrontendContract.Surface.DSL

data LeaveRequests

data LeaveRequestsScope
data VenueId

data LeaveRequestsContent
data LeaveAvailabilityWarnings
data LeaveSection
data LeaveSectionCount
data LeaveSectionList
data Leave
data LeaveTargetSuffix
data ArchiveLeaveRequestsPage
data ApproveLeaveRequest
data DenyLeaveRequest
data ArchivePage
data None
data LeaveArchivePageContent

type LeaveAvailabilityWarningsResource = Resource LeaveAvailabilityWarnings '[ Field VenueId 'WireUUID ]
type LeaveRequestsSectionResource = Resource LeaveRequestsSection '[ Field VenueId 'WireUUID, Field LeaveSection 'WireText ]
data LeaveRequestsSection

type LeaveRequestsSurface =
    Surface LeaveRequests
        '[ Scope LeaveRequestsScope
            '[ Field VenueId 'WireUUID
             ]
            '[ 'Authorize 'CurrentVenueManager '[ VenueId ] ]
         , Fragment LeaveAvailabilityWarnings
            '[]
            '[ 'MountTarget LeaveAvailabilityWarnings '[]
             , 'Eager
             , 'Live
             , 'DependsOn LeaveAvailabilityWarningsResource '[ 'FromScope VenueId ]
             ]
         , Fragment LeaveSectionCount
            '[ Field LeaveSection 'WireText ]
            '[ 'MountTarget Leave '[ Field LeaveSection 'WireText, Field LeaveTargetSuffix 'WireText ]
             , 'Eager
             , 'Live
             , 'DependsOn LeaveRequestsSectionResource '[ 'FromScope VenueId, 'FromFragment LeaveSection ]
             ]
         , Fragment LeaveSectionList
            '[ Field LeaveSection 'WireText ]
            '[ 'MountTarget Leave '[ Field LeaveSection 'WireText, Field LeaveTargetSuffix 'WireText ]
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
         , DomToken LeaveRequestsContent
         , DomToken LeaveArchivePageContent
         ]
