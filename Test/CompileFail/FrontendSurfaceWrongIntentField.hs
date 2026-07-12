{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongIntentField where

import qualified Application.Helper.FrontendContract.Surface.Lab as Lab
import Application.Helper.FrontendContract.Surface.Values

-- PanelId is not carried by MoveLabCard. Intent field ownership must fail at
-- compile time rather than becoming an unchecked hidden input.
wrongIntentField = surfaceIntentFieldName @Lab.SurfaceLabSurface @Lab.MoveLabCard @Lab.PanelId
