{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongScopeField where

import Application.Helper.FrontendContract.Surface.Values
import qualified Test.Support.FrontendSurfaceFixture as Fixture

-- PanelId belongs to a fixture fragment/action, not the FixtureScope identity.
wrongScopeField = surfaceScopeFieldName @Fixture.FrontendSurfaceFixture @Fixture.FixtureScope @Fixture.PanelId
