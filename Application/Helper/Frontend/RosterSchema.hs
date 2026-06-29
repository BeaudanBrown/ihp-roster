{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.RosterSchema
    ( rosterContractsDeclaration
    ) where

import Application.Helper.Frontend.Codec (FrontendCodec, HasFrontendCodec (..),
                                          someFrontendCodec, stringEnumCodec)
import Application.Helper.Frontend.ContractGroup (FrontendContractGroup (..),
                                                  renderFrontendContractGroup)
import Application.Helper.Frontend.RosterConstants
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..))
import IHP.Prelude

rosterContractsDeclaration :: TypeScriptDeclaration
rosterContractsDeclaration =
    renderFrontendContractGroup FrontendContractGroup
        { contractGroupName = "RosterContracts"
        , contractGroupComment = Nothing
        , contractGroupCodecs = [someFrontendCodec @RosterStaffSortKey]
        , contractGroupConstants = []
        }

instance HasFrontendCodec RosterStaffSortKey where
    frontendCodec =
        stringEnumCodec "RosterStaffSortKey" rosterStaffSortKeyValues
