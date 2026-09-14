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
    , coalesceSurfaceFragmentKeys
    , currentLiveUpdateVersion
    , currentLiveUpdateVersionWithBus
    , advanceLiveUpdateVersionWithBus
    , broadcastLiveInvalidationAtVersion
    , broadcastLiveInvalidationAtVersionWithBus
    , liveUpdateSubscriptionNeedsResync
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

import Application.Error.Parser (parserFailure)
import qualified Control.Exception.Safe as Exception
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import Data.IORef
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import IHP.Prelude
import qualified Network.WebSockets as WebSocket
import System.IO.Unsafe (unsafePerformIO)

import Application.Helper.FrontendContract.Surface.Identity.Registered (canonicalFrontendSurfaceScopeKey)
import qualified Application.Helper.FrontendContract.Wire.LiveUpdate as Wire

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
    { subscriptionScope                       :: !SurfaceScope
    , subscriptionScopeKey                    :: !Text
    , subscriptionFragmentKeys                :: ![SurfaceFragmentKey]
    , subscriptionRenderedDependencyWatermark :: !Int
    }
    deriving (Eq, Show)

data LiveUpdateCommand
    = SubscribeLiveUpdates
        { subscription    :: !SurfaceSubscription
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
        { scope     :: !SurfaceScope
        , scopeKey  :: !Text
        , version   :: !Int
        , fragments :: ![SurfaceFragmentKey]
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

liveUpdateSubscriptionNeedsResync :: Int -> Int -> Maybe Int -> Int -> Bool
liveUpdateSubscriptionNeedsResync renderedWatermark durableWatermark lastSeenVersion currentVersion =
    renderedWatermark /= durableWatermark
        || maybe False (/= currentVersion) lastSeenVersion

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
    , liveBusAdvanceVersion           :: SurfaceScope -> Int -> IO Bool
    , liveBusBroadcastInvalidationAtVersion :: SurfaceScope -> Int -> [SurfaceFragmentKey] -> IO LiveUpdateBroadcastResult
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
        , liveBusAdvanceVersion = advanceInMemoryVersion state
        , liveBusBroadcastInvalidationAtVersion = broadcastInMemoryInvalidationAtVersion state
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

advanceLiveUpdateVersionWithBus :: LiveBus -> SurfaceScope -> Int -> IO Bool
advanceLiveUpdateVersionWithBus = liveBusAdvanceVersion

advanceInMemoryVersion :: InMemoryLiveBusState -> SurfaceScope -> Int -> IO Bool
advanceInMemoryVersion state scope version =
    atomicModifyIORef' state.inMemoryScopeVersionsRef \versions ->
        let scopeKey = surfaceScopeKey scope
            current = Map.findWithDefault 0 scopeKey versions
         in if version <= current
                then (versions, False)
                else (Map.insert scopeKey version versions, True)

broadcastLiveInvalidationAtVersion :: SurfaceScope -> Int -> [SurfaceFragmentKey] -> IO LiveUpdateBroadcastResult
broadcastLiveInvalidationAtVersion = broadcastLiveInvalidationAtVersionWithBus defaultLiveBus

broadcastLiveInvalidationAtVersionWithBus :: LiveBus -> SurfaceScope -> Int -> [SurfaceFragmentKey] -> IO LiveUpdateBroadcastResult
broadcastLiveInvalidationAtVersionWithBus = liveBusBroadcastInvalidationAtVersion

broadcastInMemoryInvalidationAtVersion :: InMemoryLiveBusState -> SurfaceScope -> Int -> [SurfaceFragmentKey] -> IO LiveUpdateBroadcastResult
broadcastInMemoryInvalidationAtVersion state scope version fragments = do
    advanced <- advanceInMemoryVersion state scope version
    if advanced
        then broadcastInMemoryInvalidationKnownAdvanced state scope version fragments
        else pure LiveUpdateBroadcastResult
            { broadcastVersion = version
            , broadcastSubscriberCount = 0
            , broadcastFragmentCount = length fragments
            , broadcastRefetchFragmentCount = 0
            , broadcastCoalescedFragmentCount = 0
            , broadcastDroppedSubscriptions = 0
            }

broadcastInMemoryInvalidationKnownAdvanced :: InMemoryLiveBusState -> SurfaceScope -> Int -> [SurfaceFragmentKey] -> IO LiveUpdateBroadcastResult
broadcastInMemoryInvalidationKnownAdvanced state scope version fragments = do
    let coalescedFragments = coalesceSurfaceFragmentKeys fragments
    subscriptions <- readIORef state.inMemorySubscriptionsRef
    let scopeKey = surfaceScopeKey scope
    let matchingSubscriptions = filter (\subscription -> subscription.activeSubscription.subscriptionScopeKey == scopeKey) subscriptions
    staleIds <- mapMaybeM (sendInvalidation scope version coalescedFragments) matchingSubscriptions
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

sendInvalidation :: SurfaceScope -> Int -> [SurfaceFragmentKey] -> ActiveLiveSubscription -> IO (Maybe UUID.UUID)
sendInvalidation scope version fragments subscription = do
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
liveUpdateSubscriptionToWire SurfaceSubscription { subscriptionScope, subscriptionScopeKey, subscriptionFragmentKeys, subscriptionRenderedDependencyWatermark } =
    Wire.SurfaceSubscription
        { Wire.scope = surfaceScopeToWire subscriptionScope
        , Wire.scopeKey = subscriptionScopeKey
        , Wire.fragments = map surfaceFragmentKeyToWire subscriptionFragmentKeys
        , Wire.renderedDependencyWatermark = subscriptionRenderedDependencyWatermark
        }

liveUpdateSubscriptionFromWire :: Wire.SurfaceSubscription -> Aeson.Parser SurfaceSubscription
liveUpdateSubscriptionFromWire Wire.SurfaceSubscription { scope, scopeKey, fragments, renderedDependencyWatermark } = do
    subscriptionScope <- surfaceScopeFromWire scope
    let canonicalScopeKey = surfaceScopeKey subscriptionScope
    unless (scopeKey == canonicalScopeKey) do
        parserFailure "Live update subscription scope key does not match its canonical Surface scope"
    forM_ fragments \Wire.SurfaceFragmentKey { surface = fragmentSurface } ->
        unless (fragmentSurface == scope.surface) do
            parserFailure "Live update subscription fragment key does not belong to its Surface scope"
    subscriptionFragmentKeys <- mapM surfaceFragmentKeyFromWire fragments
    unless (renderedDependencyWatermark >= 0) do
        parserFailure "Live update dependency watermark must be non-negative"
    pure SurfaceSubscription { subscriptionScope, subscriptionScopeKey = canonicalScopeKey, subscriptionFragmentKeys, subscriptionRenderedDependencyWatermark = renderedDependencyWatermark }

liveUpdateCommandToWire :: LiveUpdateCommand -> Wire.LiveUpdateCommand
liveUpdateCommandToWire SubscribeLiveUpdates { subscription, lastSeenVersion } = Wire.Subscribe (liveUpdateSubscriptionToWire subscription) lastSeenVersion
liveUpdateCommandToWire UnsubscribeLiveUpdates { subscription } = Wire.Unsubscribe (liveUpdateSubscriptionToWire subscription)

liveUpdateCommandFromWire :: Wire.LiveUpdateCommand -> Aeson.Parser LiveUpdateCommand
liveUpdateCommandFromWire Wire.Subscribe { subscription, lastSeenVersion } = SubscribeLiveUpdates <$> liveUpdateSubscriptionFromWire subscription <*> pure lastSeenVersion
liveUpdateCommandFromWire Wire.Unsubscribe { subscription } = UnsubscribeLiveUpdates <$> liveUpdateSubscriptionFromWire subscription

liveUpdateMessageToWire :: LiveUpdateMessage -> Wire.LiveUpdateMessage
liveUpdateMessageToWire LiveUpdatesSubscribed { scope, scopeKey, currentVersion, resync } =
    Wire.Subscribed (surfaceScopeToWire scope) scopeKey currentVersion resync
liveUpdateMessageToWire LiveUpdatesInvalidated { scope, scopeKey, version, fragments } =
    Wire.Invalidate (surfaceScopeToWire scope) scopeKey version (map surfaceFragmentKeyToWire fragments)
liveUpdateMessageToWire LiveUpdatesError { message } = Wire.Error message

mapMaybeM :: (a -> IO (Maybe b)) -> [a] -> IO [b]
mapMaybeM action values =
    catMaybes <$> mapM action values
