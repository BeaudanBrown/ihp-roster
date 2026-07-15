{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.LeaveRequests.Resource
    ( archivedLeaveRequestsResource
    , approvedLeaveRequestsResource
    , deniedLeaveRequestsResource
    , leaveRequestsSectionResource
    , pendingLeaveRequestsResource
    ) where

import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as Surface
import Application.Helper.FrontendContract.Surface.Resource
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.UUID as UUID
import IHP.Prelude

leaveRequestsSectionResource :: UUID.UUID -> Text -> SurfaceResourceValue
leaveRequestsSectionResource venueId section =
    frontendSurfaceResource @Surface.LeaveRequestsSurface @Surface.LeaveRequestsSection
        ( surfaceField @Surface.VenueId venueId
            :& surfaceField @Surface.LeaveSection section
            :& NoSurfaceFields
        )

pendingLeaveRequestsResource, approvedLeaveRequestsResource, deniedLeaveRequestsResource, archivedLeaveRequestsResource :: UUID.UUID -> SurfaceResourceValue
pendingLeaveRequestsResource venueId = leaveRequestsSectionResource venueId "pending"
approvedLeaveRequestsResource venueId = leaveRequestsSectionResource venueId "approved"
deniedLeaveRequestsResource venueId = leaveRequestsSectionResource venueId "denied"
archivedLeaveRequestsResource venueId = leaveRequestsSectionResource venueId "archive"
