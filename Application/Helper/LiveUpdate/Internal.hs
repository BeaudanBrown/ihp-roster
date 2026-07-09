module Application.Helper.LiveUpdate.Internal
    ( SurfaceFragmentKey (..)
    , SurfaceFragmentProtection (..)
    , SurfaceWireFragment (..)
    , LiveBus
    , FocusedFieldProtectionConfig (..)
    , LiveUpdateBroadcastResult (..)
    , LiveUpdateCommand (..)
    , LiveUpdateMessage (..)
    , SurfaceScope (..)
    , SurfaceSubscription (..)
    , activeSurfaceSubscriptions
    , activeSurfaceSubscriptionsWithBus
    , activeSurfaceScopes
    , activeSurfaceScopesWithBus
    , activeSurfaceScopeMatches
    , activeSurfaceScopeMatchesWithBus
    , activeRosterWeekScopes
    , activeRosterWeekScopesWithBus
    , broadcastLiveInvalidation
    , broadcastLiveInvalidationDetailed
    , broadcastLiveInvalidationDetailedWithBus
    , broadcastLiveInvalidationDetailedWithoutContext
    , broadcastLiveInvalidationWithoutContext
    , broadcastLiveResync
    , broadcastLiveResyncWithoutContext
    , coalesceSurfaceWireFragments
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
    , frontendSurfaceSurfaceFragmentKey
    , frontendSurfaceLiveScope
    , leaveRequestsContentLiveFragment
    , leaveRequestsLiveScope
    , liveUpdateSourceClientId
    , surfaceScopeFromWire
    , surfaceScopeFieldUuid
    , surfaceScopeKey
    , surfaceScopeKind
    , surfaceScopeToWire
    , surfaceFragmentKeyKind
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
    , surfaceWireFragmentFromWire
    , surfaceWireFragmentFromSurface
    , surfaceWireFragmentKind
    , surfaceWireFragmentToWire
    , mkSurfaceWireFragment
    , newInMemoryLiveBus
    , registerSurfaceSubscription
    , registerSurfaceSubscriptionWithBus
    , unregisterSurfaceSubscription
    , unregisterSurfaceSubscriptionWithBus
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

import qualified Application.Helper.FrontendContract.Wire.LiveUpdate as Wire
import Application.Helper.Profiling (profileActionSpan,
                                     profileActionSpanWithDetail)

data SurfaceScope = FrontendSurfaceScope
    { surfaceScopeSurface   :: !Text
    , surfaceScopePayload   :: !Aeson.Value
    , surfaceScopeStableKey :: !Text
    }
    deriving (Eq, Ord, Show)

surfaceScopeKind :: SurfaceScope -> Text
surfaceScopeKind = (.surfaceScopeSurface)

surfaceScopeFieldUuid :: Text -> SurfaceScope -> Maybe UUID.UUID
surfaceScopeFieldUuid fieldName scope =
    case scope.surfaceScopePayload of
        Aeson.Object object -> do
            Aeson.String value <- Aeson.KeyMap.lookup (Aeson.Key.fromText fieldName) object
            UUID.fromText (Text.strip value)
        _ -> Nothing

data SurfaceFragmentKey = FrontendSurfaceSurfaceFragmentKey
    { surfaceFragmentSurface  :: !Text
    , surfaceFragmentWireKind :: !Text
    , surfaceFragmentParams   :: !Aeson.Value
    }
    deriving (Eq, Ord, Show)

surfaceFragmentKeyKind :: SurfaceFragmentKey -> Text
surfaceFragmentKeyKind = Text.replace "-" "_" . (.surfaceFragmentWireKind)

surfaceWireFragmentKind :: SurfaceWireFragment -> Text
surfaceWireFragmentKind fragment = surfaceFragmentKeyKind fragment.fragmentKey

frontendSurfaceLiveScope :: Text -> Aeson.Value -> Text -> SurfaceScope
frontendSurfaceLiveScope surfaceScopeSurface surfaceScopePayload surfaceScopeStableKey =
    FrontendSurfaceScope { surfaceScopeSurface, surfaceScopePayload, surfaceScopeStableKey }

venueScopePayload :: UUID.UUID -> Aeson.Value
venueScopePayload scopeVenueId = Aeson.object ["venueId" Aeson..= UUID.toText scopeVenueId]

rosterWeekLiveScope :: UUID.UUID -> UUID.UUID -> Int -> SurfaceScope
rosterWeekLiveScope scopeVenueId scopeRosterGroupId scopeWeekOffset =
    frontendSurfaceLiveScope "roster" payload (Text.intercalate ":" ["roster", UUID.toText scopeVenueId, UUID.toText scopeRosterGroupId, tshow scopeWeekOffset])
    where
        payload = Aeson.object ["venueId" Aeson..= UUID.toText scopeVenueId, "rosterGroupId" Aeson..= UUID.toText scopeRosterGroupId, "weekOffset" Aeson..= scopeWeekOffset]

adminVenueConfigLiveScope, adminShiftTypesLiveScope, adminRosterGroupsLiveScope, adminInvitesLiveScope, adminExportsLiveScope, adminXeroLiveScope, billingLiveScope, leaveRequestsLiveScope :: UUID.UUID -> SurfaceScope
adminVenueConfigLiveScope scopeVenueId = frontendSurfaceLiveScope "admin-venue-config" (venueScopePayload scopeVenueId) (Text.intercalate ":" ["admin-venue-config", UUID.toText scopeVenueId])
adminShiftTypesLiveScope scopeVenueId = frontendSurfaceLiveScope "admin-shift-types" (venueScopePayload scopeVenueId) (Text.intercalate ":" ["admin-shift-types", UUID.toText scopeVenueId])
adminRosterGroupsLiveScope scopeVenueId = frontendSurfaceLiveScope "admin-roster-groups" (venueScopePayload scopeVenueId) (Text.intercalate ":" ["admin-roster-groups", UUID.toText scopeVenueId])
adminInvitesLiveScope scopeVenueId = frontendSurfaceLiveScope "admin-invites" (venueScopePayload scopeVenueId) (Text.intercalate ":" ["admin-invites", UUID.toText scopeVenueId])
adminExportsLiveScope scopeVenueId = frontendSurfaceLiveScope "admin-exports" (venueScopePayload scopeVenueId) (Text.intercalate ":" ["admin-exports", UUID.toText scopeVenueId])
adminXeroLiveScope scopeVenueId = frontendSurfaceLiveScope "admin-xero" (venueScopePayload scopeVenueId) (Text.intercalate ":" ["admin-xero", UUID.toText scopeVenueId])
billingLiveScope scopeVenueId = frontendSurfaceLiveScope "billing" (venueScopePayload scopeVenueId) (Text.intercalate ":" ["billing", UUID.toText scopeVenueId])
leaveRequestsLiveScope scopeVenueId = frontendSurfaceLiveScope "leave-requests" (venueScopePayload scopeVenueId) (Text.intercalate ":" ["leave-requests", UUID.toText scopeVenueId])

timesheetWeekLiveScope :: UUID.UUID -> Int -> SurfaceScope
timesheetWeekLiveScope scopeVenueId scopeWeekOffset =
    frontendSurfaceLiveScope "timesheets" payload (Text.intercalate ":" ["timesheets", UUID.toText scopeVenueId, tshow scopeWeekOffset])
    where
        payload = Aeson.object ["venueId" Aeson..= UUID.toText scopeVenueId, "weekOffset" Aeson..= scopeWeekOffset]

profileLiveScope :: UUID.UUID -> UUID.UUID -> SurfaceScope
profileLiveScope scopeVenueId scopeStaffId =
    frontendSurfaceLiveScope "profile" payload (Text.intercalate ":" ["profile", UUID.toText scopeVenueId, UUID.toText scopeStaffId])
    where
        payload = Aeson.object ["venueId" Aeson..= UUID.toText scopeVenueId, "staffId" Aeson..= UUID.toText scopeStaffId]

supportPlatformLiveScope :: SurfaceScope
supportPlatformLiveScope = frontendSurfaceLiveScope "support" (Aeson.object []) "support"

frontendSurfaceSurfaceFragmentKey :: Text -> Text -> Aeson.Value -> SurfaceFragmentKey
frontendSurfaceSurfaceFragmentKey surfaceFragmentSurface surfaceFragmentWireKind surfaceFragmentParams =
    FrontendSurfaceSurfaceFragmentKey { surfaceFragmentSurface, surfaceFragmentWireKind, surfaceFragmentParams = normalizeFragmentParams surfaceFragmentParams }

normalizeFragmentParams :: Aeson.Value -> Aeson.Value
normalizeFragmentParams Aeson.Null = Aeson.object []
normalizeFragmentParams value      = value

simpleSurfaceFragmentKey :: Text -> Text -> SurfaceFragmentKey
simpleSurfaceFragmentKey surface kind = frontendSurfaceSurfaceFragmentKey surface kind (Aeson.object [])

rosterContentLiveFragment, rosterGridToolbarLiveFragment, rosterGridFrameLiveFragment, rosterDayColumnsLiveFragment, rosterDayRailLiveFragment, rosterWageRailLiveFragment, rosterSlotsGridLiveFragment, rosterStaffPanelLiveFragment :: SurfaceFragmentKey
rosterContentLiveFragment = simpleSurfaceFragmentKey "roster" "roster-content"
rosterGridToolbarLiveFragment = simpleSurfaceFragmentKey "roster" "roster-grid-toolbar"
rosterGridFrameLiveFragment = simpleSurfaceFragmentKey "roster" "roster-grid-frame"
rosterDayColumnsLiveFragment = simpleSurfaceFragmentKey "roster" "roster-day-columns"
rosterDayRailLiveFragment = simpleSurfaceFragmentKey "roster" "roster-day-rail"
rosterWageRailLiveFragment = simpleSurfaceFragmentKey "roster" "roster-wage-rail"
rosterSlotsGridLiveFragment = simpleSurfaceFragmentKey "roster" "roster-slots-grid"
rosterStaffPanelLiveFragment = simpleSurfaceFragmentKey "roster" "roster-staff-panel"

rosterDaySectionLiveFragment, rosterRowLiveFragment :: UUID.UUID -> Int -> SurfaceFragmentKey
rosterDaySectionLiveFragment dayId _ = frontendSurfaceSurfaceFragmentKey "roster" "roster-day-section" (Aeson.object ["rosterDayId" Aeson..= UUID.toText dayId])
rosterRowLiveFragment dayId row = frontendSurfaceSurfaceFragmentKey "roster" "roster-row" (Aeson.object ["rosterDayId" Aeson..= UUID.toText dayId, "rowIndex" Aeson..= row])

leaveRequestsContentLiveFragment, timesheetToolbarLiveFragment, timesheetDayColumnsLiveFragment :: SurfaceFragmentKey
leaveRequestsContentLiveFragment = simpleSurfaceFragmentKey "leave-requests" "leave-requests-content"
timesheetToolbarLiveFragment = simpleSurfaceFragmentKey "timesheets" "timesheet-toolbar"
timesheetDayColumnsLiveFragment = simpleSurfaceFragmentKey "timesheets" "timesheet-day-columns"

timesheetDaySectionLiveFragment :: Int -> SurfaceFragmentKey
timesheetDaySectionLiveFragment offset = frontendSurfaceSurfaceFragmentKey "timesheets" "timesheet-day-section" (Aeson.object ["dayOffset" Aeson..= offset])

adminVenueConfigLiveFragment, adminInvitesLiveFragment, adminExportsLiveFragment, adminShiftTypesLiveFragment, adminRosterGroupsLiveFragment, adminXeroShellLiveFragment, adminXeroStaffMappingsLiveFragment, adminXeroPayItemsLiveFragment, adminXeroTimesheetsLiveFragment, billingStatusLiveFragment, profileContentLiveFragment, profileDetailsSectionLiveFragment, profilePreferencesSectionLiveFragment, profileSecuritySectionLiveFragment, profileLeaveSectionLiveFragment, profileRsaSectionLiveFragment, profileLeaveRequestsContentLiveFragment, supportAwardRatesSectionLiveFragment, supportPublicHolidaysSectionLiveFragment :: SurfaceFragmentKey
adminVenueConfigLiveFragment = simpleSurfaceFragmentKey "admin-venue-config" "admin-venue-settings"
adminInvitesLiveFragment = simpleSurfaceFragmentKey "admin-invites" "admin-invites"
adminExportsLiveFragment = simpleSurfaceFragmentKey "admin-exports" "admin-exports"
adminShiftTypesLiveFragment = simpleSurfaceFragmentKey "admin-shift-types" "admin-shift-types"
adminRosterGroupsLiveFragment = simpleSurfaceFragmentKey "admin-roster-groups" "admin-roster-groups"
adminXeroShellLiveFragment = simpleSurfaceFragmentKey "admin-xero" "admin-xero-shell"
adminXeroStaffMappingsLiveFragment = simpleSurfaceFragmentKey "admin-xero" "admin-xero-staff-mappings"
adminXeroPayItemsLiveFragment = simpleSurfaceFragmentKey "admin-xero" "admin-xero-pay-items"
adminXeroTimesheetsLiveFragment = simpleSurfaceFragmentKey "admin-xero" "admin-xero-timesheets"
billingStatusLiveFragment = simpleSurfaceFragmentKey "billing" "billing-status"
profileContentLiveFragment = profileDetailsSectionLiveFragment
profileDetailsSectionLiveFragment = simpleSurfaceFragmentKey "profile" "profile-details-section"
profilePreferencesSectionLiveFragment = simpleSurfaceFragmentKey "profile" "profile-preferences-section"
profileSecuritySectionLiveFragment = simpleSurfaceFragmentKey "profile" "profile-security-section"
profileLeaveSectionLiveFragment = simpleSurfaceFragmentKey "profile" "profile-leave-section"
profileRsaSectionLiveFragment = simpleSurfaceFragmentKey "profile" "profile-rsa-section"
profileLeaveRequestsContentLiveFragment = profileLeaveSectionLiveFragment
supportAwardRatesSectionLiveFragment = simpleSurfaceFragmentKey "support" "support-award-rates"
supportPublicHolidaysSectionLiveFragment = simpleSurfaceFragmentKey "support" "support-public-holidays"

data FocusedFieldProtectionConfig = FocusedFieldProtectionConfig
    { activeSelector    :: !Text
    , fieldKeyAttr      :: !Text
    , fieldNameFallback :: !Bool
    , containerSelector :: !(Maybe Text)
    }
    deriving (Eq, Show)

data SurfaceFragmentProtection
    = NoProtection
    | FocusedFieldProtection FocusedFieldProtectionConfig
    deriving (Eq, Show)

data SurfaceWireFragment = SurfaceWireFragment
    { fragmentKey      :: !SurfaceFragmentKey
    , targetId         :: !Text
    , url              :: !Text
    , deferUntilBlur   :: !Bool
    , protectionPolicy :: !SurfaceFragmentProtection
    }
    deriving (Eq, Show)

mkSurfaceWireFragment :: SurfaceFragmentKey -> Text -> Text -> SurfaceWireFragment
mkSurfaceWireFragment fragmentKey targetId url =
    SurfaceWireFragment
        { fragmentKey
        , targetId
        , url
        , deferUntilBlur = False
        , protectionPolicy = NoProtection
        }

surfaceWireFragmentFromSurface :: Text -> Text -> Aeson.Value -> Text -> Text -> Bool -> SurfaceFragmentProtection -> Maybe SurfaceWireFragment
surfaceWireFragmentFromSurface surface kind params targetId url deferUntilBlur protectionPolicy =
    Just SurfaceWireFragment { fragmentKey = frontendSurfaceSurfaceFragmentKey surface kind params, targetId, url, deferUntilBlur, protectionPolicy }

data SurfaceSubscription = SurfaceSubscription
    { subscriptionScope            :: !SurfaceScope
    , subscriptionScopeKey         :: !Text
    , subscriptionMountedFragments :: ![SurfaceWireFragment]
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
        , fragments      :: ![SurfaceWireFragment]
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
    cs <$> getHeader "X-Live-Update-Client-Id"

instance Aeson.ToJSON SurfaceScope where
    toJSON = Aeson.toJSON . surfaceScopeToWire

instance Aeson.FromJSON SurfaceScope where
    parseJSON value = surfaceScopeFromWire =<< Aeson.parseJSON value

instance Aeson.ToJSON SurfaceFragmentKey where
    toJSON = Aeson.toJSON . surfaceFragmentKeyToWire

instance Aeson.FromJSON SurfaceFragmentKey where
    parseJSON value = surfaceFragmentKeyFromWire =<< Aeson.parseJSON value

instance Aeson.ToJSON FocusedFieldProtectionConfig where
    toJSON = Aeson.toJSON . focusedFieldProtectionConfigToWire

instance Aeson.FromJSON FocusedFieldProtectionConfig where
    parseJSON value = focusedFieldProtectionConfigFromWire <$> Aeson.parseJSON value

instance Aeson.ToJSON SurfaceFragmentProtection where
    toJSON = Aeson.toJSON . surfaceFragmentProtectionToWire

instance Aeson.FromJSON SurfaceFragmentProtection where
    parseJSON value = surfaceFragmentProtectionFromWire <$> Aeson.parseJSON value

instance Aeson.ToJSON SurfaceWireFragment where
    toJSON = Aeson.toJSON . surfaceWireFragmentToWire

instance Aeson.FromJSON SurfaceWireFragment where
    parseJSON value = surfaceWireFragmentFromWire =<< Aeson.parseJSON value

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
    , liveBusBroadcastInvalidation    :: SurfaceScope -> Maybe Text -> [SurfaceWireFragment] -> IO LiveUpdateBroadcastResult
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

activeSurfaceScopes :: IO [SurfaceScope]
activeSurfaceScopes =
    activeSurfaceScopesWithBus defaultLiveBus

activeSurfaceScopesWithBus :: LiveBus -> IO [SurfaceScope]
activeSurfaceScopesWithBus bus =
    Set.toList . Set.fromList . map (.subscriptionScope) <$> activeSurfaceSubscriptionsWithBus bus

activeSurfaceScopeMatches :: Ord a => (SurfaceScope -> Maybe a) -> IO [a]
activeSurfaceScopeMatches =
    activeSurfaceScopeMatchesWithBus defaultLiveBus

activeSurfaceScopeMatchesWithBus :: Ord a => LiveBus -> (SurfaceScope -> Maybe a) -> IO [a]
activeSurfaceScopeMatchesWithBus bus matcher =
    Set.toList . Set.fromList . mapMaybe matcher <$> activeSurfaceScopesWithBus bus

activeRosterWeekScopes :: IO [(UUID.UUID, UUID.UUID, Int)]
activeRosterWeekScopes =
    activeRosterWeekScopesWithBus defaultLiveBus

activeRosterWeekScopesWithBus :: LiveBus -> IO [(UUID.UUID, UUID.UUID, Int)]
activeRosterWeekScopesWithBus bus =
    Set.toList . Set.fromList . mapMaybe rosterWeekSubscriptionParts <$> activeSurfaceSubscriptionsWithBus bus

rosterWeekSubscriptionParts :: SurfaceSubscription -> Maybe (UUID.UUID, UUID.UUID, Int)
rosterWeekSubscriptionParts subscription = do
    let Wire.SurfaceScope { surface, scope } = surfaceScopeToWire subscription.subscriptionScope
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

currentLiveUpdateVersion :: SurfaceScope -> IO Int
currentLiveUpdateVersion =
    currentLiveUpdateVersionWithBus defaultLiveBus

currentLiveUpdateVersionWithBus :: LiveBus -> SurfaceScope -> IO Int
currentLiveUpdateVersionWithBus =
    liveBusCurrentVersion

currentInMemoryVersion :: InMemoryLiveBusState -> SurfaceScope -> IO Int
currentInMemoryVersion state scope =
    Map.findWithDefault 0 (surfaceScopeKey scope) <$> readIORef state.inMemoryScopeVersionsRef

incrementLiveUpdateVersion :: SurfaceScope -> IO Int
incrementLiveUpdateVersion =
    incrementLiveUpdateVersionWithBus defaultLiveBus

incrementLiveUpdateVersionWithBus :: LiveBus -> SurfaceScope -> IO Int
incrementLiveUpdateVersionWithBus =
    liveBusIncrementVersion

incrementInMemoryVersion :: InMemoryLiveBusState -> SurfaceScope -> IO Int
incrementInMemoryVersion state scope =
    atomicModifyIORef' state.inMemoryScopeVersionsRef \versions ->
        let scopeKey = surfaceScopeKey scope
            nextVersion = Map.findWithDefault 0 scopeKey versions + 1
         in (Map.insert scopeKey nextVersion versions, nextVersion)

broadcastLiveInvalidation :: (?context :: ControllerContext) => SurfaceScope -> Maybe Text -> [SurfaceWireFragment] -> IO ()
broadcastLiveInvalidation scope sourceClientId fragments = do
    _ <- broadcastLiveInvalidationDetailed scope sourceClientId fragments
    pure ()

broadcastLiveInvalidationDetailed :: (?context :: ControllerContext) => SurfaceScope -> Maybe Text -> [SurfaceWireFragment] -> IO LiveUpdateBroadcastResult
broadcastLiveInvalidationDetailed scope sourceClientId fragments =
    profileActionSpanWithDetail "live_updates.broadcast_invalidation" do
        result <- broadcastLiveInvalidationDetailedWithoutContext scope sourceClientId fragments
        pure (result, Just (liveUpdateBroadcastDetail result))

broadcastLiveInvalidationWithoutContext :: SurfaceScope -> Maybe Text -> [SurfaceWireFragment] -> IO ()
broadcastLiveInvalidationWithoutContext scope sourceClientId fragments = do
    _ <- broadcastLiveInvalidationDetailedWithoutContext scope sourceClientId fragments
    pure ()

broadcastLiveInvalidationDetailedWithoutContext :: SurfaceScope -> Maybe Text -> [SurfaceWireFragment] -> IO LiveUpdateBroadcastResult
broadcastLiveInvalidationDetailedWithoutContext =
    broadcastLiveInvalidationDetailedWithBus defaultLiveBus

broadcastLiveInvalidationDetailedWithBus :: LiveBus -> SurfaceScope -> Maybe Text -> [SurfaceWireFragment] -> IO LiveUpdateBroadcastResult
broadcastLiveInvalidationDetailedWithBus =
    liveBusBroadcastInvalidation

broadcastInMemoryInvalidation :: InMemoryLiveBusState -> SurfaceScope -> Maybe Text -> [SurfaceWireFragment] -> IO LiveUpdateBroadcastResult
broadcastInMemoryInvalidation state scope sourceClientId fragments = do
    let coalescedFragments = coalesceSurfaceWireFragments fragments
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

coalesceSurfaceWireFragments :: [SurfaceWireFragment] -> [SurfaceWireFragment]
coalesceSurfaceWireFragments fragments =
    reverse (fst (foldl' step ([], Set.empty) fragments))
    where
        step (kept, seen) fragment =
            let key = surfaceWireFragmentMergeKey fragment
             in if Set.member key seen
                    then (kept, seen)
                    else (fragment : kept, Set.insert key seen)

surfaceWireFragmentMergeKey :: SurfaceWireFragment -> (SurfaceFragmentKey, Text, Text)
surfaceWireFragmentMergeKey fragment =
    (fragment.fragmentKey, fragment.targetId, fragment.url)

broadcastLiveResync :: (?context :: ControllerContext) => SurfaceScope -> Maybe Text -> IO ()
broadcastLiveResync scope sourceClientId =
    profileActionSpanWithDetail "live_updates.broadcast_resync" do
        result <- broadcastLiveInvalidationDetailedWithoutContext scope sourceClientId []
        pure ((), Just (liveUpdateBroadcastDetail result))

broadcastLiveResyncWithoutContext :: SurfaceScope -> Maybe Text -> IO ()
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

sendInvalidation :: SurfaceScope -> Int -> Maybe Text -> [SurfaceWireFragment] -> ActiveLiveSubscription -> IO (Maybe UUID.UUID)
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
    pure (frontendSurfaceLiveScope surface scope stableKey)

surfaceScopeStableKeyFromWire :: Text -> Aeson.Value -> Aeson.Parser Text
surfaceScopeStableKeyFromWire surface scopePayload =
    case scopePayload of
        Aeson.Object object -> case surface of
            "roster" -> do
                venueId <- parseUuidField object "venueId"
                rosterGroupId <- parseUuidField object "rosterGroupId"
                weekOffset <- object Aeson..: "weekOffset"
                pure (Text.intercalate ":" ["roster", UUID.toText venueId, UUID.toText rosterGroupId, tshow (weekOffset :: Int)])
            "timesheets" -> do
                venueId <- parseUuidField object "venueId"
                weekOffset <- object Aeson..: "weekOffset"
                pure (Text.intercalate ":" ["timesheets", UUID.toText venueId, tshow (weekOffset :: Int)])
            "profile" -> do
                venueId <- parseUuidField object "venueId"
                staffId <- parseUuidField object "staffId"
                pure (Text.intercalate ":" ["profile", UUID.toText venueId, UUID.toText staffId])
            "support" -> pure "support"
            _ -> do
                venueId <- parseUuidField object "venueId"
                pure (Text.intercalate ":" [surface, UUID.toText venueId])
        _ | surface == "support" -> pure "support"
        _ -> fail ("Invalid live update scope payload for surface: " <> cs surface)

surfaceFragmentKeyToWire :: SurfaceFragmentKey -> Wire.SurfaceFragmentKey
surfaceFragmentKeyToWire key = Wire.SurfaceFragmentKey
    { Wire.surface = key.surfaceFragmentSurface
    , Wire.kind = key.surfaceFragmentWireKind
    , Wire.params = key.surfaceFragmentParams
    }

surfaceFragmentKeyFromWire :: Wire.SurfaceFragmentKey -> Aeson.Parser SurfaceFragmentKey
surfaceFragmentKeyFromWire Wire.SurfaceFragmentKey { surface, kind, params } =
    pure (frontendSurfaceSurfaceFragmentKey surface kind params)

focusedFieldProtectionConfigToWire :: FocusedFieldProtectionConfig -> Wire.FocusedFieldProtectionConfig
focusedFieldProtectionConfigToWire FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector } =
    Wire.FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector }

focusedFieldProtectionConfigFromWire :: Wire.FocusedFieldProtectionConfig -> FocusedFieldProtectionConfig
focusedFieldProtectionConfigFromWire Wire.FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector } =
    FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector }

surfaceFragmentProtectionToWire :: SurfaceFragmentProtection -> Wire.SurfaceFragmentProtection
surfaceFragmentProtectionToWire NoProtection = Wire.NoProtection
surfaceFragmentProtectionToWire (FocusedFieldProtection FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector }) =
    Wire.FocusedFieldProtection { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector }

surfaceFragmentProtectionFromWire :: Wire.SurfaceFragmentProtection -> SurfaceFragmentProtection
surfaceFragmentProtectionFromWire Wire.NoProtection = NoProtection
surfaceFragmentProtectionFromWire Wire.FocusedFieldProtection { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector } =
    FocusedFieldProtection FocusedFieldProtectionConfig { activeSelector, fieldKeyAttr, fieldNameFallback, containerSelector }

surfaceWireFragmentToWire :: SurfaceWireFragment -> Wire.SurfaceWireFragment
surfaceWireFragmentToWire SurfaceWireFragment { fragmentKey, targetId, url, deferUntilBlur, protectionPolicy } =
    Wire.SurfaceWireFragment (surfaceFragmentKeyToWire fragmentKey) targetId url deferUntilBlur (surfaceFragmentProtectionToWire protectionPolicy)

surfaceWireFragmentFromWire :: Wire.SurfaceWireFragment -> Aeson.Parser SurfaceWireFragment
surfaceWireFragmentFromWire Wire.SurfaceWireFragment { fragmentKey, targetId, url, deferUntilBlur, protectionPolicy } = do
    parsedFragmentKey <- surfaceFragmentKeyFromWire fragmentKey
    pure SurfaceWireFragment { fragmentKey = parsedFragmentKey, targetId, url, deferUntilBlur, protectionPolicy = surfaceFragmentProtectionFromWire protectionPolicy }

liveUpdateSubscriptionToWire :: SurfaceSubscription -> Wire.SurfaceSubscription
liveUpdateSubscriptionToWire SurfaceSubscription { subscriptionScope, subscriptionScopeKey, subscriptionMountedFragments } =
    Wire.SurfaceSubscription
        { Wire.scope = surfaceScopeToWire subscriptionScope
        , Wire.scopeKey = subscriptionScopeKey
        , Wire.mountedFragments = map surfaceWireFragmentToWire subscriptionMountedFragments
        }

liveUpdateSubscriptionFromWire :: Wire.SurfaceSubscription -> Aeson.Parser SurfaceSubscription
liveUpdateSubscriptionFromWire Wire.SurfaceSubscription { scope, scopeKey, mountedFragments } = do
    parsedScope <- surfaceScopeFromWire scope
    let subscriptionScope = parsedScope { surfaceScopeStableKey = scopeKey }
    subscriptionMountedFragments <- mapM surfaceWireFragmentFromWire mountedFragments
    pure SurfaceSubscription { subscriptionScope, subscriptionScopeKey = scopeKey, subscriptionMountedFragments }

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
    Wire.Invalidate (surfaceScopeToWire scope) scopeKey version (map surfaceWireFragmentToWire fragments) sourceClientId
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
