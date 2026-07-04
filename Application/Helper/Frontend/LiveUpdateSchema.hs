{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.LiveUpdateSchema
    ( FocusedFieldProtectionConfig (..)
    , LiveFragmentKey (..)
    , LiveFragmentProtection (..)
    , LiveUpdateCommand (..)
    , LiveUpdateMessage (..)
    , LiveUpdateScope (..)
    , LiveUpdateSubscription (..)
    , LiveUpdateWireFragment (..)
    , liveUpdateSchemaDeclaration
    ) where

import Application.Helper.Frontend.Codec (someFrontendCodec)
import Application.Helper.Frontend.ContractGroup (FrontendContractGroup (..),
                                                  renderFrontendContractGroup)
import Application.Helper.Frontend.Dto.LiveUpdate
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..))
import IHP.Prelude

liveUpdateSchemaDeclaration :: TypeScriptDeclaration
liveUpdateSchemaDeclaration =
    renderFrontendContractGroup FrontendContractGroup
        { contractGroupName = "LiveUpdateContracts"
        , contractGroupComment = Just "Live-update wire protocol generated from Haskell DTO codecs."
        , contractGroupCodecs =
            [ someFrontendCodec @LiveUpdateScope
            , someFrontendCodec @LiveFragmentKey
            , someFrontendCodec @LiveFragmentProtection
            , someFrontendCodec @LiveUpdateWireFragment
            , someFrontendCodec @LiveUpdateSubscription
            , someFrontendCodec @LiveUpdateCommand
            , someFrontendCodec @LiveUpdateMessage
            ]
        , contractGroupConstants = []
        }
