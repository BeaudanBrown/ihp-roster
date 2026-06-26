module Application.Helper.Frontend.SurfaceManifestSchema
    ( surfaceManifestDeclaration
    ) where

import Application.Helper.Frontend.Codec (FrontendCodec (..),
                                          FrontendField (..),
                                          FrontendSchema (..),
                                          SomeFrontendCodec (..),
                                          renderFrontendContracts,
                                          renderTypedConstant, stringEnumCodec)
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..),
                                               TypeScriptDeclarationOrigin (HaskellSchemaGenerated))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Text as Text
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
            , surfaceManifestTypesSource
            , surfaceManifestConstantSource
            ]
        }

surfaceManifestTypesSource :: Text
surfaceManifestTypesSource =
    case renderFrontendContracts surfaceManifestCodecs of
        Right source -> source
        Left message -> error ("Unable to render live-surface manifest contracts: " <> cs message)

surfaceManifestConstantSource :: Text
surfaceManifestConstantSource =
    renderTypedConstant "LiveSurfaceManifest" liveSurfaceManifestRegistryCodec liveSurfaceManifestJson

surfaceManifestCodecs :: [SomeFrontendCodec]
surfaceManifestCodecs =
    [ SomeFrontendCodec liveSurfaceFamilyCodec
    , SomeFrontendCodec registeredLiveSurfaceScopeKindCodec
    , SomeFrontendCodec registeredLiveSurfaceFragmentKindCodec
    , SomeFrontendCodec liveSurfaceManifestEntryCodec
    , SomeFrontendCodec liveSurfaceManifestRegistryCodec
    ]

liveSurfaceFamilyCodec :: FrontendCodec Text
liveSurfaceFamilyCodec = textEnumCodec "LiveSurfaceFamily" (fmap (.surfaceFamily) registeredLiveSurfaceManifest)

registeredLiveSurfaceScopeKindCodec :: FrontendCodec Text
registeredLiveSurfaceScopeKindCodec = textEnumCodec "RegisteredLiveSurfaceScopeKind" (unique (concatMap (.scopeKinds) registeredLiveSurfaceManifest))

registeredLiveSurfaceFragmentKindCodec :: FrontendCodec Text
registeredLiveSurfaceFragmentKindCodec = textEnumCodec "RegisteredLiveSurfaceFragmentKind" (unique (concatMap (.fragmentKinds) registeredLiveSurfaceManifest))

liveSurfaceManifestEntryCodec :: FrontendCodec Aeson.Value
liveSurfaceManifestEntryCodec = valueCodec "LiveSurfaceManifestEntry" $ SchemaRecord "LiveSurfaceManifestEntry"
    [ FrontendField "scopeKinds" (SchemaArray (SchemaRef "RegisteredLiveSurfaceScopeKind"))
    , FrontendField "fragmentKinds" (SchemaArray (SchemaRef "RegisteredLiveSurfaceFragmentKind"))
    , FrontendField "interactionSchema" (SchemaNullable (SchemaRef "InteractionSurfaceFamily"))
    ]

liveSurfaceManifestRegistryCodec :: FrontendCodec Aeson.Value
liveSurfaceManifestRegistryCodec = valueCodec "LiveSurfaceManifestRegistry" $ SchemaRecord "LiveSurfaceManifestRegistry"
    [ FrontendField surface.surfaceFamily (SchemaRef "LiveSurfaceManifestEntry")
    | surface <- registeredLiveSurfaceManifest
    ]

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

valueCodec :: Text -> FrontendSchema -> FrontendCodec Aeson.Value
valueCodec name schema =
    FrontendCodec
        { codecName = Just name
        , codecSchema = schema
        , codecEncode = id
        , codecParse = pure
        }

textEnumCodec :: Text -> [Text] -> FrontendCodec Text
textEnumCodec name values =
    stringEnumCodec name [(value, value) | value <- values]

unique :: [Text] -> [Text]
unique = foldr (\value acc -> if value `elem` acc then acc else value : acc) []
