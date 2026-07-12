{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}

module Application.Helper.FrontendContract.Wire.LiveUpdate
    ( LiveFragmentsRefreshEventDetail (..)
    , LiveUpdateCommand (..)
    , LiveUpdateMessage (..)
    , SurfaceFragmentKey (..)
    , SurfaceScope (..)
    , SurfaceSubscription (..)
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

data SurfaceSubscription = SurfaceSubscription
    { scope     :: !SurfaceScope
    , scopeKey  :: !Text
    , fragments :: ![SurfaceFragmentKey]
    }
    deriving (Eq, Show)

data LiveFragmentsRefreshEventDetail = LiveFragmentsRefreshEventDetail
    { scope     :: !SurfaceScope
    , scopeKey  :: !Text
    , fragments :: ![SurfaceFragmentKey]
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
        , fragments      :: ![SurfaceFragmentKey]
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
    parseJSON raw = do
        validateSurfaceScopeValue raw
        Aeson.withObject "SurfaceScope" (\object -> SurfaceScope <$> object Aeson..: "surface" <*> object Aeson..: "scope") raw

instance Aeson.ToJSON SurfaceFragmentKey where
    toJSON SurfaceFragmentKey { surface, kind, params } = Aeson.object
        [ "surface" Aeson..= surface
        , "kind" Aeson..= kind
        , "params" Aeson..= params
        ]

instance Aeson.FromJSON SurfaceFragmentKey where
    parseJSON raw = do
        validateSurfaceFragmentKeyValue raw
        Aeson.withObject "SurfaceFragmentKey" (\object -> SurfaceFragmentKey <$> object Aeson..: "surface" <*> object Aeson..: "kind" <*> object Aeson..: "params") raw

instance Aeson.ToJSON SurfaceSubscription where
    toJSON SurfaceSubscription { scope, scopeKey, fragments } = Aeson.object
        [ "scope" Aeson..= scope
        , "scopeKey" Aeson..= scopeKey
        , "fragments" Aeson..= fragments
        ]

instance Aeson.FromJSON SurfaceSubscription where
    parseJSON raw = do
        validateContractValue "SurfaceSubscription" raw
        Aeson.withObject "SurfaceSubscription"
            ( \object ->
                SurfaceSubscription
                    <$> object Aeson..: "scope"
                    <*> object Aeson..: "scopeKey"
                    <*> object Aeson..: "fragments"
            )
            raw

instance Aeson.ToJSON LiveFragmentsRefreshEventDetail where
    toJSON LiveFragmentsRefreshEventDetail { scope, scopeKey, fragments } = Aeson.object
        [ "scope" Aeson..= scope
        , "scopeKey" Aeson..= scopeKey
        , "fragments" Aeson..= fragments
        ]

instance Aeson.FromJSON LiveFragmentsRefreshEventDetail where
    parseJSON raw = do
        validateContractValue "LiveFragmentsRefreshEventDetail" raw
        Aeson.withObject "LiveFragmentsRefreshEventDetail"
            ( \object ->
                LiveFragmentsRefreshEventDetail
                    <$> object Aeson..: "scope"
                    <*> object Aeson..: "scopeKey"
                    <*> object Aeson..: "fragments"
            )
            raw

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
    parseJSON raw = do
        validateContractValue "LiveUpdateCommand" raw
        Aeson.withObject "LiveUpdateCommand"
            ( \object -> do
                commandType <- object Aeson..: "type" :: AesonTypes.Parser Text
                case commandType of
                    "subscribe" -> Subscribe
                        <$> object Aeson..: "subscription"
                        <*> object Aeson..: "clientId"
                        <*> object Aeson..: "lastSeenVersion"
                    "unsubscribe" -> Unsubscribe <$> object Aeson..: "subscription"
                    other -> fail ("unsupported LiveUpdateCommand type " <> cs other)
            )
            raw

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
    parseJSON raw = do
        validateContractValue "LiveUpdateMessage" raw
        Aeson.withObject "LiveUpdateMessage"
            ( \object -> do
                messageType <- object Aeson..: "type" :: AesonTypes.Parser Text
                case messageType of
                    "subscribed" -> Subscribed
                        <$> object Aeson..: "scope"
                        <*> object Aeson..: "scopeKey"
                        <*> object Aeson..: "currentVersion"
                        <*> object Aeson..: "resync"
                    "invalidate" -> Invalidate
                        <$> object Aeson..: "scope"
                        <*> object Aeson..: "scopeKey"
                        <*> object Aeson..: "version"
                        <*> object Aeson..: "fragments"
                        <*> object Aeson..: "sourceClientId"
                    "error" -> Error <$> object Aeson..: "message"
                    other -> fail ("unsupported LiveUpdateMessage type " <> cs other)
            )
            raw
