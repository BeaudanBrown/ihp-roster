{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.Support.LiveUpdates
    ( SupportLiveFragment (..)
    , supportAffectedMountedFragments
    , supportCandidateMountedFragments
    , supportFragmentDependencies
    , supportLiveSurface
    , supportLiveUpdateScope
    , supportSurfaceWireFragments
    ) where

import Application.Helper.FrontendSurface.DSL
import Application.Helper.FrontendSurface.Runtime
import qualified Application.Helper.FrontendSurface.Support as Surface
import Application.Helper.LiveResource (LiveResource (..))
import Application.Helper.LiveUpdate
import Application.Helper.LiveUpdate.Runtime (LiveUpdateWireFragment (..))
import qualified Data.Aeson as Aeson
import qualified Data.Set as Set
import IHP.Prelude

data SupportLiveFragment
    = SupportAwardRatesLiveFragment
    | SupportPublicHolidaysLiveFragment
    deriving (Eq, Show)

supportLiveUpdateScope :: LiveUpdateScope
supportLiveUpdateScope = SupportPlatformScope

supportLiveSurface :: SurfaceImpl Surface.SupportSurface
supportLiveSurface =
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

supportAffectedMountedFragments :: Set.Set LiveResource -> [FrontendSurfaceMountedFragment]
supportAffectedMountedFragments touchedResources =
    supportCandidateMountedFragments
        |> filter (not . Set.null . Set.intersection touchedResources . Set.fromList . supportFragmentDependencies)

supportFragmentDependencies :: FrontendSurfaceMountedFragment -> [LiveResource]
supportFragmentDependencies fragment =
    case fragment.mountedFragmentKey.fragmentKind of
        "support-award-rates"     -> [SupportAwardRatesResource]
        "support-public-holidays" -> [SupportPublicHolidaysResource]
        _                         -> []

supportSurfaceWireFragments :: [FrontendSurfaceMountedFragment] -> [LiveUpdateWireFragment]
supportSurfaceWireFragments =
    mapMaybe mountedFragmentToWireFragment

mountedFragmentToWireFragment :: FrontendSurfaceMountedFragment -> Maybe LiveUpdateWireFragment
mountedFragmentToWireFragment fragment = do
    fragmentKey <- mountedFragmentLiveKey fragment
    pure LiveUpdateWireFragment
        { fragmentKey
        , targetId = fragment.mountedFragmentTargetId
        , url = fragment.mountedFragmentUrl
        , deferUntilBlur = False
        , protectionPolicy = mountedFragmentProtectionPolicy fragment.mountedFragmentProtection
        }

mountedFragmentLiveKey :: FrontendSurfaceMountedFragment -> Maybe LiveFragmentKey
mountedFragmentLiveKey fragment =
    case fragment.mountedFragmentKey.fragmentKind of
        "support-award-rates"     -> Just SupportAwardRatesSectionFragment
        "support-public-holidays" -> Just SupportPublicHolidaysSectionFragment
        _                         -> Nothing

mountedFragmentProtectionPolicy :: FrontendSurfaceProtection -> LiveFragmentProtection
mountedFragmentProtectionPolicy = \case
    FrontendSurfaceReplace -> NoProtection
    FrontendSurfaceFocusedField -> NoProtection
    FrontendSurfaceFocusedFieldConfig config ->
        FocusedFieldProtection FocusedFieldProtectionConfig
            { activeSelector = config.focusedProtectionActiveSelector
            , fieldKeyAttr = config.focusedProtectionFieldKeyAttr
            , fieldNameFallback = config.focusedProtectionFieldNameFallback
            , containerSelector = config.focusedProtectionContainerSelector
            }

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
        }

supportPublicHolidaysMountedFragment :: FrontendSurfaceMountedFragment
supportPublicHolidaysMountedFragment =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "support-public-holidays" Aeson.Null
        , mountedFragmentTargetId = "support-public-holidays-section"
        , mountedFragmentUrl = "/ShowPublicHolidaysSection"
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }
