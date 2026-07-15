{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.Profile.Resource
    ( matchStaffPreferencesResource
    , matchStaffProfileResource
    , staffLeaveRequestsResource
    , staffPreferencesResource
    , staffProfileResource
    , staffRsaDocumentsResource
    ) where

import qualified Application.Helper.FrontendContract.Surface.Profile as Surface
import Application.Helper.FrontendContract.Surface.Resource
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.UUID as UUID
import IHP.Prelude

staffLeaveRequestsResource, staffProfileResource, staffPreferencesResource, staffRsaDocumentsResource :: UUID.UUID -> SurfaceResourceValue
staffLeaveRequestsResource staffId =
    frontendSurfaceResource @Surface.ProfileSurface @Surface.StaffLeaveRequests
        (surfaceField @Surface.StaffId staffId :& NoSurfaceFields)
staffProfileResource staffId =
    frontendSurfaceResource @Surface.ProfileSurface @Surface.StaffProfile
        (surfaceField @Surface.StaffId staffId :& NoSurfaceFields)
staffPreferencesResource staffId =
    frontendSurfaceResource @Surface.ProfileSurface @Surface.StaffPreferences
        (surfaceField @Surface.StaffId staffId :& NoSurfaceFields)
staffRsaDocumentsResource staffId =
    frontendSurfaceResource @Surface.ProfileSurface @Surface.StaffRsaDocuments
        (surfaceField @Surface.StaffId staffId :& NoSurfaceFields)

matchStaffProfileResource :: SurfaceResourceValue -> Maybe UUID.UUID
matchStaffProfileResource value = do
    (staffId, ()) <-
        matchFrontendSurfaceResource @Surface.ProfileSurface @Surface.StaffProfile value
    pure staffId

matchStaffPreferencesResource :: SurfaceResourceValue -> Maybe UUID.UUID
matchStaffPreferencesResource value = do
    (staffId, ()) <-
        matchFrontendSurfaceResource @Surface.ProfileSurface @Surface.StaffPreferences value
    pure staffId
