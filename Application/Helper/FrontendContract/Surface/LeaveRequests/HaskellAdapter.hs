{-# LANGUAGE TypeFamilies #-}

-- | Typed generator ownership for Leave Requests Surface adapters.
module Application.Helper.FrontendContract.Surface.LeaveRequests.HaskellAdapter
    ( LeaveRequestsAdapterFamily
    ) where

import Application.Helper.FrontendContract.Surface.HaskellAdapter.Association
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as LeaveRequests

data LeaveRequestsAdapterFamily

instance SurfaceAdapterFamily LeaveRequestsAdapterFamily where
    type AdapterFamilySurface LeaveRequestsAdapterFamily = LeaveRequests.LeaveRequestsSurface
