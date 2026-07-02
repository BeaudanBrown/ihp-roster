{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.Profiles.FrontendSurface
    ( ProfileScopeValue (..)
    , profileAffectedMountedFragments
    , profileCandidateMountedFragments
    , profileFragmentDependencies
    , profileLiveUpdateScope
    , profileSectionFragmentForSection
    , profileSurfaceImpl
    , profileSurfaceMountConfig
    , profileSurfaceScopeKey
    , profileSurfaceWireFragments
    ) where

import Application.Helper.FrontendSurface.DSL
import qualified Application.Helper.FrontendSurface.Profile as Surface
import Application.Helper.FrontendSurface.Runtime
import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveUpdate.Runtime (LiveFragmentKey (..),
                                              LiveFragmentProtection (..),
                                              LiveUpdateScope (..),
                                              LiveUpdateWireFragment (..))
import Application.Helper.Url (appendQueryParams)
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import Web.Controller.Prelude

data ProfileScopeValue = ProfileScopeValue
    { profileVenueId :: !UUID.UUID
    , profileStaffId :: !UUID.UUID
    }
    deriving (Eq, Show)

profileSurfaceImpl :: ProfileScopeValue -> SurfaceImpl Surface.ProfileSurface
profileSurfaceImpl scope =
    let impl = mkSurfaceImpl "profile" (profileSurfaceMountConfig scope) (profileSurfaceHandlers scope)
     in impl { surfaceImplMountConfig = impl.surfaceImplMountConfig { mountFragments = profileCandidateMountedFragments scope } }

profileSurfaceMountConfig :: ProfileScopeValue -> FrontendSurfaceMountConfig
profileSurfaceMountConfig scope =
    FrontendSurfaceMountConfig
        { mountSurfaceName = "profile"
        , mountScopeKey = profileSurfaceScopeKey scope
        , mountKey = "primary"
        , mountState = Aeson.Null
        , mountFragments = profileCandidateMountedFragments scope
        }

profileSurfaceScopeKey :: ProfileScopeValue -> Text
profileSurfaceScopeKey scope =
    "profile:" <> tshow scope.profileVenueId <> ":" <> tshow scope.profileStaffId

profileLiveUpdateScope :: ProfileScopeValue -> LiveUpdateScope
profileLiveUpdateScope scope =
    ProfileScope { venueId = scope.profileVenueId, staffId = scope.profileStaffId }

profileCandidateMountedFragments :: ProfileScopeValue -> [FrontendSurfaceMountedFragment]
profileCandidateMountedFragments _ =
    [ profileDetailsMountedFragment
    , profilePreferencesMountedFragment
    , profileSecurityMountedFragment
    , profileLeaveMountedFragment
    , profileRsaMountedFragment
    ]

profileAffectedMountedFragments :: ProfileScopeValue -> Set.Set LiveResource -> [FrontendSurfaceMountedFragment]
profileAffectedMountedFragments scope touchedResources =
    profileCandidateMountedFragments scope
        |> filter (not . Set.null . Set.intersection touchedResources . Set.fromList . profileFragmentDependencies scope)

profileFragmentDependencies :: ProfileScopeValue -> FrontendSurfaceMountedFragment -> [LiveResource]
profileFragmentDependencies scope fragment =
    case fragment.mountedFragmentKey.fragmentKind of
        "profile-details-section" -> [StaffProfileResource scope.profileStaffId, StaffPreferencesResource scope.profileStaffId]
        "profile-preferences-section" -> [StaffPreferencesResource scope.profileStaffId]
        "profile-rsa-section" -> [StaffRsaDocumentsResource scope.profileStaffId]
        "profile-leave-section" -> [StaffLeaveRequestsResource scope.profileStaffId]
        _ -> []

profileSurfaceWireFragments :: [FrontendSurfaceMountedFragment] -> [LiveUpdateWireFragment]
profileSurfaceWireFragments =
    map mountedFragmentToWireFragment

mountedFragmentToWireFragment :: FrontendSurfaceMountedFragment -> LiveUpdateWireFragment
mountedFragmentToWireFragment fragment =
    LiveUpdateWireFragment
        { fragmentKey = profileLiveFragmentKey fragment.mountedFragmentKey.fragmentKind
        , targetId = fragment.mountedFragmentTargetId
        , url = fragment.mountedFragmentUrl
        , deferUntilBlur = False
        , protectionPolicy = mountedFragmentProtectionPolicy fragment.mountedFragmentProtection
        }

profileLiveFragmentKey :: Text -> LiveFragmentKey
profileLiveFragmentKey = \case
    "profile-details-section" -> ProfileDetailsSectionFragment
    "profile-preferences-section" -> ProfilePreferencesSectionFragment
    "profile-security-section" -> ProfileSecuritySectionFragment
    "profile-leave-section" -> ProfileLeaveSectionFragment
    "profile-rsa-section" -> ProfileRsaSectionFragment
    _ -> ProfileContentFragment

mountedFragmentProtectionPolicy :: FrontendSurfaceProtection -> LiveFragmentProtection
mountedFragmentProtectionPolicy = \case
    FrontendSurfaceReplace -> NoProtection
    FrontendSurfaceFocusedField -> NoProtection

profileSurfaceHandlers :: ProfileScopeValue -> SurfaceImplHandlers Surface.ProfileSurface
profileSurfaceHandlers scope =
    SurfaceImplHandlers
        { surfaceScopeHandlers =
            FrontendSurfaceScopeHandler
                { scopeHandlerDefaultValue = profileScopeFields scope
                , scopeHandlerKey = \fields ->
                    let venueId = fromMaybe (tshow scope.profileVenueId) (getSurfaceField @Surface.VenueId fields)
                        staffId = fromMaybe (tshow scope.profileStaffId) (getSurfaceField @Surface.StaffId fields)
                     in "profile:" <> venueId <> ":" <> staffId
                }
                `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers =
            FrontendSurfaceFragmentHandler
                { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                , fragmentHandlerMountedFragment = const profileDetailsMountedFragment
                , fragmentHandlerRender = const mempty
                }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const profilePreferencesMountedFragment
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const profileSecurityMountedFragment
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const profileLeaveMountedFragment
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const profileRsaMountedFragment
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` HandlerNil
        , surfaceActionHandlers = HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

profileScopeFields :: ProfileScopeValue -> FrontendSurfaceFieldValues '[ 'Field Surface.VenueId 'WireUUID, 'Field Surface.StaffId 'WireUUID]
profileScopeFields scope =
    frontendSurfaceFieldValues (Aeson.object ["venueId" Aeson..= tshow scope.profileVenueId, "staffId" Aeson..= tshow scope.profileStaffId])

profileSectionFragmentForSection :: Text -> FrontendSurfaceMountedFragment
profileSectionFragmentForSection = \case
    "preferences" -> profilePreferencesMountedFragment
    "security" -> profileSecurityMountedFragment
    "leave" -> profileLeaveMountedFragment
    "rsa" -> profileRsaMountedFragment
    _ -> profileDetailsMountedFragment

profileDetailsMountedFragment :: FrontendSurfaceMountedFragment
profileDetailsMountedFragment =
    profileSectionMountedFragment "profile-details-section" "profile-details" "profile"

profilePreferencesMountedFragment :: FrontendSurfaceMountedFragment
profilePreferencesMountedFragment =
    profileSectionMountedFragment "profile-preferences-section" "profile-preferences" "preferences"

profileSecurityMountedFragment :: FrontendSurfaceMountedFragment
profileSecurityMountedFragment =
    profileSectionMountedFragment "profile-security-section" "profile-security" "security"

profileLeaveMountedFragment :: FrontendSurfaceMountedFragment
profileLeaveMountedFragment =
    profileSectionMountedFragment "profile-leave-section" "profile-leave" "leave"

profileRsaMountedFragment :: FrontendSurfaceMountedFragment
profileRsaMountedFragment =
    profileSectionMountedFragment "profile-rsa-section" "profile-rsa" "rsa"

profileSectionMountedFragment :: Text -> Text -> Text -> FrontendSurfaceMountedFragment
profileSectionMountedFragment keyName targetId section =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey keyName Aeson.Null
        , mountedFragmentTargetId = targetId
        , mountedFragmentUrl = appendQueryParams (pathTo ShowProfileContentFragmentAction) [("section", section)]
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }
