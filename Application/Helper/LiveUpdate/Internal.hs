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
    , LiveUpdateSubscription (..)
    , activeLiveUpdateSubscriptions
    , activeLiveUpdateSubscriptionsWithBus
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
    , liveUpdateWireFragmentFromSurface
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
liveUpdateScopeKind = liveUpdateSurfaceName

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
    | ProfileDetailsSectionFragment
    | ProfilePreferencesSectionFragment
    | ProfileSecuritySectionFragment
    | ProfileLeaveSectionFragment
    | ProfileRsaSectionFragment
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
liveFragmentKeyKind ProfileDetailsSectionFragment = "profile_details_section"
liveFragmentKeyKind ProfilePreferencesSectionFragment = "profile_preferences_section"
liveFragmentKeyKind ProfileSecuritySectionFragment = "profile_security_section"
liveFragmentKeyKind ProfileLeaveSectionFragment = "profile_leave_section"
liveFragmentKeyKind ProfileRsaSectionFragment = "profile_rsa_section"
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

liveUpdateWireFragmentFromSurface :: Text -> Text -> Aeson.Value -> Text -> Text -> Bool -> LiveFragmentProtection -> Maybe LiveUpdateWireFragment
liveUpdateWireFragmentFromSurface surface kind params targetId url deferUntilBlur protectionPolicy = do
    fragmentKey <- Aeson.parseMaybe (liveFragmentKeyFromSurface surface kind) params
    pure LiveUpdateWireFragment { fragmentKey, targetId, url, deferUntilBlur, protectionPolicy }

data LiveUpdateSubscription = LiveUpdateSubscription
    { subscriptionScope            :: !LiveUpdateScope
    , subscriptionScopeKey         :: !Text
    , subscriptionMountedFragments :: ![LiveUpdateWireFragment]
    }
    deriving (Eq, Show)

data LiveUpdateCommand
    = SubscribeLiveUpdates
        { subscription    :: !LiveUpdateSubscription
        , clientId        :: !Text
        , lastSeenVersion :: !(Maybe Int)
        }
    | UnsubscribeLiveUpdates
        { subscription :: !LiveUpdateSubscription
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
    Text.intercalate ":" ["roster", UUID.toText venueId, UUID.toText rosterGroupId, tshow weekOffset]
liveUpdateScopeKey AdminVenueConfigScope { venueId } =
    Text.intercalate ":" ["admin-venue-config", UUID.toText venueId]
liveUpdateScopeKey AdminShiftTypesScope { venueId } =
    Text.intercalate ":" ["admin-shift-types", UUID.toText venueId]
liveUpdateScopeKey AdminRosterGroupsScope { venueId } =
    Text.intercalate ":" ["admin-roster-groups", UUID.toText venueId]
liveUpdateScopeKey AdminInvitesScope { venueId } =
    Text.intercalate ":" ["admin-invites", UUID.toText venueId]
liveUpdateScopeKey AdminExportsScope { venueId } =
    Text.intercalate ":" ["admin-exports", UUID.toText venueId]
liveUpdateScopeKey AdminXeroScope { venueId } =
    Text.intercalate ":" ["admin-xero", UUID.toText venueId]
liveUpdateScopeKey BillingScope { venueId } =
    Text.intercalate ":" ["billing", UUID.toText venueId]
liveUpdateScopeKey LeaveRequestsScope { venueId } =
    Text.intercalate ":" ["leave-requests", UUID.toText venueId]
liveUpdateScopeKey TimesheetWeekScope { venueId, weekOffset } =
    Text.intercalate ":" ["timesheets", UUID.toText venueId, tshow weekOffset]
liveUpdateScopeKey ProfileScope { venueId, staffId } =
    Text.intercalate ":" ["profile", UUID.toText venueId, UUID.toText staffId]
liveUpdateScopeKey SupportPlatformScope =
    "support"

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

data ActiveLiveSubscription = ActiveLiveSubscription
    { activeSubscriptionId         :: !UUID.UUID
    , activeSubscription           :: !LiveUpdateSubscription
    , activeSubscriptionConnection :: WebSocket.Connection
    }

data LiveBus = LiveBus
    { liveBusRegisterSubscription     :: UUID.UUID -> LiveUpdateSubscription -> WebSocket.Connection -> IO ()
    , liveBusUnregisterSubscription   :: UUID.UUID -> IO ()
    , liveBusActiveSubscriptions      :: IO [LiveUpdateSubscription]
    , liveBusCurrentVersion           :: LiveUpdateScope -> IO Int
    , liveBusIncrementVersion         :: LiveUpdateScope -> IO Int
    , liveBusBroadcastInvalidation    :: LiveUpdateScope -> Maybe Text -> [LiveUpdateWireFragment] -> IO LiveUpdateBroadcastResult
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

registerLiveSubscription :: UUID.UUID -> LiveUpdateSubscription -> WebSocket.Connection -> IO ()
registerLiveSubscription =
    registerLiveSubscriptionWithBus defaultLiveBus

registerLiveSubscriptionWithBus :: LiveBus -> UUID.UUID -> LiveUpdateSubscription -> WebSocket.Connection -> IO ()
registerLiveSubscriptionWithBus =
    liveBusRegisterSubscription

registerInMemorySubscription :: InMemoryLiveBusState -> UUID.UUID -> LiveUpdateSubscription -> WebSocket.Connection -> IO ()
registerInMemorySubscription state activeSubscriptionId activeSubscription connection =
    atomicModifyIORef' state.inMemorySubscriptionsRef \subscriptions ->
        ( ActiveLiveSubscription { activeSubscriptionId, activeSubscription, activeSubscriptionConnection = connection }
            : filter (\subscription -> subscription.activeSubscriptionId /= activeSubscriptionId) subscriptions
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
        (filter (\subscription -> subscription.activeSubscriptionId /= subscriptionId) subscriptions, ())

activeLiveUpdateSubscriptions :: IO [LiveUpdateSubscription]
activeLiveUpdateSubscriptions =
    activeLiveUpdateSubscriptionsWithBus defaultLiveBus

activeLiveUpdateSubscriptionsWithBus :: LiveBus -> IO [LiveUpdateSubscription]
activeLiveUpdateSubscriptionsWithBus =
    liveBusActiveSubscriptions

activeInMemorySubscriptions :: InMemoryLiveBusState -> IO [LiveUpdateSubscription]
activeInMemorySubscriptions state =
    map (.activeSubscription) <$> readIORef state.inMemorySubscriptionsRef

activeLiveUpdateScopes :: IO [LiveUpdateScope]
activeLiveUpdateScopes =
    activeLiveUpdateScopesWithBus defaultLiveBus

activeLiveUpdateScopesWithBus :: LiveBus -> IO [LiveUpdateScope]
activeLiveUpdateScopesWithBus bus =
    Set.toList . Set.fromList . map (.subscriptionScope) <$> activeLiveUpdateSubscriptionsWithBus bus

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
    Map.findWithDefault 0 (liveUpdateScopeKey scope) <$> readIORef state.inMemoryScopeVersionsRef

incrementLiveUpdateVersion :: LiveUpdateScope -> IO Int
incrementLiveUpdateVersion =
    incrementLiveUpdateVersionWithBus defaultLiveBus

incrementLiveUpdateVersionWithBus :: LiveBus -> LiveUpdateScope -> IO Int
incrementLiveUpdateVersionWithBus =
    liveBusIncrementVersion

incrementInMemoryVersion :: InMemoryLiveBusState -> LiveUpdateScope -> IO Int
incrementInMemoryVersion state scope =
    atomicModifyIORef' state.inMemoryScopeVersionsRef \versions ->
        let scopeKey = liveUpdateScopeKey scope
            nextVersion = Map.findWithDefault 0 scopeKey versions + 1
         in (Map.insert scopeKey nextVersion versions, nextVersion)

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
    let scopeKey = liveUpdateScopeKey scope
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

sendInvalidation :: LiveUpdateScope -> Int -> Maybe Text -> [LiveUpdateWireFragment] -> ActiveLiveSubscription -> IO (Maybe UUID.UUID)
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
                , scopeKey = liveUpdateScopeKey scope
                , version
                , fragments
                , sourceClientId
                }

liveUpdateScopeToWire :: LiveUpdateScope -> Wire.LiveUpdateScope
liveUpdateScopeToWire scope = Wire.LiveUpdateScope
    { Wire.surface = liveUpdateSurfaceName scope
    , Wire.scope = liveUpdateScopePayload scope
    }

liveUpdateScopeFromWire :: Wire.LiveUpdateScope -> Aeson.Parser LiveUpdateScope
liveUpdateScopeFromWire Wire.LiveUpdateScope { surface, scope } =
    liveUpdateScopeFromSurface surface scope

liveUpdateSurfaceName :: LiveUpdateScope -> Text
liveUpdateSurfaceName = \case
    RosterWeekScope {} -> "roster"
    AdminVenueConfigScope {} -> "admin-venue-config"
    AdminShiftTypesScope {} -> "admin-shift-types"
    AdminRosterGroupsScope {} -> "admin-roster-groups"
    AdminInvitesScope {} -> "admin-invites"
    AdminExportsScope {} -> "admin-exports"
    AdminXeroScope {} -> "admin-xero"
    BillingScope {} -> "billing"
    LeaveRequestsScope {} -> "leave-requests"
    TimesheetWeekScope {} -> "timesheets"
    ProfileScope {} -> "profile"
    SupportPlatformScope -> "support"

liveUpdateScopePayload :: LiveUpdateScope -> Aeson.Value
liveUpdateScopePayload = \case
    RosterWeekScope { venueId, rosterGroupId, weekOffset } -> Aeson.object ["venueId" Aeson..= UUID.toText venueId, "rosterGroupId" Aeson..= UUID.toText rosterGroupId, "weekOffset" Aeson..= weekOffset]
    AdminVenueConfigScope { venueId } -> venueScopePayload venueId
    AdminShiftTypesScope { venueId } -> venueScopePayload venueId
    AdminRosterGroupsScope { venueId } -> venueScopePayload venueId
    AdminInvitesScope { venueId } -> venueScopePayload venueId
    AdminExportsScope { venueId } -> venueScopePayload venueId
    AdminXeroScope { venueId } -> venueScopePayload venueId
    BillingScope { venueId } -> venueScopePayload venueId
    LeaveRequestsScope { venueId } -> venueScopePayload venueId
    TimesheetWeekScope { venueId, weekOffset } -> Aeson.object ["venueId" Aeson..= UUID.toText venueId, "weekOffset" Aeson..= weekOffset]
    ProfileScope { venueId, staffId } -> Aeson.object ["venueId" Aeson..= UUID.toText venueId, "staffId" Aeson..= UUID.toText staffId]
    SupportPlatformScope -> Aeson.object []
    where
        venueScopePayload venueId = Aeson.object ["venueId" Aeson..= UUID.toText venueId]

liveUpdateScopeFromSurface :: Text -> Aeson.Value -> Aeson.Parser LiveUpdateScope
liveUpdateScopeFromSurface surface = Aeson.withObject "FrontendSurfaceLiveScope" \object ->
    case surface of
        "roster" -> RosterWeekScope <$> parseUuidField object "venueId" <*> parseUuidField object "rosterGroupId" <*> object Aeson..: "weekOffset"
        "admin-venue-config" -> AdminVenueConfigScope <$> parseUuidField object "venueId"
        "admin-shift-types" -> AdminShiftTypesScope <$> parseUuidField object "venueId"
        "admin-roster-groups" -> AdminRosterGroupsScope <$> parseUuidField object "venueId"
        "admin-invites" -> AdminInvitesScope <$> parseUuidField object "venueId"
        "admin-exports" -> AdminExportsScope <$> parseUuidField object "venueId"
        "admin-xero" -> AdminXeroScope <$> parseUuidField object "venueId"
        "billing" -> BillingScope <$> parseUuidField object "venueId"
        "leave-requests" -> LeaveRequestsScope <$> parseUuidField object "venueId"
        "timesheets" -> TimesheetWeekScope <$> parseUuidField object "venueId" <*> object Aeson..: "weekOffset"
        "profile" -> ProfileScope <$> parseUuidField object "venueId" <*> parseUuidField object "staffId"
        "support" -> pure SupportPlatformScope
        _ -> fail ("Unknown FrontendSurface live scope: " <> cs surface)

liveFragmentKeyToWire :: LiveFragmentKey -> Wire.LiveFragmentKey
liveFragmentKeyToWire key = Wire.LiveFragmentKey
    { Wire.surface = liveFragmentSurfaceName key
    , Wire.kind = liveFragmentWireKind key
    , Wire.params = liveFragmentKeyParams key
    }

liveFragmentKeyFromWire :: Wire.LiveFragmentKey -> Aeson.Parser LiveFragmentKey
liveFragmentKeyFromWire Wire.LiveFragmentKey { surface, kind, params } =
    liveFragmentKeyFromSurface surface kind params

liveFragmentSurfaceName :: LiveFragmentKey -> Text
liveFragmentSurfaceName = \case
    RosterContentFragment -> "roster"
    RosterGridToolbarFragment -> "roster"
    RosterGridFrameFragment -> "roster"
    RosterDayColumnsFragment -> "roster"
    RosterDayRailFragment -> "roster"
    RosterWageRailFragment -> "roster"
    RosterSlotsGridFragment -> "roster"
    RosterStaffPanelFragment -> "roster"
    RosterDaySectionFragment {} -> "roster"
    RosterRowFragment {} -> "roster"
    LeaveRequestsContentFragment -> "leave-requests"
    TimesheetToolbarFragment -> "timesheets"
    TimesheetDayColumnsFragment -> "timesheets"
    TimesheetDaySectionFragment {} -> "timesheets"
    AdminVenueConfigFragment -> "admin-venue-config"
    AdminInvitesFragment -> "admin-invites"
    AdminExportsFragment -> "admin-exports"
    AdminShiftTypesFragment -> "admin-shift-types"
    AdminRosterGroupsFragment -> "admin-roster-groups"
    AdminXeroFragment -> "admin-xero"
    AdminXeroStaffMappingsFragment -> "admin-xero"
    AdminXeroPayItemsFragment -> "admin-xero"
    AdminXeroTimesheetsFragment -> "admin-xero"
    BillingStatusFragment -> "billing"
    ProfileContentFragment -> "profile"
    ProfileDetailsSectionFragment -> "profile"
    ProfilePreferencesSectionFragment -> "profile"
    ProfileSecuritySectionFragment -> "profile"
    ProfileLeaveSectionFragment -> "profile"
    ProfileRsaSectionFragment -> "profile"
    ProfileLeaveRequestsContentFragment -> "profile"
    SupportAwardRatesSectionFragment -> "support"
    SupportPublicHolidaysSectionFragment -> "support"

liveFragmentWireKind :: LiveFragmentKey -> Text
liveFragmentWireKind = \case
    RosterContentFragment -> "roster-content"
    RosterGridToolbarFragment -> "roster-grid-toolbar"
    RosterGridFrameFragment -> "roster-grid-frame"
    RosterDayColumnsFragment -> "roster-day-columns"
    RosterDayRailFragment -> "roster-day-rail"
    RosterWageRailFragment -> "roster-wage-rail"
    RosterSlotsGridFragment -> "roster-slots-grid"
    RosterStaffPanelFragment -> "roster-staff-panel"
    RosterDaySectionFragment {} -> "roster-day-section"
    RosterRowFragment {} -> "roster-row"
    LeaveRequestsContentFragment -> "leave-requests-content"
    TimesheetToolbarFragment -> "timesheet-toolbar"
    TimesheetDayColumnsFragment -> "timesheet-day-columns"
    TimesheetDaySectionFragment {} -> "timesheet-day-section"
    AdminVenueConfigFragment -> "admin-venue-config"
    AdminInvitesFragment -> "admin-invites"
    AdminExportsFragment -> "admin-exports"
    AdminShiftTypesFragment -> "admin-shift-types"
    AdminRosterGroupsFragment -> "admin-roster-groups"
    AdminXeroFragment -> "admin-xero-shell"
    AdminXeroStaffMappingsFragment -> "admin-xero-staff-mappings"
    AdminXeroPayItemsFragment -> "admin-xero-pay-items"
    AdminXeroTimesheetsFragment -> "admin-xero-timesheets"
    BillingStatusFragment -> "billing-status"
    ProfileContentFragment -> "profile-content"
    ProfileDetailsSectionFragment -> "profile-details-section"
    ProfilePreferencesSectionFragment -> "profile-preferences-section"
    ProfileSecuritySectionFragment -> "profile-security-section"
    ProfileLeaveSectionFragment -> "profile-leave-section"
    ProfileRsaSectionFragment -> "profile-rsa-section"
    ProfileLeaveRequestsContentFragment -> "profile-leave-requests-content"
    SupportAwardRatesSectionFragment -> "support-award-rates"
    SupportPublicHolidaysSectionFragment -> "support-public-holidays"

liveFragmentKeyParams :: LiveFragmentKey -> Aeson.Value
liveFragmentKeyParams = \case
    RosterDaySectionFragment { rosterDayId } -> Aeson.object ["rosterDayId" Aeson..= UUID.toText rosterDayId]
    RosterRowFragment { rosterDayId, rowIndex } -> Aeson.object ["rosterDayId" Aeson..= UUID.toText rosterDayId, "rowIndex" Aeson..= rowIndex]
    TimesheetDaySectionFragment { dayOffset } -> Aeson.object ["dayOffset" Aeson..= dayOffset]
    _ -> Aeson.object []

liveFragmentKeyFromSurface :: Text -> Text -> Aeson.Value -> Aeson.Parser LiveFragmentKey
liveFragmentKeyFromSurface surface kind params =
    case (surface, kind) of
        ("roster", "roster-content") -> pure RosterContentFragment
        ("roster", "roster-grid-toolbar") -> pure RosterGridToolbarFragment
        ("roster", "roster-grid-frame") -> pure RosterGridFrameFragment
        ("roster", "roster-day-columns") -> pure RosterDayColumnsFragment
        ("roster", "roster-day-rail") -> pure RosterDayRailFragment
        ("roster", "roster-wage-rail") -> pure RosterWageRailFragment
        ("roster", "roster-slots-grid") -> pure RosterSlotsGridFragment
        ("roster", "roster-staff-panel") -> pure RosterStaffPanelFragment
        ("roster", "roster-day-section") -> Aeson.withObject "RosterDaySection" (\object -> RosterDaySectionFragment <$> parseUuidField object "rosterDayId") params
        ("roster", "roster-row") -> Aeson.withObject "RosterRow" (\object -> RosterRowFragment <$> parseUuidField object "rosterDayId" <*> object Aeson..: "rowIndex") params
        ("leave-requests", "leave-requests-content") -> pure LeaveRequestsContentFragment
        ("timesheets", "timesheet-toolbar") -> pure TimesheetToolbarFragment
        ("timesheets", "timesheet-day-columns") -> pure TimesheetDayColumnsFragment
        ("timesheets", "timesheet-day-section") -> Aeson.withObject "TimesheetDaySection" (\object -> TimesheetDaySectionFragment <$> object Aeson..: "dayOffset") params
        ("admin-venue-config", "admin-venue-config") -> pure AdminVenueConfigFragment
        ("admin-invites", "admin-invites") -> pure AdminInvitesFragment
        ("admin-exports", "admin-exports") -> pure AdminExportsFragment
        ("admin-shift-types", "admin-shift-types") -> pure AdminShiftTypesFragment
        ("admin-roster-groups", "admin-roster-groups") -> pure AdminRosterGroupsFragment
        ("admin-xero", "admin-xero-shell") -> pure AdminXeroFragment
        ("admin-xero", "admin-xero-staff-mappings") -> pure AdminXeroStaffMappingsFragment
        ("admin-xero", "admin-xero-pay-items") -> pure AdminXeroPayItemsFragment
        ("admin-xero", "admin-xero-timesheets") -> pure AdminXeroTimesheetsFragment
        ("billing", "billing-status") -> pure BillingStatusFragment
        ("profile", "profile-content") -> pure ProfileContentFragment
        ("profile", "profile-details-section") -> pure ProfileDetailsSectionFragment
        ("profile", "profile-preferences-section") -> pure ProfilePreferencesSectionFragment
        ("profile", "profile-security-section") -> pure ProfileSecuritySectionFragment
        ("profile", "profile-leave-section") -> pure ProfileLeaveSectionFragment
        ("profile", "profile-rsa-section") -> pure ProfileRsaSectionFragment
        ("profile", "profile-leave-requests-content") -> pure ProfileLeaveRequestsContentFragment
        ("support", "support-award-rates") -> pure SupportAwardRatesSectionFragment
        ("support", "support-public-holidays") -> pure SupportPublicHolidaysSectionFragment
        _ -> fail ("Unknown FrontendSurface live fragment: " <> cs surface <> ":" <> cs kind)

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

liveUpdateSubscriptionToWire :: LiveUpdateSubscription -> Wire.LiveUpdateSubscription
liveUpdateSubscriptionToWire LiveUpdateSubscription { subscriptionScope, subscriptionScopeKey, subscriptionMountedFragments } =
    Wire.LiveUpdateSubscription
        { Wire.scope = liveUpdateScopeToWire subscriptionScope
        , Wire.scopeKey = subscriptionScopeKey
        , Wire.mountedFragments = map liveUpdateWireFragmentToWire subscriptionMountedFragments
        }

liveUpdateSubscriptionFromWire :: Wire.LiveUpdateSubscription -> Aeson.Parser LiveUpdateSubscription
liveUpdateSubscriptionFromWire Wire.LiveUpdateSubscription { scope, scopeKey, mountedFragments } = do
    subscriptionScope <- liveUpdateScopeFromWire scope
    subscriptionMountedFragments <- mapM liveUpdateWireFragmentFromWire mountedFragments
    pure LiveUpdateSubscription { subscriptionScope, subscriptionScopeKey = scopeKey, subscriptionMountedFragments }

liveUpdateCommandToWire :: LiveUpdateCommand -> Wire.LiveUpdateCommand
liveUpdateCommandToWire SubscribeLiveUpdates { subscription, clientId, lastSeenVersion } = Wire.Subscribe (liveUpdateSubscriptionToWire subscription) clientId lastSeenVersion
liveUpdateCommandToWire UnsubscribeLiveUpdates { subscription } = Wire.Unsubscribe (liveUpdateSubscriptionToWire subscription)

liveUpdateCommandFromWire :: Wire.LiveUpdateCommand -> Aeson.Parser LiveUpdateCommand
liveUpdateCommandFromWire Wire.Subscribe { subscription, clientId, lastSeenVersion } = SubscribeLiveUpdates <$> liveUpdateSubscriptionFromWire subscription <*> pure clientId <*> pure lastSeenVersion
liveUpdateCommandFromWire Wire.Unsubscribe { subscription } = UnsubscribeLiveUpdates <$> liveUpdateSubscriptionFromWire subscription

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

parseUuidField :: Aeson.Object -> Text -> Aeson.Parser UUID.UUID
parseUuidField object fieldName =
    parseUuid =<< object Aeson..: cs fieldName

mapMaybeM :: (a -> IO (Maybe b)) -> [a] -> IO [b]
mapMaybeM action values =
    catMaybes <$> mapM action values
