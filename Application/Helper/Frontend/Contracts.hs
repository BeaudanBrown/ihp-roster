module Application.Helper.Frontend.Contracts
    ( TypeScriptDeclaration (..)
    , frontendContractDeclarations
    , frontendContractsTypeScript
    )
where

import Application.Helper.Frontend.AesonTypeScriptSpike (aesonTypeScriptSpikeDeclaration)
import Application.Helper.Frontend.InteractionSchema (interactionSchemaDeclaration)
import Application.Helper.Frontend.LiveUpdateSchema (liveUpdateSchemaDeclaration)
import Application.Helper.Frontend.SurfaceManifestSchema (surfaceManifestDeclaration)
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..),
                                               renderTypeScriptDeclarations,
                                               stringUnionDeclaration)
import IHP.Prelude

-- Keep this module as the small composition root for frontend contracts. New
-- Haskell/TypeScript shared DTOs should be represented as Haskell-owned schema
-- declarations and formatted via Application.Helper.Frontend.TypeScript, not by
-- embedding broad TypeScript source blocks here.
data OverlayLane
    = DialogLane
    | PickerLane
    | ToastLane
    deriving (Eq, Show)

overlayLaneTypeName :: Text
overlayLaneTypeName = "OverlayLane"

overlayLaneValues :: [(OverlayLane, Text)]
overlayLaneValues =
    [ (DialogLane, "dialog")
    , (PickerLane, "picker")
    , (ToastLane, "toast")
    ]

frontendContractDeclarations :: [TypeScriptDeclaration]
frontendContractDeclarations =
    [ stringUnionDeclaration overlayLaneTypeName (fmap snd overlayLaneValues)
    , liveUpdateSchemaDeclaration
    , interactionSchemaDeclaration
    , surfaceManifestDeclaration
    , aesonTypeScriptSpikeDeclaration
    ]

frontendContractsTypeScript :: Text
frontendContractsTypeScript =
    renderTypeScriptDeclarations frontendContractDeclarations
