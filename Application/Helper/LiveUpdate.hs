module Application.Helper.LiveUpdate
    ( LiveFragmentKey (..)
    , LiveFragmentRef (..)
    , LiveUpdateCommand (..)
    , LiveUpdateMessage (..)
    , LiveUpdateScope (..)
    , broadcastLiveInvalidation
    , currentLiveUpdateVersion
    , registerLiveSubscription
    , unregisterLiveSubscription
    ) where

import qualified Control.Exception.Safe as Exception
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import Data.IORef
import qualified Data.Map.Strict as Map
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import IHP.Prelude
import qualified Network.WebSockets as WebSocket
import System.IO.Unsafe (unsafePerformIO)

data LiveUpdateScope
    = RosterWeekScope
        { venueId    :: !UUID.UUID
        , rosterGroupId :: !UUID.UUID
        , weekOffset :: !Int
        }
    | LeaveRequestsScope
        { venueId :: !UUID.UUID
        }
    | TimesheetWeekScope
        { venueId    :: !UUID.UUID
        , weekOffset :: !Int
        }
    deriving (Eq, Ord, Show)

data LiveFragmentKey
    = RosterContentFragment
    | RosterStaffPanelFragment
    | RosterDaySectionFragment
        { rosterDayId :: !UUID.UUID
        }
    | RosterRowFragment
        { rosterDayId :: !UUID.UUID
        , rowIndex    :: !Int
        }
    | LeaveRequestsContentFragment
    | TimesheetDaySectionFragment
        { dayOffset :: !Int
        }
    deriving (Eq, Ord, Show)

data LiveFragmentRef = LiveFragmentRef
    { fragmentKey    :: !LiveFragmentKey
    , targetId       :: !Text
    , url            :: !Text
    , deferUntilBlur :: !Bool
    }
    deriving (Eq, Show)

data LiveUpdateCommand
    = SubscribeLiveUpdates
        { scope           :: !LiveUpdateScope
        , clientId        :: !Text
        , lastSeenVersion :: !(Maybe Int)
        }
    | UnsubscribeLiveUpdates
        { scope :: !LiveUpdateScope
        }
    deriving (Eq, Show)

data LiveUpdateMessage
    = LiveUpdatesSubscribed
        { scope          :: !LiveUpdateScope
        , currentVersion :: !Int
        , resync         :: !Bool
        }
    | LiveUpdatesInvalidated
        { scope          :: !LiveUpdateScope
        , version        :: !Int
        , fragments      :: ![LiveFragmentRef]
        , sourceClientId :: !(Maybe Text)
        }
    | LiveUpdatesError
        { message :: !Text
        }
    deriving (Eq, Show)

instance Aeson.ToJSON LiveUpdateScope where
    toJSON RosterWeekScope { venueId, rosterGroupId, weekOffset } =
        Aeson.object
            [ "kind" Aeson..= ("roster_week" :: Text)
            , "venueId" Aeson..= UUID.toText venueId
            , "rosterGroupId" Aeson..= UUID.toText rosterGroupId
            , "weekOffset" Aeson..= weekOffset
            ]
    toJSON LeaveRequestsScope { venueId } =
        Aeson.object
            [ "kind" Aeson..= ("leave_requests" :: Text)
            , "venueId" Aeson..= UUID.toText venueId
            ]
    toJSON TimesheetWeekScope { venueId, weekOffset } =
        Aeson.object
            [ "kind" Aeson..= ("timesheet_week" :: Text)
            , "venueId" Aeson..= UUID.toText venueId
            , "weekOffset" Aeson..= weekOffset
            ]

instance Aeson.FromJSON LiveUpdateScope where
    parseJSON = Aeson.withObject "LiveUpdateScope" \object -> do
        kind <- object Aeson..: "kind"
        case (kind :: Text) of
            "roster_week" ->
                RosterWeekScope
                    <$> (parseUuid =<< object Aeson..: "venueId")
                    <*> (parseUuid =<< object Aeson..: "rosterGroupId")
                    <*> object Aeson..: "weekOffset"
            "leave_requests" ->
                LeaveRequestsScope
                    <$> (parseUuid =<< object Aeson..: "venueId")
            "timesheet_week" ->
                TimesheetWeekScope
                    <$> (parseUuid =<< object Aeson..: "venueId")
                    <*> object Aeson..: "weekOffset"
            _ -> fail ("Unknown live update scope kind: " <> cs kind)

instance Aeson.ToJSON LiveFragmentKey where
    toJSON RosterContentFragment =
        Aeson.object ["kind" Aeson..= ("roster_content" :: Text)]
    toJSON RosterStaffPanelFragment =
        Aeson.object ["kind" Aeson..= ("roster_staff_panel" :: Text)]
    toJSON RosterDaySectionFragment { rosterDayId } =
        Aeson.object
            [ "kind" Aeson..= ("roster_day_section" :: Text)
            , "rosterDayId" Aeson..= UUID.toText rosterDayId
            ]
    toJSON RosterRowFragment { rosterDayId, rowIndex } =
        Aeson.object
            [ "kind" Aeson..= ("roster_row" :: Text)
            , "rosterDayId" Aeson..= UUID.toText rosterDayId
            , "rowIndex" Aeson..= rowIndex
            ]
    toJSON LeaveRequestsContentFragment =
        Aeson.object ["kind" Aeson..= ("leave_requests_content" :: Text)]
    toJSON TimesheetDaySectionFragment { dayOffset } =
        Aeson.object
            [ "kind" Aeson..= ("timesheet_day_section" :: Text)
            , "dayOffset" Aeson..= dayOffset
            ]

instance Aeson.FromJSON LiveFragmentKey where
    parseJSON = Aeson.withObject "LiveFragmentKey" \object -> do
        kind <- object Aeson..: "kind"
        case (kind :: Text) of
            "roster_content" -> pure RosterContentFragment
            "roster_staff_panel" -> pure RosterStaffPanelFragment
            "roster_day_section" ->
                RosterDaySectionFragment
                    <$> (parseUuid =<< object Aeson..: "rosterDayId")
            "roster_row" ->
                RosterRowFragment
                    <$> (parseUuid =<< object Aeson..: "rosterDayId")
                    <*> object Aeson..: "rowIndex"
            "leave_requests_content" -> pure LeaveRequestsContentFragment
            "timesheet_day_section" ->
                TimesheetDaySectionFragment
                    <$> object Aeson..: "dayOffset"
            _ -> fail ("Unknown live fragment kind: " <> cs kind)

instance Aeson.ToJSON LiveFragmentRef where
    toJSON LiveFragmentRef { fragmentKey, targetId, url, deferUntilBlur } =
        Aeson.object
            [ "fragmentKey" Aeson..= fragmentKey
            , "targetId" Aeson..= targetId
            , "url" Aeson..= url
            , "deferUntilBlur" Aeson..= deferUntilBlur
            ]

instance Aeson.FromJSON LiveFragmentRef where
    parseJSON = Aeson.withObject "LiveFragmentRef" \object ->
        LiveFragmentRef
            <$> object Aeson..: "fragmentKey"
            <*> object Aeson..: "targetId"
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

data LiveSubscription = LiveSubscription
    { subscriptionId         :: !UUID.UUID
    , subscriptionScope      :: !LiveUpdateScope
    , subscriptionConnection :: !WebSocket.Connection
    }

liveSubscriptionsRef :: IORef [LiveSubscription]
liveSubscriptionsRef = unsafePerformIO (newIORef [])
{-# NOINLINE liveSubscriptionsRef #-}

liveScopeVersionsRef :: IORef (Map.Map LiveUpdateScope Int)
liveScopeVersionsRef = unsafePerformIO (newIORef Map.empty)
{-# NOINLINE liveScopeVersionsRef #-}

registerLiveSubscription :: UUID.UUID -> LiveUpdateScope -> WebSocket.Connection -> IO ()
registerLiveSubscription subscriptionId scope connection =
    atomicModifyIORef' liveSubscriptionsRef \subscriptions ->
        ( LiveSubscription { subscriptionId, subscriptionScope = scope, subscriptionConnection = connection }
            : filter (\subscription -> subscription.subscriptionId /= subscriptionId) subscriptions
        , ()
        )

unregisterLiveSubscription :: UUID.UUID -> IO ()
unregisterLiveSubscription subscriptionId =
    atomicModifyIORef' liveSubscriptionsRef \subscriptions ->
        (filter (\subscription -> subscription.subscriptionId /= subscriptionId) subscriptions, ())

currentLiveUpdateVersion :: LiveUpdateScope -> IO Int
currentLiveUpdateVersion scope =
    Map.findWithDefault 0 scope <$> readIORef liveScopeVersionsRef

incrementLiveUpdateVersion :: LiveUpdateScope -> IO Int
incrementLiveUpdateVersion scope =
    atomicModifyIORef' liveScopeVersionsRef \versions ->
        let nextVersion = Map.findWithDefault 0 scope versions + 1
         in (Map.insert scope nextVersion versions, nextVersion)

broadcastLiveInvalidation :: LiveUpdateScope -> Maybe Text -> [LiveFragmentRef] -> IO ()
broadcastLiveInvalidation scope sourceClientId fragments = do
    version <- incrementLiveUpdateVersion scope
    subscriptions <- readIORef liveSubscriptionsRef
    let matchingSubscriptions = filter (\subscription -> subscription.subscriptionScope == scope) subscriptions
    staleIds <- mapMaybeM (sendInvalidation scope version sourceClientId fragments) matchingSubscriptions
    unless (null staleIds) do
        atomicModifyIORef' liveSubscriptionsRef \activeSubscriptions ->
            ( filter (\subscription -> subscription.subscriptionId `notElem` staleIds) activeSubscriptions
            , ()
            )

sendInvalidation :: LiveUpdateScope -> Int -> Maybe Text -> [LiveFragmentRef] -> LiveSubscription -> IO (Maybe UUID.UUID)
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

parseUuid :: Text -> Aeson.Parser UUID.UUID
parseUuid value =
    case UUID.fromText (Text.strip value) of
        Just uuid -> pure uuid
        Nothing   -> fail ("Invalid UUID: " <> cs value)

mapMaybeM :: (a -> IO (Maybe b)) -> [a] -> IO [b]
mapMaybeM action values =
    catMaybes <$> mapM action values
