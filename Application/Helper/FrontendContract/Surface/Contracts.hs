module Application.Helper.FrontendContract.Surface.Contracts
    ( registeredFrontendSurfaceContractIR
    ) where

import Application.Helper.FrontendContract.Surface.ContractIR
import Application.Helper.FrontendContract.Surface.Reflect (reflectRegisteredFrontendSurfaces)
import IHP.Prelude

registeredFrontendSurfaceContractIR :: SurfaceContractIR
registeredFrontendSurfaceContractIR =
    case checkedSurfaceContractIR reflectRegisteredFrontendSurfaces of
        Right contract -> contract
        Left diagnostics -> error (cs ("invalid FrontendContract Surface registry: " <> tshow diagnostics))
