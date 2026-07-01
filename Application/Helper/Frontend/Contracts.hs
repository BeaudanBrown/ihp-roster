{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.Contracts
    ( TypeScriptDeclaration (..)
    , frontendContractDeclarations
    , frontendContractsTypeScript
    )
where

import Application.Helper.Frontend.AppSchema (appSharedConstantsDeclaration)
import Application.Helper.Frontend.Codec (someFrontendCodec)
import Application.Helper.Frontend.ContractGroup (FrontendContractGroup (..),
                                                  renderFrontendContractGroup)
import Application.Helper.Frontend.Dto.App (OverlayLane)
import Application.Helper.Frontend.InteractionSchema (interactionSchemaDeclaration)
import Application.Helper.Frontend.LiveUpdateSchema (liveUpdateSchemaDeclaration)
import Application.Helper.Frontend.RosterSchema (rosterContractsDeclaration)
import Application.Helper.Frontend.SurfaceManifestSchema (surfaceManifestDeclaration)
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..),
                                               renderTypeScriptDeclarations)
import Application.Helper.Frontend.UiRegionSchema (uiRegionSchemaDeclaration)
import IHP.Prelude

-- Keep this module as the small composition root for frontend contracts. New
-- Haskell/TypeScript shared DTOs should be represented as Haskell-owned schema
-- declarations and formatted via Application.Helper.Frontend.TypeScript, not by
-- embedding broad TypeScript source blocks here.
overlayLaneDeclaration :: TypeScriptDeclaration
overlayLaneDeclaration =
    renderFrontendContractGroup FrontendContractGroup
        { contractGroupName = "OverlayLane"
        , contractGroupComment = Nothing
        , contractGroupCodecs = [someFrontendCodec @OverlayLane]
        , contractGroupConstants = []
        }

frontendContractDeclarations :: [TypeScriptDeclaration]
frontendContractDeclarations =
    [ overlayLaneDeclaration
    , appSharedConstantsDeclaration
    , liveUpdateSchemaDeclaration
    , interactionSchemaDeclaration
    , uiRegionSchemaDeclaration
    , rosterContractsDeclaration
    , surfaceManifestDeclaration
    ]

frontendContractsTypeScript :: Text
frontendContractsTypeScript =
    renderTypeScriptDeclarations frontendContractDeclarations
