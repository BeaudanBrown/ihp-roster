module Application.Helper.LiveUpdate
    ( LiveFragmentKey (..)
    , LiveFragmentProtection (..)
    , LiveFragmentRef (..)
    , FocusedFieldProtectionConfig (..)
    , LiveUpdateBroadcastResult (..)
    , LiveUpdateCommand (..)
    , LiveUpdateMessage (..)
    , LiveUpdateScope (..)
    , activeLiveUpdateScopes
    , activeLiveUpdateScopeMatches
    , activeRosterWeekScopes
    , broadcastLiveInvalidation
    , broadcastLiveInvalidationDetailed
    , broadcastLiveInvalidationDetailedWithoutContext
    , broadcastLiveInvalidationWithoutContext
    , broadcastLiveResync
    , broadcastLiveResyncWithoutContext
    , currentLiveUpdateVersion
    , liveUpdateSourceClientId
    , liveUpdateScopeKey
    , liveFragmentsRefreshTriggerPayload
    , mkLiveFragmentRef
    , registerLiveSubscription
    , unregisterLiveSubscription
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

import Application.Helper.Profiling (profileActionSpan)

data LiveUpdateScope
    = RosterWeekScope
        { venueId       :: !UUID.UUID
        , rosterGroupId :: !UUID.UUID
        , weekOffset    :: !Int
        }
    | RosterGroupConfigScope
        { venueId       :: !UUID.UUID
        , rosterGroupId :: !UUID.UUID
        }
    | AdminSlotNamesScope
        { venueId       :: !UUID.UUID
        , rosterGroupId :: !UUID.UUID
        }
    | AdminShiftTypesScope
        { venueId :: !UUID.UUID
        }
    | AdminRosterGroupsScope
        { venueId :: !UUID.UUID
        }
    | AdminInvitesScope
        { venueId :: !UUID.UUID
        }
    | AdminXeroScope
        { venueId :: !UUID.UUID
        }
    | LeaveRequestsScope
        { venueId :: !UUID.UUID
        }
    | TimesheetWeekScope
        { venueId    :: !UUID.UUID
        , weekOffset :: !Int
        }
    | SupportPlatformScope
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
    | AdminInvitesFragment
    | AdminSlotNamesFragment
        { rosterGroupId :: !UUID.UUID
        }
    | AdminShiftTypesFragment
    | AdminRosterGroupsFragment
    | AdminXeroFragment
    | AdminXeroStaffMappingsFragment
    | ProfileLeaveRequestsContentFragment
    | SupportAwardRatesSectionFragment
    | SupportPublicHolidaysSectionFragment
    deriving (Eq, Ord, Show)

data FocusedFieldProtectionConfig = FocusedFieldProtectionConfig
    { activeSelector    :: !Text
    , fieldKeyAttr      :: !Text
    , fieldNameFallback :: !Bool
    , containerSelector :: !(Maybe Text)
    }
    deriving (Eq, Show)

data LiveFragmentProtection
    = NoProtection
    | FocusedFieldProtection FocusedFieldProtectionConfig
    deriving (Eq, Show)

data LiveFragmentRef = LiveFragmentRef
    { fragmentKey      :: !LiveFragmentKey
    , targetId         :: !Text
    , url              :: !Text
    , deferUntilBlur   :: !Bool
    , protectionPolicy :: !LiveFragmentProtection
    }
    deriving (Eq, Show)

mkLiveFragmentRef :: LiveFragmentKey -> Text -> Text -> LiveFragmentRef
mkLiveFragmentRef fragmentKey targetId url =
    LiveFragmentRef
        { fragmentKey
        , targetId
        , url
        , deferUntilBlur = False
        , protectionPolicy = NoProtection
        }

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
        , scopeKey       :: !Text
        , currentVersion :: !Int
        , resync         :: !Bool
        }
    | LiveUpdatesInvalidated
        { scope          :: !LiveUpdateScope
        , scopeKey       :: !Text
        , version        :: !Int
        , fragments      :: ![LiveFragmentRef]
        , sourceClientId :: !(Maybe Text)
        }
    | LiveUpdatesError
        { message :: !Text
        }
    deriving (Eq, Show)

data LiveUpdateBroadcastResult = LiveUpdateBroadcastResult
    { broadcastVersion              :: !Int
    , broadcastSubscriberCount      :: !Int
    , broadcastFragmentCount        :: !Int
    , broadcastDroppedSubscriptions :: !Int
    }
    deriving (Eq, Show)

liveUpdateScopeKey :: LiveUpdateScope -> Text
liveUpdateScopeKey RosterWeekScope { venueId, rosterGroupId, weekOffset } =
    Text.intercalate ":" ["roster_week", UUID.toText venueId, UUID.toText rosterGroupId, tshow weekOffset]
liveUpdateScopeKey RosterGroupConfigScope { venueId, rosterGroupId } =
    Text.intercalate ":" ["roster_group_config", UUID.toText venueId, UUID.toText rosterGroupId]
liveUpdateScopeKey AdminSlotNamesScope { venueId, rosterGroupId } =
    Text.intercalate ":" ["admin_slot_names", UUID.toText venueId, UUID.toText rosterGroupId]
liveUpdateScopeKey AdminShiftTypesScope { venueId } =
    Text.intercalate ":" ["admin_shift_types", UUID.toText venueId]
liveUpdateScopeKey AdminRosterGroupsScope { venueId } =
    Text.intercalate ":" ["admin_roster_groups", UUID.toText venueId]
liveUpdateScopeKey AdminInvitesScope { venueId } =
    Text.intercalate ":" ["admin_invites", UUID.toText venueId]
liveUpdateScopeKey AdminXeroScope { venueId } =
    Text.intercalate ":" ["admin_xero", UUID.toText venueId]
liveUpdateScopeKey LeaveRequestsScope { venueId } =
    Text.intercalate ":" ["leave_requests", UUID.toText venueId]
liveUpdateScopeKey TimesheetWeekScope { venueId, weekOffset } =
    Text.intercalate ":" ["timesheet_week", UUID.toText venueId, tshow weekOffset]
liveUpdateScopeKey SupportPlatformScope =
    "support_platform"

liveUpdateSourceClientId :: (?request :: Request) => Maybe Text
liveUpdateSourceClientId =
    cs <$> getHeader "X-Live-Update-Client-Id"

liveFragmentsRefreshTriggerPayload :: [LiveFragmentRef] -> Aeson.Value
liveFragmentsRefreshTriggerPayload fragments =
    let detail =
            Aeson.object
                [ "fragments" Aeson..= fragments
                ]
     in Aeson.object
            [ "app-live-fragments-refresh" Aeson..= detail
            , "app-roster-fragments-refresh" Aeson..= detail
            ]

instance Aeson.ToJSON LiveUpdateScope where
    toJSON RosterWeekScope { venueId, rosterGroupId, weekOffset } =
        Aeson.object
            [ "kind" Aeson..= ("roster_week" :: Text)
            , "venueId" Aeson..= UUID.toText venueId
            , "rosterGroupId" Aeson..= UUID.toText rosterGroupId
            , "weekOffset" Aeson..= weekOffset
            ]
    toJSON RosterGroupConfigScope { venueId, rosterGroupId } =
        Aeson.object
            [ "kind" Aeson..= ("roster_group_config" :: Text)
            , "venueId" Aeson..= UUID.toText venueId
            , "rosterGroupId" Aeson..= UUID.toText rosterGroupId
            ]
    toJSON AdminSlotNamesScope { venueId, rosterGroupId } =
        Aeson.object
            [ "kind" Aeson..= ("admin_slot_names" :: Text)
            , "venueId" Aeson..= UUID.toText venueId
            , "rosterGroupId" Aeson..= UUID.toText rosterGroupId
            ]
    toJSON AdminShiftTypesScope { venueId } =
        Aeson.object
            [ "kind" Aeson..= ("admin_shift_types" :: Text)
            , "venueId" Aeson..= UUID.toText venueId
            ]
    toJSON AdminRosterGroupsScope { venueId } =
        Aeson.object
            [ "kind" Aeson..= ("admin_roster_groups" :: Text)
            , "venueId" Aeson..= UUID.toText venueId
            ]
    toJSON AdminInvitesScope { venueId } =
        Aeson.object
            [ "kind" Aeson..= ("admin_invites" :: Text)
            , "venueId" Aeson..= UUID.toText venueId
            ]
    toJSON AdminXeroScope { venueId } =
        Aeson.object
            [ "kind" Aeson..= ("admin_xero" :: Text)
            , "venueId" Aeson..= UUID.toText venueId
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
    toJSON SupportPlatformScope =
        Aeson.object
            [ "kind" Aeson..= ("support_platform" :: Text)
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
            "roster_group_config" ->
                RosterGroupConfigScope
                    <$> (parseUuid =<< object Aeson..: "venueId")
                    <*> (parseUuid =<< object Aeson..: "rosterGroupId")
            "admin_slot_names" ->
                AdminSlotNamesScope
                    <$> (parseUuid =<< object Aeson..: "venueId")
                    <*> (parseUuid =<< object Aeson..: "rosterGroupId")
            "admin_shift_types" ->
                AdminShiftTypesScope
                    <$> (parseUuid =<< object Aeson..: "venueId")
            "admin_roster_groups" ->
                AdminRosterGroupsScope
                    <$> (parseUuid =<< object Aeson..: "venueId")
            "admin_invites" ->
                AdminInvitesScope
                    <$> (parseUuid =<< object Aeson..: "venueId")
            "admin_xero" ->
                AdminXeroScope
                    <$> (parseUuid =<< object Aeson..: "venueId")
            "leave_requests" ->
                LeaveRequestsScope
                    <$> (parseUuid =<< object Aeson..: "venueId")
            "timesheet_week" ->
                TimesheetWeekScope
                    <$> (parseUuid =<< object Aeson..: "venueId")
                    <*> object Aeson..: "weekOffset"
            "support_platform" -> pure SupportPlatformScope
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
    toJSON AdminInvitesFragment =
        Aeson.object ["kind" Aeson..= ("admin_invites" :: Text)]
    toJSON AdminSlotNamesFragment { rosterGroupId } =
        Aeson.object
            [ "kind" Aeson..= ("admin_slot_names" :: Text)
            , "rosterGroupId" Aeson..= UUID.toText rosterGroupId
            ]
    toJSON AdminShiftTypesFragment =
        Aeson.object ["kind" Aeson..= ("admin_shift_types" :: Text)]
    toJSON AdminRosterGroupsFragment =
        Aeson.object ["kind" Aeson..= ("admin_roster_groups" :: Text)]
    toJSON AdminXeroFragment =
        Aeson.object ["kind" Aeson..= ("admin_xero" :: Text)]
    toJSON AdminXeroStaffMappingsFragment =
        Aeson.object ["kind" Aeson..= ("admin_xero_staff_mappings" :: Text)]
    toJSON ProfileLeaveRequestsContentFragment =
        Aeson.object ["kind" Aeson..= ("profile_leave_requests_content" :: Text)]
    toJSON SupportAwardRatesSectionFragment =
        Aeson.object ["kind" Aeson..= ("support_award_rates_section" :: Text)]
    toJSON SupportPublicHolidaysSectionFragment =
        Aeson.object ["kind" Aeson..= ("support_public_holidays_section" :: Text)]

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
            "admin_invites" -> pure AdminInvitesFragment
            "admin_slot_names" ->
                AdminSlotNamesFragment
                    <$> (parseUuid =<< object Aeson..: "rosterGroupId")
            "admin_shift_types" -> pure AdminShiftTypesFragment
            "admin_roster_groups" -> pure AdminRosterGroupsFragment
            "admin_xero" -> pure AdminXeroFragment
            "admin_xero_staff_mappings" -> pure AdminXeroStaffMappingsFragment
            "profile_leave_requests_content" -> pure ProfileLeaveRequestsContentFragment
            "support_award_rates_section" -> pure SupportAwardRatesSectionFragment
            "support_public_holidays_section" -> pure SupportPublicHolidaysSectionFragment
            _ -> fail ("Unknown live fragment kind: " <> cs kind)

instance Aeson.ToJSON FocusedFieldProtectionConfig where
    toJSON FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector } =
        Aeson.object
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
            <*> object Aeson..:? "containerSelector"

instance Aeson.ToJSON LiveFragmentProtection where
    toJSON NoProtection = Aeson.Null
    toJSON (FocusedFieldProtection config) =
        Aeson.object
            [ "kind" Aeson..= ("focused_field" :: Text)
            , "activeSelector" Aeson..= config.activeSelector
            , "fieldKeyAttr" Aeson..= config.fieldKeyAttr
            , "fieldNameFallback" Aeson..= config.fieldNameFallback
            , "containerSelector" Aeson..= config.containerSelector
            ]

instance Aeson.FromJSON LiveFragmentProtection where
    parseJSON Aeson.Null = pure NoProtection
    parseJSON value = Aeson.withObject "LiveFragmentProtection" parseProtection value
      where
        parseProtection object = do
            kind <- object Aeson..: "kind"
            case (kind :: Text) of
                "focused_field" ->
                    FocusedFieldProtection
                        <$> (FocusedFieldProtectionConfig
                            <$> object Aeson..: "activeSelector"
                            <*> object Aeson..: "fieldKeyAttr"
                            <*> object Aeson..: "fieldNameFallback"
                            <*> object Aeson..:? "containerSelector"
                            )
                _ -> fail ("Unknown live fragment protection kind: " <> cs kind)

instance Aeson.ToJSON LiveFragmentRef where
    toJSON LiveFragmentRef { fragmentKey, targetId, url, deferUntilBlur, protectionPolicy } =
        Aeson.object
            [ "fragmentKey" Aeson..= fragmentKey
            , "targetId" Aeson..= targetId
            , "url" Aeson..= url
            , "deferUntilBlur" Aeson..= deferUntilBlur
            , "protectionPolicy" Aeson..= protectionPolicy
            ]

instance Aeson.FromJSON LiveFragmentRef where
    parseJSON = Aeson.withObject "LiveFragmentRef" \object ->
        LiveFragmentRef
            <$> object Aeson..: "fragmentKey"
            <*> object Aeson..: "targetId"
            <*> object Aeson..: "url"
            <*> object Aeson..: "deferUntilBlur"
            <*> object Aeson..:? "protectionPolicy" Aeson..!= NoProtection

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
    toJSON LiveUpdatesSubscribed { scope, scopeKey, currentVersion, resync } =
        Aeson.object
            [ "type" Aeson..= ("subscribed" :: Text)
            , "scope" Aeson..= scope
            , "scopeKey" Aeson..= scopeKey
            , "currentVersion" Aeson..= currentVersion
            , "resync" Aeson..= resync
            ]
    toJSON LiveUpdatesInvalidated { scope, scopeKey, version, fragments, sourceClientId } =
        Aeson.object
            [ "type" Aeson..= ("invalidate" :: Text)
            , "scope" Aeson..= scope
            , "scopeKey" Aeson..= scopeKey
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

activeLiveUpdateScopes :: IO [LiveUpdateScope]
activeLiveUpdateScopes =
    Set.toList . Set.fromList . map (.subscriptionScope) <$> readIORef liveSubscriptionsRef

activeLiveUpdateScopeMatches :: Ord a => (LiveUpdateScope -> Maybe a) -> IO [a]
activeLiveUpdateScopeMatches matcher =
    Set.toList . Set.fromList . mapMaybe matcher <$> activeLiveUpdateScopes

activeRosterWeekScopes :: IO [(UUID.UUID, UUID.UUID, Int)]
activeRosterWeekScopes =
    activeLiveUpdateScopeMatches rosterWeekScopeParts
    where
        rosterWeekScopeParts RosterWeekScope { venueId, rosterGroupId, weekOffset } =
            Just (venueId, rosterGroupId, weekOffset)
        rosterWeekScopeParts _ =
            Nothing

currentLiveUpdateVersion :: LiveUpdateScope -> IO Int
currentLiveUpdateVersion scope =
    Map.findWithDefault 0 scope <$> readIORef liveScopeVersionsRef

incrementLiveUpdateVersion :: LiveUpdateScope -> IO Int
incrementLiveUpdateVersion scope =
    atomicModifyIORef' liveScopeVersionsRef \versions ->
        let nextVersion = Map.findWithDefault 0 scope versions + 1
         in (Map.insert scope nextVersion versions, nextVersion)

broadcastLiveInvalidation :: (?context :: ControllerContext) => LiveUpdateScope -> Maybe Text -> [LiveFragmentRef] -> IO ()
broadcastLiveInvalidation scope sourceClientId fragments =
    profileActionSpan "live_updates.broadcast_invalidation" $
        broadcastLiveInvalidationWithoutContext scope sourceClientId fragments

broadcastLiveInvalidationDetailed :: (?context :: ControllerContext) => LiveUpdateScope -> Maybe Text -> [LiveFragmentRef] -> IO LiveUpdateBroadcastResult
broadcastLiveInvalidationDetailed scope sourceClientId fragments =
    profileActionSpan "live_updates.broadcast_invalidation" $
        broadcastLiveInvalidationDetailedWithoutContext scope sourceClientId fragments

broadcastLiveInvalidationWithoutContext :: LiveUpdateScope -> Maybe Text -> [LiveFragmentRef] -> IO ()
broadcastLiveInvalidationWithoutContext scope sourceClientId fragments = do
    _ <- broadcastLiveInvalidationDetailedWithoutContext scope sourceClientId fragments
    pure ()

broadcastLiveInvalidationDetailedWithoutContext :: LiveUpdateScope -> Maybe Text -> [LiveFragmentRef] -> IO LiveUpdateBroadcastResult
broadcastLiveInvalidationDetailedWithoutContext scope sourceClientId fragments = do
    version <- incrementLiveUpdateVersion scope
    subscriptions <- readIORef liveSubscriptionsRef
    let matchingSubscriptions = filter (\subscription -> subscription.subscriptionScope == scope) subscriptions
    staleIds <- mapMaybeM (sendInvalidation scope version sourceClientId fragments) matchingSubscriptions
    unless (null staleIds) do
        atomicModifyIORef' liveSubscriptionsRef \activeSubscriptions ->
            ( filter (\subscription -> subscription.subscriptionId `notElem` staleIds) activeSubscriptions
            , ()
            )
    pure
        LiveUpdateBroadcastResult
            { broadcastVersion = version
            , broadcastSubscriberCount = length matchingSubscriptions
            , broadcastFragmentCount = length fragments
            , broadcastDroppedSubscriptions = length staleIds
            }

broadcastLiveResync :: (?context :: ControllerContext) => LiveUpdateScope -> Maybe Text -> IO ()
broadcastLiveResync scope sourceClientId =
    profileActionSpan "live_updates.broadcast_resync" $
        broadcastLiveResyncWithoutContext scope sourceClientId

broadcastLiveResyncWithoutContext :: LiveUpdateScope -> Maybe Text -> IO ()
broadcastLiveResyncWithoutContext scope sourceClientId =
    -- The declarative client treats an invalidation with no explicit fragments as
    -- "resync every fragment configured for this subscribed surface".
    broadcastLiveInvalidationWithoutContext scope sourceClientId []

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
                , scopeKey = liveUpdateScopeKey scope
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
