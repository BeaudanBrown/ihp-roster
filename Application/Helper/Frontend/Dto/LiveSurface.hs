{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.Dto.LiveSurface
    ( LiveSurfaceFamily (..)
    , LiveSurfaceManifestEntry (..)
    , LiveSurfaceManifestRegistry (..)
    , RegisteredLiveSurfaceFragmentKind (..)
    , RegisteredLiveSurfaceScopeKind (..)
    , liveSurfaceFamilyValues
    , liveSurfaceManifestDto
    , registeredLiveSurfaceFragmentKindValues
    , registeredLiveSurfaceScopeKindValues
    ) where

import Application.Helper.Frontend.Codec (FrontendCodec (..),
                                          FrontendSchema (..),
                                          HasFrontendCodec (..), encodeFrontend,
                                          parseFrontend)
import qualified Application.Helper.Frontend.Dto.Interaction as InteractionDto
import Application.Helper.Frontend.Generic (genericFrontendCodecWith)
import Application.Helper.Frontend.Options (FrontendCodecOptions (..),
                                            defaultFrontendCodecOptions)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.KeyMap as AesonKeyMap
import qualified Data.Aeson.Types as AesonTypes
import GHC.Generics (Generic)
import IHP.Prelude

newtype LiveSurfaceFamily = LiveSurfaceFamily { unLiveSurfaceFamily :: Text }
    deriving (Eq, Show)

newtype RegisteredLiveSurfaceScopeKind = RegisteredLiveSurfaceScopeKind { unRegisteredLiveSurfaceScopeKind :: Text }
    deriving (Eq, Show)

newtype RegisteredLiveSurfaceFragmentKind = RegisteredLiveSurfaceFragmentKind { unRegisteredLiveSurfaceFragmentKind :: Text }
    deriving (Eq, Show)

data LiveSurfaceManifestEntry = LiveSurfaceManifestEntry
    { scopeKinds        :: ![RegisteredLiveSurfaceScopeKind]
    , fragmentKinds     :: ![RegisteredLiveSurfaceFragmentKind]
    , interactionSchema :: !(Maybe InteractionDto.InteractionSurfaceFamily)
    }
    deriving (Eq, Show, Generic)

newtype LiveSurfaceManifestRegistry = LiveSurfaceManifestRegistry
    { unLiveSurfaceManifestRegistry :: [(LiveSurfaceFamily, LiveSurfaceManifestEntry)] }
    deriving (Eq, Show)

instance HasFrontendCodec LiveSurfaceFamily where
    frontendCodec = textNewtypeEnumCodec "LiveSurfaceFamily" liveSurfaceFamilyValues LiveSurfaceFamily unLiveSurfaceFamily

instance HasFrontendCodec RegisteredLiveSurfaceScopeKind where
    frontendCodec = textNewtypeEnumCodec "RegisteredLiveSurfaceScopeKind" registeredLiveSurfaceScopeKindValues RegisteredLiveSurfaceScopeKind unRegisteredLiveSurfaceScopeKind

instance HasFrontendCodec RegisteredLiveSurfaceFragmentKind where
    frontendCodec = textNewtypeEnumCodec "RegisteredLiveSurfaceFragmentKind" registeredLiveSurfaceFragmentKindValues RegisteredLiveSurfaceFragmentKind unRegisteredLiveSurfaceFragmentKind

instance HasFrontendCodec LiveSurfaceManifestEntry where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "LiveSurfaceManifestEntry" }

instance HasFrontendCodec LiveSurfaceManifestRegistry where
    frontendCodec = FrontendCodec
        { codecName = Just "LiveSurfaceManifestRegistry"
        , codecSchema = SchemaPartialRecord (SchemaRef "LiveSurfaceFamily") (SchemaRef "LiveSurfaceManifestEntry")
        , codecEncode = encodeRegistry
        , codecParse = parseRegistry
        }

liveSurfaceManifestDto :: LiveSurfaceManifestRegistry
liveSurfaceManifestDto = LiveSurfaceManifestRegistry []

encodeRegistry :: LiveSurfaceManifestRegistry -> Aeson.Value
encodeRegistry (LiveSurfaceManifestRegistry entries) =
    Aeson.object
        [ AesonKey.fromText family.unLiveSurfaceFamily Aeson..= encodeFrontend (frontendCodec @LiveSurfaceManifestEntry) entry
        | (family, entry) <- entries
        ]

parseRegistry :: Aeson.Value -> AesonTypes.Parser LiveSurfaceManifestRegistry
parseRegistry = Aeson.withObject "LiveSurfaceManifestRegistry" \object -> do
    entries <- forM (AesonKeyMap.toList object) \(key, value) -> do
        family <- parseFrontend (frontendCodec @LiveSurfaceFamily) (Aeson.String (AesonKey.toText key))
        entry <- parseFrontend (frontendCodec @LiveSurfaceManifestEntry) value
        pure (family, entry)
    pure (LiveSurfaceManifestRegistry entries)

liveSurfaceFamilyValues :: [Text]
liveSurfaceFamilyValues = []

registeredLiveSurfaceScopeKindValues :: [Text]
registeredLiveSurfaceScopeKindValues = []

registeredLiveSurfaceFragmentKindValues :: [Text]
registeredLiveSurfaceFragmentKindValues = []

textNewtypeEnumCodec :: Text -> [Text] -> (Text -> a) -> (a -> Text) -> FrontendCodec a
textNewtypeEnumCodec name values construct unwrap = FrontendCodec
    { codecName = Just name
    , codecSchema = SchemaStringEnum name values
    , codecEncode = Aeson.String . unwrap
    , codecParse = Aeson.withText (cs name) \value ->
        if value `elem` values
            then pure (construct value)
            else fail ("Unknown " <> cs name <> ": " <> cs value)
    }

unique :: [Text] -> [Text]
unique = foldr (\value acc -> if value `elem` acc then acc else value : acc) []
