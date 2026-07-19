{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Registry
    ( RegisteredFrontendContracts
    , registeredFrontendContractIR
    ) where

import Application.Helper.FrontendContract.App
import Application.Helper.FrontendContract.AppShell
import Application.Helper.FrontendContract.DSL
import Application.Helper.FrontendContract.HorizontalScroll
import Application.Helper.FrontendContract.Interaction
import Application.Helper.FrontendContract.IR
import Application.Helper.FrontendContract.LiveUpdate
import Application.Helper.FrontendContract.OrderedRange
import Application.Helper.FrontendContract.Overlay
import Application.Helper.FrontendContract.Reflect
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import Application.Helper.FrontendContract.TimePicker
import Application.Helper.FrontendContract.Toggle
import Application.Helper.FrontendContract.UiRegion

-- | Root frontend browser contract registry. Global roots live here; Surface
-- roots are appended from the registered surface contract registry.
type RegisteredFrontendContracts =
    '[ AppContract
     , OverlayContract
     , AppShellContract
     , UiRegionContract
     , InteractionContract
     , ToggleContract
     , TimePickerContract
     , OrderedRangeContract
     , HorizontalScrollContract
     , LiveUpdateContract
     ] :: [FrontendContractSpec]

registeredFrontendContractIR :: FrontendContractIR
registeredFrontendContractIR = FrontendContractIR
    { contractGlobals = reflectedGlobals.contractGlobals
    , contractSurfaces = registeredFrontendSurfaceContractIR.contractSurfaces
    }
  where
    reflectedGlobals = reflectFrontendContracts @RegisteredFrontendContracts
