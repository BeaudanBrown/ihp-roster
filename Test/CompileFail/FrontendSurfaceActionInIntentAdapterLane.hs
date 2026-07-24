{-# LANGUAGE DataKinds #-}

module Test.CompileFail.FrontendSurfaceActionInIntentAdapterLane where

import Application.Helper.FrontendContract.Surface.HaskellAdapter.Action
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Core
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Intent
import IHP.Prelude

actionInIntentLane =
    renderSurfaceIntentAdapterModules
        (undefined :: [ResolvedAdapter 'ActionAdapterKind SurfaceActionAdapterDeclaration])
