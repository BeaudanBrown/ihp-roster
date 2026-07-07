{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Test.CompileFail.FrontendSurfaceMissingFragmentHandler where

import Application.Helper.FrontendContract.Surface.Lab (SurfaceLabSurface)
import Application.Helper.FrontendContract.Surface.Runtime
import qualified Data.Aeson as Aeson
import IHP.Prelude

-- This fixture intentionally omits the LabPanel fragment handler. It should fail
-- to compile because SurfaceLabSurface declares both LabShell and LabPanel.
missingFragmentHandlers :: SurfaceImplHandlers SurfaceLabSurface
missingFragmentHandlers = SurfaceImplHandlers
    { surfaceScopeHandlers = FrontendSurfaceScopeHandler
        { scopeHandlerDefaultValue = frontendSurfaceFieldValues (Aeson.object ["venueId" Aeson..= ("venue-1" :: Text), "weekOffset" Aeson..= (0 :: Int)])
        , scopeHandlerKey = const "surface-lab:scope"
        } `HandlerCons` HandlerNil
    , surfaceMountStateHandlers = FrontendSurfaceMountStateHandler
        { mountStateHandlerDefaultValue = frontendSurfaceFieldValues Aeson.Null
        } `HandlerCons` HandlerNil
    , surfaceFragmentHandlers = FrontendSurfaceFragmentHandler
        { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
        , fragmentHandlerMountedFragment = const dummyFragment
        , fragmentHandlerRender = const mempty
        } `HandlerCons` HandlerNil
    , surfaceActionHandlers = FrontendSurfaceActionHandler
        { actionHandlerDefaultFields = frontendSurfaceFieldValues Aeson.Null
        , actionHandlerRequest = const dummyRequest
        } `HandlerCons` HandlerNil
    , surfaceIntentHandlers = FrontendSurfaceIntentHandler
        { intentHandlerDefaultFields = frontendSurfaceFieldValues Aeson.Null
        , intentHandlerForm = const (FrontendSurfaceIntentForm "move-lab-card" dummyRequest)
        } `HandlerCons` HandlerNil
    }

dummyFragment :: FrontendSurfaceMountedFragment
dummyFragment = FrontendSurfaceMountedFragment
    { mountedFragmentKey = FrontendSurfaceFragmentKey "lab-shell" Aeson.Null
    , mountedFragmentTargetId = "surface-lab-shell"
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
