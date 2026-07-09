{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.LeaveRequests
    ( LeaveRequestsContent
    , LeaveSection
    , LeaveSectionCount
    , LeaveSectionList
    , LeaveRequestsSectionResource
    , LeaveRequestsSurface
    , LeaveRequestsScope
    , ArchiveLeaveRequestsPage
    , ApproveLeaveRequest
    , DenyLeaveRequest
    , VenueId
    ) where

import Application.Helper.FrontendContract.Surface.DSL

data LeaveRequests

data LeaveRequestsScope
data VenueId

data LeaveRequestsContent
data LeaveSection
data LeaveSectionCount
data LeaveSectionList
data ArchiveLeaveRequestsPage
data ApproveLeaveRequest
data DenyLeaveRequest
data ArchivePage
data None
data LeaveArchivePageContent

type LeaveRequestsSectionResource = Resource LeaveRequestsSection '[ Field VenueId 'WireUUID, Field LeaveSection 'WireText ]
data LeaveRequestsSection

type LeaveRequestsSurface =
    Surface LeaveRequests
        '[ Scope LeaveRequestsScope
            '[ Field VenueId 'WireUUID
             ]
            '[ 'Authorize 'CurrentVenueManager '[ VenueId ] ]
         , Fragment LeaveSectionCount
            '[ Field LeaveSection 'WireText ]
            '[ 'Eager
             , 'Live
             , 'DependsOn LeaveRequestsSectionResource '[ 'FromScope VenueId, 'FromFragment LeaveSection ]
             ]
         , Fragment LeaveSectionList
            '[ Field LeaveSection 'WireText ]
            '[ 'Eager
             , 'Live
             , 'DependsOn LeaveRequestsSectionResource '[ 'FromScope VenueId, 'FromFragment LeaveSection ]
             ]
         , Action ArchiveLeaveRequestsPage
            '[ Field ArchivePage 'WireInt ]
            '[ 'HtmxMethod 'HtmxGet
             , 'HtmxTarget LeaveArchivePageContent
             , 'HtmxSwap None
             , 'HtmxPushUrl 'HtmxPushUrlTrue
             ]
         , Action ApproveLeaveRequest
            '[]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget LeaveRequestsContent
             , 'HtmxSwap None
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , Action DenyLeaveRequest
            '[]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget LeaveRequestsContent
             , 'HtmxSwap None
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         , DomToken LeaveRequestsContent
         , DomToken LeaveSectionCount
         , DomToken LeaveSectionList
         , DomToken LeaveArchivePageContent
         ]
