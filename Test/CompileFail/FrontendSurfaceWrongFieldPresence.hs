{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongFieldPresence where

import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude
import qualified Test.Support.FrontendSurfaceFixture as Fixture

-- FixtureViewState declares staffFilterId as an OptionalField. Building it as
-- a required field must identify the marker and both presence contracts.
wrongFieldPresence :: SurfaceFields (SurfaceMountStateFieldSpecs Fixture.FrontendSurfaceFixture)
wrongFieldPresence =
    surfaceField @Fixture.ShowArchived False
        &: surfaceField @Fixture.StaffFilterId (error "fixture UUID")
        &: noSurfaceFields
