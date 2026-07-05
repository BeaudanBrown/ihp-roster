{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.FrontendContract.Wire.LiveUpdate
    ( FocusedFieldProtectionConfig (..)
    , SurfaceFragmentKey (..)
    , SurfaceFragmentProtection (..)
    , LiveUpdateCommand (..)
    , LiveUpdateMessage (..)
    , SurfaceScope (..)
    , SurfaceSubscription (..)
    , SurfaceWireFragment (..)
    ) where

import Application.Helper.FrontendContract.Wire.Json (validateContractValue,
                                                      validateSurfaceFragmentKeyValue,
                                                      validateSurfaceScopeValue)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as AesonTypes
import IHP.Prelude

-- Surface-native live transport. The surface/scope/fragment names and payloads
-- are validated against the FrontendContract registry. These runtime types are
-- JSON plumbing only; the browser-visible contract shape is owned by
-- Application.Helper.FrontendContract.LiveUpdate and registered Surface roots.
data SurfaceScope = SurfaceScope
    { surface :: !Text
    , scope   :: !Aeson.Value
    }
    deriving (Eq, Show)

data SurfaceFragmentKey = SurfaceFragmentKey
    { surface :: !Text
    , kind    :: !Text
    , params  :: !Aeson.Value
    }
    deriving (Eq, Show)

data FocusedFieldProtectionConfig = FocusedFieldProtectionConfig
    { activeSelector    :: !Text
    , fieldKeyAttr      :: !Text
    , fieldNameFallback :: !Bool
    , containerSelector :: !(Maybe Text)
    }
    deriving (Eq, Show)

data SurfaceFragmentProtection
    = NoProtection
    | FocusedFieldProtection
        { activeSelector    :: !Text
        , fieldKeyAttr      :: !Text
        , fieldNameFallback :: !Bool
        , containerSelector :: !(Maybe Text)
        }
    deriving (Eq, Show)

data SurfaceWireFragment = SurfaceWireFragment
    { fragmentKey      :: !SurfaceFragmentKey
    , targetId         :: !Text
    , url              :: !Text
    , deferUntilBlur   :: !Bool
    , protectionPolicy :: !SurfaceFragmentProtection
    }
    deriving (Eq, Show)

data SurfaceSubscription = SurfaceSubscription
    { scope            :: !SurfaceScope
    , scopeKey         :: !Text
    , mountedFragments :: ![SurfaceWireFragment]
    }
    deriving (Eq, Show)

data LiveUpdateCommand
    = Subscribe
        { subscription    :: !SurfaceSubscription
        , clientId        :: !Text
        , lastSeenVersion :: !(Maybe Int)
        }
    | Unsubscribe
        { subscription :: !SurfaceSubscription
        }
    deriving (Eq, Show)

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
    deriving (Eq, Show)

instance Aeson.ToJSON SurfaceScope where
    toJSON SurfaceScope { surface, scope } = Aeson.object
        [ "surface" Aeson..= surface
        , "scope" Aeson..= scope
        ]

instance Aeson.FromJSON SurfaceScope where
    parseJSON = Aeson.withObject "SurfaceScope" \object -> do
        value <- SurfaceScope <$> object Aeson..: "surface" <*> object Aeson..: "scope"
        validateSurfaceScope value
        pure value

instance Aeson.ToJSON SurfaceFragmentKey where
    toJSON SurfaceFragmentKey { surface, kind, params } = Aeson.object
        [ "surface" Aeson..= surface
        , "kind" Aeson..= kind
        , "params" Aeson..= params
        ]

instance Aeson.FromJSON SurfaceFragmentKey where
    parseJSON = Aeson.withObject "SurfaceFragmentKey" \object -> do
        value <- SurfaceFragmentKey <$> object Aeson..: "surface" <*> object Aeson..: "kind" <*> object Aeson..: "params"
        validateSurfaceFragmentKey value
        pure value

instance Aeson.ToJSON FocusedFieldProtectionConfig where
    toJSON FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector } = Aeson.object
        [ "activeSelector" Aeson..= activeSelector
        , "fieldKeyAttr" Aeson..= fieldKeyAttr
        , "fieldNameFallback" Aeson..= fieldNameFallback
        , "containerSelector" Aeson..= containerSelector
        ]

instance Aeson.FromJSON FocusedFieldProtectionConfig where
    parseJSON = Aeson.withObject "FocusedFieldProtectionConfig" \object ->
        FocusedFieldProtectionConfig
            <$> object Aeson..: "activeSelector"
            <*> object Aeson..: "fieldKeyAttr"
            <*> object Aeson..: "fieldNameFallback"
            <*> object Aeson..: "containerSelector"

instance Aeson.ToJSON SurfaceFragmentProtection where
    toJSON NoProtection = Aeson.object ["kind" Aeson..= ("none" :: Text)]
    toJSON FocusedFieldProtection { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector } = Aeson.object
        [ "kind" Aeson..= ("focused-field" :: Text)
        , "activeSelector" Aeson..= activeSelector
        , "fieldKeyAttr" Aeson..= fieldKeyAttr
        , "fieldNameFallback" Aeson..= fieldNameFallback
        , "containerSelector" Aeson..= containerSelector
        ]

instance Aeson.FromJSON SurfaceFragmentProtection where
    parseJSON = Aeson.withObject "SurfaceFragmentProtection" \object -> do
        kind <- object Aeson..: "kind" :: AesonTypes.Parser Text
        case kind of
            "none" -> pure NoProtection
            "focused-field" -> FocusedFieldProtection
                <$> object Aeson..: "activeSelector"
                <*> object Aeson..: "fieldKeyAttr"
                <*> object Aeson..: "fieldNameFallback"
                <*> object Aeson..: "containerSelector"
            other -> fail ("unsupported SurfaceFragmentProtection kind " <> cs other)

instance Aeson.ToJSON SurfaceWireFragment where
    toJSON SurfaceWireFragment { fragmentKey, targetId, url, deferUntilBlur, protectionPolicy } = Aeson.object
        [ "fragmentKey" Aeson..= fragmentKey
        , "targetId" Aeson..= targetId
        , "url" Aeson..= url
        , "deferUntilBlur" Aeson..= deferUntilBlur
        , "protectionPolicy" Aeson..= protectionPolicy
        ]

instance Aeson.FromJSON SurfaceWireFragment where
    parseJSON = Aeson.withObject "SurfaceWireFragment" \object -> do
        value <- SurfaceWireFragment
            <$> object Aeson..: "fragmentKey"
            <*> object Aeson..: "targetId"
            <*> object Aeson..: "url"
            <*> object Aeson..: "deferUntilBlur"
            <*> object Aeson..: "protectionPolicy"
        validateSchemaValue "SurfaceWireFragment" value
        pure value

instance Aeson.ToJSON SurfaceSubscription where
    toJSON SurfaceSubscription { scope, scopeKey, mountedFragments } = Aeson.object
        [ "scope" Aeson..= scope
        , "scopeKey" Aeson..= scopeKey
        , "mountedFragments" Aeson..= mountedFragments
        ]

instance Aeson.FromJSON SurfaceSubscription where
    parseJSON = Aeson.withObject "SurfaceSubscription" \object -> do
        value <- SurfaceSubscription
            <$> object Aeson..: "scope"
            <*> object Aeson..: "scopeKey"
            <*> object Aeson..: "mountedFragments"
        validateSchemaValue "SurfaceSubscription" value
        pure value

instance Aeson.ToJSON LiveUpdateCommand where
    toJSON Subscribe { subscription, clientId, lastSeenVersion } = Aeson.object
        [ "type" Aeson..= ("subscribe" :: Text)
        , "subscription" Aeson..= subscription
        , "clientId" Aeson..= clientId
        , "lastSeenVersion" Aeson..= lastSeenVersion
        ]
    toJSON Unsubscribe { subscription } = Aeson.object
        [ "type" Aeson..= ("unsubscribe" :: Text)
        , "subscription" Aeson..= subscription
        ]

instance Aeson.FromJSON LiveUpdateCommand where
    parseJSON = Aeson.withObject "LiveUpdateCommand" \object -> do
        commandType <- object Aeson..: "type" :: AesonTypes.Parser Text
        case commandType of
            "subscribe" -> do
                value <- Subscribe
                    <$> object Aeson..: "subscription"
                    <*> object Aeson..: "clientId"
                    <*> object Aeson..: "lastSeenVersion"
                validateSchemaValue "LiveUpdateCommand" value
                pure value
            "unsubscribe" -> do
                value <- Unsubscribe <$> object Aeson..: "subscription"
                validateSchemaValue "LiveUpdateCommand" value
                pure value
            other -> fail ("unsupported LiveUpdateCommand type " <> cs other)

instance Aeson.ToJSON LiveUpdateMessage where
    toJSON Subscribed { scope, scopeKey, currentVersion, resync } = Aeson.object
        [ "type" Aeson..= ("subscribed" :: Text)
        , "scope" Aeson..= scope
        , "scopeKey" Aeson..= scopeKey
        , "currentVersion" Aeson..= currentVersion
        , "resync" Aeson..= resync
        ]
    toJSON Invalidate { scope, scopeKey, version, fragments, sourceClientId } = Aeson.object
        [ "type" Aeson..= ("invalidate" :: Text)
        , "scope" Aeson..= scope
        , "scopeKey" Aeson..= scopeKey
        , "version" Aeson..= version
        , "fragments" Aeson..= fragments
        , "sourceClientId" Aeson..= sourceClientId
        ]
    toJSON Error { message } = Aeson.object
        [ "type" Aeson..= ("error" :: Text)
        , "message" Aeson..= message
        ]

instance Aeson.FromJSON LiveUpdateMessage where
    parseJSON = Aeson.withObject "LiveUpdateMessage" \object -> do
        messageType <- object Aeson..: "type" :: AesonTypes.Parser Text
        case messageType of
            "subscribed" -> do
                value <- Subscribed
                    <$> object Aeson..: "scope"
                    <*> object Aeson..: "scopeKey"
                    <*> object Aeson..: "currentVersion"
                    <*> object Aeson..: "resync"
                validateSchemaValue "LiveUpdateMessage" value
                pure value
            "invalidate" -> do
                value <- Invalidate
                    <$> object Aeson..: "scope"
                    <*> object Aeson..: "scopeKey"
                    <*> object Aeson..: "version"
                    <*> object Aeson..: "fragments"
                    <*> object Aeson..: "sourceClientId"
                validateSchemaValue "LiveUpdateMessage" value
                pure value
            "error" -> do
                value <- Error <$> object Aeson..: "message"
                validateSchemaValue "LiveUpdateMessage" value
                pure value
            other -> fail ("unsupported LiveUpdateMessage type " <> cs other)

validateSurfaceScope :: SurfaceScope -> AesonTypes.Parser ()
validateSurfaceScope = validateSurfaceScopeValue . Aeson.toJSON

validateSurfaceFragmentKey :: SurfaceFragmentKey -> AesonTypes.Parser ()
validateSurfaceFragmentKey = validateSurfaceFragmentKeyValue . Aeson.toJSON

validateSchemaValue :: Aeson.ToJSON value => Text -> value -> AesonTypes.Parser ()
validateSchemaValue name = validateContractValue name . Aeson.toJSON
