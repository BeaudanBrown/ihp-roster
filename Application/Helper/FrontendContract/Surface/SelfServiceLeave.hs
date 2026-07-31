{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.SelfServiceLeave
    ( CreateSelfServiceLeaveRequest
    , EndDate
    , Notes
    , SelfServiceLeave
    , SelfServiceLeaveFormFragment
    , SelfServiceLeaveHistoryFragment
    , VisibleUnavailabilityBlackoutsFragment
    , UnavailabilityBlackoutsResource
    , SelfServiceLeaveScope
    , SelfServiceLeaveSurface
    , StaffId
    , StaffLeaveRequests
    , StaffLeaveRequestsResource
    , StartDate
    , VenueId
    ) where

import Application.Helper.FrontendContract.Surface.DSL
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as LeaveRequests

data SelfServiceLeave
data SelfServiceLeaveScope
data VenueId
data StaffId

data SelfServiceLeaveFormFragment
data SelfServiceLeaveHistoryFragment
data VisibleUnavailabilityBlackoutsFragment
data StaffLeaveRequests
data CreateSelfServiceLeaveRequest
data StartDate
data EndDate
data Notes

type StaffLeaveRequestsResource = Resource StaffLeaveRequests '[ Field StaffId 'WireUUID ]
type UnavailabilityBlackoutsResource = LeaveRequests.UnavailabilityBlackoutsResource

type SelfServiceLeaveSurface =
    Surface SelfServiceLeave
        '[ Scope SelfServiceLeaveScope
            '[ Field VenueId 'WireUUID
             , Field StaffId 'WireUUID
             ]
            '[ 'Authorize 'CurrentVenueStaff '[ VenueId, StaffId ] ]
         , Fragment SelfServiceLeaveFormFragment
            '[]
            '[ 'MountTarget SelfServiceLeaveFormFragment '[]
             , 'Eager
             , 'Live
             , 'ResyncOnly
             ]
         , Fragment VisibleUnavailabilityBlackoutsFragment
            '[]
            '[ 'MountTarget VisibleUnavailabilityBlackoutsFragment '[]
             , 'Eager
             , 'Live
             , 'DependsOn UnavailabilityBlackoutsResource '[ 'FromScope VenueId ]
             ]
         , Fragment SelfServiceLeaveHistoryFragment
            '[]
            '[ 'MountTarget SelfServiceLeaveHistoryFragment '[]
             , 'Eager
             , 'Live
             , 'DependsOn StaffLeaveRequestsResource '[ 'FromScope StaffId ]
             ]
         , Action CreateSelfServiceLeaveRequest
            '[ Field StartDate 'WireDay
             , Field EndDate 'WireDay
             , Field Notes 'WireText
             ]
            '[ 'HtmxMethod 'HtmxPost
             , 'HtmxTarget ('HtmxId SelfServiceLeaveFormFragment)
             , 'HtmxSwap 'HtmxOuterHTML
             , 'HtmxPushUrl 'HtmxPushUrlFalse
             ]
         ]
