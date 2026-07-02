{-# LANGUAGE DataKinds     #-}
{-# LANGUAGE TypeOperators #-}

module Test.CompileFail.FrontendSurfaceMissingFragmentHandler where

import Application.Helper.FrontendSurface.Lab (SurfaceLabSurface)
import Application.Helper.FrontendSurface.Runtime
import qualified Data.Aeson as Aeson
import IHP.Prelude

-- This fixture intentionally omits the LabPanel fragment handler. It should fail
-- to compile because SurfaceLabSurface declares both LabShell and LabPanel.
missingFragmentHandlers :: SurfaceImplHandlers SurfaceLabSurface
missingFragmentHandlers = SurfaceImplHandlers
    { surfaceScopeHandlers = FrontendSurfaceScopeHandler "surface-lab:scope" `HandlerCons` HandlerNil
    , surfaceMountStateHandlers = FrontendSurfaceMountStateHandler Aeson.Null `HandlerCons` HandlerNil
    , surfaceFragmentHandlers = FrontendSurfaceFragmentHandler dummyFragment mempty `HandlerCons` HandlerNil
    , surfaceActionHandlers = FrontendSurfaceActionHandler dummyRequest `HandlerCons` HandlerNil
    , surfaceIntentHandlers = FrontendSurfaceIntentHandler (FrontendSurfaceIntentForm "move-lab-card" dummyRequest) `HandlerCons` HandlerNil
    }

dummyFragment :: FrontendSurfaceMountedFragment
dummyFragment = FrontendSurfaceMountedFragment
    { mountedFragmentKey = FrontendSurfaceFragmentKey "lab-shell" Aeson.Null
    , mountedFragmentTargetId = "surface-lab-shell"
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
