{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.Contracts
    ( registeredFrontendSurfaceContractIR
    ) where

import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.Reflect (ReflectSurfaceRegistry (..))
import Application.Helper.FrontendContract.Surface.Registry (RegisteredFrontendSurfaces)
import IHP.Prelude

registeredFrontendSurfaceContractIR :: SurfaceContractIR
registeredFrontendSurfaceContractIR =
    case checkedSurfaceContractIR reflectedRegisteredFrontendSurfaces of
        Right contract -> contract
        Left diagnostics -> error (cs ("invalid FrontendContract Surface registry: " <> tshow diagnostics))
  where
    reflectedRegisteredFrontendSurfaces =
        SurfaceContractIR
            { contractSurfaces = reflectSurfaceRegistry @RegisteredFrontendSurfaces
            }
