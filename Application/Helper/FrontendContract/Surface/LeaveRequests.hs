{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.LeaveRequests
    ( LeaveRequestsContent
    , LeavePendingCount
    , LeavePendingList
    , LeaveApprovedCount
    , LeaveApprovedList
    , LeaveDeniedCount
    , LeaveDeniedList
    , LeaveArchiveCount
    , LeaveArchiveList
    , PendingLeaveRequestsResource
    , ApprovedLeaveRequestsResource
    , DeniedLeaveRequestsResource
    , ArchivedLeaveRequestsResource
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
data LeavePendingCount
data LeavePendingList
data LeaveApprovedCount
data LeaveApprovedList
data LeaveDeniedCount
data LeaveDeniedList
data LeaveArchiveCount
data LeaveArchiveList
data ArchiveLeaveRequestsPage
data ApproveLeaveRequest
data DenyLeaveRequest
data ArchivePage
data None
data LeaveArchivePageContent

type PendingLeaveRequestsResource = Resource LeavePendingCount '[ Field VenueId 'WireUUID ]
type ApprovedLeaveRequestsResource = Resource LeaveApprovedCount '[ Field VenueId 'WireUUID ]
type DeniedLeaveRequestsResource = Resource LeaveDeniedCount '[ Field VenueId 'WireUUID ]
type ArchivedLeaveRequestsResource = Resource LeaveArchiveCount '[ Field VenueId 'WireUUID ]

type LeaveRequestsSurface =
    Surface LeaveRequests
        '[ Scope LeaveRequestsScope
            '[ Field VenueId 'WireUUID
             ]
            '[ 'Authorize 'CurrentVenueManager '[ VenueId ] ]
         , Fragment LeavePendingCount '[] '[ 'Eager, 'Live, 'DependsOn PendingLeaveRequestsResource '[ 'FromScope VenueId ] ]
         , Fragment LeavePendingList '[] '[ 'Eager, 'Live, 'DependsOn PendingLeaveRequestsResource '[ 'FromScope VenueId ] ]
         , Fragment LeaveApprovedCount '[] '[ 'Eager, 'Live, 'DependsOn ApprovedLeaveRequestsResource '[ 'FromScope VenueId ] ]
         , Fragment LeaveApprovedList '[] '[ 'Eager, 'Live, 'DependsOn ApprovedLeaveRequestsResource '[ 'FromScope VenueId ] ]
         , Fragment LeaveDeniedCount '[] '[ 'Eager, 'Live, 'DependsOn DeniedLeaveRequestsResource '[ 'FromScope VenueId ] ]
         , Fragment LeaveDeniedList '[] '[ 'Eager, 'Live, 'DependsOn DeniedLeaveRequestsResource '[ 'FromScope VenueId ] ]
         , Fragment LeaveArchiveCount '[] '[ 'Eager, 'Live, 'DependsOn ArchivedLeaveRequestsResource '[ 'FromScope VenueId ] ]
         , Fragment LeaveArchiveList '[] '[ 'Eager, 'Live, 'DependsOn ArchivedLeaveRequestsResource '[ 'FromScope VenueId ] ]
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
         , DomToken LeavePendingCount
         , DomToken LeavePendingList
         , DomToken LeaveApprovedCount
         , DomToken LeaveApprovedList
         , DomToken LeaveDeniedCount
         , DomToken LeaveDeniedList
         , DomToken LeaveArchiveCount
         , DomToken LeaveArchiveList
         , DomToken LeaveArchivePageContent
         ]
