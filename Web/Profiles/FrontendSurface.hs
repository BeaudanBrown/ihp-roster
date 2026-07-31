{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.Profiles.FrontendSurface
    ( ProfileScopeValue (..)
    , profileCandidateMountedFragments
    , profileSurfaceScope
    , profileSectionFragmentForSection
    , profileSurfaceImpl
    , profileSurfaceMountConfig
    , profileSurfaceScopeKey
    , profileSurfaceFragmentKeys
    , staffCandidateMountedFragments
    , staffSectionFragmentForSection
    , staffSurfaceImpl
    , staffSurfaceScope
    , staffSurfaceScopeKey
    , staffSurfaceFragmentKeys
    ) where

import Application.Helper.FrontendContract.Surface.Live (SurfaceFragmentKey,
                                                         SurfaceScope,
                                                         surfaceScopeKey)
import qualified Application.Helper.FrontendContract.Surface.Profile as Surface
import qualified Application.Helper.FrontendContract.Surface.Profile.Live as SurfaceLive
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.Url (appendQueryParams)
import qualified Data.UUID as UUID
import Web.Controller.Prelude

data ProfileScopeValue = ProfileScopeValue
    { profileVenueId :: !UUID.UUID
    , profileStaffId :: !UUID.UUID
    }
    deriving (Eq, Show)

type StaffScopeValue = ProfileScopeValue

profileSurfaceImpl :: ProfileScopeValue -> SurfaceImpl Surface.ProfileSurface
profileSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.ProfileSurface @Surface.ProfileScope
        "primary"
        (profileScopeFields scope)
        noSurfaceFields
        (profileCandidateMountedFragments scope)

profileSurfaceMountConfig :: ProfileScopeValue -> FrontendSurfaceMountConfig
profileSurfaceMountConfig scope =
    (profileSurfaceImpl scope).surfaceImplMountConfig

profileSurfaceScopeKey :: ProfileScopeValue -> Text
profileSurfaceScopeKey = surfaceScopeKey . profileSurfaceScope

profileSurfaceScope :: ProfileScopeValue -> SurfaceScope
profileSurfaceScope scope =
    SurfaceLive.profileLiveScope scope.profileVenueId scope.profileStaffId

profileCandidateMountedFragments :: ProfileScopeValue -> [FrontendSurfaceMountedFragment]
profileCandidateMountedFragments _ =
    [ profileDetailsMountedFragment
    , profilePreferencesMountedFragment
    , profileSecurityMountedFragment
    , profileLeaveMountedFragment
    , profileRsaMountedFragment
    ]

profileSurfaceFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
profileSurfaceFragmentKeys = map (.mountedFragmentKey)

staffSurfaceImpl :: StaffScopeValue -> SurfaceImpl Surface.StaffSurface
staffSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.StaffSurface @Surface.StaffScope
        ("staff-" <> tshow scope.profileStaffId)
        (staffScopeFields scope)
        noSurfaceFields
        (staffCandidateMountedFragments scope)

staffSurfaceMountConfig :: StaffScopeValue -> FrontendSurfaceMountConfig
staffSurfaceMountConfig scope =
    (staffSurfaceImpl scope).surfaceImplMountConfig

staffSurfaceScopeKey :: StaffScopeValue -> Text
staffSurfaceScopeKey = surfaceScopeKey . staffSurfaceScope

staffSurfaceScope :: StaffScopeValue -> SurfaceScope
staffSurfaceScope scope =
    SurfaceLive.staffLiveScope scope.profileVenueId scope.profileStaffId

staffCandidateMountedFragments :: StaffScopeValue -> [FrontendSurfaceMountedFragment]
staffCandidateMountedFragments scope =
    [ staffDetailsMountedFragment scope
    , staffPreferencesMountedFragment scope
    , staffVisibleUnavailabilityBlackoutsMountedFragment
    , staffLeaveMountedFragment scope
    ]

staffSurfaceFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
staffSurfaceFragmentKeys = map (.mountedFragmentKey)

staffSectionFragmentForSection :: StaffScopeValue -> Text -> FrontendSurfaceMountedFragment
staffSectionFragmentForSection scope = \case
    "preferences" -> staffPreferencesMountedFragment scope
    "leave" -> staffLeaveMountedFragment scope
    _ -> staffDetailsMountedFragment scope

staffDetailsMountedFragment :: StaffScopeValue -> FrontendSurfaceMountedFragment
staffDetailsMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.StaffSurface @Surface.StaffDetailsSection
        noSurfaceFields
        noSurfaceFields
        (staffSectionFragmentUrl scope "profile")
        FrontendSurfaceReplace

staffPreferencesMountedFragment :: StaffScopeValue -> FrontendSurfaceMountedFragment
staffPreferencesMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.StaffSurface @Surface.StaffPreferencesSection
        noSurfaceFields
        noSurfaceFields
        (staffSectionFragmentUrl scope "preferences")
        FrontendSurfaceReplace

staffVisibleUnavailabilityBlackoutsMountedFragment :: FrontendSurfaceMountedFragment
staffVisibleUnavailabilityBlackoutsMountedFragment =
    frontendSurfaceMountedFragmentFor @Surface.StaffSurface @Surface.StaffVisibleUnavailabilityBlackouts
        noSurfaceFields
        noSurfaceFields
        (appendQueryParams (pathTo ShowVisibleUnavailabilityBlackoutsFragmentAction) [("surface", "staff")])
        FrontendSurfaceReplace

staffLeaveMountedFragment :: StaffScopeValue -> FrontendSurfaceMountedFragment
staffLeaveMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.StaffSurface @Surface.StaffLeaveSection
        noSurfaceFields
        noSurfaceFields
        (staffSectionFragmentUrl scope "leave")
        FrontendSurfaceReplace

staffSectionFragmentUrl :: StaffScopeValue -> Text -> Text
staffSectionFragmentUrl scope section =
    appendQueryParams
        (pathTo (ShowStaffContentLiveFragmentAction (Id scope.profileStaffId)))
        [("section", section)]

profileScopeFields :: ProfileScopeValue -> SurfaceFields (SurfaceScopeFieldSpecs Surface.ProfileSurface Surface.ProfileScope)
profileScopeFields scope =
    surfaceField @Surface.VenueId scope.profileVenueId
        &: surfaceField @Surface.StaffId scope.profileStaffId
        &: noSurfaceFields

staffScopeFields :: StaffScopeValue -> SurfaceFields (SurfaceScopeFieldSpecs Surface.StaffSurface Surface.StaffScope)
staffScopeFields scope =
    surfaceField @Surface.VenueId scope.profileVenueId
        &: surfaceField @Surface.StaffId scope.profileStaffId
        &: noSurfaceFields

profileSectionFragmentForSection :: Text -> FrontendSurfaceMountedFragment
profileSectionFragmentForSection = \case
    "preferences" -> profilePreferencesMountedFragment
    "security" -> profileSecurityMountedFragment
    "leave" -> profileLeaveMountedFragment
    "rsa" -> profileRsaMountedFragment
    _ -> profileDetailsMountedFragment

profileDetailsMountedFragment :: FrontendSurfaceMountedFragment
profileDetailsMountedFragment =
    frontendSurfaceMountedFragmentFor @Surface.ProfileSurface @Surface.ProfileDetailsSection
        noSurfaceFields
        noSurfaceFields
        (profileSectionFragmentUrl "profile")
        FrontendSurfaceReplace

profilePreferencesMountedFragment :: FrontendSurfaceMountedFragment
profilePreferencesMountedFragment =
    frontendSurfaceMountedFragmentFor @Surface.ProfileSurface @Surface.ProfilePreferencesSection
        noSurfaceFields
        noSurfaceFields
        (profileSectionFragmentUrl "preferences")
        FrontendSurfaceReplace

profileSecurityMountedFragment :: FrontendSurfaceMountedFragment
profileSecurityMountedFragment =
    frontendSurfaceMountedFragmentFor @Surface.ProfileSurface @Surface.ProfileSecuritySection
        noSurfaceFields
        noSurfaceFields
        (profileSectionFragmentUrl "security")
        FrontendSurfaceReplace

profileLeaveMountedFragment :: FrontendSurfaceMountedFragment
profileLeaveMountedFragment =
    frontendSurfaceMountedFragmentFor @Surface.ProfileSurface @Surface.ProfileLeaveSection
        noSurfaceFields
        noSurfaceFields
        (profileSectionFragmentUrl "leave")
        FrontendSurfaceReplace

profileRsaMountedFragment :: FrontendSurfaceMountedFragment
profileRsaMountedFragment =
    frontendSurfaceMountedFragmentFor @Surface.ProfileSurface @Surface.ProfileRsaSection
        noSurfaceFields
        noSurfaceFields
        (profileSectionFragmentUrl "rsa")
        FrontendSurfaceReplace

profileSectionFragmentUrl :: Text -> Text
profileSectionFragmentUrl section =
    appendQueryParams (pathTo ShowprofileContentLiveFragmentAction) [("section", section)]
