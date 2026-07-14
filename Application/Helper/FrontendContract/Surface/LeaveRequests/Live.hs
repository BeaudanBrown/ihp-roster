{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.LeaveRequests.Live
    ( leaveRequestsLiveScope
    , leaveSectionCountLiveFragment
    , leaveSectionListLiveFragment
    , matchLeaveRequestsLiveScope
    ) where

import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as Surface
import Application.Helper.FrontendContract.Surface.Live
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.UUID as UUID
import IHP.Prelude

leaveRequestsLiveScope :: UUID.UUID -> SurfaceScope
leaveRequestsLiveScope venueId =
    frontendSurfaceScope @Surface.LeaveRequestsSurface @Surface.LeaveRequestsScope
        (surfaceField @Surface.VenueId venueId :& NoSurfaceFields)

matchLeaveRequestsLiveScope :: SurfaceScope -> Maybe UUID.UUID
matchLeaveRequestsLiveScope scope = do
    (venueId, ()) <-
        matchFrontendSurfaceScope @Surface.LeaveRequestsSurface @Surface.LeaveRequestsScope scope
    pure venueId

leaveSectionCountLiveFragment :: Text -> SurfaceFragmentKey
leaveSectionCountLiveFragment section =
    frontendSurfaceFragmentKey @Surface.LeaveRequestsSurface @Surface.LeaveSectionCount
        (surfaceField @Surface.LeaveSection section :& NoSurfaceFields)

leaveSectionListLiveFragment :: Text -> SurfaceFragmentKey
leaveSectionListLiveFragment section =
    frontendSurfaceFragmentKey @Surface.LeaveRequestsSurface @Surface.LeaveSectionList
        (surfaceField @Surface.LeaveSection section :& NoSurfaceFields)
