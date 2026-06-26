module Application.Helper.Frontend.RosterSchema
    ( rosterContractsDeclaration
    ) where

import Application.Helper.Frontend.Codec (FrontendCodec, SomeFrontendCodec (..),
                                          renderFrontendContracts,
                                          stringEnumCodec)
import Application.Helper.Frontend.RosterConstants
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..),
                                               TypeScriptDeclarationOrigin (HaskellSchemaGenerated))
import IHP.Prelude

rosterContractsDeclaration :: TypeScriptDeclaration
rosterContractsDeclaration =
    TypeScriptDeclaration
        { name = "RosterContracts"
        , origin = HaskellSchemaGenerated
        , source = case renderFrontendContracts [SomeFrontendCodec rosterStaffSortKeyCodec] of
            Right generated -> generated
            Left message -> error ("Unable to render roster frontend contracts: " <> cs message)
        }

rosterStaffSortKeyCodec :: FrontendCodec RosterStaffSortKey
rosterStaffSortKeyCodec =
    stringEnumCodec "RosterStaffSortKey" rosterStaffSortKeyValues
