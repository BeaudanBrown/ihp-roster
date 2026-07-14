{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.Profile.Live
    ( matchProfileLiveScope
    , matchStaffLiveScope
    , profileDetailsLiveFragment
    , profileLeaveLiveFragment
    , profileLiveScope
    , profilePreferencesLiveFragment
    , profileRsaLiveFragment
    , profileSecurityLiveFragment
    , staffDetailsLiveFragment
    , staffLeaveLiveFragment
    , staffLiveScope
    , staffPreferencesLiveFragment
    ) where

import Application.Helper.FrontendContract.Surface.Live
import qualified Application.Helper.FrontendContract.Surface.Profile as Surface
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.UUID as UUID
import IHP.Prelude

profileLiveScope :: UUID.UUID -> UUID.UUID -> SurfaceScope
profileLiveScope venueId staffId =
    frontendSurfaceScope @Surface.ProfileSurface @Surface.ProfileScope (profileAndStaffScopeFields venueId staffId)

staffLiveScope :: UUID.UUID -> UUID.UUID -> SurfaceScope
staffLiveScope venueId staffId =
    frontendSurfaceScope @Surface.StaffSurface @Surface.StaffScope (profileAndStaffScopeFields venueId staffId)

matchProfileLiveScope :: SurfaceScope -> Maybe (UUID.UUID, UUID.UUID)
matchProfileLiveScope scope = do
    (venueId, (staffId, ())) <-
        matchFrontendSurfaceScope @Surface.ProfileSurface @Surface.ProfileScope scope
    pure (venueId, staffId)

matchStaffLiveScope :: SurfaceScope -> Maybe (UUID.UUID, UUID.UUID)
matchStaffLiveScope scope = do
    (venueId, (staffId, ())) <-
        matchFrontendSurfaceScope @Surface.StaffSurface @Surface.StaffScope scope
    pure (venueId, staffId)

profileAndStaffScopeFields :: UUID.UUID -> UUID.UUID -> SurfaceFields (SurfaceScopeFieldSpecs Surface.ProfileSurface Surface.ProfileScope)
profileAndStaffScopeFields venueId staffId =
    surfaceField @Surface.VenueId venueId
        :& surfaceField @Surface.StaffId staffId
        :& NoSurfaceFields

profileDetailsLiveFragment, profilePreferencesLiveFragment, profileSecurityLiveFragment, profileLeaveLiveFragment, profileRsaLiveFragment :: SurfaceFragmentKey
profileDetailsLiveFragment = frontendSurfaceFragmentKey @Surface.ProfileSurface @Surface.ProfileDetailsSection NoSurfaceFields
profilePreferencesLiveFragment = frontendSurfaceFragmentKey @Surface.ProfileSurface @Surface.ProfilePreferencesSection NoSurfaceFields
profileSecurityLiveFragment = frontendSurfaceFragmentKey @Surface.ProfileSurface @Surface.ProfileSecuritySection NoSurfaceFields
profileLeaveLiveFragment = frontendSurfaceFragmentKey @Surface.ProfileSurface @Surface.ProfileLeaveSection NoSurfaceFields
profileRsaLiveFragment = frontendSurfaceFragmentKey @Surface.ProfileSurface @Surface.ProfileRsaSection NoSurfaceFields

staffDetailsLiveFragment, staffPreferencesLiveFragment, staffLeaveLiveFragment :: SurfaceFragmentKey
staffDetailsLiveFragment = frontendSurfaceFragmentKey @Surface.StaffSurface @Surface.StaffDetailsSection NoSurfaceFields
staffPreferencesLiveFragment = frontendSurfaceFragmentKey @Surface.StaffSurface @Surface.StaffPreferencesSection NoSurfaceFields
staffLeaveLiveFragment = frontendSurfaceFragmentKey @Surface.StaffSurface @Surface.StaffLeaveSection NoSurfaceFields
