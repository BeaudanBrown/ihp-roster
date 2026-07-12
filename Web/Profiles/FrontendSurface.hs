{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.Profiles.FrontendSurface
    ( ProfileScopeValue (..)
    , profileCandidateMountedFragments
    , profileSurfaceScope
    , profileSectionFragmentForSection
    , profileSurfaceImpl
    , profileSurfaceAction
    , staffSurfaceAction
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

import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import Application.Helper.FrontendContract.Surface.DSL
import qualified Application.Helper.FrontendContract.Surface.Profile as Surface
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.Url (appendQueryParams)
import qualified Data.Aeson as Aeson
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
    mkSurfaceImpl "profile" (profileSurfaceMountConfig scope) (profileSurfaceHandlers scope)
        |> surfaceImplWithMountedFragments (profileCandidateMountedFragments scope)

profileSurfaceMountConfig :: ProfileScopeValue -> FrontendSurfaceMountConfig
profileSurfaceMountConfig scope =
    FrontendSurfaceMountConfig
        { mountSurfaceName = "profile"
        , mountScopeKey = profileSurfaceScopeKey scope
        , mountKey = "primary"
        , mountScope = Aeson.Null
        , mountSubscription = Nothing
        , mountState = Aeson.Null
        , mountFragments = profileCandidateMountedFragments scope
        }

profileSurfaceScopeKey :: ProfileScopeValue -> Text
profileSurfaceScopeKey scope =
    "profile:" <> tshow scope.profileVenueId <> ":" <> tshow scope.profileStaffId

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
    frontendSurfaceMountedFragmentsToKeys "profile"

staffSurfaceImpl :: StaffScopeValue -> SurfaceImpl Surface.StaffSurface
staffSurfaceImpl scope =
    mkSurfaceImpl "staff" (staffSurfaceMountConfig scope) (staffSurfaceHandlers scope)
        |> surfaceImplWithMountedFragments (staffCandidateMountedFragments scope)

staffSurfaceMountConfig :: StaffScopeValue -> FrontendSurfaceMountConfig
staffSurfaceMountConfig scope =
    FrontendSurfaceMountConfig
        { mountSurfaceName = "staff"
        , mountScopeKey = staffSurfaceScopeKey scope
        , mountKey = "staff-" <> tshow scope.profileStaffId
        , mountScope = Aeson.Null
        , mountSubscription = Nothing
        , mountState = Aeson.Null
        , mountFragments = staffCandidateMountedFragments scope
        }

staffSurfaceScopeKey :: StaffScopeValue -> Text
staffSurfaceScopeKey scope =
    "staff:" <> tshow scope.profileVenueId <> ":" <> tshow scope.profileStaffId

staffSurfaceScope :: StaffScopeValue -> SurfaceScope
staffSurfaceScope scope =
    frontendSurfaceLiveScope "staff" payload (staffSurfaceScopeKey scope)
    where
        payload = Aeson.object ["venueId" Aeson..= tshow scope.profileVenueId, "staffId" Aeson..= tshow scope.profileStaffId]

staffCandidateMountedFragments :: StaffScopeValue -> [FrontendSurfaceMountedFragment]
staffCandidateMountedFragments scope =
    [ staffDetailsMountedFragment scope
    , staffPreferencesMountedFragment scope
    , staffLeaveMountedFragment scope
    ]

staffSurfaceFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
staffSurfaceFragmentKeys =
    frontendSurfaceMountedFragmentsToKeys "staff"

staffSurfaceHandlers :: StaffScopeValue -> SurfaceImplHandlers Surface.StaffSurface
staffSurfaceHandlers scope =
    SurfaceImplHandlers
        { surfaceScopeHandlers =
            FrontendSurfaceScopeHandler
                { scopeHandlerDefaultValue = profileScopeFields scope
                , scopeHandlerKey = \fields ->
                    let venueId = fromMaybe (tshow scope.profileVenueId) (getSurfaceField @Surface.VenueId fields)
                        staffId = fromMaybe (tshow scope.profileStaffId) (getSurfaceField @Surface.StaffId fields)
                     in "staff:" <> venueId <> ":" <> staffId
                }
                `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers =
            FrontendSurfaceFragmentHandler
                { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                , fragmentHandlerMountedFragment = const (staffDetailsMountedFragment scope)
                , fragmentHandlerRender = const mempty
                }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (staffPreferencesMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (staffLeaveMountedFragment scope)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` HandlerNil
        , surfaceActionHandlers =
            profileActionHandler "update-staff-profile" (pathTo (UpdateStaffAction (Id scope.profileStaffId))) "#staff-profile-details" "outerHTML show:none" `HandlerCons`
            profileActionHandler "update-staff-shift-preferences" (pathTo (UpdateStaffAction (Id scope.profileStaffId))) "#staff-profile-preferences" "outerHTML show:none" `HandlerCons`
            profileActionHandler "create-staff-leave-request" (pathTo CreateLeaveRequestAction) "#staff-leave-request-form-fragment" "outerHTML" `HandlerCons`
            HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

staffSectionFragmentForSection :: StaffScopeValue -> Text -> FrontendSurfaceMountedFragment
staffSectionFragmentForSection scope = \case
    "preferences" -> staffPreferencesMountedFragment scope
    "leave" -> staffLeaveMountedFragment scope
    _ -> staffDetailsMountedFragment scope

staffDetailsMountedFragment :: StaffScopeValue -> FrontendSurfaceMountedFragment
staffDetailsMountedFragment =
    staffSectionMountedFragment "staff-details-section" "staff-profile-details" "profile"

staffPreferencesMountedFragment :: StaffScopeValue -> FrontendSurfaceMountedFragment
staffPreferencesMountedFragment =
    staffSectionMountedFragment "staff-preferences-section" "staff-profile-preferences" "preferences"

staffLeaveMountedFragment :: StaffScopeValue -> FrontendSurfaceMountedFragment
staffLeaveMountedFragment =
    staffSectionMountedFragment "staff-leave-section" "staff-profile-leave" "leave"

staffSectionMountedFragment :: Text -> Text -> Text -> StaffScopeValue -> FrontendSurfaceMountedFragment
staffSectionMountedFragment keyName targetId section scope =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey keyName Aeson.Null
        , mountedFragmentTargetId = targetId
        , mountedFragmentUrl = appendQueryParams (pathTo (ShowStaffContentLiveFragmentAction (Id scope.profileStaffId))) [ ("section", section) ]
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLazyTrigger = Nothing
        , mountedFragmentPlaceholderKind = Nothing
        }

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
        , surfaceActionHandlers =
            profileActionHandler "update-profile-details" (pathTo UpdateProfileAction) "#profile-details" "outerHTML show:none" `HandlerCons`
            profileActionHandler "update-profile-shift-preferences" (pathTo UpdateProfileAction) "#profile-preferences" "outerHTML show:none" `HandlerCons`
            profileActionHandler "create-profile-leave-request" (appendQueryParams (pathTo CreateLeaveRequestAction) [("responseContext", "profile"), ("section", "leave")]) "#profile-leave-request-form-fragment" "outerHTML" `HandlerCons`
            HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

profileActionHandler :: Text -> Text -> Text -> Text -> FrontendSurfaceActionHandler ('Action marker fields options)
profileActionHandler actionName actionUrl target swap = FrontendSurfaceActionHandler
    { actionHandlerDefaultFields = frontendSurfaceFieldValues Aeson.Null
    , actionHandlerRequest = const FrontendSurfaceHtmxRequest
        { htmxRequestName = actionName
        , htmxRequestMethod = FrontendSurfacePost
        , htmxRequestUrl = actionUrl
        , htmxRequestTarget = target
        , htmxRequestSwap = swap
        , htmxRequestFields = []
        }
    }

profileSurfaceAction :: Text -> SurfaceIR.HtmxActionIR
profileSurfaceAction = surfaceAction "profile"

staffSurfaceAction :: Text -> SurfaceIR.HtmxActionIR
staffSurfaceAction = surfaceAction "staff"

surfaceAction :: Text -> Text -> SurfaceIR.HtmxActionIR
surfaceAction surfaceName actionName =
    case [action | surface <- registeredFrontendSurfaceContractIR.contractSurfaces, surface.surfaceName == surfaceName, action <- surface.surfaceHtmxActions, action.htmxActionName == actionName] of
        action : _ -> action
        [] -> error ("missing " <> cs surfaceName <> " surface action: " <> cs actionName)

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
        , mountedFragmentUrl = appendQueryParams (pathTo ShowprofileContentLiveFragmentAction) [("section", section)]
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLazyTrigger = Nothing
        , mountedFragmentPlaceholderKind = Nothing
        }
