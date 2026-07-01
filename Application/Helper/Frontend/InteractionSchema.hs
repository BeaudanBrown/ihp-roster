{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.InteractionSchema
    ( interactionSchemaDeclaration
    ) where

import Application.Helper.Frontend.Codec (HasFrontendCodec (..),
                                          SomeFrontendCodec (..),
                                          someFrontendCodec)
import Application.Helper.Frontend.ContractGroup (FrontendContractGroup (..),
                                                  renderFrontendContractGroup,
                                                  typedConstant)
import qualified Application.Helper.Frontend.Dto.Interaction as Dto
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..))
import IHP.Prelude

interactionSchemaDeclaration :: TypeScriptDeclaration
interactionSchemaDeclaration =
    renderFrontendContractGroup FrontendContractGroup
        { contractGroupName = "InteractionContracts"
        , contractGroupComment = Just "Interaction contracts generated from Haskell static interaction schemas."
        , contractGroupCodecs = interactionContractCodecs
        , contractGroupConstants =
            [ typedConstant "InteractionDom" (frontendCodec @Dto.InteractionDom) Dto.canonicalInteractionDomDto
            , typedConstant "InteractionStaticSchemas" (frontendCodec @Dto.InteractionStaticSchemaRegistry) Dto.interactionStaticSchemasDto
            ]
        }

interactionContractCodecs :: [SomeFrontendCodec]
interactionContractCodecs =
    [ someFrontendCodec @Dto.InteractionDomAttributes
    , someFrontendCodec @Dto.InteractionDomValues
    , someFrontendCodec @Dto.InteractionPointerFields
    , someFrontendCodec @Dto.InteractionDom
    , someFrontendCodec @Dto.InteractionDomAttribute
    , someFrontendCodec @Dto.InteractionActivationTrigger
    , someFrontendCodec @Dto.InteractionFieldPresence
    , someFrontendCodec @Dto.HtmxMethod
    , someFrontendCodec @Dto.HtmxSwap
    , someFrontendCodec @Dto.InteractionConflictResolution
    , someFrontendCodec @Dto.InteractionSurfaceFamily
    , someFrontendCodec @Dto.InteractionDisposableLayerName
    , someFrontendCodec @Dto.InteractionSessionKindName
    , someFrontendCodec @Dto.InteractionIntentName
    , someFrontendCodec @Dto.InteractionIntentFieldName
    , someFrontendCodec @Dto.InteractionSessionSelector
    , someFrontendCodec @Dto.InteractionFragmentSelector
    , someFrontendCodec @Dto.InteractionMountMetadata
    , someFrontendCodec @Dto.ServerLayerContract
    , someFrontendCodec @Dto.DisposableLayerContract
    , someFrontendCodec @Dto.SessionKindContract
    , someFrontendCodec @Dto.IntentFieldSchema
    , someFrontendCodec @Dto.IntentHiddenField
    , someFrontendCodec @Dto.InteractionIntentTarget
    , someFrontendCodec @Dto.IntentFormContract
    , someFrontendCodec @Dto.InteractionConflictPolicy
    , someFrontendCodec @Dto.InteractionCapabilityContract
    , someFrontendCodec @Dto.InteractionStaticServerLayer
    , someFrontendCodec @Dto.InteractionStaticDisposableLayer
    , someFrontendCodec @Dto.InteractionStaticSessionKind
    , someFrontendCodec @Dto.InteractionStaticIntent
    , someFrontendCodec @Dto.InteractionStaticSchema
    , someFrontendCodec @Dto.InteractionStaticSchemaRegistry
    ]
