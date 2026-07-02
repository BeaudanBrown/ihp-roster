module Application.Helper.FrontendSurface.Contracts
    ( frontendSurfaceContractDeclaration
    , frontendSurfaceContractsTypeScript
    , registeredFrontendSurfaceContractIR
    ) where

import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..),
                                               TypeScriptDeclarationOrigin (..))
import Application.Helper.FrontendSurface.ContractIR
import Application.Helper.FrontendSurface.Reflect (reflectRegisteredFrontendSurfaces)
import Application.Helper.FrontendSurface.TypeScript (renderFrontendSurfaceContractsTypeScript)
import IHP.Prelude

registeredFrontendSurfaceContractIR :: SurfaceContractIR
registeredFrontendSurfaceContractIR =
    case checkedSurfaceContractIR reflectRegisteredFrontendSurfaces of
        Right contract -> contract
        Left diagnostics -> error (cs ("invalid FrontendSurface contract registry: " <> tshow diagnostics))

frontendSurfaceContractsTypeScript :: Text
frontendSurfaceContractsTypeScript =
    renderFrontendSurfaceContractsTypeScript registeredFrontendSurfaceContractIR

frontendSurfaceContractDeclaration :: TypeScriptDeclaration
frontendSurfaceContractDeclaration =
    TypeScriptDeclaration
        { name = "FrontendSurfaceContracts"
        , origin = HaskellSchemaGenerated
        , source = frontendSurfaceContractsTypeScript
        }
