module Application.Helper.Frontend.Contracts
    ( TypeScriptDeclaration (..)
    , frontendContractDeclarations
    , frontendContractsTypeScript
    )
where

import Application.Helper.Frontend.AppSchema (appSharedConstantsDeclaration)
import Application.Helper.Frontend.Codec (FrontendCodec, SomeFrontendCodec (..),
                                          renderFrontendContracts,
                                          stringEnumCodec)
import Application.Helper.Frontend.InteractionSchema (interactionSchemaDeclaration)
import Application.Helper.Frontend.LiveUpdateSchema (liveUpdateSchemaDeclaration)
import Application.Helper.Frontend.RosterSchema (rosterContractsDeclaration)
import Application.Helper.Frontend.SurfaceManifestSchema (surfaceManifestDeclaration)
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..),
                                               TypeScriptDeclarationOrigin (HaskellSchemaGenerated),
                                               renderTypeScriptDeclarations)
import Application.Helper.Frontend.UiRegionSchema (uiRegionSchemaDeclaration)
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

overlayLaneCodec :: FrontendCodec OverlayLane
overlayLaneCodec =
    stringEnumCodec "OverlayLane"
        [ (DialogLane, "dialog")
        , (PickerLane, "picker")
        , (ToastLane, "toast")
        ]

overlayLaneDeclaration :: TypeScriptDeclaration
overlayLaneDeclaration =
    TypeScriptDeclaration
        { name = "OverlayLane"
        , origin = HaskellSchemaGenerated
        , source = case renderFrontendContracts [SomeFrontendCodec overlayLaneCodec] of
            Right generated -> generated
            Left message -> error ("Unable to render OverlayLane contract: " <> cs message)
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
