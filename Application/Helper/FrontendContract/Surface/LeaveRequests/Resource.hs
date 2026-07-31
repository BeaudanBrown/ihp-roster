module Application.Helper.FrontendContract.Surface.LeaveRequests.Resource
    ( archivedLeaveRequestsResource
    , approvedLeaveRequestsResource
    , deniedLeaveRequestsResource
    , leaveAvailabilityWarningsResource
    , leaveRequestsSectionResource
    , pendingLeaveRequestsResource
    ) where

import Application.Helper.FrontendContract.Surface.LeaveRequests.Generated.Resource (leaveAvailabilityWarningsResource,
                                                                                     leaveRequestsSectionResource)
import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import qualified Data.UUID as UUID
import IHP.Prelude

pendingLeaveRequestsResource, approvedLeaveRequestsResource, deniedLeaveRequestsResource, archivedLeaveRequestsResource :: UUID.UUID -> SurfaceResourceValue
pendingLeaveRequestsResource venueId = leaveRequestsSectionResource venueId "pending"
approvedLeaveRequestsResource venueId = leaveRequestsSectionResource venueId "approved"
deniedLeaveRequestsResource venueId = leaveRequestsSectionResource venueId "denied"
archivedLeaveRequestsResource venueId = leaveRequestsSectionResource venueId "archive"
