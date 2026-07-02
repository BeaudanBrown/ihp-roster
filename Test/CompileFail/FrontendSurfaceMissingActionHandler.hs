{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Test.CompileFail.FrontendSurfaceMissingActionHandler where

import Application.Helper.FrontendSurface.Lab (SurfaceLabSurface)
import Application.Helper.FrontendSurface.Runtime
import qualified Data.Aeson as Aeson
import IHP.Prelude

-- This fixture intentionally omits the RefreshPanel action handler.
missingActionHandlers :: SurfaceImplHandlers SurfaceLabSurface
missingActionHandlers = SurfaceImplHandlers
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
    , surfaceActionHandlers = HandlerNil
    , surfaceIntentHandlers = FrontendSurfaceIntentHandler
        { intentHandlerDefaultFields = frontendSurfaceFieldValues Aeson.Null
        , intentHandlerForm = const (FrontendSurfaceIntentForm "move-lab-card" dummyRequest)
        } `HandlerCons` HandlerNil
    }

dummyFragment :: Text -> FrontendSurfaceMountedFragment
dummyFragment kind = FrontendSurfaceMountedFragment
    { mountedFragmentKey = FrontendSurfaceFragmentKey kind Aeson.Null
    , mountedFragmentTargetId = "surface-lab-fragment"
    , mountedFragmentUrl = "/frontend-surface-lab"
    , mountedFragmentProtection = FrontendSurfaceReplace
    , mountedFragmentLoadPolicy = "eager"
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
