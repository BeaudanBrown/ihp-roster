module Application.Helper.Frontend.Contracts
    ( TypeScriptDeclaration (..)
    , frontendContractDeclarations
    , frontendContractsTypeScript
    )
where

import Application.Helper.Frontend.AesonTypeScriptSpike (aesonTypeScriptSpikeDeclaration)
import Application.Helper.Frontend.LegacyManualContracts (interactionContracts,
                                                          liveUpdateContracts)
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
    -- Legacy manual compatibility blocks are isolated in
    -- Application.Helper.Frontend.LegacyManualContracts until ir-k3q0/ir-bfj9
    -- migrate live-update and interaction contracts onto generated schemas.
    , liveUpdateContracts
    , interactionContracts
    , aesonTypeScriptSpikeDeclaration
    ]

frontendContractsTypeScript :: Text
frontendContractsTypeScript =
    renderTypeScriptDeclarations frontendContractDeclarations
