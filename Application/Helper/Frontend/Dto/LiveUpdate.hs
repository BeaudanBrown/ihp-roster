{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.Dto.LiveUpdate
    ( FocusedFieldProtectionConfig (..)
    , LiveFragmentKey (..)
    , LiveFragmentProtection (..)
    , LiveSurfaceConfig (..)
    , LiveUpdateCommand (..)
    , LiveUpdateMessage (..)
    , LiveUpdateScope (..)
    , LiveUpdateSubscription (..)
    , LiveUpdateWireFragment (..)
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
data LiveUpdateScope = LiveUpdateScope
    { surface :: !Text
    , scope   :: !Aeson.Value
    }
    deriving (Eq, Show, Generic)

data LiveFragmentKey = LiveFragmentKey
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

data LiveFragmentProtection
    = NoProtection
    | FocusedFieldProtection
        { activeSelector    :: !Text
        , fieldKeyAttr      :: !Text
        , fieldNameFallback :: !Bool
        , containerSelector :: !(Maybe Text)
        }
    deriving (Eq, Show, Generic)

data LiveUpdateWireFragment = LiveUpdateWireFragment
    { fragmentKey      :: !LiveFragmentKey
    , targetId         :: !Text
    , url              :: !Text
    , deferUntilBlur   :: !Bool
    , protectionPolicy :: !LiveFragmentProtection
    }
    deriving (Eq, Show, Generic)

data LiveUpdateSubscription = LiveUpdateSubscription
    { scope            :: !LiveUpdateScope
    , scopeKey         :: !Text
    , mountedFragments :: ![LiveUpdateWireFragment]
    }
    deriving (Eq, Show, Generic)

data LiveUpdateCommand
    = Subscribe
        { subscription    :: !LiveUpdateSubscription
        , clientId        :: !Text
        , lastSeenVersion :: !(Maybe Int)
        }
    | Unsubscribe
        { subscription :: !LiveUpdateSubscription
        }
    deriving (Eq, Show, Generic)

data LiveUpdateMessage
    = Subscribed
        { scope          :: !LiveUpdateScope
        , scopeKey       :: !Text
        , currentVersion :: !Int
        , resync         :: !Bool
        }
    | Invalidate
        { scope          :: !LiveUpdateScope
        , scopeKey       :: !Text
        , version        :: !Int
        , fragments      :: ![LiveUpdateWireFragment]
        , sourceClientId :: !(Maybe Text)
        }
    | Error
        { message :: !Text
        }
    deriving (Eq, Show, Generic)

data LiveSurfaceConfig = LiveSurfaceConfig
    { feature                :: !Text
    , socketPath             :: !Text
    , scope                  :: !LiveUpdateScope
    , scopeKey               :: !Text
    , resyncFragments        :: ![LiveUpdateWireFragment]
    , decorateRequestsWithin :: ![Text]
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

liveUpdateScopeCodec :: FrontendCodec LiveUpdateScope
liveUpdateScopeCodec = FrontendCodec
    { codecName = Just "LiveUpdateScope"
    , codecSchema = SchemaRecord "LiveUpdateScope" [FrontendField "surface" SchemaString, FrontendField "scope" jsonValueSchema]
    , codecEncode = \LiveUpdateScope { surface, scope } -> Aeson.object ["surface" Aeson..= surface, "scope" Aeson..= scope]
    , codecParse = Aeson.withObject "LiveUpdateScope" \object -> LiveUpdateScope <$> object Aeson..: "surface" <*> object Aeson..: "scope"
    }

liveFragmentKeyCodec :: FrontendCodec LiveFragmentKey
liveFragmentKeyCodec = FrontendCodec
    { codecName = Just "LiveFragmentKey"
    , codecSchema = SchemaRecord "LiveFragmentKey" [FrontendField "surface" SchemaString, FrontendField "kind" SchemaString, FrontendField "params" jsonValueSchema]
    , codecEncode = \LiveFragmentKey { surface, kind, params } -> Aeson.object ["surface" Aeson..= surface, "kind" Aeson..= kind, "params" Aeson..= params]
    , codecParse = Aeson.withObject "LiveFragmentKey" \object -> LiveFragmentKey <$> object Aeson..: "surface" <*> object Aeson..: "kind" <*> object Aeson..: "params"
    }

instance HasFrontendCodec LiveUpdateScope where
    frontendCodec = liveUpdateScopeCodec

instance HasFrontendCodec LiveFragmentKey where
    frontendCodec = liveFragmentKeyCodec

instance HasFrontendCodec FocusedFieldProtectionConfig where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "FocusedFieldProtectionConfig"
        }

instance HasFrontendCodec LiveFragmentProtection where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "LiveFragmentProtection"
        , frontendConstructorTagModifier = \case
            "NoProtection" -> "none"
            "FocusedFieldProtection" -> "focused_field"
            constructorName -> constructorName
        }

instance HasFrontendCodec LiveUpdateWireFragment where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "LiveUpdateWireFragment"
        }

instance HasFrontendCodec LiveSurfaceConfig where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "LiveSurfaceConfig"
        }

instance HasFrontendCodec LiveUpdateSubscription where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "LiveUpdateSubscription"
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

instance Aeson.ToJSON LiveUpdateScope where
    toJSON = encodeFrontend (frontendCodec @LiveUpdateScope)

instance Aeson.FromJSON LiveUpdateScope where
    parseJSON = parseFrontend (frontendCodec @LiveUpdateScope)

instance Aeson.ToJSON LiveFragmentKey where
    toJSON = encodeFrontend (frontendCodec @LiveFragmentKey)

instance Aeson.FromJSON LiveFragmentKey where
    parseJSON = parseFrontend (frontendCodec @LiveFragmentKey)

instance Aeson.ToJSON FocusedFieldProtectionConfig where
    toJSON = encodeFrontend (frontendCodec @FocusedFieldProtectionConfig)

instance Aeson.FromJSON FocusedFieldProtectionConfig where
    parseJSON = parseFrontend (frontendCodec @FocusedFieldProtectionConfig)

instance Aeson.ToJSON LiveFragmentProtection where
    toJSON = encodeFrontend (frontendCodec @LiveFragmentProtection)

instance Aeson.FromJSON LiveFragmentProtection where
    parseJSON = parseFrontend (frontendCodec @LiveFragmentProtection)

instance Aeson.ToJSON LiveUpdateWireFragment where
    toJSON = encodeFrontend (frontendCodec @LiveUpdateWireFragment)

instance Aeson.FromJSON LiveUpdateWireFragment where
    parseJSON = parseFrontend (frontendCodec @LiveUpdateWireFragment)

instance Aeson.ToJSON LiveUpdateSubscription where
    toJSON = encodeFrontend (frontendCodec @LiveUpdateSubscription)

instance Aeson.FromJSON LiveUpdateSubscription where
    parseJSON = parseFrontend (frontendCodec @LiveUpdateSubscription)

instance Aeson.ToJSON LiveUpdateCommand where
    toJSON = encodeFrontend (frontendCodec @LiveUpdateCommand)

instance Aeson.FromJSON LiveUpdateCommand where
    parseJSON = parseFrontend (frontendCodec @LiveUpdateCommand)

instance Aeson.ToJSON LiveUpdateMessage where
    toJSON = encodeFrontend (frontendCodec @LiveUpdateMessage)

instance Aeson.FromJSON LiveUpdateMessage where
    parseJSON = parseFrontend (frontendCodec @LiveUpdateMessage)

instance Aeson.ToJSON LiveSurfaceConfig where
    toJSON = encodeFrontend (frontendCodec @LiveSurfaceConfig)

instance Aeson.FromJSON LiveSurfaceConfig where
    parseJSON = parseFrontend (frontendCodec @LiveSurfaceConfig)
