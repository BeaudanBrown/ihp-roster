module Application.Helper.LiveUpdate
    ( LiveFragmentRef (..)
    , LiveUpdateCommand (..)
    , LiveUpdateMessage (..)
    , broadcastLiveInvalidation
    , currentLiveUpdateVersion
    , registerLiveSubscription
    , resetLiveUpdateScope
    , unregisterLiveSubscription
    ) where

import qualified Control.Exception.Safe as Exception
import qualified Data.Aeson as Aeson
import Data.IORef
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import IHP.Prelude
import qualified Network.WebSockets as WebSocket
import System.IO.Unsafe (unsafePerformIO)

data LiveFragmentRef = LiveFragmentRef
    { targetId       :: !Text
    , url            :: !Text
    , deferUntilBlur :: !Bool
    }
    deriving (Eq, Show)

data LiveUpdateCommand
    = SubscribeLiveUpdates
        { scope           :: !Text
        , clientId        :: !Text
        , lastSeenVersion :: !(Maybe Int)
        }
    | UnsubscribeLiveUpdates
        { scope :: !Text
        }
    deriving (Eq, Show)

data LiveUpdateMessage
    = LiveUpdatesSubscribed
        { scope          :: !Text
        , currentVersion :: !Int
        , resync         :: !Bool
        }
    | LiveUpdatesInvalidated
        { scope          :: !Text
        , version        :: !Int
        , fragments      :: ![LiveFragmentRef]
        , sourceClientId :: !(Maybe Text)
        }
    | LiveUpdatesError
        { message :: !Text
        }
    deriving (Eq, Show)

instance Aeson.ToJSON LiveFragmentRef where
    toJSON LiveFragmentRef { targetId, url, deferUntilBlur } =
        Aeson.object
            [ "targetId" Aeson..= targetId
            , "url" Aeson..= url
            , "deferUntilBlur" Aeson..= deferUntilBlur
            ]

instance Aeson.FromJSON LiveFragmentRef where
    parseJSON = Aeson.withObject "LiveFragmentRef" \object ->
        LiveFragmentRef
            <$> object Aeson..: "targetId"
            <*> object Aeson..: "url"
            <*> object Aeson..: "deferUntilBlur"

instance Aeson.ToJSON LiveUpdateCommand where
    toJSON SubscribeLiveUpdates { scope, clientId, lastSeenVersion } =
        Aeson.object
            [ "type" Aeson..= ("subscribe" :: Text)
            , "scope" Aeson..= scope
            , "clientId" Aeson..= clientId
            , "lastSeenVersion" Aeson..= lastSeenVersion
            ]
    toJSON UnsubscribeLiveUpdates { scope } =
        Aeson.object
            [ "type" Aeson..= ("unsubscribe" :: Text)
            , "scope" Aeson..= scope
            ]

instance Aeson.FromJSON LiveUpdateCommand where
    parseJSON = Aeson.withObject "LiveUpdateCommand" \object -> do
        messageType <- object Aeson..: "type"
        case (messageType :: Text) of
            "subscribe" ->
                SubscribeLiveUpdates
                    <$> object Aeson..: "scope"
                    <*> object Aeson..: "clientId"
                    <*> object Aeson..:? "lastSeenVersion"
            "unsubscribe" ->
                UnsubscribeLiveUpdates
                    <$> object Aeson..: "scope"
            _ -> fail ("Unknown live update command: " <> cs messageType)

instance Aeson.ToJSON LiveUpdateMessage where
    toJSON LiveUpdatesSubscribed { scope, currentVersion, resync } =
        Aeson.object
            [ "type" Aeson..= ("subscribed" :: Text)
            , "scope" Aeson..= scope
            , "currentVersion" Aeson..= currentVersion
            , "resync" Aeson..= resync
            ]
    toJSON LiveUpdatesInvalidated { scope, version, fragments, sourceClientId } =
        Aeson.object
            [ "type" Aeson..= ("invalidate" :: Text)
            , "scope" Aeson..= scope
            , "version" Aeson..= version
            , "fragments" Aeson..= fragments
            , "sourceClientId" Aeson..= sourceClientId
            ]
    toJSON LiveUpdatesError { message } =
        Aeson.object
            [ "type" Aeson..= ("error" :: Text)
            , "message" Aeson..= message
            ]

instance Aeson.FromJSON LiveUpdateMessage where
    parseJSON = Aeson.withObject "LiveUpdateMessage" \object -> do
        messageType <- object Aeson..: "type"
        case (messageType :: Text) of
            "subscribed" ->
                LiveUpdatesSubscribed
                    <$> object Aeson..: "scope"
                    <*> object Aeson..: "currentVersion"
                    <*> object Aeson..: "resync"
            "invalidate" ->
                LiveUpdatesInvalidated
                    <$> object Aeson..: "scope"
                    <*> object Aeson..: "version"
                    <*> object Aeson..: "fragments"
                    <*> object Aeson..:? "sourceClientId"
            "error" ->
                LiveUpdatesError
                    <$> object Aeson..: "message"
            _ -> fail ("Unknown live update message: " <> cs messageType)

data LiveSubscription = LiveSubscription
    { subscriptionId         :: !UUID.UUID
    , subscriptionScope      :: !Text
    , subscriptionConnection :: !WebSocket.Connection
    }

liveSubscriptionsRef :: IORef [LiveSubscription]
liveSubscriptionsRef = unsafePerformIO (newIORef [])
{-# NOINLINE liveSubscriptionsRef #-}

liveScopeVersionsRef :: IORef (Map.Map Text Int)
liveScopeVersionsRef = unsafePerformIO (newIORef Map.empty)
{-# NOINLINE liveScopeVersionsRef #-}

registerLiveSubscription :: UUID.UUID -> Text -> WebSocket.Connection -> IO ()
registerLiveSubscription subscriptionId scope connection =
    atomicModifyIORef' liveSubscriptionsRef \subscriptions ->
        ( LiveSubscription
            { subscriptionId
            , subscriptionScope = scope
            , subscriptionConnection = connection
            } : filter (\subscription -> subscription.subscriptionId /= subscriptionId) subscriptions
        , ()
        )

unregisterLiveSubscription :: UUID.UUID -> IO ()
unregisterLiveSubscription subscriptionId =
    atomicModifyIORef' liveSubscriptionsRef \subscriptions ->
        (filter (\subscription -> subscription.subscriptionId /= subscriptionId) subscriptions, ())

currentLiveUpdateVersion :: Text -> IO Int
currentLiveUpdateVersion scope =
    Map.findWithDefault 0 scope <$> readIORef liveScopeVersionsRef

resetLiveUpdateScope :: Text -> IO ()
resetLiveUpdateScope scope =
    atomicModifyIORef' liveScopeVersionsRef \versions ->
        (Map.delete scope versions, ())

incrementLiveUpdateVersion :: Text -> IO Int
incrementLiveUpdateVersion scope =
    atomicModifyIORef' liveScopeVersionsRef \versions ->
        let nextVersion = Map.findWithDefault 0 scope versions + 1
         in (Map.insert scope nextVersion versions, nextVersion)

broadcastLiveInvalidation :: Text -> [LiveFragmentRef] -> Maybe Text -> IO ()
broadcastLiveInvalidation scope fragments sourceClientId = do
    version <- incrementLiveUpdateVersion scope
    subscriptions <- readIORef liveSubscriptionsRef
    let matchingSubscriptions = filter (\subscription -> subscription.subscriptionScope == scope) subscriptions
    staleIds <- mapMaybeM (sendInvalidation scope version sourceClientId fragments) matchingSubscriptions
    unless (null staleIds) do
        atomicModifyIORef' liveSubscriptionsRef \activeSubscriptions ->
            ( filter (\subscription -> subscription.subscriptionId `notElem` staleIds) activeSubscriptions
            , ()
            )

sendInvalidation :: Text -> Int -> Maybe Text -> [LiveFragmentRef] -> LiveSubscription -> IO (Maybe UUID.UUID)
sendInvalidation scope version sourceClientId fragments subscription = do
    result <-
        Exception.tryAny $
            WebSocket.sendTextData subscription.subscriptionConnection (Aeson.encode message)
    pure $
        case result of
            Left _  -> Just subscription.subscriptionId
            Right _ -> Nothing
    where
        message =
            LiveUpdatesInvalidated
                { scope
                , version
                , fragments
                , sourceClientId
                }

mapMaybeM :: (a -> IO (Maybe b)) -> [a] -> IO [b]
mapMaybeM action values =
    catMaybes <$> mapM action values
