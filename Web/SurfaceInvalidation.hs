module Web.SurfaceInvalidation
    ( LiveInvalidationProfile (..)
    , LiveInvalidationStageDurations (..)
    , SurfaceInvalidationTarget (..)
    , authorizeSurfaceScope
    , bepisLiveFactFromProfile
    , expandSurfaceResources
    , expandSurfaceResourcesWithoutContext
    , invalidateTouchedResources
    , invalidateTouchedResourcesWithoutContext
    , liveInvalidationProfile
    , performSurfaceInvalidationTarget
    , performSurfaceInvalidationTargetWithoutContext
    , planSurfaceInvalidations
    , planSurfaceInvalidationsWithoutContext
    , renderLiveInvalidationProfile
    ) where

import Application.Bepis.Fact (BepisFact (..), BepisLiveFact (..),
                               BepisLiveMechanism (..), emitBepisFact)
import Application.Helper.ControllerContext (currentVenueOrNothing)
import Application.Helper.FrontendContract.Surface.Authorization (authorizeFrontendSurfaceScope)
import Application.Helper.FrontendContract.Surface.DependencyPlanner (SurfaceInvalidationTarget (..),
                                                                      planFrontendSurfaceInvalidations)
import Application.Helper.FrontendContract.Surface.Roster.Live (activeRosterWeekScopes)
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.LiveUpdate.DurablePublisher (publishDurableInvalidation)
import Application.Helper.Profiling (profileActionSpanWithDetail)
import Application.Helper.SurfaceResource
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.UUID (UUID)
import GHC.Clock (getMonotonicTimeNSec)
import qualified System.Environment as Environment
import Web.Controller.Prelude
import Web.RosterWeeks.SurfaceInvalidation (expandRosterSurfaceResources,
                                            expandRosterSurfaceResourcesWithoutContext)

authorizeSurfaceScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => SurfaceScope -> IO Bool
authorizeSurfaceScope = authorizeFrontendSurfaceScope

planSurfaceInvalidations :: (?context :: ControllerContext) => Set.Set SurfaceResourceValue -> [SurfaceSubscription] -> [SurfaceInvalidationTarget]
planSurfaceInvalidations = planSurfaceInvalidationsWithoutContext

planSurfaceInvalidationsWithoutContext :: Set.Set SurfaceResourceValue -> [SurfaceSubscription] -> [SurfaceInvalidationTarget]
planSurfaceInvalidationsWithoutContext = planFrontendSurfaceInvalidations

performSurfaceInvalidationTarget :: (?context :: ControllerContext, ?request :: Request) => SurfaceInvalidationTarget -> IO LiveUpdateBroadcastResult
performSurfaceInvalidationTarget target = broadcastLiveInvalidationDetailed target.targetScope liveUpdateSourceClientId target.targetFragments

performSurfaceInvalidationTargetWithoutContext :: SurfaceInvalidationTarget -> IO LiveUpdateBroadcastResult
performSurfaceInvalidationTargetWithoutContext target = broadcastLiveInvalidationDetailedWithoutContext target.targetScope Nothing target.targetFragments

expandSurfaceResources ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    [(UUID, UUID, Int)] ->
    Set.Set SurfaceResourceValue ->
    IO (Set.Set SurfaceResourceValue)
expandSurfaceResources = expandRosterSurfaceResources

expandSurfaceResourcesWithoutContext :: [(UUID, UUID, Int)] -> Set.Set SurfaceResourceValue -> Set.Set SurfaceResourceValue
expandSurfaceResourcesWithoutContext = expandRosterSurfaceResourcesWithoutContext

invalidateTouchedResources :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> LiveMutationResult a -> IO (LiveMutationResult a)
invalidateTouchedResources label result =
    profileActionSpanWithDetail "surface_resources.invalidate" do
        startedAtNs <- getMonotonicTimeNSec
        (observed, observeDurationMs) <- measureDuration (recordLiveMutationDiagnostics label result)
        -- Compatibility stage: publication follows the existing business commit;
        -- #389/#390 move this into each business transaction.
        _eventId <- publishDurableInvalidation label observed.liveMutationTouchedResources
        (activeSubscriptions, activeSubscriptionDurationMs) <- measureDuration activeSurfaceSubscriptions
        (activeRosterScopes, activeRosterDurationMs) <- measureDuration activeRosterWeekScopes
        let activeDurationMs = activeSubscriptionDurationMs + activeRosterDurationMs
        let activeScopes = coalesceScopes (map (.subscriptionScope) activeSubscriptions)
        (expandedResources, expandDurationMs) <- measureDuration $
            case currentVenueOrNothing of
                Just _ -> expandSurfaceResources activeRosterScopes (liveMutationTouchedResources observed)
                Nothing -> pure (expandSurfaceResourcesWithoutContext activeRosterScopes (liveMutationTouchedResources observed))
        (dependencyTargets, planDurationMs) <- measureDuration (pure (planSurfaceInvalidations expandedResources activeSubscriptions))
        (broadcastResults, broadcastDurationMs) <- measureDuration (mapM performSurfaceInvalidationTarget dependencyTargets)
        completedAtNs <- getMonotonicTimeNSec
        let profile =
                liveInvalidationProfile
                    label
                    (durationBetweenMs startedAtNs completedAtNs)
                    (liveMutationTouchedResources observed)
                    activeScopes
                    expandedResources
                    dependencyTargets
                    broadcastResults
                    LiveInvalidationStageDurations { observeDurationMs, activeDurationMs, expandDurationMs, planDurationMs, broadcastDurationMs }
        emitLiveInvalidationProfileLog profile
        emitLiveFactFromProfile BepisWebSocketFragmentRefetch profile
        pure (observed, Just (renderLiveInvalidationProfile profile))

invalidateTouchedResourcesWithoutContext :: Text -> LiveMutationResult a -> IO (LiveMutationResult a)
invalidateTouchedResourcesWithoutContext label result = do
    startedAtNs <- getMonotonicTimeNSec
    (observed, observeDurationMs) <- measureDuration (recordLiveMutationDiagnostics label result)
    (activeSubscriptions, activeDurationMs) <- measureDuration activeSurfaceSubscriptions
    let activeScopes = coalesceScopes (map (.subscriptionScope) activeSubscriptions)
    (activeRosterScopes, activeRosterDurationMs) <- measureDuration activeRosterWeekScopes
    let activeDurationMs' = activeDurationMs + activeRosterDurationMs
    (expandedResources, expandDurationMs) <- measureDuration (pure (expandSurfaceResourcesWithoutContext activeRosterScopes (liveMutationTouchedResources observed)))
    (dependencyTargets, planDurationMs) <- measureDuration (pure (planSurfaceInvalidationsWithoutContext expandedResources activeSubscriptions))
    (broadcastResults, broadcastDurationMs) <- measureDuration (mapM performSurfaceInvalidationTargetWithoutContext dependencyTargets)
    completedAtNs <- getMonotonicTimeNSec
    let profile =
            liveInvalidationProfile
                label
                (durationBetweenMs startedAtNs completedAtNs)
                (liveMutationTouchedResources observed)
                activeScopes
                expandedResources
                dependencyTargets
                broadcastResults
                LiveInvalidationStageDurations { observeDurationMs, activeDurationMs = activeDurationMs', expandDurationMs, planDurationMs, broadcastDurationMs }
    emitLiveInvalidationProfileLog profile
    emitLiveFactFromProfile BepisBackgroundLiveInvalidation profile
    pure observed

data LiveInvalidationProfile = LiveInvalidationProfile
    { profileLabel                    :: !Text
    , profileTotalDurationMs          :: !Double
    , profileTouchedResourceCount     :: !Int
    , profileActiveScopeCount         :: !Int
    , profileExpandedResourceCount    :: !Int
    , profileTargetCount              :: !Int
    , profileTargetFragmentCount      :: !Int
    , profileBroadcastCount           :: !Int
    , profileBroadcastSubscriberCount :: !Int
    , profileStageDurations           :: !LiveInvalidationStageDurations
    }
    deriving (Eq, Show)

data LiveInvalidationStageDurations = LiveInvalidationStageDurations
    { observeDurationMs   :: !Double
    , activeDurationMs    :: !Double
    , expandDurationMs    :: !Double
    , planDurationMs      :: !Double
    , broadcastDurationMs :: !Double
    }
    deriving (Eq, Show)

liveInvalidationProfile ::
    Text ->
    Double ->
    Set.Set SurfaceResourceValue ->
    [SurfaceScope] ->
    Set.Set SurfaceResourceValue ->
    [SurfaceInvalidationTarget] ->
    [LiveUpdateBroadcastResult] ->
    LiveInvalidationStageDurations ->
    LiveInvalidationProfile
liveInvalidationProfile label totalDurationMs touchedResources activeScopes expandedResources targets broadcastResults stageDurations =
    LiveInvalidationProfile
        { profileLabel = label
        , profileTotalDurationMs = totalDurationMs
        , profileTouchedResourceCount = Set.size touchedResources
        , profileActiveScopeCount = length activeScopes
        , profileExpandedResourceCount = Set.size expandedResources
        , profileTargetCount = length targets
        , profileTargetFragmentCount = sum (map (length . (.targetFragments)) targets)
        , profileBroadcastCount = length broadcastResults
        , profileBroadcastSubscriberCount = sum (map (.broadcastSubscriberCount) broadcastResults)
        , profileStageDurations = stageDurations
        }

renderLiveInvalidationProfile :: LiveInvalidationProfile -> Text
renderLiveInvalidationProfile profile =
    Text.intercalate
        " "
        [ "label=" <> profile.profileLabel
        , "touched=" <> tshow profile.profileTouchedResourceCount
        , "active_scopes=" <> tshow profile.profileActiveScopeCount
        , "expanded=" <> tshow profile.profileExpandedResourceCount
        , "targets=" <> tshow profile.profileTargetCount
        , "target_fragments=" <> tshow profile.profileTargetFragmentCount
        , "broadcasts=" <> tshow profile.profileBroadcastCount
        , "subscribers=" <> tshow profile.profileBroadcastSubscriberCount
        , "total_ms=" <> renderDuration profile.profileTotalDurationMs
        , "observe_ms=" <> renderDuration profile.profileStageDurations.observeDurationMs
        , "active_ms=" <> renderDuration profile.profileStageDurations.activeDurationMs
        , "expand_ms=" <> renderDuration profile.profileStageDurations.expandDurationMs
        , "plan_ms=" <> renderDuration profile.profileStageDurations.planDurationMs
        , "broadcast_ms=" <> renderDuration profile.profileStageDurations.broadcastDurationMs
        ]

emitLiveFactFromProfile :: BepisLiveMechanism -> LiveInvalidationProfile -> IO ()
emitLiveFactFromProfile mechanism profile =
    emitBepisFact (BepisLiveFactValue (bepisLiveFactFromProfile mechanism profile))

bepisLiveFactFromProfile :: BepisLiveMechanism -> LiveInvalidationProfile -> BepisLiveFact
bepisLiveFactFromProfile mechanism profile =
    BepisLiveFact
        { liveFactLabel = profile.profileLabel
        , liveFactTouchedResourceCount = profile.profileTouchedResourceCount
        , liveFactExpandedResourceCount = profile.profileExpandedResourceCount
        , liveFactTargetCount = profile.profileTargetCount
        , liveFactTargetFragmentCount = profile.profileTargetFragmentCount
        , liveFactMechanism = mechanism
        }

emitLiveInvalidationProfileLog :: LiveInvalidationProfile -> IO ()
emitLiveInvalidationProfileLog profile = do
    enabled <- liveInvalidationProfilingLogEnabled
    when enabled do
        TextIO.putStrLn ("[live-invalidation] " <> renderLiveInvalidationProfile profile)

liveInvalidationProfilingLogEnabled :: IO Bool
liveInvalidationProfilingLogEnabled = do
    value <- Environment.lookupEnv "LIVE_INVALIDATION_PROFILING"
    pure (maybe False (`elem` ["1", "true", "TRUE", "yes", "YES", "on", "ON"]) value)

measureDuration :: IO a -> IO (a, Double)
measureDuration action = do
    startedAtNs <- getMonotonicTimeNSec
    result <- action
    completedAtNs <- getMonotonicTimeNSec
    pure (result, durationBetweenMs startedAtNs completedAtNs)

durationBetweenMs :: Word64 -> Word64 -> Double
durationBetweenMs startedAtNs completedAtNs =
    fromIntegral (completedAtNs - startedAtNs) / 1000000

renderDuration :: Double -> Text
renderDuration durationMs =
    tshow (fromIntegral (round (durationMs * 10)) / 10 :: Double)

coalesceScopes :: [SurfaceScope] -> [SurfaceScope]
coalesceScopes =
    Set.toList . Set.fromList
