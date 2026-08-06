module Application.Helper.FrontendContract.Surface.LeaveRequests.Resource
    ( archivedLeaveRequestsResource
    , approvedLeaveRequestsResource
    , deniedLeaveRequestsResource
    , leaveAvailabilityWarningsResource
    , unavailabilityBlackoutsResource
    , leaveRequestsSectionResource
    , pendingLeaveRequestsResource
    ) where

import Application.Helper.FrontendContract.Surface.LeaveRequests (LeaveSectionValue (..))
import Application.Helper.FrontendContract.Surface.LeaveRequests.Generated.Resource (leaveAvailabilityWarningsResource,
                                                                                     leaveRequestsSectionResource,
                                                                                     unavailabilityBlackoutsResource)
import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import qualified Data.UUID as UUID
import IHP.Prelude

pendingLeaveRequestsResource, approvedLeaveRequestsResource, deniedLeaveRequestsResource, archivedLeaveRequestsResource :: UUID.UUID -> SurfaceResourceValue
pendingLeaveRequestsResource venueId = leaveRequestsSectionResource venueId LeavePendingSection
approvedLeaveRequestsResource venueId = leaveRequestsSectionResource venueId LeaveApprovedSection
deniedLeaveRequestsResource venueId = leaveRequestsSectionResource venueId LeaveDeniedSection
archivedLeaveRequestsResource venueId = leaveRequestsSectionResource venueId LeaveArchiveSection
