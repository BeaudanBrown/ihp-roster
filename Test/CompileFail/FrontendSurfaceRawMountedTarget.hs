{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceRawMountedTarget where

import qualified Application.Helper.FrontendContract.Surface.Lab as Surface
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

rawMountedTarget :: FrontendSurfaceMountedFragment
rawMountedTarget =
    frontendSurfaceMountedFragmentFor @Surface.SurfaceLabSurface @Surface.LabPanel
        (surfaceField @Surface.PanelId (error "fixture UUID") :& NoSurfaceFields)
        "raw-target-id"
        "/fixture"
        FrontendSurfaceReplace
