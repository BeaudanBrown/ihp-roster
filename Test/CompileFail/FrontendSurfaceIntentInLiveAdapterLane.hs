{-# LANGUAGE DataKinds #-}

module Test.CompileFail.FrontendSurfaceIntentInLiveAdapterLane where

import Application.Helper.FrontendContract.Surface.ContractIR (IntentIR)
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Core
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Live
import IHP.Prelude

intentInLiveLane =
    renderSurfaceLiveAdapterModules
        []
        (undefined :: [ResolvedAdapter 'IntentAdapterKind IntentIR])
