{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.LiveUpdateSchema
    ( FocusedFieldProtectionConfig (..)
    , SurfaceFragmentKey (..)
    , SurfaceFragmentProtection (..)
    , LiveUpdateCommand (..)
    , LiveUpdateMessage (..)
    , SurfaceScope (..)
    , SurfaceSubscription (..)
    , SurfaceWireFragment (..)
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
        { contractGroupName = "SurfaceLiveUpdateContracts"
        , contractGroupComment = Just "Live-update wire protocol generated from Haskell DTO codecs."
        , contractGroupCodecs =
            [ someFrontendCodec @SurfaceScope
            , someFrontendCodec @SurfaceFragmentKey
            , someFrontendCodec @SurfaceFragmentProtection
            , someFrontendCodec @SurfaceWireFragment
            , someFrontendCodec @SurfaceSubscription
            , someFrontendCodec @LiveUpdateCommand
            , someFrontendCodec @LiveUpdateMessage
            ]
        , contractGroupConstants = []
        }
