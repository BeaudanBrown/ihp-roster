{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceRawMountedTarget where

import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude
import qualified Test.Support.FrontendSurfaceFixture as Surface

rawMountedTarget :: FrontendSurfaceMountedFragment
rawMountedTarget =
    frontendSurfaceMountedFragmentFor @Surface.FrontendSurfaceFixture @Surface.FixturePanel
        (surfaceField @Surface.PanelId (error "fixture UUID") :& NoSurfaceFields)
        "raw-target-id"
        "/fixture"
        FrontendSurfaceReplace
