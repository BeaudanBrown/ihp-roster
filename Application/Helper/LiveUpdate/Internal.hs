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
    , adminExportsLiveFragment
    , adminExportsLiveScope
    , adminInvitesLiveFragment
    , adminInvitesLiveScope
    , adminRosterGroupsLiveFragment
    , adminRosterGroupsLiveScope
    , adminShiftTypesLiveFragment
    , adminShiftTypesLiveScope
    , adminVenueConfigLiveFragment
    , adminVenueConfigLiveScope
    , adminXeroLiveScope
    , adminXeroPayItemsLiveFragment
    , adminXeroShellLiveFragment
    , adminXeroStaffMappingsLiveFragment
    , adminXeroTimesheetsLiveFragment
    , billingLiveScope
    , billingStatusLiveFragment
    , frontendSurfaceLiveFragmentKey
    , frontendSurfaceLiveScope
    , leaveRequestsContentLiveFragment
    , leaveRequestsLiveScope
    , liveUpdateSourceClientId
    , liveUpdateScopeFromWire
    , liveUpdateScopeFieldUuid
    , liveUpdateScopeKey
    , liveUpdateScopeKind
    , liveUpdateScopeToWire
    , liveFragmentKeyKind
    , profileContentLiveFragment
    , profileDetailsSectionLiveFragment
    , profileLeaveRequestsContentLiveFragment
    , profileLeaveSectionLiveFragment
    , profileLiveScope
    , profilePreferencesSectionLiveFragment
    , profileRsaSectionLiveFragment
    , profileSecuritySectionLiveFragment
    , rosterContentLiveFragment
    , rosterDayColumnsLiveFragment
    , rosterDayRailLiveFragment
    , rosterDaySectionLiveFragment
    , rosterGridFrameLiveFragment
    , rosterGridToolbarLiveFragment
    , rosterRowLiveFragment
    , rosterSlotsGridLiveFragment
    , rosterStaffPanelLiveFragment
    , rosterWageRailLiveFragment
    , rosterWeekLiveScope
    , supportAwardRatesSectionLiveFragment
    , supportPlatformLiveScope
    , supportPublicHolidaysSectionLiveFragment
    , timesheetDayColumnsLiveFragment
    , timesheetDaySectionLiveFragment
    , timesheetToolbarLiveFragment
    , timesheetWeekLiveScope
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
import qualified Data.Aeson.Key as Aeson.Key
import qualified Data.Aeson.KeyMap as Aeson.KeyMap
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

data LiveUpdateScope = FrontendSurfaceLiveScope
    { liveUpdateScopeSurface   :: !Text
    , liveUpdateScopePayload   :: !Aeson.Value
    , liveUpdateScopeStableKey :: !Text
    }
    deriving (Eq, Ord, Show)

liveUpdateScopeKind :: LiveUpdateScope -> Text
liveUpdateScopeKind = (.liveUpdateScopeSurface)

liveUpdateScopeFieldUuid :: Text -> LiveUpdateScope -> Maybe UUID.UUID
liveUpdateScopeFieldUuid fieldName scope =
    case scope.liveUpdateScopePayload of
        Aeson.Object object -> do
            Aeson.String value <- Aeson.KeyMap.lookup (Aeson.Key.fromText fieldName) object
            UUID.fromText (Text.strip value)
        _ -> Nothing

data LiveFragmentKey = FrontendSurfaceLiveFragmentKey
    { liveFragmentSurface  :: !Text
    , liveFragmentWireKind :: !Text
    , liveFragmentParams   :: !Aeson.Value
    }
    deriving (Eq, Ord, Show)

liveFragmentKeyKind :: LiveFragmentKey -> Text
liveFragmentKeyKind = Text.replace "-" "_" . (.liveFragmentWireKind)

liveUpdateWireFragmentKind :: LiveUpdateWireFragment -> Text
liveUpdateWireFragmentKind fragment = liveFragmentKeyKind fragment.fragmentKey

frontendSurfaceLiveScope :: Text -> Aeson.Value -> Text -> LiveUpdateScope
frontendSurfaceLiveScope liveUpdateScopeSurface liveUpdateScopePayload liveUpdateScopeStableKey =
    FrontendSurfaceLiveScope { liveUpdateScopeSurface, liveUpdateScopePayload, liveUpdateScopeStableKey }

venueScopePayload :: UUID.UUID -> Aeson.Value
venueScopePayload scopeVenueId = Aeson.object ["venueId" Aeson..= UUID.toText scopeVenueId]

rosterWeekLiveScope :: UUID.UUID -> UUID.UUID -> Int -> LiveUpdateScope
rosterWeekLiveScope scopeVenueId scopeRosterGroupId scopeWeekOffset =
    frontendSurfaceLiveScope "roster" payload (Text.intercalate ":" ["roster", UUID.toText scopeVenueId, UUID.toText scopeRosterGroupId, tshow scopeWeekOffset])
    where
        payload = Aeson.object ["venueId" Aeson..= UUID.toText scopeVenueId, "rosterGroupId" Aeson..= UUID.toText scopeRosterGroupId, "weekOffset" Aeson..= scopeWeekOffset]

adminVenueConfigLiveScope, adminShiftTypesLiveScope, adminRosterGroupsLiveScope, adminInvitesLiveScope, adminExportsLiveScope, adminXeroLiveScope, billingLiveScope, leaveRequestsLiveScope :: UUID.UUID -> LiveUpdateScope
adminVenueConfigLiveScope scopeVenueId = frontendSurfaceLiveScope "admin-venue-config" (venueScopePayload scopeVenueId) (Text.intercalate ":" ["admin-venue-config", UUID.toText scopeVenueId])
adminShiftTypesLiveScope scopeVenueId = frontendSurfaceLiveScope "admin-shift-types" (venueScopePayload scopeVenueId) (Text.intercalate ":" ["admin-shift-types", UUID.toText scopeVenueId])
adminRosterGroupsLiveScope scopeVenueId = frontendSurfaceLiveScope "admin-roster-groups" (venueScopePayload scopeVenueId) (Text.intercalate ":" ["admin-roster-groups", UUID.toText scopeVenueId])
adminInvitesLiveScope scopeVenueId = frontendSurfaceLiveScope "admin-invites" (venueScopePayload scopeVenueId) (Text.intercalate ":" ["admin-invites", UUID.toText scopeVenueId])
adminExportsLiveScope scopeVenueId = frontendSurfaceLiveScope "admin-exports" (venueScopePayload scopeVenueId) (Text.intercalate ":" ["admin-exports", UUID.toText scopeVenueId])
adminXeroLiveScope scopeVenueId = frontendSurfaceLiveScope "admin-xero" (venueScopePayload scopeVenueId) (Text.intercalate ":" ["admin-xero", UUID.toText scopeVenueId])
billingLiveScope scopeVenueId = frontendSurfaceLiveScope "billing" (venueScopePayload scopeVenueId) (Text.intercalate ":" ["billing", UUID.toText scopeVenueId])
leaveRequestsLiveScope scopeVenueId = frontendSurfaceLiveScope "leave-requests" (venueScopePayload scopeVenueId) (Text.intercalate ":" ["leave-requests", UUID.toText scopeVenueId])

timesheetWeekLiveScope :: UUID.UUID -> Int -> LiveUpdateScope
timesheetWeekLiveScope scopeVenueId scopeWeekOffset =
    frontendSurfaceLiveScope "timesheets" payload (Text.intercalate ":" ["timesheets", UUID.toText scopeVenueId, tshow scopeWeekOffset])
    where
        payload = Aeson.object ["venueId" Aeson..= UUID.toText scopeVenueId, "weekOffset" Aeson..= scopeWeekOffset]

profileLiveScope :: UUID.UUID -> UUID.UUID -> LiveUpdateScope
profileLiveScope scopeVenueId scopeStaffId =
    frontendSurfaceLiveScope "profile" payload (Text.intercalate ":" ["profile", UUID.toText scopeVenueId, UUID.toText scopeStaffId])
    where
        payload = Aeson.object ["venueId" Aeson..= UUID.toText scopeVenueId, "staffId" Aeson..= UUID.toText scopeStaffId]

supportPlatformLiveScope :: LiveUpdateScope
supportPlatformLiveScope = frontendSurfaceLiveScope "support" (Aeson.object []) "support"

frontendSurfaceLiveFragmentKey :: Text -> Text -> Aeson.Value -> LiveFragmentKey
frontendSurfaceLiveFragmentKey liveFragmentSurface liveFragmentWireKind liveFragmentParams =
    FrontendSurfaceLiveFragmentKey { liveFragmentSurface, liveFragmentWireKind, liveFragmentParams }

simpleLiveFragmentKey :: Text -> Text -> LiveFragmentKey
simpleLiveFragmentKey surface kind = frontendSurfaceLiveFragmentKey surface kind (Aeson.object [])

rosterContentLiveFragment, rosterGridToolbarLiveFragment, rosterGridFrameLiveFragment, rosterDayColumnsLiveFragment, rosterDayRailLiveFragment, rosterWageRailLiveFragment, rosterSlotsGridLiveFragment, rosterStaffPanelLiveFragment :: LiveFragmentKey
rosterContentLiveFragment = simpleLiveFragmentKey "roster" "roster-content"
rosterGridToolbarLiveFragment = simpleLiveFragmentKey "roster" "roster-grid-toolbar"
rosterGridFrameLiveFragment = simpleLiveFragmentKey "roster" "roster-grid-frame"
rosterDayColumnsLiveFragment = simpleLiveFragmentKey "roster" "roster-day-columns"
rosterDayRailLiveFragment = simpleLiveFragmentKey "roster" "roster-day-rail"
rosterWageRailLiveFragment = simpleLiveFragmentKey "roster" "roster-wage-rail"
rosterSlotsGridLiveFragment = simpleLiveFragmentKey "roster" "roster-slots-grid"
rosterStaffPanelLiveFragment = simpleLiveFragmentKey "roster" "roster-staff-panel"

rosterDaySectionLiveFragment, rosterRowLiveFragment :: UUID.UUID -> Int -> LiveFragmentKey
rosterDaySectionLiveFragment dayId _ = frontendSurfaceLiveFragmentKey "roster" "roster-day-section" (Aeson.object ["rosterDayId" Aeson..= UUID.toText dayId])
rosterRowLiveFragment dayId row = frontendSurfaceLiveFragmentKey "roster" "roster-row" (Aeson.object ["rosterDayId" Aeson..= UUID.toText dayId, "rowIndex" Aeson..= row])

leaveRequestsContentLiveFragment, timesheetToolbarLiveFragment, timesheetDayColumnsLiveFragment :: LiveFragmentKey
leaveRequestsContentLiveFragment = simpleLiveFragmentKey "leave-requests" "leave-requests-content"
timesheetToolbarLiveFragment = simpleLiveFragmentKey "timesheets" "timesheet-toolbar"
timesheetDayColumnsLiveFragment = simpleLiveFragmentKey "timesheets" "timesheet-day-columns"

timesheetDaySectionLiveFragment :: Int -> LiveFragmentKey
timesheetDaySectionLiveFragment offset = frontendSurfaceLiveFragmentKey "timesheets" "timesheet-day-section" (Aeson.object ["dayOffset" Aeson..= offset])

adminVenueConfigLiveFragment, adminInvitesLiveFragment, adminExportsLiveFragment, adminShiftTypesLiveFragment, adminRosterGroupsLiveFragment, adminXeroShellLiveFragment, adminXeroStaffMappingsLiveFragment, adminXeroPayItemsLiveFragment, adminXeroTimesheetsLiveFragment, billingStatusLiveFragment, profileContentLiveFragment, profileDetailsSectionLiveFragment, profilePreferencesSectionLiveFragment, profileSecuritySectionLiveFragment, profileLeaveSectionLiveFragment, profileRsaSectionLiveFragment, profileLeaveRequestsContentLiveFragment, supportAwardRatesSectionLiveFragment, supportPublicHolidaysSectionLiveFragment :: LiveFragmentKey
adminVenueConfigLiveFragment = simpleLiveFragmentKey "admin-venue-config" "admin-venue-config"
adminInvitesLiveFragment = simpleLiveFragmentKey "admin-invites" "admin-invites"
adminExportsLiveFragment = simpleLiveFragmentKey "admin-exports" "admin-exports"
adminShiftTypesLiveFragment = simpleLiveFragmentKey "admin-shift-types" "admin-shift-types"
adminRosterGroupsLiveFragment = simpleLiveFragmentKey "admin-roster-groups" "admin-roster-groups"
adminXeroShellLiveFragment = simpleLiveFragmentKey "admin-xero" "admin-xero-shell"
adminXeroStaffMappingsLiveFragment = simpleLiveFragmentKey "admin-xero" "admin-xero-staff-mappings"
adminXeroPayItemsLiveFragment = simpleLiveFragmentKey "admin-xero" "admin-xero-pay-items"
adminXeroTimesheetsLiveFragment = simpleLiveFragmentKey "admin-xero" "admin-xero-timesheets"
billingStatusLiveFragment = simpleLiveFragmentKey "billing" "billing-status"
profileContentLiveFragment = simpleLiveFragmentKey "profile" "profile-content"
profileDetailsSectionLiveFragment = simpleLiveFragmentKey "profile" "profile-details-section"
profilePreferencesSectionLiveFragment = simpleLiveFragmentKey "profile" "profile-preferences-section"
profileSecuritySectionLiveFragment = simpleLiveFragmentKey "profile" "profile-security-section"
profileLeaveSectionLiveFragment = simpleLiveFragmentKey "profile" "profile-leave-section"
profileRsaSectionLiveFragment = simpleLiveFragmentKey "profile" "profile-rsa-section"
profileLeaveRequestsContentLiveFragment = simpleLiveFragmentKey "profile" "profile-leave-requests-content"
supportAwardRatesSectionLiveFragment = simpleLiveFragmentKey "support" "support-award-rates"
supportPublicHolidaysSectionLiveFragment = simpleLiveFragmentKey "support" "support-public-holidays"

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
liveUpdateWireFragmentFromSurface surface kind params targetId url deferUntilBlur protectionPolicy =
    Just LiveUpdateWireFragment { fragmentKey = frontendSurfaceLiveFragmentKey surface kind params, targetId, url, deferUntilBlur, protectionPolicy }

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
liveUpdateScopeKey = (.liveUpdateScopeStableKey)

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
    Set.toList . Set.fromList . mapMaybe rosterWeekSubscriptionParts <$> activeLiveUpdateSubscriptionsWithBus bus

rosterWeekSubscriptionParts :: LiveUpdateSubscription -> Maybe (UUID.UUID, UUID.UUID, Int)
rosterWeekSubscriptionParts subscription = do
    let Wire.LiveUpdateScope { surface, scope } = liveUpdateScopeToWire subscription.subscriptionScope
    guardMaybe (surface == "roster")
    Aeson.parseMaybe (Aeson.withObject "RosterWeekScope" \object -> do
        venueId <- parseUuidField object "venueId"
        rosterGroupId <- parseUuidField object "rosterGroupId"
        weekOffset <- object Aeson..: "weekOffset"
        pure (venueId, rosterGroupId, weekOffset)
        ) scope


guardMaybe :: Bool -> Maybe ()
guardMaybe True  = Just ()
guardMaybe False = Nothing

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
    { Wire.surface = scope.liveUpdateScopeSurface
    , Wire.scope = scope.liveUpdateScopePayload
    }

liveUpdateScopeFromWire :: Wire.LiveUpdateScope -> Aeson.Parser LiveUpdateScope
liveUpdateScopeFromWire Wire.LiveUpdateScope { surface, scope } =
    pure (frontendSurfaceLiveScope surface scope surface)

liveFragmentKeyToWire :: LiveFragmentKey -> Wire.LiveFragmentKey
liveFragmentKeyToWire key = Wire.LiveFragmentKey
    { Wire.surface = key.liveFragmentSurface
    , Wire.kind = key.liveFragmentWireKind
    , Wire.params = key.liveFragmentParams
    }

liveFragmentKeyFromWire :: Wire.LiveFragmentKey -> Aeson.Parser LiveFragmentKey
liveFragmentKeyFromWire Wire.LiveFragmentKey { surface, kind, params } =
    pure (frontendSurfaceLiveFragmentKey surface kind params)

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
    parsedScope <- liveUpdateScopeFromWire scope
    let subscriptionScope = parsedScope { liveUpdateScopeStableKey = scopeKey }
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
