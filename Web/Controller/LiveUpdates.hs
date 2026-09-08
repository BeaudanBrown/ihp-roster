module Web.Controller.LiveUpdates where

import Application.Helper.Controller
import Application.Helper.FrontendContract.Surface.Authorization (validateFrontendSurfaceLiveSubscription)
import Application.Helper.LiveUpdate.DurableState (fetchDurableDependencyWatermark)
import Application.Helper.LiveUpdate.Runtime
import qualified Data.Aeson as Aeson
import qualified Data.ByteString.Lazy as LByteString
import qualified Data.UUID as UUID
import qualified Data.UUID.V4 as UUIDv4
import qualified Network.WebSockets as WebSocket
import Web.Controller.Prelude
import Web.SurfaceInvalidation (authorizeSurfaceScope)

instance WSApp LiveUpdatesWSApp where
    initialState = LiveUpdatesWSApp { subscriptionIds = [] }

    run = do
        let ?context = ?request
        -- HTTP response callbacks are unavailable after the WebSocket upgrade.
        -- Reject through the socket protocol, before accepting any commands.
        allowed <- if isNothing (withRequestContext (currentUserOrNothing @User))
                || (not currentUserIsUnimpersonatedSuperAdmin && isNothing currentVenueOrNothing)
            then pure False
            else isOperationallyActive
        if not allowed
            then WebSocket.sendCloseCode ?connection 1008 ("Not authorized" :: Text)
            else receiveCommands

    onClose = do
        LiveUpdatesWSApp { subscriptionIds } <- getState
        mapM_ (unregisterSurfaceSubscription . fst) subscriptionIds

receiveCommands :: (?state :: IORef LiveUpdatesWSApp, ?connection :: WebSocket.Connection, ?context :: ControllerContext, ?modelContext :: ModelContext) => IO ()
receiveCommands =
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

handleCommand ::
    ( ?state :: IORef LiveUpdatesWSApp
    , ?connection :: WebSocket.Connection
    , ?context :: ControllerContext
    , ?modelContext :: ModelContext
    ) =>
    LiveUpdateCommand ->
    IO ()
handleCommand command =
    withLiveUpdateTelemetrySpan (liveUpdateCommandForTelemetry command) $
    case command of
        SubscribeLiveUpdates { subscription = liveSubscription, lastSeenVersion } -> do
            let scope = liveSubscription.subscriptionScope
            authorized <- authorizeSurfaceScope scope
            if authorized && validateFrontendSurfaceLiveSubscription liveSubscription
                then do
                    unregisterScopeSubscription scope
                    subscriptionId <- UUIDv4.nextRandom
                    registerSurfaceSubscription subscriptionId liveSubscription ?connection
                    addScopeSubscription subscriptionId scope
                    durableWatermark <- fetchDurableDependencyWatermark liveSubscription
                    let currentVersion = durableWatermark
                    sendJSON
                        LiveUpdatesSubscribed
                            { scope
                            , scopeKey = liveSubscription.subscriptionScopeKey
                            , currentVersion
                            , resync = liveUpdateSubscriptionNeedsResync
                                liveSubscription.subscriptionRenderedDependencyWatermark
                                durableWatermark
                                lastSeenVersion
                                currentVersion
                            }
                else
                    sendJSON
                        LiveUpdatesError
                            { message = "Not authorized for requested live update subscription"
                            }
        UnsubscribeLiveUpdates { subscription = liveSubscription } ->
            unregisterScopeSubscription liveSubscription.subscriptionScope

liveUpdateCommandForTelemetry :: LiveUpdateCommand -> Text
liveUpdateCommandForTelemetry SubscribeLiveUpdates {}   = "subscribe"
liveUpdateCommandForTelemetry UnsubscribeLiveUpdates {} = "unsubscribe"

unregisterScopeSubscription ::
    (?state :: IORef LiveUpdatesWSApp) =>
    SurfaceScope ->
    IO ()
unregisterScopeSubscription scope = do
    LiveUpdatesWSApp { subscriptionIds } <- getState
    let (removed, kept) = partition (\(_, encodedScope) -> encodedScope == encodeScopeKey scope) subscriptionIds
    mapM_ (unregisterSurfaceSubscription . fst) removed
    setState LiveUpdatesWSApp { subscriptionIds = kept }

addScopeSubscription ::
    (?state :: IORef LiveUpdatesWSApp) =>
    UUID.UUID ->
    SurfaceScope ->
    IO ()
addScopeSubscription subscriptionId scope = do
    LiveUpdatesWSApp { subscriptionIds } <- getState
    setState
        LiveUpdatesWSApp
            { subscriptionIds = (subscriptionId, encodeScopeKey scope) : subscriptionIds
            }

encodeScopeKey :: SurfaceScope -> Text
encodeScopeKey = cs . Aeson.encode
