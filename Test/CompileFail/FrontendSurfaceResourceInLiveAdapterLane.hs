{-# LANGUAGE DataKinds #-}

module Test.CompileFail.FrontendSurfaceResourceInLiveAdapterLane where

import Application.Helper.FrontendContract.Surface.ContractIR (ResourceIR)
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Core
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Live
import IHP.Prelude

resourceInLiveLane =
    renderSurfaceLiveAdapterModules
        (undefined :: [ResolvedAdapter 'ResourceAdapterKind ResourceIR])
        []
