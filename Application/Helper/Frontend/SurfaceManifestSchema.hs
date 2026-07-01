{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.SurfaceManifestSchema
    ( surfaceManifestDeclaration
    ) where

import Application.Helper.Frontend.Codec (HasFrontendCodec (..),
                                          SomeFrontendCodec, someFrontendCodec)
import Application.Helper.Frontend.ContractGroup (FrontendContractGroup (..),
                                                  renderFrontendContractGroup,
                                                  typedConstant)
import qualified Application.Helper.Frontend.Dto.LiveSurface as Dto
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..))
import IHP.Prelude

surfaceManifestDeclaration :: TypeScriptDeclaration
surfaceManifestDeclaration =
    renderFrontendContractGroup FrontendContractGroup
        { contractGroupName = "LiveSurfaceManifest"
        , contractGroupComment = Just "Live-surface manifest generated from the registered Haskell surface registry."
        , contractGroupCodecs = surfaceManifestCodecs
        , contractGroupConstants = [typedConstant "LiveSurfaceManifest" (frontendCodec @Dto.LiveSurfaceManifestRegistry) Dto.liveSurfaceManifestDto]
        }

surfaceManifestCodecs :: [SomeFrontendCodec]
surfaceManifestCodecs =
    [ someFrontendCodec @Dto.LiveSurfaceFamily
    , someFrontendCodec @Dto.RegisteredLiveSurfaceScopeKind
    , someFrontendCodec @Dto.RegisteredLiveSurfaceFragmentKind
    , someFrontendCodec @Dto.LiveSurfaceManifestEntry
    , someFrontendCodec @Dto.LiveSurfaceManifestRegistry
    ]
