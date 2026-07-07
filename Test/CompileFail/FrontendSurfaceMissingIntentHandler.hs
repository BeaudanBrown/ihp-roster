{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Test.CompileFail.FrontendSurfaceMissingIntentHandler where

import Application.Helper.FrontendContract.Surface.Lab (SurfaceLabSurface)
import Application.Helper.FrontendContract.Surface.Runtime
import qualified Data.Aeson as Aeson
import IHP.Prelude

-- This fixture intentionally omits the MoveLabCard intent handler.
missingIntentHandlers :: SurfaceImplHandlers SurfaceLabSurface
missingIntentHandlers = SurfaceImplHandlers
    { surfaceScopeHandlers = FrontendSurfaceScopeHandler
        { scopeHandlerDefaultValue = frontendSurfaceFieldValues (Aeson.object ["venueId" Aeson..= ("venue-1" :: Text), "weekOffset" Aeson..= (0 :: Int)])
        , scopeHandlerKey = const "surface-lab:scope"
        } `HandlerCons` HandlerNil
    , surfaceMountStateHandlers = FrontendSurfaceMountStateHandler
        { mountStateHandlerDefaultValue = frontendSurfaceFieldValues Aeson.Null
        } `HandlerCons` HandlerNil
    , surfaceFragmentHandlers = FrontendSurfaceFragmentHandler
        { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
        , fragmentHandlerMountedFragment = const (dummyFragment "lab-shell")
        , fragmentHandlerRender = const mempty
        } `HandlerCons` FrontendSurfaceFragmentHandler
        { fragmentHandlerDefaultParams = frontendSurfaceFieldValues (Aeson.object ["panelId" Aeson..= ("panel-1" :: Text)])
        , fragmentHandlerMountedFragment = const (dummyFragment "lab-panel")
        , fragmentHandlerRender = const mempty
        } `HandlerCons` HandlerNil
    , surfaceActionHandlers = FrontendSurfaceActionHandler
        { actionHandlerDefaultFields = frontendSurfaceFieldValues Aeson.Null
        , actionHandlerRequest = const dummyRequest
        } `HandlerCons` HandlerNil
    , surfaceIntentHandlers = HandlerNil
    }

dummyFragment :: Text -> FrontendSurfaceMountedFragment
dummyFragment kind = FrontendSurfaceMountedFragment
    { mountedFragmentKey = FrontendSurfaceFragmentKey kind Aeson.Null
    , mountedFragmentTargetId = "surface-lab-fragment"
    , mountedFragmentUrl = "/frontend-surface-lab"
    , mountedFragmentProtection = FrontendSurfaceReplace
    , mountedFragmentLoadPolicy = "eager"
    , mountedFragmentLazyTrigger = Nothing
    , mountedFragmentPlaceholderKind = Nothing
    }

dummyRequest :: FrontendSurfaceHtmxRequest
dummyRequest = FrontendSurfaceHtmxRequest
    { htmxRequestName = "refresh-panel"
    , htmxRequestMethod = FrontendSurfacePost
    , htmxRequestUrl = "/RefreshFrontendSurfaceLabPanel"
    , htmxRequestTarget = "#surface-lab-panel"
    , htmxRequestSwap = "outerHTML"
    , htmxRequestFields = []
    }
