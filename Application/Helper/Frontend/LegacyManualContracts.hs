module Application.Helper.Frontend.LegacyManualContracts
    ( legacyManualContracts
    ) where

import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration,
                                               legacyManualDeclaration)
import IHP.Prelude

-- Compatibility module kept only so guard tests can assert that old handwritten
-- Haskell-owned frontend DTO blocks do not return. Live-update contracts and
-- interaction contracts are generated from Haskell schemas.
legacyManualContracts :: TypeScriptDeclaration
legacyManualContracts = legacyManualDeclaration "LegacyManualContracts" ""
