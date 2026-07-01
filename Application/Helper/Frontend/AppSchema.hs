{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.AppSchema
    ( appSharedConstantsDeclaration
    ) where

import Application.Helper.Frontend.AppConstants
import Application.Helper.Frontend.Codec (HasFrontendCodec (..),
                                          someFrontendCodec)
import Application.Helper.Frontend.ContractGroup (FrontendContractGroup (..),
                                                  renderFrontendContractGroup,
                                                  typedConstant)
import Application.Helper.Frontend.Dto.App ()
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..))
import IHP.Prelude

appSharedConstantsDeclaration :: TypeScriptDeclaration
appSharedConstantsDeclaration =
    renderFrontendContractGroup FrontendContractGroup
        { contractGroupName = "AppSharedConstants"
        , contractGroupComment = Just "Shared app DOM and browser event constants generated from Haskell."
        , contractGroupCodecs = [someFrontendCodec @AppOverlayDom, someFrontendCodec @AppEvents]
        , contractGroupConstants =
            [ typedConstant "AppOverlayDom" (frontendCodec @AppOverlayDom) canonicalAppOverlayDom
            , typedConstant "AppEvents" (frontendCodec @AppEvents) canonicalAppEvents
            ]
        }
