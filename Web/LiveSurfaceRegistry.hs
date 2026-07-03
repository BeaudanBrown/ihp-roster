module Web.LiveSurfaceRegistry
    ( LiveSurfaceInvalidationTarget (..)
    , authorizeRegisteredLiveSurfaceScope
    , performLiveSurfaceInvalidationTarget
    , performLiveSurfaceInvalidationTargetWithoutContext
    , planRegisteredLiveSurfaceInvalidations
    , planRegisteredLiveSurfaceInvalidationsWithoutContext
    ) where

import Application.Helper.FrontendSurface.Authorization (authorizeFrontendSurfaceLiveScope)
import Application.Helper.FrontendSurface.DependencyPlanner (planFrontendSurfaceWireInvalidation)
import Application.Helper.LiveResource
import Application.Helper.LiveUpdate.Runtime
import qualified Data.Map.Strict as Map
import qualified Data.Set as Set
import Web.Controller.Prelude

data LiveSurfaceInvalidationTarget = LiveSurfaceInvalidationTarget
    { targetScope     :: !LiveUpdateScope
    , targetFragments :: ![LiveUpdateWireFragment]
    }
    deriving (Eq, Show)

authorizeRegisteredLiveSurfaceScope :: (?context :: ControllerContext, ?modelContext :: ModelContext) => LiveUpdateScope -> IO Bool
authorizeRegisteredLiveSurfaceScope = authorizeFrontendSurfaceLiveScope

planRegisteredLiveSurfaceInvalidations :: (?context :: ControllerContext) => Set.Set LiveResource -> [LiveUpdateSubscription] -> [LiveSurfaceInvalidationTarget]
planRegisteredLiveSurfaceInvalidations = planRegisteredLiveSurfaceInvalidationsWithoutContext

planRegisteredLiveSurfaceInvalidationsWithoutContext :: Set.Set LiveResource -> [LiveUpdateSubscription] -> [LiveSurfaceInvalidationTarget]
planRegisteredLiveSurfaceInvalidationsWithoutContext resources subscriptions =
    coalesceTargets $ mapMaybe (planSubscriptionInvalidation resources) subscriptions

performLiveSurfaceInvalidationTarget :: (?context :: ControllerContext, ?request :: Request) => LiveSurfaceInvalidationTarget -> IO LiveUpdateBroadcastResult
performLiveSurfaceInvalidationTarget target = broadcastLiveInvalidationDetailed target.targetScope liveUpdateSourceClientId target.targetFragments

performLiveSurfaceInvalidationTargetWithoutContext :: LiveSurfaceInvalidationTarget -> IO LiveUpdateBroadcastResult
performLiveSurfaceInvalidationTargetWithoutContext target = broadcastLiveInvalidationDetailedWithoutContext target.targetScope Nothing target.targetFragments

planSubscriptionInvalidation :: Set.Set LiveResource -> LiveUpdateSubscription -> Maybe LiveSurfaceInvalidationTarget
planSubscriptionInvalidation resources subscription = do
    let fragments = planFrontendSurfaceWireInvalidation resources subscription.subscriptionScope subscription.subscriptionMountedFragments
    if null fragments then Nothing else Just LiveSurfaceInvalidationTarget { targetScope = subscription.subscriptionScope, targetFragments = fragments }

coalesceTargets :: [LiveSurfaceInvalidationTarget] -> [LiveSurfaceInvalidationTarget]
coalesceTargets targets =
    [ LiveSurfaceInvalidationTarget scope (coalesceLiveUpdateWireFragments fragments)
    | (scope, fragments) <- Map.toAscList grouped
    ]
    where
        grouped = Map.fromListWith (<>) [(target.targetScope, target.targetFragments) | target <- targets]
