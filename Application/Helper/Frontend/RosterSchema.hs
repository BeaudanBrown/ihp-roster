{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.RosterSchema
    ( rosterContractsDeclaration
    ) where

import Application.Helper.Frontend.Codec (someFrontendCodec)
import Application.Helper.Frontend.ContractGroup (FrontendContractGroup (..),
                                                  renderFrontendContractGroup)
import Application.Helper.Frontend.Dto.Roster ()
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
