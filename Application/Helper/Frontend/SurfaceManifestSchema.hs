module Application.Helper.Frontend.SurfaceManifestSchema
    ( surfaceManifestDeclaration
    ) where

import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..),
                                               TypeScriptDeclarationOrigin (HaskellSchemaGenerated),
                                               stringUnionDeclaration)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude
import Web.LiveSurfaceRegistry (RegisteredLiveSurfaceManifest (..),
                                registeredLiveSurfaceManifest)

surfaceManifestDeclaration :: TypeScriptDeclaration
surfaceManifestDeclaration =
    TypeScriptDeclaration
        { name = "LiveSurfaceManifest"
        , origin = HaskellSchemaGenerated
        , source = Text.unlines
            [ "// Live-surface manifest generated from the registered Haskell surface registry."
            , stringUnionSource "LiveSurfaceFamily" (fmap (.surfaceFamily) registeredLiveSurfaceManifest)
            , stringUnionSource "RegisteredLiveSurfaceScopeKind" (unique (concatMap (.scopeKinds) registeredLiveSurfaceManifest))
            , stringUnionSource "RegisteredLiveSurfaceFragmentKind" (unique (concatMap (.fragmentKinds) registeredLiveSurfaceManifest))
            , "export const LiveSurfaceManifest = " <> encodeJsonText liveSurfaceManifestJson <> " as const;"
            , ""
            , "export type LiveSurfaceManifestRegistry = typeof LiveSurfaceManifest;"
            ]
        }

stringUnionSource :: Text -> [Text] -> Text
stringUnionSource name values =
    (stringUnionDeclaration name values).source

liveSurfaceManifestJson :: Aeson.Value
liveSurfaceManifestJson =
    Aeson.object (fmap surfacePair registeredLiveSurfaceManifest)
    where
        surfacePair surface = AesonKey.fromText surface.surfaceFamily Aeson..= surfaceJson surface

surfaceJson :: RegisteredLiveSurfaceManifest -> Aeson.Value
surfaceJson surface = Aeson.object
    [ "scopeKinds" Aeson..= surface.scopeKinds
    , "fragmentKinds" Aeson..= surface.fragmentKinds
    , "interactionSchema" Aeson..= surface.interactionSchema
    ]

encodeJsonText :: Aeson.Value -> Text
encodeJsonText = TextEncoding.decodeUtf8 . LBS.toStrict . Aeson.encode

unique :: [Text] -> [Text]
unique = foldr (\value acc -> if value `elem` acc then acc else value : acc) []
