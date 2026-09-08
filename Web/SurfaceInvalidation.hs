module Web.SurfaceInvalidation
    ( SurfaceInvalidationTarget (..)
    , authorizeSurfaceScope
    , dispatchDurableInvalidation
    , dispatchDurableInvalidationWithBus
    , expandSurfaceResourcesWithoutContext
    , withDurableLiveMutation
    , withDurableLiveMutationOutcome
    , planSurfaceInvalidations
    , planSurfaceInvalidationsWithoutContext
    ) where

import Application.Bepis.Fact (BepisLiveMechanism (..))
import Application.Error.Runtime (ExternalRuntimeCategory (..), externalRuntimeInvariantFailure)
import Application.Helper.FrontendContract.Surface.Authorization (authorizeFrontendSurfaceScope)
import Application.Helper.FrontendContract.Surface.DependencyPlanner (SurfaceInvalidationTarget (..),
                                                                      planFrontendSurfaceInvalidations)
import Application.Helper.FrontendContract.Surface.Roster.Live (activeRosterWindowScopes)
import qualified Application.Helper.FrontendContract.Surface.Roster.Live as RosterLive
import Application.Helper.LiveUpdate.Diagnostics
import Application.Helper.LiveUpdate.DurableCodec (DurableResource (..))
import Application.Helper.LiveUpdate.DurablePublisher (DurablePublication (..),
                                                       withDurableLiveMutationOutcomeTransaction)
import Application.Helper.LiveUpdate.Runtime
import Application.Helper.Profiling (profileActionSpanWithDetail)
import Application.Helper.SurfaceResource
import Control.Monad (forM_)
import qualified Data.Set as Set
import Data.Time.Calendar (Day)
import Data.UUID (UUID)
import GHC.Clock (getMonotonicTimeNSec)
import Web.Controller.Prelude
import Web.RosterWeeks.SurfaceInvalidation (expandRosterSurfaceResourcesWithoutContext)

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
            (broadcastLiveInvalidationAtVersion target.targetScope eventSequence target.targetFragments)
            (\bus -> broadcastLiveInvalidationAtVersionWithBus bus target.targetScope eventSequence target.targetFragments)
            maybeBus

authorizeSurfaceScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => SurfaceScope -> IO Bool
authorizeSurfaceScope = authorizeFrontendSurfaceScope

planSurfaceInvalidations :: (?context :: ControllerContext) => Set.Set SurfaceResourceValue -> [SurfaceSubscription] -> [SurfaceInvalidationTarget]
planSurfaceInvalidations = planSurfaceInvalidationsWithoutContext

planSurfaceInvalidationsWithoutContext :: Set.Set SurfaceResourceValue -> [SurfaceSubscription] -> [SurfaceInvalidationTarget]
planSurfaceInvalidationsWithoutContext = planFrontendSurfaceInvalidations

expandSurfaceResourcesWithoutContext :: [(UUID, UUID, Day, Day, Int)] -> Set.Set SurfaceResourceValue -> Set.Set SurfaceResourceValue
expandSurfaceResourcesWithoutContext = expandRosterSurfaceResourcesWithoutContext

-- | Atomically commits a request-originated business mutation and its durable
-- invalidation. Process-local delivery is owned exclusively by the durable
-- listener after commit.
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
            _ -> externalRuntimeInvariantFailure PersistedRuntimeInvariant "durable live mutation outcome/publication mismatch"

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
    completedAtNs <- getMonotonicTimeNSec
    let resources = liveMutationTouchedResources observed
    let profile =
            liveInvalidationProfile
                label
                (durationBetweenMs startedAtNs completedAtNs)
                resources
                []
                resources
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
    emitLiveFactFromProfile BepisWebSocketFragmentRefetch profile
    pure (observed, Just (renderLiveInvalidationProfile profile))
