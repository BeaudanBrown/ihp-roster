{-# LANGUAGE DataKinds           #-}
{-# LANGUAGE FlexibleInstances   #-}
{-# LANGUAGE OverloadedRecordDot #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

module Application.Helper.FrontendContract.Wire.LiveUpdate
    ( LiveFragmentsRefreshEventDetail (..)
    , LiveUpdateCommand (..)
    , LiveUpdateMessage (..)
    , SurfaceFragmentKey (..)
    , SurfaceScope (..)
    , SurfaceSubscription (..)
    ) where

import qualified Application.Helper.FrontendContract.App as AppContract
import Application.Helper.FrontendContract.DSL (WireType (..))
import qualified Application.Helper.FrontendContract.LiveUpdate as Contract
import Application.Helper.FrontendContract.Wire.Carrier
import qualified Data.Aeson as Aeson
import IHP.Prelude

-- Surface-native live transport. Surface names and payloads are validated
-- against registered Surface declarations. Global record fields, union
-- discriminators, cases, presence, and recursive wire types are selected from
-- their registered FrontendContract declarations by Wire.Carrier.
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

instance CustomWire 'WireSurfaceScope where
    type CustomWireSourceType 'WireSurfaceScope = SurfaceScope
    customWireJson = Aeson.toJSON
    parseCustomWire = Aeson.parseJSON

instance CustomWire 'WireSurfaceFragmentKey where
    type CustomWireSourceType 'WireSurfaceFragmentKey = SurfaceFragmentKey
    customWireJson = Aeson.toJSON
    parseCustomWire = Aeson.parseJSON

instance ContractReference Contract.SurfaceSubscription where
    type ContractReferenceValue Contract.SurfaceSubscription = SurfaceSubscription
    contractReferenceJson = Aeson.toJSON
    parseContractReference = Aeson.parseJSON

instance Aeson.ToJSON SurfaceScope where
    toJSON SurfaceScope { surface, scope } = semanticSurfaceScopeJson surface scope

instance Aeson.FromJSON SurfaceScope where
    parseJSON raw = uncurry SurfaceScope <$> parseSemanticSurfaceScopeJson raw

instance Aeson.ToJSON SurfaceFragmentKey where
    toJSON SurfaceFragmentKey { surface, kind, params } = semanticSurfaceFragmentKeyJson surface kind params

instance Aeson.FromJSON SurfaceFragmentKey where
    parseJSON raw = do
        (surface, kind, params) <- parseSemanticSurfaceFragmentKeyJson raw
        pure SurfaceFragmentKey { surface, kind, params }

instance Aeson.ToJSON SurfaceSubscription where
    toJSON SurfaceSubscription { scope, scopeKey, fragments } =
        recordValue @Contract.SurfaceSubscription
            ( requiredField @Contract.Scope scope
                &: requiredField @Contract.ScopeKey scopeKey
                &: requiredField @Contract.Fragments fragments
                &: noFields
            )

instance Aeson.FromJSON SurfaceSubscription where
    parseJSON =
        parseRecord @Contract.SurfaceSubscription
            (\(scope, (scopeKey, (fragments, ()))) -> pure SurfaceSubscription { scope, scopeKey, fragments })

instance Aeson.ToJSON LiveFragmentsRefreshEventDetail where
    toJSON LiveFragmentsRefreshEventDetail { scope, scopeKey, fragments } =
        eventValue @AppContract.LiveFragmentsRefresh
            ( requiredField @AppContract.Scope scope
                &: requiredField @AppContract.ScopeKey scopeKey
                &: requiredField @AppContract.Fragments fragments
                &: noFields
            )

instance Aeson.FromJSON LiveFragmentsRefreshEventDetail where
    parseJSON =
        parseEvent @AppContract.LiveFragmentsRefresh
            (\(scope, (scopeKey, (fragments, ()))) -> pure LiveFragmentsRefreshEventDetail { scope, scopeKey, fragments })

instance Aeson.ToJSON LiveUpdateCommand where
    toJSON Subscribe { subscription, clientId, lastSeenVersion } =
        taggedUnionValue @Contract.LiveUpdateCommand @Contract.Subscribe
            ( requiredField @Contract.Subscription subscription
                &: requiredField @Contract.ClientId clientId
                &: nullableField @Contract.LastSeenVersion lastSeenVersion
                &: noFields
            )
    toJSON Unsubscribe { subscription } =
        taggedUnionValue @Contract.LiveUpdateCommand @Contract.Unsubscribe
            ( requiredField @Contract.Subscription subscription
                &: noFields
            )

instance Aeson.FromJSON LiveUpdateCommand where
    parseJSON =
        parseTaggedUnion @Contract.LiveUpdateCommand
            ( unionCase @Contract.Subscribe
                (\(subscription, (clientId, (lastSeenVersion, ()))) -> pure Subscribe { subscription, clientId, lastSeenVersion })
                |: unionCase @Contract.Unsubscribe
                    (\(subscription, ()) -> pure Unsubscribe { subscription })
                |: noUnionCases
            )

instance Aeson.ToJSON LiveUpdateMessage where
    toJSON Subscribed { scope, scopeKey, currentVersion, resync } =
        taggedUnionValue @Contract.LiveUpdateMessage @Contract.Subscribed
            ( requiredField @Contract.Scope scope
                &: requiredField @Contract.ScopeKey scopeKey
                &: requiredField @Contract.CurrentVersion currentVersion
                &: requiredField @Contract.Resync resync
                &: noFields
            )
    toJSON Invalidate { scope, scopeKey, version, fragments, sourceClientId } =
        taggedUnionValue @Contract.LiveUpdateMessage @Contract.Invalidate
            ( requiredField @Contract.Scope scope
                &: requiredField @Contract.ScopeKey scopeKey
                &: requiredField @Contract.Version version
                &: requiredField @Contract.Fragments fragments
                &: nullableField @Contract.SourceClientId sourceClientId
                &: noFields
            )
    toJSON Error { message } =
        taggedUnionValue @Contract.LiveUpdateMessage @Contract.Error
            ( requiredField @Contract.Message message
                &: noFields
            )

instance Aeson.FromJSON LiveUpdateMessage where
    parseJSON =
        parseTaggedUnion @Contract.LiveUpdateMessage
            ( unionCase @Contract.Subscribed
                (\(scope, (scopeKey, (currentVersion, (resync, ())))) -> pure Subscribed { scope, scopeKey, currentVersion, resync })
                |: unionCase @Contract.Invalidate
                    (\(scope, (scopeKey, (version, (fragments, (sourceClientId, ()))))) -> pure Invalidate { scope, scopeKey, version, fragments, sourceClientId })
                |: unionCase @Contract.Error
                    (\(message, ()) -> pure Error { message })
                |: noUnionCases
            )
