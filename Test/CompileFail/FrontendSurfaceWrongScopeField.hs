{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongScopeField where

import qualified Application.Helper.FrontendContract.Surface.Lab as Lab
import Application.Helper.FrontendContract.Surface.Values

-- PanelId belongs to a Lab fragment/action, not the LabScope identity.
wrongScopeField = surfaceScopeFieldName @Lab.SurfaceLabSurface @Lab.LabScope @Lab.PanelId
