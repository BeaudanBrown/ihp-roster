{-# LANGUAGE DataKinds #-}

module Test.CompileFail.FrontendSurfaceIntentInActionAdapterLane where

import Application.Helper.FrontendContract.Surface.HaskellAdapter.Action
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Core
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Intent
import IHP.Prelude

intentInActionLane =
    renderSurfaceActionAdapterModules
        (undefined :: [ResolvedAdapter 'IntentAdapterKind SurfaceIntentAdapterDeclaration])
