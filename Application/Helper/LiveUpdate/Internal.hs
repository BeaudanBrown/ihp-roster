module Application.Helper.LiveUpdate.Internal
    ( SurfaceFragmentKey (..)
    , LiveBus
    , LiveUpdateBroadcastResult (..)
    , LiveUpdateCommand (..)
    , LiveUpdateMessage (..)
    , SurfaceScope (..)
    , SurfaceSubscription (..)
    , activeSurfaceSubscriptions
    , activeSurfaceSubscriptionsWithBus
    , activeSurfaceScopesWithBus
    , activeSurfaceScopeMatches
    , activeSurfaceScopeMatchesWithBus
    , broadcastLiveInvalidationDetailed
    , broadcastLiveInvalidationDetailedWithBus
    , broadcastLiveInvalidationDetailedWithoutContext
    , coalesceSurfaceFragmentKeys
    , currentLiveUpdateVersion
    , currentLiveUpdateVersionWithBus
    , incrementLiveUpdateVersionWithBus
    , liveUpdateSourceClientId
    , mkSurfaceFragmentKey
    , mkSurfaceScope
    , surfaceFragmentKeyIdentity
    , surfaceScopeIdentity
    , surfaceScopeFromWire
    , surfaceScopeKey
    , surfaceScopeToWire
    , surfaceFragmentKeyFromWire
    , surfaceFragmentKeyToWire
    , newInMemoryLiveBus
    , registerSurfaceSubscription
    , registerSurfaceSubscriptionWithBus
    , unregisterSurfaceSubscription
    , unregisterSurfaceSubscriptionWithBus
    ) where

import qualified Control.Exception.Safe as Exception
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import Data.IORef
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import IHP.Controller.Context (ControllerContext)
import IHP.ControllerSupport (Request, getHeader)
import IHP.Prelude
import qualified Network.WebSockets as WebSocket
import System.IO.Unsafe (unsafePerformIO)

import Application.Helper.FrontendContract.LiveUpdateValues (liveUpdateClientIdHeaderName)
import Application.Helper.FrontendContract.Surface.Identity (canonicalFrontendSurfaceScopeKey)
import qualified Application.Helper.FrontendContract.Wire.LiveUpdate as Wire
import Application.Helper.Profiling (profileActionSpan,
                                     profileActionSpanWithDetail)

data SurfaceScope = FrontendSurfaceScope
    { surfaceScopeSurface   :: !Text
    , surfaceScopePayload   :: !Aeson.Value
    , surfaceScopeStableKey :: !Text
    }
    deriving (Eq, Ord, Show)

data SurfaceFragmentKey = FrontendSurfaceSurfaceFragmentKey
    { surfaceFragmentSurface  :: !Text
    , surfaceFragmentWireKind :: !Text
    , surfaceFragmentParams   :: !Aeson.Value
    }
    deriving (Eq, Ord, Show)

mkSurfaceScope :: Text -> Aeson.Value -> Text -> SurfaceScope
mkSurfaceScope surfaceScopeSurface surfaceScopePayload surfaceScopeStableKey =
    FrontendSurfaceScope { surfaceScopeSurface, surfaceScopePayload, surfaceScopeStableKey }

surfaceScopeIdentity :: SurfaceScope -> (Text, Aeson.Value)
surfaceScopeIdentity scope = (scope.surfaceScopeSurface, scope.surfaceScopePayload)

mkSurfaceFragmentKey :: Text -> Text -> Aeson.Value -> SurfaceFragmentKey
mkSurfaceFragmentKey surfaceFragmentSurface surfaceFragmentWireKind surfaceFragmentParams =
    FrontendSurfaceSurfaceFragmentKey { surfaceFragmentSurface, surfaceFragmentWireKind, surfaceFragmentParams = normalizeFragmentParams surfaceFragmentParams }

surfaceFragmentKeyIdentity :: SurfaceFragmentKey -> (Text, Text, Aeson.Value)
surfaceFragmentKeyIdentity key = (key.surfaceFragmentSurface, key.surfaceFragmentWireKind, key.surfaceFragmentParams)

normalizeFragmentParams :: Aeson.Value -> Aeson.Value
normalizeFragmentParams Aeson.Null = Aeson.object []
normalizeFragmentParams value      = value

data SurfaceSubscription = SurfaceSubscription
    { subscriptionScope        :: !SurfaceScope
    , subscriptionScopeKey     :: !Text
    , subscriptionFragmentKeys :: ![SurfaceFragmentKey]
    }
    deriving (Eq, Show)

data LiveUpdateCommand
    = SubscribeLiveUpdates
        { subscription    :: !SurfaceSubscription
        , clientId        :: !Text
        , lastSeenVersion :: !(Maybe Int)
        }
    | UnsubscribeLiveUpdates
        { subscription :: !SurfaceSubscription
        }
    deriving (Eq, Show)

data LiveUpdateMessage
    = LiveUpdatesSubscribed
        { scope          :: !SurfaceScope
        , scopeKey       :: !Text
        , currentVersion :: !Int
        , resync         :: !Bool
        }
    | LiveUpdatesInvalidated
        { scope          :: !SurfaceScope
        , scopeKey       :: !Text
        , version        :: !Int
        , fragments      :: ![SurfaceFragmentKey]
        , sourceClientId :: !(Maybe Text)
        }
    | LiveUpdatesError
        { message :: !Text
        }
    deriving (Eq, Show)

data LiveUpdateBroadcastResult = LiveUpdateBroadcastResult
    { broadcastVersion                :: !Int
    , broadcastSubscriberCount        :: !Int
    , broadcastFragmentCount          :: !Int
    , broadcastRefetchFragmentCount   :: !Int
    , broadcastCoalescedFragmentCount :: !Int
    , broadcastDroppedSubscriptions   :: !Int
    }
    deriving (Eq, Show)

surfaceScopeKey :: SurfaceScope -> Text
surfaceScopeKey = (.surfaceScopeStableKey)

liveUpdateSourceClientId :: (?request :: Request) => Maybe Text
liveUpdateSourceClientId =
    cs <$> getHeader (cs liveUpdateClientIdHeaderName)

instance Aeson.ToJSON SurfaceScope where
    toJSON = Aeson.toJSON . surfaceScopeToWire

instance Aeson.FromJSON SurfaceScope where
    parseJSON value = surfaceScopeFromWire =<< Aeson.parseJSON value

instance Aeson.ToJSON SurfaceFragmentKey where
    toJSON = Aeson.toJSON . surfaceFragmentKeyToWire

instance Aeson.FromJSON SurfaceFragmentKey where
    parseJSON value = surfaceFragmentKeyFromWire =<< Aeson.parseJSON value

instance Aeson.ToJSON LiveUpdateCommand where
    toJSON = Aeson.toJSON . liveUpdateCommandToWire

instance Aeson.FromJSON LiveUpdateCommand where
    parseJSON value = liveUpdateCommandFromWire =<< Aeson.parseJSON value

instance Aeson.ToJSON LiveUpdateMessage where
    toJSON = Aeson.toJSON . liveUpdateMessageToWire

data ActiveLiveSubscription = ActiveLiveSubscription
    { activeSubscriptionId         :: !UUID.UUID
    , activeSubscription           :: !SurfaceSubscription
    , activeSubscriptionConnection :: WebSocket.Connection
    }

data LiveBus = LiveBus
    { liveBusRegisterSubscription     :: UUID.UUID -> SurfaceSubscription -> WebSocket.Connection -> IO ()
    , liveBusUnregisterSubscription   :: UUID.UUID -> IO ()
    , liveBusActiveSubscriptions      :: IO [SurfaceSubscription]
    , liveBusCurrentVersion           :: SurfaceScope -> IO Int
    , liveBusIncrementVersion         :: SurfaceScope -> IO Int
    , liveBusBroadcastInvalidation    :: SurfaceScope -> Maybe Text -> [SurfaceFragmentKey] -> IO LiveUpdateBroadcastResult
    }

data InMemoryLiveBusState = InMemoryLiveBusState
    { inMemorySubscriptionsRef :: !(IORef [ActiveLiveSubscription])
    , inMemoryScopeVersionsRef :: !(IORef (Map.Map Text Int))
    }

newInMemoryLiveBus :: IO LiveBus
newInMemoryLiveBus = do
    subscriptionsRef <- newIORef []
    scopeVersionsRef <- newIORef Map.empty
    pure
        (inMemoryLiveBus
            InMemoryLiveBusState
                { inMemorySubscriptionsRef = subscriptionsRef
                , inMemoryScopeVersionsRef = scopeVersionsRef
                })

defaultLiveBus :: LiveBus
defaultLiveBus = unsafePerformIO newInMemoryLiveBus
{-# NOINLINE defaultLiveBus #-}

inMemoryLiveBus :: InMemoryLiveBusState -> LiveBus
inMemoryLiveBus state =
    LiveBus
        { liveBusRegisterSubscription = registerInMemorySubscription state
        , liveBusUnregisterSubscription = unregisterInMemorySubscription state
        , liveBusActiveSubscriptions = activeInMemorySubscriptions state
        , liveBusCurrentVersion = currentInMemoryVersion state
        , liveBusIncrementVersion = incrementInMemoryVersion state
        , liveBusBroadcastInvalidation = broadcastInMemoryInvalidation state
        }

registerSurfaceSubscription :: UUID.UUID -> SurfaceSubscription -> WebSocket.Connection -> IO ()
registerSurfaceSubscription =
    registerSurfaceSubscriptionWithBus defaultLiveBus

registerSurfaceSubscriptionWithBus :: LiveBus -> UUID.UUID -> SurfaceSubscription -> WebSocket.Connection -> IO ()
registerSurfaceSubscriptionWithBus =
    liveBusRegisterSubscription

registerInMemorySubscription :: InMemoryLiveBusState -> UUID.UUID -> SurfaceSubscription -> WebSocket.Connection -> IO ()
registerInMemorySubscription state activeSubscriptionId activeSubscription connection =
    atomicModifyIORef' state.inMemorySubscriptionsRef \subscriptions ->
        ( ActiveLiveSubscription { activeSubscriptionId, activeSubscription, activeSubscriptionConnection = connection }
            : filter (\subscription -> subscription.activeSubscriptionId /= activeSubscriptionId) subscriptions
        , ()
        )

unregisterSurfaceSubscription :: UUID.UUID -> IO ()
unregisterSurfaceSubscription =
    unregisterSurfaceSubscriptionWithBus defaultLiveBus

unregisterSurfaceSubscriptionWithBus :: LiveBus -> UUID.UUID -> IO ()
unregisterSurfaceSubscriptionWithBus =
    liveBusUnregisterSubscription

unregisterInMemorySubscription :: InMemoryLiveBusState -> UUID.UUID -> IO ()
unregisterInMemorySubscription state subscriptionId =
    atomicModifyIORef' state.inMemorySubscriptionsRef \subscriptions ->
        (filter (\subscription -> subscription.activeSubscriptionId /= subscriptionId) subscriptions, ())

activeSurfaceSubscriptions :: IO [SurfaceSubscription]
activeSurfaceSubscriptions =
    activeSurfaceSubscriptionsWithBus defaultLiveBus

activeSurfaceSubscriptionsWithBus :: LiveBus -> IO [SurfaceSubscription]
activeSurfaceSubscriptionsWithBus =
    liveBusActiveSubscriptions

activeInMemorySubscriptions :: InMemoryLiveBusState -> IO [SurfaceSubscription]
activeInMemorySubscriptions state =
    map (.activeSubscription) <$> readIORef state.inMemorySubscriptionsRef

activeSurfaceScopesWithBus :: LiveBus -> IO [SurfaceScope]
activeSurfaceScopesWithBus bus =
    Set.toList . Set.fromList . map (.subscriptionScope) <$> activeSurfaceSubscriptionsWithBus bus

activeSurfaceScopeMatches :: Ord a => (SurfaceScope -> Maybe a) -> IO [a]
activeSurfaceScopeMatches = activeSurfaceScopeMatchesWithBus defaultLiveBus

activeSurfaceScopeMatchesWithBus :: Ord a => LiveBus -> (SurfaceScope -> Maybe a) -> IO [a]
activeSurfaceScopeMatchesWithBus bus matcher =
    Set.toList . Set.fromList . mapMaybe matcher <$> activeSurfaceScopesWithBus bus

currentLiveUpdateVersion :: SurfaceScope -> IO Int
currentLiveUpdateVersion =
    currentLiveUpdateVersionWithBus defaultLiveBus

currentLiveUpdateVersionWithBus :: LiveBus -> SurfaceScope -> IO Int
currentLiveUpdateVersionWithBus =
    liveBusCurrentVersion

currentInMemoryVersion :: InMemoryLiveBusState -> SurfaceScope -> IO Int
currentInMemoryVersion state scope =
    Map.findWithDefault 0 (surfaceScopeKey scope) <$> readIORef state.inMemoryScopeVersionsRef

incrementLiveUpdateVersionWithBus :: LiveBus -> SurfaceScope -> IO Int
incrementLiveUpdateVersionWithBus =
    liveBusIncrementVersion

incrementInMemoryVersion :: InMemoryLiveBusState -> SurfaceScope -> IO Int
incrementInMemoryVersion state scope =
    atomicModifyIORef' state.inMemoryScopeVersionsRef \versions ->
        let scopeKey = surfaceScopeKey scope
            nextVersion = Map.findWithDefault 0 scopeKey versions + 1
         in (Map.insert scopeKey nextVersion versions, nextVersion)

broadcastLiveInvalidationDetailed :: (?context :: ControllerContext) => SurfaceScope -> Maybe Text -> [SurfaceFragmentKey] -> IO LiveUpdateBroadcastResult
broadcastLiveInvalidationDetailed scope sourceClientId fragments =
    profileActionSpanWithDetail "live_updates.broadcast_invalidation" do
        result <- broadcastLiveInvalidationDetailedWithoutContext scope sourceClientId fragments
        pure (result, Just (liveUpdateBroadcastDetail result))

broadcastLiveInvalidationDetailedWithoutContext :: SurfaceScope -> Maybe Text -> [SurfaceFragmentKey] -> IO LiveUpdateBroadcastResult
broadcastLiveInvalidationDetailedWithoutContext =
    broadcastLiveInvalidationDetailedWithBus defaultLiveBus

broadcastLiveInvalidationDetailedWithBus :: LiveBus -> SurfaceScope -> Maybe Text -> [SurfaceFragmentKey] -> IO LiveUpdateBroadcastResult
broadcastLiveInvalidationDetailedWithBus =
    liveBusBroadcastInvalidation

broadcastInMemoryInvalidation :: InMemoryLiveBusState -> SurfaceScope -> Maybe Text -> [SurfaceFragmentKey] -> IO LiveUpdateBroadcastResult
broadcastInMemoryInvalidation state scope sourceClientId fragments = do
    let coalescedFragments = coalesceSurfaceFragmentKeys fragments
    version <- incrementInMemoryVersion state scope
    subscriptions <- readIORef state.inMemorySubscriptionsRef
    let scopeKey = surfaceScopeKey scope
    let matchingSubscriptions = filter (\subscription -> subscription.activeSubscription.subscriptionScopeKey == scopeKey) subscriptions
    staleIds <- mapMaybeM (sendInvalidation scope version sourceClientId coalescedFragments) matchingSubscriptions
    unless (null staleIds) do
        atomicModifyIORef' state.inMemorySubscriptionsRef \activeSubscriptions ->
            ( filter (\subscription -> subscription.activeSubscriptionId `notElem` staleIds) activeSubscriptions
            , ()
            )
    pure
        LiveUpdateBroadcastResult
            { broadcastVersion = version
            , broadcastSubscriberCount = length matchingSubscriptions
            , broadcastFragmentCount = length fragments
            , broadcastRefetchFragmentCount = length coalescedFragments
            , broadcastCoalescedFragmentCount = length fragments - length coalescedFragments
            , broadcastDroppedSubscriptions = length staleIds
            }

coalesceSurfaceFragmentKeys :: [SurfaceFragmentKey] -> [SurfaceFragmentKey]
coalesceSurfaceFragmentKeys fragments =
    reverse (fst (foldl' step ([], Set.empty) fragments))
  where
    step (kept, seen) fragmentKey
        | Set.member fragmentKey seen = (kept, seen)
        | otherwise = (fragmentKey : kept, Set.insert fragmentKey seen)

liveUpdateBroadcastDetail :: LiveUpdateBroadcastResult -> Text
liveUpdateBroadcastDetail result =
    Text.intercalate
        ","
        [ "subscribers=" <> tshow result.broadcastSubscriberCount
        , "fragments=" <> tshow result.broadcastFragmentCount
        , "refetch=" <> tshow result.broadcastRefetchFragmentCount
        , "coalesced=" <> tshow result.broadcastCoalescedFragmentCount
        , "dropped=" <> tshow result.broadcastDroppedSubscriptions
        ]

sendInvalidation :: SurfaceScope -> Int -> Maybe Text -> [SurfaceFragmentKey] -> ActiveLiveSubscription -> IO (Maybe UUID.UUID)
sendInvalidation scope version sourceClientId fragments subscription = do
    result <-
        Exception.tryAny $
            WebSocket.sendTextData subscription.activeSubscriptionConnection (Aeson.encode message)
    pure $
        case result of
            Left _  -> Just subscription.activeSubscriptionId
            Right _ -> Nothing
    where
        message =
            LiveUpdatesInvalidated
                { scope
                , scopeKey = surfaceScopeKey scope
                , version
                , fragments
                , sourceClientId
                }

surfaceScopeToWire :: SurfaceScope -> Wire.SurfaceScope
surfaceScopeToWire scope = Wire.SurfaceScope
    { Wire.surface = scope.surfaceScopeSurface
    , Wire.scope = scope.surfaceScopePayload
    }

surfaceScopeFromWire :: Wire.SurfaceScope -> Aeson.Parser SurfaceScope
surfaceScopeFromWire Wire.SurfaceScope { surface, scope } = do
    stableKey <- surfaceScopeStableKeyFromWire surface scope
    pure (mkSurfaceScope surface scope stableKey)

surfaceScopeStableKeyFromWire :: Text -> Aeson.Value -> Aeson.Parser Text
surfaceScopeStableKeyFromWire = canonicalFrontendSurfaceScopeKey

surfaceFragmentKeyToWire :: SurfaceFragmentKey -> Wire.SurfaceFragmentKey
surfaceFragmentKeyToWire key = Wire.SurfaceFragmentKey
    { Wire.surface = key.surfaceFragmentSurface
    , Wire.kind = key.surfaceFragmentWireKind
    , Wire.params = key.surfaceFragmentParams
    }

surfaceFragmentKeyFromWire :: Wire.SurfaceFragmentKey -> Aeson.Parser SurfaceFragmentKey
surfaceFragmentKeyFromWire Wire.SurfaceFragmentKey { surface, kind, params } =
    pure (mkSurfaceFragmentKey surface kind params)

liveUpdateSubscriptionToWire :: SurfaceSubscription -> Wire.SurfaceSubscription
liveUpdateSubscriptionToWire SurfaceSubscription { subscriptionScope, subscriptionScopeKey, subscriptionFragmentKeys } =
    Wire.SurfaceSubscription
        { Wire.scope = surfaceScopeToWire subscriptionScope
        , Wire.scopeKey = subscriptionScopeKey
        , Wire.fragments = map surfaceFragmentKeyToWire subscriptionFragmentKeys
        }

liveUpdateSubscriptionFromWire :: Wire.SurfaceSubscription -> Aeson.Parser SurfaceSubscription
liveUpdateSubscriptionFromWire Wire.SurfaceSubscription { scope, scopeKey, fragments } = do
    subscriptionScope <- surfaceScopeFromWire scope
    let canonicalScopeKey = surfaceScopeKey subscriptionScope
    unless (scopeKey == canonicalScopeKey) do
        fail "Live update subscription scope key does not match its canonical Surface scope"
    forM_ fragments \Wire.SurfaceFragmentKey { surface = fragmentSurface } ->
        unless (fragmentSurface == scope.surface) do
            fail "Live update subscription fragment key does not belong to its Surface scope"
    subscriptionFragmentKeys <- mapM surfaceFragmentKeyFromWire fragments
    pure SurfaceSubscription { subscriptionScope, subscriptionScopeKey = canonicalScopeKey, subscriptionFragmentKeys }

liveUpdateCommandToWire :: LiveUpdateCommand -> Wire.LiveUpdateCommand
liveUpdateCommandToWire SubscribeLiveUpdates { subscription, clientId, lastSeenVersion } = Wire.Subscribe (liveUpdateSubscriptionToWire subscription) clientId lastSeenVersion
liveUpdateCommandToWire UnsubscribeLiveUpdates { subscription } = Wire.Unsubscribe (liveUpdateSubscriptionToWire subscription)

liveUpdateCommandFromWire :: Wire.LiveUpdateCommand -> Aeson.Parser LiveUpdateCommand
liveUpdateCommandFromWire Wire.Subscribe { subscription, clientId, lastSeenVersion } = SubscribeLiveUpdates <$> liveUpdateSubscriptionFromWire subscription <*> pure clientId <*> pure lastSeenVersion
liveUpdateCommandFromWire Wire.Unsubscribe { subscription } = UnsubscribeLiveUpdates <$> liveUpdateSubscriptionFromWire subscription

liveUpdateMessageToWire :: LiveUpdateMessage -> Wire.LiveUpdateMessage
liveUpdateMessageToWire LiveUpdatesSubscribed { scope, scopeKey, currentVersion, resync } =
    Wire.Subscribed (surfaceScopeToWire scope) scopeKey currentVersion resync
liveUpdateMessageToWire LiveUpdatesInvalidated { scope, scopeKey, version, fragments, sourceClientId } =
    Wire.Invalidate (surfaceScopeToWire scope) scopeKey version (map surfaceFragmentKeyToWire fragments) sourceClientId
liveUpdateMessageToWire LiveUpdatesError { message } = Wire.Error message

mapMaybeM :: (a -> IO (Maybe b)) -> [a] -> IO [b]
mapMaybeM action values =
    catMaybes <$> mapM action values
