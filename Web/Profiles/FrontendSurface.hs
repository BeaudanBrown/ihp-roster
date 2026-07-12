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

import qualified Application.Helper.FrontendContract.Surface.Profile as Surface
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.Url (appendQueryParams)
import qualified Data.UUID as UUID
import qualified IHP.Prelude as Prelude
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
        NoSurfaceFields
        (profileCandidateMountedFragments scope)

profileSurfaceMountConfig :: ProfileScopeValue -> FrontendSurfaceMountConfig
profileSurfaceMountConfig scope =
    (profileSurfaceImpl scope).surfaceImplMountConfig

profileSurfaceScopeKey :: ProfileScopeValue -> Text
profileSurfaceScopeKey scope =
    frontendSurfaceScopeKeyFor @Surface.ProfileSurface @Surface.ProfileScope (profileScopeFields scope)
        |> either (error . ("Typed Profile scope invariant failed: " <>)) Prelude.id

profileSurfaceScope :: ProfileScopeValue -> SurfaceScope
profileSurfaceScope scope =
    profileLiveScope scope.profileVenueId scope.profileStaffId

profileCandidateMountedFragments :: ProfileScopeValue -> [FrontendSurfaceMountedFragment]
profileCandidateMountedFragments _ =
    [ profileDetailsMountedFragment
    , profilePreferencesMountedFragment
    , profileSecurityMountedFragment
    , profileLeaveMountedFragment
    , profileRsaMountedFragment
    ]

profileSurfaceFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
profileSurfaceFragmentKeys =
    frontendSurfaceMountedFragmentsToKeysFor @Surface.ProfileSurface

staffSurfaceImpl :: StaffScopeValue -> SurfaceImpl Surface.StaffSurface
staffSurfaceImpl scope =
    mkSurfaceImplFromValues @Surface.StaffSurface @Surface.StaffScope
        ("staff-" <> tshow scope.profileStaffId)
        (staffScopeFields scope)
        NoSurfaceFields
        (staffCandidateMountedFragments scope)

staffSurfaceMountConfig :: StaffScopeValue -> FrontendSurfaceMountConfig
staffSurfaceMountConfig scope =
    (staffSurfaceImpl scope).surfaceImplMountConfig

staffSurfaceScopeKey :: StaffScopeValue -> Text
staffSurfaceScopeKey scope =
    frontendSurfaceScopeKeyFor @Surface.StaffSurface @Surface.StaffScope (staffScopeFields scope)
        |> either (error . ("Typed Staff scope invariant failed: " <>)) Prelude.id

staffSurfaceScope :: StaffScopeValue -> SurfaceScope
staffSurfaceScope scope =
    frontendSurfaceLiveScope
        (surfaceNameValue @Surface.StaffSurface)
        (surfaceFieldsJson (staffScopeFields scope))
        (staffSurfaceScopeKey scope)

staffCandidateMountedFragments :: StaffScopeValue -> [FrontendSurfaceMountedFragment]
staffCandidateMountedFragments scope =
    [ staffDetailsMountedFragment scope
    , staffPreferencesMountedFragment scope
    , staffLeaveMountedFragment scope
    ]

staffSurfaceFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
staffSurfaceFragmentKeys =
    frontendSurfaceMountedFragmentsToKeysFor @Surface.StaffSurface

staffSectionFragmentForSection :: StaffScopeValue -> Text -> FrontendSurfaceMountedFragment
staffSectionFragmentForSection scope = \case
    "preferences" -> staffPreferencesMountedFragment scope
    "leave" -> staffLeaveMountedFragment scope
    _ -> staffDetailsMountedFragment scope

staffDetailsMountedFragment :: StaffScopeValue -> FrontendSurfaceMountedFragment
staffDetailsMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.StaffSurface @Surface.StaffDetailsSection
        NoSurfaceFields
        "staff-profile-details"
        (staffSectionFragmentUrl scope "profile")
        FrontendSurfaceReplace

staffPreferencesMountedFragment :: StaffScopeValue -> FrontendSurfaceMountedFragment
staffPreferencesMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.StaffSurface @Surface.StaffPreferencesSection
        NoSurfaceFields
        "staff-profile-preferences"
        (staffSectionFragmentUrl scope "preferences")
        FrontendSurfaceReplace

staffLeaveMountedFragment :: StaffScopeValue -> FrontendSurfaceMountedFragment
staffLeaveMountedFragment scope =
    frontendSurfaceMountedFragmentFor @Surface.StaffSurface @Surface.StaffLeaveSection
        NoSurfaceFields
        "staff-profile-leave"
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
        :& surfaceField @Surface.StaffId scope.profileStaffId
        :& NoSurfaceFields

staffScopeFields :: StaffScopeValue -> SurfaceFields (SurfaceScopeFieldSpecs Surface.StaffSurface Surface.StaffScope)
staffScopeFields scope =
    surfaceField @Surface.VenueId scope.profileVenueId
        :& surfaceField @Surface.StaffId scope.profileStaffId
        :& NoSurfaceFields

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
        NoSurfaceFields
        "profile-details"
        (profileSectionFragmentUrl "profile")
        FrontendSurfaceReplace

profilePreferencesMountedFragment :: FrontendSurfaceMountedFragment
profilePreferencesMountedFragment =
    frontendSurfaceMountedFragmentFor @Surface.ProfileSurface @Surface.ProfilePreferencesSection
        NoSurfaceFields
        "profile-preferences"
        (profileSectionFragmentUrl "preferences")
        FrontendSurfaceReplace

profileSecurityMountedFragment :: FrontendSurfaceMountedFragment
profileSecurityMountedFragment =
    frontendSurfaceMountedFragmentFor @Surface.ProfileSurface @Surface.ProfileSecuritySection
        NoSurfaceFields
        "profile-security"
        (profileSectionFragmentUrl "security")
        FrontendSurfaceReplace

profileLeaveMountedFragment :: FrontendSurfaceMountedFragment
profileLeaveMountedFragment =
    frontendSurfaceMountedFragmentFor @Surface.ProfileSurface @Surface.ProfileLeaveSection
        NoSurfaceFields
        "profile-leave"
        (profileSectionFragmentUrl "leave")
        FrontendSurfaceReplace

profileRsaMountedFragment :: FrontendSurfaceMountedFragment
profileRsaMountedFragment =
    frontendSurfaceMountedFragmentFor @Surface.ProfileSurface @Surface.ProfileRsaSection
        NoSurfaceFields
        "profile-rsa"
        (profileSectionFragmentUrl "rsa")
        FrontendSurfaceReplace

profileSectionFragmentUrl :: Text -> Text
profileSectionFragmentUrl section =
    appendQueryParams (pathTo ShowprofileContentLiveFragmentAction) [("section", section)]
