{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongIntentField where

import Application.Helper.FrontendContract.Surface.Values
import qualified Test.Support.FrontendSurfaceFixture as Fixture

-- PanelId is not carried by MoveCard. Intent field ownership must fail at
-- compile time rather than becoming an unchecked hidden input.
wrongIntentField = surfaceIntentFieldName @Fixture.FrontendSurfaceFixture @Fixture.MoveCard @Fixture.PanelId
