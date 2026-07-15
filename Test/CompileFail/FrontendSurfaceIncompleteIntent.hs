{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceIncompleteIntent where

import Application.Helper.FrontendContract.Surface.Runtime (frontendSurfaceIntentForm)
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude
import qualified Test.Support.FrontendSurfaceFixture as Fixture

-- MoveCard owns both source and target fields. The intent form cannot be
-- constructed with only the source field.
incompleteIntent =
    frontendSurfaceIntentForm @Fixture.FrontendSurfaceFixture @Fixture.MoveCard
        (surfaceField @Fixture.SourceItemKey "source" :& NoSurfaceFields)
