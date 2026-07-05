{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendContract.Surface.LeaveRequests
    ( LeaveRequestsContent
    , LeaveRequestsResource
    , LeaveRequestsSurface
    , LeaveRequestsScope
    , VenueId
    ) where

import Application.Helper.FrontendContract.Surface.DSL

data LeaveRequests

data LeaveRequestsScope
data VenueId

data LeaveRequestsContent

type LeaveRequestsResource = Resource LeaveRequests '[ Field VenueId 'WireUUID ]

type LeaveRequestsSurface =
    Surface LeaveRequests
        '[ Scope LeaveRequestsScope
            '[ Field VenueId 'WireUUID
             ]
            '[ 'Authorize 'CurrentVenueManager '[ VenueId ] ]
         , Fragment LeaveRequestsContent '[] '[ 'Eager, 'Live, 'DependsOn LeaveRequestsResource '[ 'FromScope VenueId ] ]
         ]
