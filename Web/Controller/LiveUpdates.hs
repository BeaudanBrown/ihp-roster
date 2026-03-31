module Web.Controller.LiveUpdates where

import Application.Helper.Controller
import Application.Helper.LiveUpdate
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LByteString
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import qualified Network.WebSockets as WebSocket
import Web.Controller.Prelude

instance WSApp LiveUpdatesWSApp where
    initialState = LiveUpdatesWSApp { subscriptionIds = [] }

    run = do
        ensureIsUser

        forever do
            message <- receiveData @LByteString.ByteString
            case Aeson.decode message of
                Nothing ->
                    sendJSON
                        LiveUpdatesError
                            { message = "Could not decode live update command"
                            }
                Just command ->
                    handleCommand command

    onClose = do
        LiveUpdatesWSApp { subscriptionIds } <- getState
        mapM_ (unregisterLiveSubscription . fst) subscriptionIds

handleCommand ::
    ( ?state :: IORef LiveUpdatesWSApp
    , ?connection :: WebSocket.Connection
    , ?context :: ControllerContext
    , ?modelContext :: ModelContext
    ) =>
    LiveUpdateCommand ->
    IO ()
handleCommand command =
    case command of
        SubscribeLiveUpdates { scope, lastSeenVersion } -> do
            authorized <- isAuthorizedLiveUpdateScope scope
            if authorized
                then do
                    unregisterScopeSubscription scope
                    subscriptionId <- UUIDv4.nextRandom
                    registerLiveSubscription subscriptionId scope ?connection
                    addScopeSubscription subscriptionId scope
                    currentVersion <- liftIO (currentLiveUpdateVersion scope)
                    sendJSON
                        LiveUpdatesSubscribed
                            { scope
                            , currentVersion
                            , resync = maybe False (/= currentVersion) lastSeenVersion
                            }
                else
                    sendJSON
                        LiveUpdatesError
                            { message = "Not authorized for requested live update scope"
                            }
        UnsubscribeLiveUpdates { scope } ->
            unregisterScopeSubscription scope

unregisterScopeSubscription ::
    (?state :: IORef LiveUpdatesWSApp) =>
    Text ->
    IO ()
unregisterScopeSubscription scope = do
    LiveUpdatesWSApp { subscriptionIds } <- getState
    let (removed, kept) = partition (\(_, subscriptionScope) -> subscriptionScope == scope) subscriptionIds
    mapM_ (unregisterLiveSubscription . fst) removed
    setState LiveUpdatesWSApp { subscriptionIds = kept }

addScopeSubscription ::
    (?state :: IORef LiveUpdatesWSApp) =>
    UUID.UUID ->
    Text ->
    IO ()
addScopeSubscription subscriptionId scope = do
    LiveUpdatesWSApp { subscriptionIds } <- getState
    setState
        LiveUpdatesWSApp
            { subscriptionIds = (subscriptionId, scope) : subscriptionIds
            }
