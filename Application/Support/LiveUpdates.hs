{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.Support.LiveUpdates
    ( SupportLiveFragment (..)
    , supportCandidateMountedFragments
    , supportSurface
    , supportSurfaceScope
    , supportSurfaceWireFragments
    ) where

import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Runtime
import qualified Application.Helper.FrontendContract.Surface.Support as Surface
import Application.Helper.LiveUpdate
import Application.Helper.LiveUpdate.Runtime
import qualified Data.Aeson as Aeson
import IHP.Prelude

data SupportLiveFragment
    = SupportAwardRatesLiveFragment
    | SupportPublicHolidaysLiveFragment
    deriving (Eq, Show)

supportSurfaceScope :: SurfaceScope
supportSurfaceScope = supportPlatformLiveScope

supportSurface :: SurfaceImpl Surface.SupportSurface
supportSurface =
    let impl = mkSurfaceImpl "support" supportSurfaceMountConfig supportSurfaceHandlers
     in impl { surfaceImplMountConfig = impl.surfaceImplMountConfig { mountFragments = supportCandidateMountedFragments } }

supportSurfaceMountConfig :: FrontendSurfaceMountConfig
supportSurfaceMountConfig =
    FrontendSurfaceMountConfig
        { mountSurfaceName = "support"
        , mountScopeKey = "support"
        , mountKey = "primary"
        , mountScope = Aeson.Null
        , mountSubscription = Nothing
        , mountState = Aeson.Null
        , mountFragments = supportCandidateMountedFragments
        }

supportCandidateMountedFragments :: [FrontendSurfaceMountedFragment]
supportCandidateMountedFragments =
    [ supportAwardRatesMountedFragment
    , supportPublicHolidaysMountedFragment
    ]

supportSurfaceWireFragments :: [FrontendSurfaceMountedFragment] -> [SurfaceWireFragment]
supportSurfaceWireFragments =
    frontendSurfaceMountedFragmentsToWire "support"

supportSurfaceHandlers :: SurfaceImplHandlers Surface.SupportSurface
supportSurfaceHandlers =
    SurfaceImplHandlers
        { surfaceScopeHandlers =
            FrontendSurfaceScopeHandler
                { scopeHandlerDefaultValue = frontendSurfaceFieldValues Aeson.Null
                , scopeHandlerKey = const "support"
                }
                `HandlerCons` HandlerNil
        , surfaceMountStateHandlers = HandlerNil
        , surfaceFragmentHandlers =
            FrontendSurfaceFragmentHandler
                { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                , fragmentHandlerMountedFragment = const supportAwardRatesMountedFragment
                , fragmentHandlerRender = const mempty
                }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const supportPublicHolidaysMountedFragment
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` HandlerNil
        , surfaceActionHandlers = HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

supportAwardRatesMountedFragment :: FrontendSurfaceMountedFragment
supportAwardRatesMountedFragment =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "support-award-rates" Aeson.Null
        , mountedFragmentTargetId = "support-award-rates-section"
        , mountedFragmentUrl = "/ShowFwcMapdAwardRatesSection"
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        , mountedFragmentLazyTrigger = Nothing
        , mountedFragmentPlaceholderKind = Nothing
        }

supportPublicHolidaysMountedFragment :: FrontendSurfaceMountedFragment
supportPublicHolidaysMountedFragment =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "support-public-holidays" Aeson.Null
        , mountedFragmentTargetId = "support-public-holidays-section"
        , mountedFragmentUrl = "/ShowPublicHolidaysSection"
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        , mountedFragmentLazyTrigger = Nothing
        , mountedFragmentPlaceholderKind = Nothing
        }
