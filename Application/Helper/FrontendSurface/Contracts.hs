module Application.Helper.FrontendSurface.Contracts
    ( frontendSurfaceContractDeclaration
    , frontendSurfaceContractDeclarationFor
    , frontendSurfaceContractsTypeScript
    , frontendSurfaceContractsTypeScriptFor
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
    frontendSurfaceContractsTypeScriptFor registeredFrontendSurfaceContractIR

frontendSurfaceContractsTypeScriptFor :: SurfaceContractIR -> Text
frontendSurfaceContractsTypeScriptFor =
    renderFrontendSurfaceContractsTypeScript

frontendSurfaceContractDeclaration :: TypeScriptDeclaration
frontendSurfaceContractDeclaration =
    frontendSurfaceContractDeclarationFor registeredFrontendSurfaceContractIR

frontendSurfaceContractDeclarationFor :: SurfaceContractIR -> TypeScriptDeclaration
frontendSurfaceContractDeclarationFor contract =
    TypeScriptDeclaration
        { name = "FrontendSurfaceContracts"
        , origin = HaskellSchemaGenerated
        , source = frontendSurfaceContractsTypeScriptFor contract
        }
