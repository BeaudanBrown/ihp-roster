module Application.Helper.FrontendContract.Surface.Profile.Resource
    ( matchStaffPreferencesResource
    , matchStaffProfileResource
    , staffLeaveRequestsResource
    , staffPreferencesResource
    , staffProfileResource
    ) where

import Application.Helper.FrontendContract.Surface.Profile.Generated.Resource (staffPreferencesResource,
                                                                               staffProfileResource)
import qualified Application.Helper.FrontendContract.Surface.Profile.Generated.Resource as Generated
import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import Application.Helper.FrontendContract.Surface.SelfServiceLeave.Resource (staffLeaveRequestsResource)
import qualified Data.UUID as UUID
import IHP.Prelude

matchStaffProfileResource :: SurfaceResourceValue -> Maybe UUID.UUID
matchStaffProfileResource = fmap fst . Generated.matchStaffProfileResource

matchStaffPreferencesResource :: SurfaceResourceValue -> Maybe UUID.UUID
matchStaffPreferencesResource = fmap fst . Generated.matchStaffPreferencesResource
