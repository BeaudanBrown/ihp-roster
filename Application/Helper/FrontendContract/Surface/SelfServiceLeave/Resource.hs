module Application.Helper.FrontendContract.Surface.SelfServiceLeave.Resource
    ( matchStaffLeaveRequestsResource
    , staffLeaveRequestsResource
    ) where

import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import Application.Helper.FrontendContract.Surface.SelfServiceLeave.Generated.Resource (staffLeaveRequestsResource)
import qualified Application.Helper.FrontendContract.Surface.SelfServiceLeave.Generated.Resource as Generated
import qualified Data.UUID as UUID
import IHP.Prelude

matchStaffLeaveRequestsResource :: SurfaceResourceValue -> Maybe UUID.UUID
matchStaffLeaveRequestsResource = fmap fst . Generated.matchStaffLeaveRequestsResource
