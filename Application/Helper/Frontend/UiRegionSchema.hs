{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.UiRegionSchema
    ( uiRegionSchemaDeclaration
    ) where

import Application.Helper.Frontend.Codec (HasFrontendCodec (..),
                                          someFrontendCodec)
import Application.Helper.Frontend.ContractGroup (FrontendContractGroup (..),
                                                  renderFrontendContractGroup,
                                                  typedConstant)
import Application.Helper.Frontend.Dto.UiRegion (UiRegionEvents,
                                                 canonicalUiRegionEvents)
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..))
import Application.Helper.UiRegion
import IHP.Prelude

uiRegionSchemaDeclaration :: TypeScriptDeclaration
uiRegionSchemaDeclaration =
    renderFrontendContractGroup FrontendContractGroup
        { contractGroupName = "UiRegionContracts"
        , contractGroupComment = Just "UI region capability vocabulary generated from Haskell."
        , contractGroupCodecs =
            [ someFrontendCodec @UiRegionDomAttributes
            , someFrontendCodec @UiRegionTransitionProfile
            , someFrontendCodec @UiRegionLifecycleEvent
            , someFrontendCodec @UiRegionEvents
            ]
        , contractGroupConstants =
            [ typedConstant "UiRegionDom" (frontendCodec @UiRegionDomAttributes) canonicalUiRegionDomAttributes
            , typedConstant "UiRegionEvents" (frontendCodec @UiRegionEvents) canonicalUiRegionEvents
            ]
        }
