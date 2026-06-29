module Application.Helper.Frontend.SurfaceManifestSchema
    ( surfaceManifestDeclaration
    ) where

import Application.Helper.Frontend.Codec (FrontendCodec (..),
                                          FrontendSchema (..),
                                          SomeFrontendCodec (..), field,
                                          nullableField, recordSchema,
                                          stringEnumCodec)
import Application.Helper.Frontend.ContractGroup (FrontendContractGroup (..),
                                                  renderFrontendContractGroup,
                                                  typedConstant)
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..))
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import IHP.Prelude
import Web.LiveSurfaceRegistry (RegisteredLiveSurfaceManifest (..),
                                registeredLiveSurfaceManifest)

surfaceManifestDeclaration :: TypeScriptDeclaration
surfaceManifestDeclaration =
    renderFrontendContractGroup FrontendContractGroup
        { contractGroupName = "LiveSurfaceManifest"
        , contractGroupComment = Just "Live-surface manifest generated from the registered Haskell surface registry."
        , contractGroupCodecs = surfaceManifestCodecs
        , contractGroupConstants = [typedConstant "LiveSurfaceManifest" liveSurfaceManifestRegistryCodec liveSurfaceManifestJson]
        }

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
liveSurfaceManifestEntryCodec = valueCodec "LiveSurfaceManifestEntry" $ recordSchema "LiveSurfaceManifestEntry"
    [ field "scopeKinds" (SchemaArray (SchemaRef "RegisteredLiveSurfaceScopeKind"))
    , field "fragmentKinds" (SchemaArray (SchemaRef "RegisteredLiveSurfaceFragmentKind"))
    , nullableField "interactionSchema" (SchemaRef "InteractionSurfaceFamily")
    ]

liveSurfaceManifestRegistryCodec :: FrontendCodec Aeson.Value
liveSurfaceManifestRegistryCodec = valueCodec "LiveSurfaceManifestRegistry" $ recordSchema "LiveSurfaceManifestRegistry"
    [ field surface.surfaceFamily (SchemaRef "LiveSurfaceManifestEntry")
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
