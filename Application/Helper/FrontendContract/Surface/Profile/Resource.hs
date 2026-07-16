module Application.Helper.FrontendContract.Surface.Profile.Resource
    ( matchStaffPreferencesResource
    , matchStaffProfileResource
    , staffLeaveRequestsResource
    , staffPreferencesResource
    , staffProfileResource
    , staffRsaDocumentsResource
    ) where

import Application.Helper.FrontendContract.Surface.Profile.Generated.Resource (staffLeaveRequestsResource,
                                                                               staffPreferencesResource,
                                                                               staffProfileResource,
                                                                               staffRsaDocumentsResource)
import qualified Application.Helper.FrontendContract.Surface.Profile.Generated.Resource as Generated
import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import qualified Data.UUID as UUID
import IHP.Prelude

matchStaffProfileResource :: SurfaceResourceValue -> Maybe UUID.UUID
matchStaffProfileResource = fmap fst . Generated.matchStaffProfileResource

matchStaffPreferencesResource :: SurfaceResourceValue -> Maybe UUID.UUID
matchStaffPreferencesResource = fmap fst . Generated.matchStaffPreferencesResource
