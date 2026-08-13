module Application.Helper.LiveUpdate
    ( SurfaceFragmentKey
    , SurfaceScope
    , actorLiveFragmentsRefreshKeys
    , actorLiveFragmentsRefreshTriggerPayload
    , currentLiveUpdateVersion
    , surfaceScopeKey
    , setActorLocalFragmentsRefresh
    , setActorLiveResourcesRefresh
    , setActorLiveResourcesRefreshIncluding
    ) where

import Application.Helper.FrontendContract.AppValues (AppEvents (..),
                                                      canonicalAppEvents)
import Application.Helper.FrontendContract.Surface.DependencyPlanner (SurfaceInvalidationTarget (..),
                                                                      planFrontendSurfaceInvalidations)
import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceMountedFragment,
                                                            mountedFragmentKey)
import qualified Application.Helper.FrontendContract.Wire.LiveUpdate as Wire
import Application.Helper.LiveUpdate.Internal
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Set as Set
import IHP.ControllerPrelude

-- | Emit an explicit actor-only workflow refresh when no shared resource
-- changed (for example, viewer-local preference navigation). Mutations with
-- touched resources must use 'setActorLiveResourcesRefresh'.
setActorLocalFragmentsRefresh :: (?context :: ControllerContext, ?request :: Request) => SurfaceScope -> [SurfaceFragmentKey] -> IO ()
setActorLocalFragmentsRefresh scope fragments =
    setHeader
        ( "HX-Trigger"
        , cs (Aeson.encode (actorLiveFragmentsRefreshTriggerPayload scope fragments))
        )

setActorLiveResourcesRefresh :: (?context :: ControllerContext, ?request :: Request) => SurfaceScope -> Set.Set SurfaceResourceValue -> [FrontendSurfaceMountedFragment] -> IO ()
setActorLiveResourcesRefresh scope touchedResources mountedFragments =
    setActorLiveResourcesRefreshIncluding [] scope touchedResources mountedFragments

-- | Refresh resource-dependent actor fragments plus explicit actor-only workflow
-- fragments, such as resetting a resync-only form after a successful mutation.
setActorLiveResourcesRefreshIncluding :: (?context :: ControllerContext, ?request :: Request) => [SurfaceFragmentKey] -> SurfaceScope -> Set.Set SurfaceResourceValue -> [FrontendSurfaceMountedFragment] -> IO ()
setActorLiveResourcesRefreshIncluding actorOnlyFragments scope touchedResources mountedFragments = do
    let resourceFragmentKeys = actorLiveFragmentsRefreshKeys scope touchedResources mountedFragments
    let fragmentKeys = coalesceSurfaceFragmentKeys (actorOnlyFragments <> resourceFragmentKeys)
    unless (null fragmentKeys) do
        setActorLocalFragmentsRefresh scope fragmentKeys

actorLiveFragmentsRefreshKeys :: SurfaceScope -> Set.Set SurfaceResourceValue -> [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
actorLiveFragmentsRefreshKeys scope touchedResources mountedFragments =
    planFrontendSurfaceInvalidations touchedResources [mountSubscription]
        |> concatMap (.targetFragments)
  where
    mountSubscription = SurfaceSubscription
        { subscriptionScope = scope
        , subscriptionScopeKey = surfaceScopeKey scope
        , subscriptionFragmentKeys = map (.mountedFragmentKey) mountedFragments
        , subscriptionRenderedDependencyWatermark = 0
        }

actorLiveFragmentsRefreshTriggerPayload :: SurfaceScope -> [SurfaceFragmentKey] -> Aeson.Value
actorLiveFragmentsRefreshTriggerPayload scope fragmentKeys =
    Aeson.object
        [ AesonKey.fromText canonicalAppEvents.appLiveFragmentsRefreshEventName Aeson..= Wire.LiveFragmentsRefreshEventDetail
            { Wire.scope = surfaceScopeToWire scope
            , Wire.scopeKey = surfaceScopeKey scope
            , Wire.fragments = map surfaceFragmentKeyToWire (coalesceSurfaceFragmentKeys fragmentKeys)
            }
        ]
