module Application.Helper.FrontendContract.Surface.Identity.Registered
    ( canonicalFrontendSurfaceScopeKey
    ) where

import Application.Error.Parser (parserFailure)
import qualified Application.Helper.FrontendContract.IR as Contract
import Application.Helper.FrontendContract.Registry (checkedRegisteredFrontendContract)
import Application.Helper.FrontendContract.Surface.Identity (canonicalFrontendSurfaceScopeKeyFromFields)
import Application.Helper.FrontendContract.Wire.Json (validateSurfaceScopeValue)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import IHP.Prelude

-- | Derive transport identity from the startup-checked production registry.
-- Marker-indexed request adapters use the registry-free Identity module.
canonicalFrontendSurfaceScopeKey :: Text -> Aeson.Value -> Aeson.Parser Text
canonicalFrontendSurfaceScopeKey surfaceName scopePayload = do
    validateSurfaceScopeValue (Aeson.object ["surface" Aeson..= surfaceName, "scope" Aeson..= scopePayload])
    surface <-
        maybe
            (parserFailure ("Unknown frontend Surface scope: " <> cs surfaceName))
            pure
            (find ((== surfaceName) . (.surfaceName)) checkedContractIR.contractSurfaces)
    fields <-
        case surface.surfaceScopes of
            [scope] -> pure scope.scopeFields
            [] -> parserFailure ("Frontend Surface has no registered scope: " <> cs surfaceName)
            _ -> parserFailure ("Frontend Surface has multiple registered scopes: " <> cs surfaceName)
    canonicalFrontendSurfaceScopeKeyFromFields surfaceName fields scopePayload
  where
    checkedContractIR = Contract.frontendContractIR checkedRegisteredFrontendContract
