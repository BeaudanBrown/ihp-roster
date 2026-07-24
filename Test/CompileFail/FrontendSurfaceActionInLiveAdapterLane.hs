{-# LANGUAGE DataKinds #-}

module Test.CompileFail.FrontendSurfaceActionInLiveAdapterLane where

import Application.Helper.FrontendContract.Surface.ContractIR (HtmxActionIR)
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Core
import Application.Helper.FrontendContract.Surface.HaskellAdapter.Live
import IHP.Prelude

actionInLiveLane =
    renderSurfaceLiveAdapterModules
        (undefined :: [ResolvedAdapter 'ActionAdapterKind HtmxActionIR])
        []
