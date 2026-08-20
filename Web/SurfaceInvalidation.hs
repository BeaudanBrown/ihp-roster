module Web.SurfaceInvalidation
    ( LiveInvalidationProfile (..)
    , LiveInvalidationStageDurations (..)
    , SurfaceInvalidationTarget (..)
    , authorizeSurfaceScope
    , bepisLiveFactFromProfile
    , dispatchDurableInvalidation
    , dispatchDurableInvalidationWithBus
    , expandSurfaceResources
    , expandSurfaceResourcesWithoutContext
    , invalidateTouchedResources
    , publishTouchedResourcesWithoutContext
    , withDurableLiveMutation
    , withDurableLiveMutationOutcome
    , withDurableLiveMutationWithoutContext
    , liveInvalidationProfile
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
import Application.Helper.FrontendContract.Surface.Roster.Live (activeRosterWindowScopes)
import qualified Application.Helper.FrontendContract.Surface.Roster.Live as RosterLive
import Application.Helper.LiveUpdate.DurableCodec (DurableResource (..))
import Application.Helper.LiveUpdate.DurablePublisher (DurablePublication (..),
                                                       publishDurableInvalidation,
                                                       withDurableLiveMutationOutcomeTransaction,
                                                       withDurableLiveMutationTransaction)
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.Profiling (profileActionSpanWithDetail)
import Application.Helper.SurfaceResource
import qualified Control.Exception as Exception
import Control.Monad (forM_)
import qualified Data.Set as Set
import qualified Data.Text as Text
import qualified Data.Text.IO as TextIO
import Data.Time.Calendar (Day)
import Data.UUID (UUID)
import GHC.Clock (getMonotonicTimeNSec)
import qualified System.Environment as Environment
import Web.Controller.Prelude
import Web.RosterWeeks.SurfaceInvalidation (expandRosterSurfaceResources,
                                            expandRosterSurfaceResourcesWithoutContext)

dispatchDurableInvalidation :: Int -> [DurableResource] -> IO ()
dispatchDurableInvalidation = dispatchDurableInvalidationWithBus Nothing

dispatchDurableInvalidationWithBus :: Maybe LiveBus -> Int -> [DurableResource] -> IO ()
dispatchDurableInvalidationWithBus maybeBus eventSequence resources = do
    activeSubscriptions <- maybe activeSurfaceSubscriptions activeSurfaceSubscriptionsWithBus maybeBus
    activeRosterScopes <- maybe activeRosterWindowScopes RosterLive.activeRosterWindowScopesWithBus maybeBus
    let touchedResources = Set.fromList (map (.durableResourceValue) resources)
    let expandedResources = expandSurfaceResourcesWithoutContext activeRosterScopes touchedResources
    let targets = planSurfaceInvalidationsWithoutContext expandedResources activeSubscriptions
    forM_ targets \target ->
        maybe
            (broadcastLiveInvalidationAtVersion target.targetScope eventSequence Nothing target.targetFragments)
            (\bus -> broadcastLiveInvalidationAtVersionWithBus bus target.targetScope eventSequence Nothing target.targetFragments)
            maybeBus

authorizeSurfaceScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => SurfaceScope -> IO Bool
authorizeSurfaceScope = authorizeFrontendSurfaceScope

planSurfaceInvalidations :: (?context :: ControllerContext) => Set.Set SurfaceResourceValue -> [SurfaceSubscription] -> [SurfaceInvalidationTarget]
planSurfaceInvalidations = planSurfaceInvalidationsWithoutContext

planSurfaceInvalidationsWithoutContext :: Set.Set SurfaceResourceValue -> [SurfaceSubscription] -> [SurfaceInvalidationTarget]
planSurfaceInvalidationsWithoutContext = planFrontendSurfaceInvalidations

performSurfaceInvalidationTargetWithoutContext :: SurfaceInvalidationTarget -> IO LiveUpdateBroadcastResult
performSurfaceInvalidationTargetWithoutContext target = broadcastLiveInvalidationDetailedWithoutContext target.targetScope Nothing target.targetFragments

performSurfaceInvalidationTargetAtVersion :: Int -> Maybe Text -> SurfaceInvalidationTarget -> IO LiveUpdateBroadcastResult
performSurfaceInvalidationTargetAtVersion version sourceClientId target =
    broadcastLiveInvalidationAtVersion target.targetScope version sourceClientId target.targetFragments

expandSurfaceResources ::
    (?context :: ControllerContext, ?modelContext :: ModelContext) =>
    [(UUID, UUID, Day, Day, Int)] ->
    Set.Set SurfaceResourceValue ->
    IO (Set.Set SurfaceResourceValue)
expandSurfaceResources = expandRosterSurfaceResources

expandSurfaceResourcesWithoutContext :: [(UUID, UUID, Day, Day, Int)] -> Set.Set SurfaceResourceValue -> Set.Set SurfaceResourceValue
expandSurfaceResourcesWithoutContext = expandRosterSurfaceResourcesWithoutContext

-- | Atomically commits a request-originated business mutation and its durable
-- invalidation, then performs compatibility-stage local fanout after commit.
withDurableLiveMutation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Text ->
    ((?modelContext :: ModelContext) => IO (LiveMutationResult a)) ->
    IO (LiveMutationResult a)
withDurableLiveMutation label businessAction =
    withDurableLiveMutationOutcome
        (\result -> Just (label, result.liveMutationTouchedResources))
        businessAction

-- | Atomic request seam for mutations with validation, stale-lock, or
-- idempotent no-op outcomes. The selector returns resources only when the
-- outcome contains a committed live-visible business change.
withDurableLiveMutationOutcome ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    (outcome -> Maybe (Text, Set.Set SurfaceResourceValue)) ->
    ((?modelContext :: ModelContext) => IO outcome) ->
    IO outcome
withDurableLiveMutationOutcome publicationFor businessAction =
    profileActionSpanWithDetail "surface_resources.invalidate" do
        startedAtNs <- getMonotonicTimeNSec
        (outcome, maybePublication) <-
            withDurableLiveMutationOutcomeTransaction publicationFor businessAction
        case (publicationFor outcome, maybePublication) of
            (Nothing, Nothing) -> pure (outcome, Nothing)
            (Just (label, touchedResources), Just publication) -> do
                (observed, observeDurationMs) <- measureDuration $
                    recordLiveMutationDiagnostics label (LiveMutationResult () touchedResources)
                (_, profileDetail) <- completeRequestInvalidation startedAtNs label observed observeDurationMs publication
                pure (outcome, profileDetail)
            _ -> error "durable live mutation outcome/publication mismatch"

invalidateTouchedResources :: (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) => Text -> LiveMutationResult a -> IO (LiveMutationResult a)
invalidateTouchedResources label result =
    profileActionSpanWithDetail "surface_resources.invalidate" do
        startedAtNs <- getMonotonicTimeNSec
        (observed, observeDurationMs) <- measureDuration (recordLiveMutationDiagnostics label result)
        publication <- publishDurableInvalidation label observed.liveMutationTouchedResources `Exception.onException` emitDurablePublicationFailure label
        completeRequestInvalidation startedAtNs label observed observeDurationMs publication

completeRequestInvalidation ::
    (?context :: ControllerContext, ?modelContext :: ModelContext, ?request :: Request) =>
    Word64 ->
    Text ->
    LiveMutationResult a ->
    Double ->
    DurablePublication ->
    IO (LiveMutationResult a, Maybe Text)
completeRequestInvalidation startedAtNs label observed observeDurationMs publication = do
    emitDurablePublicationLog label publication
    (activeSubscriptions, activeSubscriptionDurationMs) <- measureDuration activeSurfaceSubscriptions
    (activeRosterScopes, activeRosterDurationMs) <- measureDuration activeRosterWindowScopes
    let activeDurationMs = activeSubscriptionDurationMs + activeRosterDurationMs
    let activeScopes = coalesceScopes (map (.subscriptionScope) activeSubscriptions)
    (expandedResources, expandDurationMs) <- measureDuration $
        case currentVenueOrNothing of
            Just _ -> expandSurfaceResources activeRosterScopes (liveMutationTouchedResources observed)
            Nothing -> pure (expandSurfaceResourcesWithoutContext activeRosterScopes (liveMutationTouchedResources observed))
    (dependencyTargets, planDurationMs) <- measureDuration (pure (planSurfaceInvalidations expandedResources activeSubscriptions))
    (broadcastResults, broadcastDurationMs) <- measureDuration (mapM (performSurfaceInvalidationTargetAtVersion publication.durablePublicationEventSequence liveUpdateSourceClientId) dependencyTargets)
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

-- | Atomically commits a worker/background business mutation and its durable
-- invalidation. Listener delivery begins only after the transaction commits.
withDurableLiveMutationWithoutContext ::
    (?modelContext :: ModelContext) =>
    Text ->
    ((?modelContext :: ModelContext) => IO (LiveMutationResult a)) ->
    IO (LiveMutationResult a)
withDurableLiveMutationWithoutContext label businessAction = do
    startedAtNs <- getMonotonicTimeNSec
    (result, publication) <- withDurableLiveMutationTransaction label businessAction
    completeBackgroundInvalidation startedAtNs label result publication

-- | Worker/background sequential compatibility seam for producer families not
-- yet migrated to 'withDurableLiveMutationWithoutContext'.
publishTouchedResourcesWithoutContext :: (?modelContext :: ModelContext) => Text -> LiveMutationResult a -> IO (LiveMutationResult a)
publishTouchedResourcesWithoutContext label result = do
    startedAtNs <- getMonotonicTimeNSec
    publication <- publishDurableInvalidation label result.liveMutationTouchedResources `Exception.onException` emitDurablePublicationFailure label
    completeBackgroundInvalidation startedAtNs label result publication

completeBackgroundInvalidation :: (?modelContext :: ModelContext) => Word64 -> Text -> LiveMutationResult a -> DurablePublication -> IO (LiveMutationResult a)
completeBackgroundInvalidation startedAtNs label result publication = do
    (observed, observeDurationMs) <- measureDuration (recordLiveMutationDiagnostics label result)
    emitDurablePublicationLog label publication
    completedAtNs <- getMonotonicTimeNSec
    let profile =
            liveInvalidationProfile
                label
                (durationBetweenMs startedAtNs completedAtNs)
                (liveMutationTouchedResources observed)
                []
                (liveMutationTouchedResources observed)
                []
                []
                LiveInvalidationStageDurations
                    { observeDurationMs
                    , activeDurationMs = 0
                    , expandDurationMs = 0
                    , planDurationMs = 0
                    , broadcastDurationMs = 0
                    }
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

emitDurablePublicationLog :: Text -> DurablePublication -> IO ()
emitDurablePublicationLog label publication = do
    enabled <- liveInvalidationProfilingLogEnabled
    when enabled do
        TextIO.putStrLn $
            "[live-invalidation] publication"
                <> " label=" <> label
                <> " event_id=" <> tshow publication.durablePublicationEventId
                <> " resources=" <> tshow publication.durablePublicationResourceCount
                <> " payload_bytes=" <> tshow publication.durablePublicationPayloadBytes
                <> " publish_ms=" <> renderDuration publication.durablePublicationDurationMs

emitDurablePublicationFailure :: Text -> IO ()
emitDurablePublicationFailure label = do
    enabled <- liveInvalidationProfilingLogEnabled
    when enabled (TextIO.putStrLn ("[live-invalidation] publication_failed=true label=" <> label))

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
