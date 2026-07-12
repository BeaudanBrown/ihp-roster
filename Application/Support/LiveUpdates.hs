{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}
{-# OPTIONS_GHC -Werror=incomplete-patterns #-}

module Application.Support.LiveUpdates
    ( SupportLiveFragment (..)
    , supportCandidateMountedFragments
    , supportSurface
    , supportSurfaceAction
    , supportSurfaceScope
    , supportSurfaceFragmentKeys
    ) where

import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
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
    mkSurfaceImpl "support" supportSurfaceMountConfig supportSurfaceHandlers
        |> surfaceImplWithMountedFragments supportCandidateMountedFragments

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

supportSurfaceFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
supportSurfaceFragmentKeys =
    frontendSurfaceMountedFragmentsToKeys "support"

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
        , surfaceActionHandlers =
            supportActionHandler "create-public-holiday-refresh-job" "/CreatePublicHolidayRefreshJob" `HandlerCons`
            supportActionHandler "create-fwc-mapd-refresh-job" "/CreateFwcMapdRefreshJob" `HandlerCons`
            HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

supportActionHandler :: Text -> Text -> FrontendSurfaceActionHandler ('Action marker fields options)
supportActionHandler actionName actionUrl = FrontendSurfaceActionHandler
    { actionHandlerDefaultFields = frontendSurfaceFieldValues Aeson.Null
    , actionHandlerRequest = const FrontendSurfaceHtmxRequest
        { htmxRequestName = actionName
        , htmxRequestMethod = FrontendSurfacePost
        , htmxRequestUrl = actionUrl
        , htmxRequestTarget = ""
        , htmxRequestSwap = "outerHTML"
        , htmxRequestFields = []
        }
    }

supportSurfaceAction :: Text -> SurfaceIR.HtmxActionIR
supportSurfaceAction actionName =
    case [action | surface <- registeredFrontendSurfaceContractIR.contractSurfaces, surface.surfaceName == "support", action <- surface.surfaceHtmxActions, action.htmxActionName == actionName] of
        action : _ -> action
        [] -> error ("missing support surface action: " <> cs actionName)

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
