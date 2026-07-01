module Application.Helper.LiveUpdate.Internal
    ( LiveFragmentKey (..)
    , LiveFragmentProtection (..)
    , LiveUpdateWireFragment (..)
    , LiveBus
    , FocusedFieldProtectionConfig (..)
    , LiveUpdateBroadcastResult (..)
    , LiveUpdateCommand (..)
    , LiveUpdateMessage (..)
    , LiveUpdateScope (..)
    , activeLiveUpdateScopes
    , activeLiveUpdateScopesWithBus
    , activeLiveUpdateScopeMatches
    , activeLiveUpdateScopeMatchesWithBus
    , activeRosterWeekScopes
    , activeRosterWeekScopesWithBus
    , broadcastLiveInvalidation
    , broadcastLiveInvalidationDetailed
    , broadcastLiveInvalidationDetailedWithBus
    , broadcastLiveInvalidationDetailedWithoutContext
    , broadcastLiveInvalidationWithoutContext
    , broadcastLiveResync
    , broadcastLiveResyncWithoutContext
    , coalesceLiveUpdateWireFragments
    , currentLiveUpdateVersion
    , currentLiveUpdateVersionWithBus
    , incrementLiveUpdateVersionWithBus
    , liveUpdateSourceClientId
    , liveUpdateScopeFromWire
    , liveUpdateScopeKey
    , liveUpdateScopeKind
    , liveUpdateScopeToWire
    , liveFragmentKeyKind
    , liveUpdateWireFragmentFromWire
    , liveUpdateWireFragmentKind
    , liveUpdateWireFragmentToWire
    , mkLiveUpdateWireFragment
    , newInMemoryLiveBus
    , registerLiveSubscription
    , registerLiveSubscriptionWithBus
    , unregisterLiveSubscription
    , unregisterLiveSubscriptionWithBus
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

import qualified Application.Helper.Frontend.LiveUpdateSchema as Wire
import Application.Helper.Profiling (profileActionSpan,
                                     profileActionSpanWithDetail)

data LiveUpdateScope
    = RosterWeekScope
        { venueId       :: !UUID.UUID
        , rosterGroupId :: !UUID.UUID
        , weekOffset    :: !Int
        }
    | AdminVenueConfigScope
        { venueId :: !UUID.UUID
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
    | AdminExportsScope
        { venueId :: !UUID.UUID
        }
    | AdminXeroScope
        { venueId :: !UUID.UUID
        }
    | BillingScope
        { venueId :: !UUID.UUID
        }
    | LeaveRequestsScope
        { venueId :: !UUID.UUID
        }
    | TimesheetWeekScope
        { venueId    :: !UUID.UUID
        , weekOffset :: !Int
        }
    | ProfileScope
        { venueId :: !UUID.UUID
        , staffId :: !UUID.UUID
        }
    | SupportPlatformScope
    deriving (Eq, Ord, Show)

liveUpdateScopeKind :: LiveUpdateScope -> Text
liveUpdateScopeKind RosterWeekScope {}        = "roster_week"
liveUpdateScopeKind AdminVenueConfigScope {}  = "admin_venue_config"
liveUpdateScopeKind AdminShiftTypesScope {}   = "admin_shift_types"
liveUpdateScopeKind AdminRosterGroupsScope {} = "admin_roster_groups"
liveUpdateScopeKind AdminInvitesScope {}      = "admin_invites"
liveUpdateScopeKind AdminExportsScope {}      = "admin_exports"
liveUpdateScopeKind AdminXeroScope {}         = "admin_xero"
liveUpdateScopeKind BillingScope {}           = "billing"
liveUpdateScopeKind LeaveRequestsScope {}     = "leave_requests"
liveUpdateScopeKind TimesheetWeekScope {}     = "timesheet_week"
liveUpdateScopeKind ProfileScope {}           = "profile"
liveUpdateScopeKind SupportPlatformScope      = "support_platform"

data LiveFragmentKey
    = RosterContentFragment
    | RosterGridToolbarFragment
    | RosterGridFrameFragment
    | RosterDayColumnsFragment
    | RosterDayRailFragment
    | RosterWageRailFragment
    | RosterSlotsGridFragment
    | RosterStaffPanelFragment
    | RosterDaySectionFragment
        { rosterDayId :: !UUID.UUID
        }
    | RosterRowFragment
        { rosterDayId :: !UUID.UUID
        , rowIndex    :: !Int
        }
    | LeaveRequestsContentFragment
    | TimesheetToolbarFragment
    | TimesheetDayColumnsFragment
    | TimesheetDaySectionFragment
        { dayOffset :: !Int
        }
    | AdminVenueConfigFragment
    | AdminInvitesFragment
    | AdminExportsFragment
    | AdminShiftTypesFragment
    | AdminRosterGroupsFragment
    | AdminXeroFragment
    | AdminXeroStaffMappingsFragment
    | AdminXeroPayItemsFragment
    | AdminXeroTimesheetsFragment
    | BillingStatusFragment
    | ProfileContentFragment
    | ProfileLeaveRequestsContentFragment
    | SupportAwardRatesSectionFragment
    | SupportPublicHolidaysSectionFragment
    deriving (Eq, Ord, Show)

liveFragmentKeyKind :: LiveFragmentKey -> Text
liveFragmentKeyKind RosterContentFragment = "roster_content"
liveFragmentKeyKind RosterGridToolbarFragment = "roster_grid_toolbar"
liveFragmentKeyKind RosterGridFrameFragment = "roster_grid_frame"
liveFragmentKeyKind RosterDayColumnsFragment = "roster_day_columns"
liveFragmentKeyKind RosterDayRailFragment = "roster_day_rail"
liveFragmentKeyKind RosterWageRailFragment = "roster_wage_rail"
liveFragmentKeyKind RosterSlotsGridFragment = "roster_slots_grid"
liveFragmentKeyKind RosterStaffPanelFragment = "roster_staff_panel"
liveFragmentKeyKind RosterDaySectionFragment {} = "roster_day_section"
liveFragmentKeyKind RosterRowFragment {} = "roster_row"
liveFragmentKeyKind LeaveRequestsContentFragment = "leave_requests_content"
liveFragmentKeyKind TimesheetToolbarFragment = "timesheet_toolbar"
liveFragmentKeyKind TimesheetDayColumnsFragment = "timesheet_day_columns"
liveFragmentKeyKind TimesheetDaySectionFragment {} = "timesheet_day_section"
liveFragmentKeyKind AdminVenueConfigFragment = "admin_venue_config"
liveFragmentKeyKind AdminInvitesFragment = "admin_invites"
liveFragmentKeyKind AdminExportsFragment = "admin_exports"
liveFragmentKeyKind AdminShiftTypesFragment = "admin_shift_types"
liveFragmentKeyKind AdminRosterGroupsFragment = "admin_roster_groups"
liveFragmentKeyKind AdminXeroFragment = "admin_xero"
liveFragmentKeyKind AdminXeroStaffMappingsFragment = "admin_xero_staff_mappings"
liveFragmentKeyKind AdminXeroPayItemsFragment = "admin_xero_pay_items"
liveFragmentKeyKind AdminXeroTimesheetsFragment = "admin_xero_timesheets"
liveFragmentKeyKind BillingStatusFragment = "billing_status"
liveFragmentKeyKind ProfileContentFragment = "profile_content"
liveFragmentKeyKind ProfileLeaveRequestsContentFragment = "profile_leave_requests_content"
liveFragmentKeyKind SupportAwardRatesSectionFragment = "support_award_rates_section"
liveFragmentKeyKind SupportPublicHolidaysSectionFragment = "support_public_holidays_section"

liveUpdateWireFragmentKind :: LiveUpdateWireFragment -> Text
liveUpdateWireFragmentKind fragment = liveFragmentKeyKind fragment.fragmentKey

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

data LiveUpdateWireFragment = LiveUpdateWireFragment
    { fragmentKey      :: !LiveFragmentKey
    , targetId         :: !Text
    , url              :: !Text
    , deferUntilBlur   :: !Bool
    , protectionPolicy :: !LiveFragmentProtection
    }
    deriving (Eq, Show)

mkLiveUpdateWireFragment :: LiveFragmentKey -> Text -> Text -> LiveUpdateWireFragment
mkLiveUpdateWireFragment fragmentKey targetId url =
    LiveUpdateWireFragment
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
        , fragments      :: ![LiveUpdateWireFragment]
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

liveUpdateScopeKey :: LiveUpdateScope -> Text
liveUpdateScopeKey RosterWeekScope { venueId, rosterGroupId, weekOffset } =
    Text.intercalate ":" ["roster_week", UUID.toText venueId, UUID.toText rosterGroupId, tshow weekOffset]
liveUpdateScopeKey AdminVenueConfigScope { venueId } =
    Text.intercalate ":" ["admin_venue_config", UUID.toText venueId]
liveUpdateScopeKey AdminShiftTypesScope { venueId } =
    Text.intercalate ":" ["admin_shift_types", UUID.toText venueId]
liveUpdateScopeKey AdminRosterGroupsScope { venueId } =
    Text.intercalate ":" ["admin_roster_groups", UUID.toText venueId]
liveUpdateScopeKey AdminInvitesScope { venueId } =
    Text.intercalate ":" ["admin_invites", UUID.toText venueId]
liveUpdateScopeKey AdminExportsScope { venueId } =
    Text.intercalate ":" ["admin_exports", UUID.toText venueId]
liveUpdateScopeKey AdminXeroScope { venueId } =
    Text.intercalate ":" ["admin_xero", UUID.toText venueId]
liveUpdateScopeKey BillingScope { venueId } =
    Text.intercalate ":" ["billing", UUID.toText venueId]
liveUpdateScopeKey LeaveRequestsScope { venueId } =
    Text.intercalate ":" ["leave_requests", UUID.toText venueId]
liveUpdateScopeKey TimesheetWeekScope { venueId, weekOffset } =
    Text.intercalate ":" ["timesheet_week", UUID.toText venueId, tshow weekOffset]
liveUpdateScopeKey ProfileScope { venueId, staffId } =
    Text.intercalate ":" ["profile", UUID.toText venueId, UUID.toText staffId]
liveUpdateScopeKey SupportPlatformScope =
    "support_platform"

liveUpdateSourceClientId :: (?request :: Request) => Maybe Text
liveUpdateSourceClientId =
    cs <$> getHeader "X-Live-Update-Client-Id"

instance Aeson.ToJSON LiveUpdateScope where
    toJSON = Aeson.toJSON . liveUpdateScopeToWire

instance Aeson.FromJSON LiveUpdateScope where
    parseJSON value = liveUpdateScopeFromWire =<< Aeson.parseJSON value

instance Aeson.ToJSON LiveFragmentKey where
    toJSON = Aeson.toJSON . liveFragmentKeyToWire

instance Aeson.FromJSON LiveFragmentKey where
    parseJSON value = liveFragmentKeyFromWire =<< Aeson.parseJSON value

instance Aeson.ToJSON FocusedFieldProtectionConfig where
    toJSON = Aeson.toJSON . focusedFieldProtectionConfigToWire

instance Aeson.FromJSON FocusedFieldProtectionConfig where
    parseJSON value = focusedFieldProtectionConfigFromWire <$> Aeson.parseJSON value

instance Aeson.ToJSON LiveFragmentProtection where
    toJSON = Aeson.toJSON . liveFragmentProtectionToWire

instance Aeson.FromJSON LiveFragmentProtection where
    parseJSON value = liveFragmentProtectionFromWire <$> Aeson.parseJSON value

instance Aeson.ToJSON LiveUpdateWireFragment where
    toJSON = Aeson.toJSON . liveUpdateWireFragmentToWire

instance Aeson.FromJSON LiveUpdateWireFragment where
    parseJSON value = liveUpdateWireFragmentFromWire =<< Aeson.parseJSON value

instance Aeson.ToJSON LiveUpdateCommand where
    toJSON = Aeson.toJSON . liveUpdateCommandToWire

instance Aeson.FromJSON LiveUpdateCommand where
    parseJSON value = liveUpdateCommandFromWire =<< Aeson.parseJSON value

instance Aeson.ToJSON LiveUpdateMessage where
    toJSON = Aeson.toJSON . liveUpdateMessageToWire

data LiveSubscription = LiveSubscription
    { subscriptionId         :: !UUID.UUID
    , subscriptionScope      :: !LiveUpdateScope
    , subscriptionConnection :: !WebSocket.Connection
    }

data LiveBus = LiveBus
    { liveBusRegisterSubscription     :: UUID.UUID -> LiveUpdateScope -> WebSocket.Connection -> IO ()
    , liveBusUnregisterSubscription   :: UUID.UUID -> IO ()
    , liveBusActiveScopes             :: IO [LiveUpdateScope]
    , liveBusCurrentVersion           :: LiveUpdateScope -> IO Int
    , liveBusIncrementVersion         :: LiveUpdateScope -> IO Int
    , liveBusBroadcastInvalidation    :: LiveUpdateScope -> Maybe Text -> [LiveUpdateWireFragment] -> IO LiveUpdateBroadcastResult
    }

data InMemoryLiveBusState = InMemoryLiveBusState
    { inMemorySubscriptionsRef :: !(IORef [LiveSubscription])
    , inMemoryScopeVersionsRef :: !(IORef (Map.Map LiveUpdateScope Int))
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
        , liveBusActiveScopes = activeInMemoryScopes state
        , liveBusCurrentVersion = currentInMemoryVersion state
        , liveBusIncrementVersion = incrementInMemoryVersion state
        , liveBusBroadcastInvalidation = broadcastInMemoryInvalidation state
        }

registerLiveSubscription :: UUID.UUID -> LiveUpdateScope -> WebSocket.Connection -> IO ()
registerLiveSubscription =
    registerLiveSubscriptionWithBus defaultLiveBus

registerLiveSubscriptionWithBus :: LiveBus -> UUID.UUID -> LiveUpdateScope -> WebSocket.Connection -> IO ()
registerLiveSubscriptionWithBus =
    liveBusRegisterSubscription

registerInMemorySubscription :: InMemoryLiveBusState -> UUID.UUID -> LiveUpdateScope -> WebSocket.Connection -> IO ()
registerInMemorySubscription state subscriptionId scope connection =
    atomicModifyIORef' state.inMemorySubscriptionsRef \subscriptions ->
        ( LiveSubscription { subscriptionId, subscriptionScope = scope, subscriptionConnection = connection }
            : filter (\subscription -> subscription.subscriptionId /= subscriptionId) subscriptions
        , ()
        )

unregisterLiveSubscription :: UUID.UUID -> IO ()
unregisterLiveSubscription =
    unregisterLiveSubscriptionWithBus defaultLiveBus

unregisterLiveSubscriptionWithBus :: LiveBus -> UUID.UUID -> IO ()
unregisterLiveSubscriptionWithBus =
    liveBusUnregisterSubscription

unregisterInMemorySubscription :: InMemoryLiveBusState -> UUID.UUID -> IO ()
unregisterInMemorySubscription state subscriptionId =
    atomicModifyIORef' state.inMemorySubscriptionsRef \subscriptions ->
        (filter (\subscription -> subscription.subscriptionId /= subscriptionId) subscriptions, ())

activeLiveUpdateScopes :: IO [LiveUpdateScope]
activeLiveUpdateScopes =
    activeLiveUpdateScopesWithBus defaultLiveBus

activeLiveUpdateScopesWithBus :: LiveBus -> IO [LiveUpdateScope]
activeLiveUpdateScopesWithBus =
    liveBusActiveScopes

activeInMemoryScopes :: InMemoryLiveBusState -> IO [LiveUpdateScope]
activeInMemoryScopes state =
    Set.toList . Set.fromList . map (.subscriptionScope) <$> readIORef state.inMemorySubscriptionsRef

activeLiveUpdateScopeMatches :: Ord a => (LiveUpdateScope -> Maybe a) -> IO [a]
activeLiveUpdateScopeMatches =
    activeLiveUpdateScopeMatchesWithBus defaultLiveBus

activeLiveUpdateScopeMatchesWithBus :: Ord a => LiveBus -> (LiveUpdateScope -> Maybe a) -> IO [a]
activeLiveUpdateScopeMatchesWithBus bus matcher =
    Set.toList . Set.fromList . mapMaybe matcher <$> activeLiveUpdateScopesWithBus bus

activeRosterWeekScopes :: IO [(UUID.UUID, UUID.UUID, Int)]
activeRosterWeekScopes =
    activeRosterWeekScopesWithBus defaultLiveBus

activeRosterWeekScopesWithBus :: LiveBus -> IO [(UUID.UUID, UUID.UUID, Int)]
activeRosterWeekScopesWithBus bus =
    activeLiveUpdateScopeMatchesWithBus bus rosterWeekScopeParts
    where
        rosterWeekScopeParts RosterWeekScope { venueId, rosterGroupId, weekOffset } =
            Just (venueId, rosterGroupId, weekOffset)
        rosterWeekScopeParts _ =
            Nothing

currentLiveUpdateVersion :: LiveUpdateScope -> IO Int
currentLiveUpdateVersion =
    currentLiveUpdateVersionWithBus defaultLiveBus

currentLiveUpdateVersionWithBus :: LiveBus -> LiveUpdateScope -> IO Int
currentLiveUpdateVersionWithBus =
    liveBusCurrentVersion

currentInMemoryVersion :: InMemoryLiveBusState -> LiveUpdateScope -> IO Int
currentInMemoryVersion state scope =
    Map.findWithDefault 0 scope <$> readIORef state.inMemoryScopeVersionsRef

incrementLiveUpdateVersion :: LiveUpdateScope -> IO Int
incrementLiveUpdateVersion =
    incrementLiveUpdateVersionWithBus defaultLiveBus

incrementLiveUpdateVersionWithBus :: LiveBus -> LiveUpdateScope -> IO Int
incrementLiveUpdateVersionWithBus =
    liveBusIncrementVersion

incrementInMemoryVersion :: InMemoryLiveBusState -> LiveUpdateScope -> IO Int
incrementInMemoryVersion state scope =
    atomicModifyIORef' state.inMemoryScopeVersionsRef \versions ->
        let nextVersion = Map.findWithDefault 0 scope versions + 1
         in (Map.insert scope nextVersion versions, nextVersion)

broadcastLiveInvalidation :: (?context :: ControllerContext) => LiveUpdateScope -> Maybe Text -> [LiveUpdateWireFragment] -> IO ()
broadcastLiveInvalidation scope sourceClientId fragments = do
    _ <- broadcastLiveInvalidationDetailed scope sourceClientId fragments
    pure ()

broadcastLiveInvalidationDetailed :: (?context :: ControllerContext) => LiveUpdateScope -> Maybe Text -> [LiveUpdateWireFragment] -> IO LiveUpdateBroadcastResult
broadcastLiveInvalidationDetailed scope sourceClientId fragments =
    profileActionSpanWithDetail "live_updates.broadcast_invalidation" do
        result <- broadcastLiveInvalidationDetailedWithoutContext scope sourceClientId fragments
        pure (result, Just (liveUpdateBroadcastDetail result))

broadcastLiveInvalidationWithoutContext :: LiveUpdateScope -> Maybe Text -> [LiveUpdateWireFragment] -> IO ()
broadcastLiveInvalidationWithoutContext scope sourceClientId fragments = do
    _ <- broadcastLiveInvalidationDetailedWithoutContext scope sourceClientId fragments
    pure ()

broadcastLiveInvalidationDetailedWithoutContext :: LiveUpdateScope -> Maybe Text -> [LiveUpdateWireFragment] -> IO LiveUpdateBroadcastResult
broadcastLiveInvalidationDetailedWithoutContext =
    broadcastLiveInvalidationDetailedWithBus defaultLiveBus

broadcastLiveInvalidationDetailedWithBus :: LiveBus -> LiveUpdateScope -> Maybe Text -> [LiveUpdateWireFragment] -> IO LiveUpdateBroadcastResult
broadcastLiveInvalidationDetailedWithBus =
    liveBusBroadcastInvalidation

broadcastInMemoryInvalidation :: InMemoryLiveBusState -> LiveUpdateScope -> Maybe Text -> [LiveUpdateWireFragment] -> IO LiveUpdateBroadcastResult
broadcastInMemoryInvalidation state scope sourceClientId fragments = do
    let coalescedFragments = coalesceLiveUpdateWireFragments fragments
    version <- incrementInMemoryVersion state scope
    subscriptions <- readIORef state.inMemorySubscriptionsRef
    let matchingSubscriptions = filter (\subscription -> subscription.subscriptionScope == scope) subscriptions
    staleIds <- mapMaybeM (sendInvalidation scope version sourceClientId coalescedFragments) matchingSubscriptions
    unless (null staleIds) do
        atomicModifyIORef' state.inMemorySubscriptionsRef \activeSubscriptions ->
            ( filter (\subscription -> subscription.subscriptionId `notElem` staleIds) activeSubscriptions
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

coalesceLiveUpdateWireFragments :: [LiveUpdateWireFragment] -> [LiveUpdateWireFragment]
coalesceLiveUpdateWireFragments fragments =
    reverse (fst (foldl' step ([], Set.empty) fragments))
    where
        step (kept, seen) fragment =
            let key = liveUpdateWireFragmentMergeKey fragment
             in if Set.member key seen
                    then (kept, seen)
                    else (fragment : kept, Set.insert key seen)

liveUpdateWireFragmentMergeKey :: LiveUpdateWireFragment -> (LiveFragmentKey, Text, Text)
liveUpdateWireFragmentMergeKey fragment =
    (fragment.fragmentKey, fragment.targetId, fragment.url)

broadcastLiveResync :: (?context :: ControllerContext) => LiveUpdateScope -> Maybe Text -> IO ()
broadcastLiveResync scope sourceClientId =
    profileActionSpanWithDetail "live_updates.broadcast_resync" do
        result <- broadcastLiveInvalidationDetailedWithoutContext scope sourceClientId []
        pure ((), Just (liveUpdateBroadcastDetail result))

broadcastLiveResyncWithoutContext :: LiveUpdateScope -> Maybe Text -> IO ()
broadcastLiveResyncWithoutContext scope sourceClientId =
    -- The declarative client treats an invalidation with no explicit fragments as
    -- "resync every fragment configured for this subscribed surface".
    broadcastLiveInvalidationWithoutContext scope sourceClientId []

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

sendInvalidation :: LiveUpdateScope -> Int -> Maybe Text -> [LiveUpdateWireFragment] -> LiveSubscription -> IO (Maybe UUID.UUID)
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

liveUpdateScopeToWire :: LiveUpdateScope -> Wire.LiveUpdateScope
liveUpdateScopeToWire RosterWeekScope { venueId, rosterGroupId, weekOffset } =
    Wire.RosterWeek (UUID.toText venueId) (UUID.toText rosterGroupId) weekOffset
liveUpdateScopeToWire AdminVenueConfigScope { venueId } = Wire.AdminVenueConfig (UUID.toText venueId)
liveUpdateScopeToWire AdminShiftTypesScope { venueId } = Wire.AdminShiftTypes (UUID.toText venueId)
liveUpdateScopeToWire AdminRosterGroupsScope { venueId } = Wire.AdminRosterGroups (UUID.toText venueId)
liveUpdateScopeToWire AdminInvitesScope { venueId } = Wire.AdminInvites (UUID.toText venueId)
liveUpdateScopeToWire AdminExportsScope { venueId } = Wire.AdminExports (UUID.toText venueId)
liveUpdateScopeToWire AdminXeroScope { venueId } = Wire.AdminXero (UUID.toText venueId)
liveUpdateScopeToWire BillingScope { venueId } = Wire.Billing (UUID.toText venueId)
liveUpdateScopeToWire LeaveRequestsScope { venueId } = Wire.LeaveRequests (UUID.toText venueId)
liveUpdateScopeToWire TimesheetWeekScope { venueId, weekOffset } = Wire.TimesheetWeek (UUID.toText venueId) weekOffset
liveUpdateScopeToWire ProfileScope { venueId, staffId } = Wire.Profile (UUID.toText venueId) (UUID.toText staffId)
liveUpdateScopeToWire SupportPlatformScope = Wire.SupportPlatform

liveUpdateScopeFromWire :: Wire.LiveUpdateScope -> Aeson.Parser LiveUpdateScope
liveUpdateScopeFromWire Wire.RosterWeek { venueId, rosterGroupId, weekOffset } = RosterWeekScope <$> parseUuid venueId <*> parseUuid rosterGroupId <*> pure weekOffset
liveUpdateScopeFromWire Wire.AdminVenueConfig { venueId } = AdminVenueConfigScope <$> parseUuid venueId
liveUpdateScopeFromWire Wire.AdminShiftTypes { venueId } = AdminShiftTypesScope <$> parseUuid venueId
liveUpdateScopeFromWire Wire.AdminRosterGroups { venueId } = AdminRosterGroupsScope <$> parseUuid venueId
liveUpdateScopeFromWire Wire.AdminInvites { venueId } = AdminInvitesScope <$> parseUuid venueId
liveUpdateScopeFromWire Wire.AdminExports { venueId } = AdminExportsScope <$> parseUuid venueId
liveUpdateScopeFromWire Wire.AdminXero { venueId } = AdminXeroScope <$> parseUuid venueId
liveUpdateScopeFromWire Wire.Billing { venueId } = BillingScope <$> parseUuid venueId
liveUpdateScopeFromWire Wire.LeaveRequests { venueId } = LeaveRequestsScope <$> parseUuid venueId
liveUpdateScopeFromWire Wire.TimesheetWeek { venueId, weekOffset } = TimesheetWeekScope <$> parseUuid venueId <*> pure weekOffset
liveUpdateScopeFromWire Wire.Profile { venueId, staffId } = ProfileScope <$> parseUuid venueId <*> parseUuid staffId
liveUpdateScopeFromWire Wire.SupportPlatform = pure SupportPlatformScope

liveFragmentKeyToWire :: LiveFragmentKey -> Wire.LiveFragmentKey
liveFragmentKeyToWire = \case
    RosterContentFragment -> Wire.RosterContent
    RosterGridToolbarFragment -> Wire.RosterGridToolbar
    RosterGridFrameFragment -> Wire.RosterGridFrame
    RosterDayColumnsFragment -> Wire.RosterDayColumns
    RosterDayRailFragment -> Wire.RosterDayRail
    RosterWageRailFragment -> Wire.RosterWageRail
    RosterSlotsGridFragment -> Wire.RosterSlotsGrid
    RosterStaffPanelFragment -> Wire.RosterStaffPanel
    RosterDaySectionFragment { rosterDayId } -> Wire.RosterDaySection (UUID.toText rosterDayId)
    RosterRowFragment { rosterDayId, rowIndex } -> Wire.RosterRow (UUID.toText rosterDayId) rowIndex
    LeaveRequestsContentFragment -> Wire.LeaveRequestsContent
    TimesheetToolbarFragment -> Wire.TimesheetToolbar
    TimesheetDayColumnsFragment -> Wire.TimesheetDayColumns
    TimesheetDaySectionFragment { dayOffset } -> Wire.TimesheetDaySection dayOffset
    AdminVenueConfigFragment -> Wire.AdminVenueConfigFragment
    AdminInvitesFragment -> Wire.AdminInvitesFragment
    AdminExportsFragment -> Wire.AdminExportsFragment
    AdminShiftTypesFragment -> Wire.AdminShiftTypesFragment
    AdminRosterGroupsFragment -> Wire.AdminRosterGroupsFragment
    AdminXeroFragment -> Wire.AdminXeroFragment
    AdminXeroStaffMappingsFragment -> Wire.AdminXeroStaffMappings
    AdminXeroPayItemsFragment -> Wire.AdminXeroPayItems
    AdminXeroTimesheetsFragment -> Wire.AdminXeroTimesheets
    BillingStatusFragment -> Wire.BillingStatus
    ProfileContentFragment -> Wire.ProfileContent
    ProfileLeaveRequestsContentFragment -> Wire.ProfileLeaveRequestsContent
    SupportAwardRatesSectionFragment -> Wire.SupportAwardRatesSection
    SupportPublicHolidaysSectionFragment -> Wire.SupportPublicHolidaysSection

liveFragmentKeyFromWire :: Wire.LiveFragmentKey -> Aeson.Parser LiveFragmentKey
liveFragmentKeyFromWire = \case
    Wire.RosterContent -> pure RosterContentFragment
    Wire.RosterGridToolbar -> pure RosterGridToolbarFragment
    Wire.RosterGridFrame -> pure RosterGridFrameFragment
    Wire.RosterDayColumns -> pure RosterDayColumnsFragment
    Wire.RosterDayRail -> pure RosterDayRailFragment
    Wire.RosterWageRail -> pure RosterWageRailFragment
    Wire.RosterSlotsGrid -> pure RosterSlotsGridFragment
    Wire.RosterStaffPanel -> pure RosterStaffPanelFragment
    Wire.RosterDaySection { rosterDayId } -> RosterDaySectionFragment <$> parseUuid rosterDayId
    Wire.RosterRow { rosterDayId, rowIndex } -> RosterRowFragment <$> parseUuid rosterDayId <*> pure rowIndex
    Wire.LeaveRequestsContent -> pure LeaveRequestsContentFragment
    Wire.TimesheetToolbar -> pure TimesheetToolbarFragment
    Wire.TimesheetDayColumns -> pure TimesheetDayColumnsFragment
    Wire.TimesheetDaySection { dayOffset } -> pure (TimesheetDaySectionFragment dayOffset)
    Wire.AdminVenueConfigFragment -> pure AdminVenueConfigFragment
    Wire.AdminInvitesFragment -> pure AdminInvitesFragment
    Wire.AdminExportsFragment -> pure AdminExportsFragment
    Wire.AdminShiftTypesFragment -> pure AdminShiftTypesFragment
    Wire.AdminRosterGroupsFragment -> pure AdminRosterGroupsFragment
    Wire.AdminXeroFragment -> pure AdminXeroFragment
    Wire.AdminXeroStaffMappings -> pure AdminXeroStaffMappingsFragment
    Wire.AdminXeroPayItems -> pure AdminXeroPayItemsFragment
    Wire.AdminXeroTimesheets -> pure AdminXeroTimesheetsFragment
    Wire.BillingStatus -> pure BillingStatusFragment
    Wire.ProfileContent -> pure ProfileContentFragment
    Wire.ProfileLeaveRequestsContent -> pure ProfileLeaveRequestsContentFragment
    Wire.SupportAwardRatesSection -> pure SupportAwardRatesSectionFragment
    Wire.SupportPublicHolidaysSection -> pure SupportPublicHolidaysSectionFragment

focusedFieldProtectionConfigToWire :: FocusedFieldProtectionConfig -> Wire.FocusedFieldProtectionConfig
focusedFieldProtectionConfigToWire FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector } =
    Wire.FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector }

focusedFieldProtectionConfigFromWire :: Wire.FocusedFieldProtectionConfig -> FocusedFieldProtectionConfig
focusedFieldProtectionConfigFromWire Wire.FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector } =
    FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector }

liveFragmentProtectionToWire :: LiveFragmentProtection -> Wire.LiveFragmentProtection
liveFragmentProtectionToWire NoProtection = Wire.NoProtection
liveFragmentProtectionToWire (FocusedFieldProtection FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector }) =
    Wire.FocusedFieldProtection { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector }

liveFragmentProtectionFromWire :: Wire.LiveFragmentProtection -> LiveFragmentProtection
liveFragmentProtectionFromWire Wire.NoProtection = NoProtection
liveFragmentProtectionFromWire Wire.FocusedFieldProtection { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector } =
    FocusedFieldProtection FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector }

liveUpdateWireFragmentToWire :: LiveUpdateWireFragment -> Wire.LiveUpdateWireFragment
liveUpdateWireFragmentToWire LiveUpdateWireFragment { fragmentKey, targetId, url, deferUntilBlur, protectionPolicy } =
    Wire.LiveUpdateWireFragment (liveFragmentKeyToWire fragmentKey) targetId url deferUntilBlur (liveFragmentProtectionToWire protectionPolicy)

liveUpdateWireFragmentFromWire :: Wire.LiveUpdateWireFragment -> Aeson.Parser LiveUpdateWireFragment
liveUpdateWireFragmentFromWire Wire.LiveUpdateWireFragment { fragmentKey, targetId, url, deferUntilBlur, protectionPolicy } = do
    parsedFragmentKey <- liveFragmentKeyFromWire fragmentKey
    pure LiveUpdateWireFragment { fragmentKey = parsedFragmentKey, targetId, url, deferUntilBlur, protectionPolicy = liveFragmentProtectionFromWire protectionPolicy }

liveUpdateCommandToWire :: LiveUpdateCommand -> Wire.LiveUpdateCommand
liveUpdateCommandToWire SubscribeLiveUpdates { scope, clientId, lastSeenVersion } = Wire.Subscribe (liveUpdateScopeToWire scope) clientId lastSeenVersion
liveUpdateCommandToWire UnsubscribeLiveUpdates { scope } = Wire.Unsubscribe (liveUpdateScopeToWire scope)

liveUpdateCommandFromWire :: Wire.LiveUpdateCommand -> Aeson.Parser LiveUpdateCommand
liveUpdateCommandFromWire Wire.Subscribe { scope, clientId, lastSeenVersion } = SubscribeLiveUpdates <$> liveUpdateScopeFromWire scope <*> pure clientId <*> pure lastSeenVersion
liveUpdateCommandFromWire Wire.Unsubscribe { scope } = UnsubscribeLiveUpdates <$> liveUpdateScopeFromWire scope

liveUpdateMessageToWire :: LiveUpdateMessage -> Wire.LiveUpdateMessage
liveUpdateMessageToWire LiveUpdatesSubscribed { scope, scopeKey, currentVersion, resync } =
    Wire.Subscribed (liveUpdateScopeToWire scope) scopeKey currentVersion resync
liveUpdateMessageToWire LiveUpdatesInvalidated { scope, scopeKey, version, fragments, sourceClientId } =
    Wire.Invalidate (liveUpdateScopeToWire scope) scopeKey version (map liveUpdateWireFragmentToWire fragments) sourceClientId
liveUpdateMessageToWire LiveUpdatesError { message } = Wire.Error message

parseUuid :: Text -> Aeson.Parser UUID.UUID
parseUuid value =
    case UUID.fromText (Text.strip value) of
        Just uuid -> pure uuid
        Nothing   -> fail ("Invalid UUID: " <> cs value)

mapMaybeM :: (a -> IO (Maybe b)) -> [a] -> IO [b]
mapMaybeM action values =
    catMaybes <$> mapM action values
