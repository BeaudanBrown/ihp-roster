{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.Dto.LiveUpdate
    ( FocusedFieldProtectionConfig (..)
    , SurfaceFragmentKey (..)
    , SurfaceFragmentProtection (..)
    , LiveUpdateCommand (..)
    , LiveUpdateMessage (..)
    , SurfaceScope (..)
    , SurfaceSubscription (..)
    , SurfaceWireFragment (..)
    ) where

import Application.Helper.Frontend.Codec (FrontendCodec (..),
                                          FrontendField (..),
                                          FrontendSchema (..),
                                          HasFrontendCodec (..), encodeFrontend,
                                          parseFrontend)
import Application.Helper.Frontend.Generic (genericFrontendCodecWith)
import Application.Helper.Frontend.Options (FrontendCodecOptions (..),
                                            defaultFrontendCodecOptions)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import GHC.Generics (Generic)
import IHP.Prelude

-- Surface-native live transport. The surface/scope/fragment names are generated
-- kebab-case FrontendSurface names; scope and params are generated surface DTO
-- payloads owned by the FrontendSurface contract.
data SurfaceScope = SurfaceScope
    { surface :: !Text
    , scope   :: !Aeson.Value
    }
    deriving (Eq, Show, Generic)

data SurfaceFragmentKey = SurfaceFragmentKey
    { surface :: !Text
    , kind    :: !Text
    , params  :: !Aeson.Value
    }
    deriving (Eq, Show, Generic)

data FocusedFieldProtectionConfig = FocusedFieldProtectionConfig
    { activeSelector    :: !Text
    , fieldKeyAttr      :: !Text
    , fieldNameFallback :: !Bool
    , containerSelector :: !(Maybe Text)
    }
    deriving (Eq, Show, Generic)

data SurfaceFragmentProtection
    = NoProtection
    | FocusedFieldProtection
        { activeSelector    :: !Text
        , fieldKeyAttr      :: !Text
        , fieldNameFallback :: !Bool
        , containerSelector :: !(Maybe Text)
        }
    deriving (Eq, Show, Generic)

data SurfaceWireFragment = SurfaceWireFragment
    { fragmentKey      :: !SurfaceFragmentKey
    , targetId         :: !Text
    , url              :: !Text
    , deferUntilBlur   :: !Bool
    , protectionPolicy :: !SurfaceFragmentProtection
    }
    deriving (Eq, Show, Generic)

data SurfaceSubscription = SurfaceSubscription
    { scope            :: !SurfaceScope
    , scopeKey         :: !Text
    , mountedFragments :: ![SurfaceWireFragment]
    }
    deriving (Eq, Show, Generic)

data LiveUpdateCommand
    = Subscribe
        { subscription    :: !SurfaceSubscription
        , clientId        :: !Text
        , lastSeenVersion :: !(Maybe Int)
        }
    | Unsubscribe
        { subscription :: !SurfaceSubscription
        }
    deriving (Eq, Show, Generic)

data LiveUpdateMessage
    = Subscribed
        { scope          :: !SurfaceScope
        , scopeKey       :: !Text
        , currentVersion :: !Int
        , resync         :: !Bool
        }
    | Invalidate
        { scope          :: !SurfaceScope
        , scopeKey       :: !Text
        , version        :: !Int
        , fragments      :: ![SurfaceWireFragment]
        , sourceClientId :: !(Maybe Text)
        }
    | Error
        { message :: !Text
        }
    deriving (Eq, Show, Generic)

jsonValueSchema :: FrontendSchema
jsonValueSchema = SchemaUnknown

jsonValueCodec :: FrontendCodec Aeson.Value
jsonValueCodec = FrontendCodec
    { codecName = Nothing
    , codecSchema = jsonValueSchema
    , codecEncode = id
    , codecParse = pure
    }

surfaceScopeCodec :: FrontendCodec SurfaceScope
surfaceScopeCodec = FrontendCodec
    { codecName = Just "SurfaceScope"
    , codecSchema = SchemaRecord "SurfaceScope" [FrontendField "surface" SchemaString, FrontendField "scope" jsonValueSchema]
    , codecEncode = \SurfaceScope { surface, scope } -> Aeson.object ["surface" Aeson..= surface, "scope" Aeson..= scope]
    , codecParse = Aeson.withObject "SurfaceScope" \object -> SurfaceScope <$> object Aeson..: "surface" <*> object Aeson..: "scope"
    }

surfaceFragmentKeyCodec :: FrontendCodec SurfaceFragmentKey
surfaceFragmentKeyCodec = FrontendCodec
    { codecName = Just "SurfaceFragmentKey"
    , codecSchema = SchemaRecord "SurfaceFragmentKey" [FrontendField "surface" SchemaString, FrontendField "kind" SchemaString, FrontendField "params" jsonValueSchema]
    , codecEncode = \SurfaceFragmentKey { surface, kind, params } -> Aeson.object ["surface" Aeson..= surface, "kind" Aeson..= kind, "params" Aeson..= params]
    , codecParse = Aeson.withObject "SurfaceFragmentKey" \object -> SurfaceFragmentKey <$> object Aeson..: "surface" <*> object Aeson..: "kind" <*> object Aeson..: "params"
    }

instance HasFrontendCodec SurfaceScope where
    frontendCodec = surfaceScopeCodec

instance HasFrontendCodec SurfaceFragmentKey where
    frontendCodec = surfaceFragmentKeyCodec

instance HasFrontendCodec FocusedFieldProtectionConfig where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "FocusedFieldProtectionConfig"
        }

instance HasFrontendCodec SurfaceFragmentProtection where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "SurfaceFragmentProtection"
        , frontendConstructorTagModifier = \case
            "NoProtection" -> "none"
            "FocusedFieldProtection" -> "focused_field"
            constructorName -> constructorName
        }

instance HasFrontendCodec SurfaceWireFragment where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "SurfaceWireFragment"
        }

instance HasFrontendCodec SurfaceSubscription where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "SurfaceSubscription"
        }

instance HasFrontendCodec LiveUpdateCommand where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "LiveUpdateCommand"
        , frontendTaggedUnionTagField = "type"
        }

instance HasFrontendCodec LiveUpdateMessage where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "LiveUpdateMessage"
        , frontendTaggedUnionTagField = "type"
        }

instance Aeson.ToJSON SurfaceScope where
    toJSON = encodeFrontend (frontendCodec @SurfaceScope)

instance Aeson.FromJSON SurfaceScope where
    parseJSON = parseFrontend (frontendCodec @SurfaceScope)

instance Aeson.ToJSON SurfaceFragmentKey where
    toJSON = encodeFrontend (frontendCodec @SurfaceFragmentKey)

instance Aeson.FromJSON SurfaceFragmentKey where
    parseJSON = parseFrontend (frontendCodec @SurfaceFragmentKey)

instance Aeson.ToJSON FocusedFieldProtectionConfig where
    toJSON = encodeFrontend (frontendCodec @FocusedFieldProtectionConfig)

instance Aeson.FromJSON FocusedFieldProtectionConfig where
    parseJSON = parseFrontend (frontendCodec @FocusedFieldProtectionConfig)

instance Aeson.ToJSON SurfaceFragmentProtection where
    toJSON = encodeFrontend (frontendCodec @SurfaceFragmentProtection)

instance Aeson.FromJSON SurfaceFragmentProtection where
    parseJSON = parseFrontend (frontendCodec @SurfaceFragmentProtection)

instance Aeson.ToJSON SurfaceWireFragment where
    toJSON = encodeFrontend (frontendCodec @SurfaceWireFragment)

instance Aeson.FromJSON SurfaceWireFragment where
    parseJSON = parseFrontend (frontendCodec @SurfaceWireFragment)

instance Aeson.ToJSON SurfaceSubscription where
    toJSON = encodeFrontend (frontendCodec @SurfaceSubscription)

instance Aeson.FromJSON SurfaceSubscription where
    parseJSON = parseFrontend (frontendCodec @SurfaceSubscription)

instance Aeson.ToJSON LiveUpdateCommand where
    toJSON = encodeFrontend (frontendCodec @LiveUpdateCommand)

instance Aeson.FromJSON LiveUpdateCommand where
    parseJSON = parseFrontend (frontendCodec @LiveUpdateCommand)

instance Aeson.ToJSON LiveUpdateMessage where
    toJSON = encodeFrontend (frontendCodec @LiveUpdateMessage)

instance Aeson.FromJSON LiveUpdateMessage where
    parseJSON = parseFrontend (frontendCodec @LiveUpdateMessage)

