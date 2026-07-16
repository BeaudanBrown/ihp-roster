module Application.Helper.FrontendContract.Surface.LeaveRequests.Live
    ( leaveRequestsLiveScope
    , leaveSectionCountLiveFragment
    , leaveSectionListLiveFragment
    , matchLeaveRequestsLiveScope
    ) where

import Application.Helper.FrontendContract.Surface.LeaveRequests.Generated.Live (leaveRequestsLiveScope,
                                                                                 leaveSectionCountLiveFragment,
                                                                                 leaveSectionListLiveFragment)
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests.Generated.Live as Generated
import Application.Helper.FrontendContract.Surface.Live (SurfaceScope)
import qualified Data.UUID as UUID
import IHP.Prelude

-- | Recover the venue identity directly for leave-request domain callers.
matchLeaveRequestsLiveScope :: SurfaceScope -> Maybe UUID.UUID
matchLeaveRequestsLiveScope scope = do
    (venueId, ()) <- Generated.matchLeaveRequestsLiveScope scope
    pure venueId
