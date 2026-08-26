module Application.Helper.FrontendContract.Surface.Contracts
    ( registeredFrontendSurfaceContractIR
    ) where

import Application.Helper.FrontendContract.IR (FrontendContractIR (..),
                                               frontendContractIR)
import Application.Helper.FrontendContract.Registry (checkedRegisteredFrontendContract)
import Application.Helper.FrontendContract.Surface.ContractIR

registeredFrontendSurfaceContractIR :: SurfaceContractIR
registeredFrontendSurfaceContractIR = SurfaceContractIR
    { contractSurfaces = (frontendContractIR checkedRegisteredFrontendContract).contractSurfaces
    }
