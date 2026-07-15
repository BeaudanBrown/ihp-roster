{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongIntentField where

import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude
import qualified Test.Support.FrontendSurfaceFixture as Fixture

intentFields :: SurfaceFields (SurfaceIntentFieldSpecs Fixture.FrontendSurfaceFixture Fixture.MoveCard)
intentFields =
    surfaceField @Fixture.SourceItemKey "source"
        :& surfaceField @Fixture.TargetDropzoneKey "target"
        :& NoSurfaceFields

-- PanelId is not carried by MoveCard. Intent field ownership must fail at
-- compile time rather than becoming an unchecked hidden input.
wrongIntentField = surfaceFieldNameFrom @Fixture.PanelId intentFields
