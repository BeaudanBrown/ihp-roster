{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Application.Helper.FrontendSurface.LeaveRequests
    ( LeaveRequestsContent
    , LeaveRequestsSurface
    , LeaveRequestsScope
    , VenueId
    ) where

import Application.Helper.FrontendSurface.DSL

data LeaveRequests

data LeaveRequestsScope
data VenueId

data LeaveRequestsContent

type LeaveRequestsSurface =
    Surface LeaveRequests
        '[ Scope LeaveRequestsScope
            '[ Field VenueId 'WireUUID
             ]
         , Fragment LeaveRequestsContent '[] '[ 'Eager, 'Live ]
         ]
