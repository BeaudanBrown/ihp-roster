{-# LANGUAGE DataKinds #-}

module Test.CompileFail.FrontendSurfaceActionInIntentAdapterLane where

import Application.Helper.FrontendContract.Surface.HaskellAdapter.Core
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Request
import IHP.Prelude

actionInIntentLane =
    renderSurfaceIntentAdapterModules
        (undefined :: [ResolvedAdapter 'ActionAdapterKind SurfaceRequestAdapterDeclaration])
