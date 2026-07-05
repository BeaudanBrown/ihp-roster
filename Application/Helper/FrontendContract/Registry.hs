{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Registry
    ( RegisteredFrontendContracts
    , registeredFrontendContractIR
    , registeredFrontendContractIRForSurfaceContract
    ) where

import Application.Helper.FrontendContract.App
import Application.Helper.FrontendContract.DSL
import Application.Helper.FrontendContract.Interaction
import Application.Helper.FrontendContract.IR
import Application.Helper.FrontendContract.LiveUpdate
import Application.Helper.FrontendContract.Reflect
import Application.Helper.FrontendContract.Roster
import Application.Helper.FrontendContract.Surface.Adapter
import qualified Application.Helper.FrontendContract.Surface.ContractIR as Surface
import Application.Helper.FrontendContract.Surface.Contracts (registeredFrontendSurfaceContractIR)
import Application.Helper.FrontendContract.UiRegion
import IHP.Prelude

-- | Root frontend browser contract registry. Global roots live here; Surface
-- roots are appended from the registered surface contract registry.
type RegisteredFrontendContracts =
    '[ AppContract
     , UiRegionContract
     , RosterGlobalContract
     , InteractionContract
     , LiveUpdateContract
     ] :: [FrontendContractSpec]

registeredFrontendContractIR :: FrontendContractIR
registeredFrontendContractIR = registeredFrontendContractIRForSurfaceContract registeredFrontendSurfaceContractIR

registeredFrontendContractIRForSurfaceContract :: Surface.SurfaceContractIR -> FrontendContractIR
registeredFrontendContractIRForSurfaceContract surfaceContract = appendFrontendContractIR
    (reflectFrontendContracts @RegisteredFrontendContracts)
    (frontendSurfaceContractToFrontendContractIR surfaceContract)

appendFrontendContractIR :: FrontendContractIR -> FrontendContractIR -> FrontendContractIR
appendFrontendContractIR left right = FrontendContractIR
    { contractGlobals = left.contractGlobals <> right.contractGlobals
    , contractSurfaces = left.contractSurfaces <> right.contractSurfaces
    }
