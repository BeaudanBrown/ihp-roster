module Application.Helper.LiveUpdate
    ( SurfaceFragmentKey (..)
    , SurfaceScope (..)
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
    , adminXeroShellLiveFragment
    , billingLiveScope
    , billingStatusLiveFragment
    , frontendSurfaceLiveScope
    , leaveRequestsContentLiveFragment
    , leaveRequestsLiveScope
    , profileContentLiveFragment
    , profileLiveScope
    , rosterContentLiveFragment
    , rosterDayColumnsLiveFragment
    , rosterDayRailLiveFragment
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
    , timesheetDaySectionLiveFragment
    , timesheetToolbarLiveFragment
    , timesheetWeekLiveScope
    , activeRosterWeekScopes
    , actorLiveFragmentsRefreshKeys
    , actorLiveFragmentsRefreshTriggerPayload
    , currentLiveUpdateVersion
    , surfaceScopeKey
    , surfaceScopeKind
    , setActorLocalFragmentsRefresh
    , setActorLiveResourcesRefresh
    ) where

import Application.Helper.FrontendContract.AppValues (AppEvents (..),
                                                      canonicalAppEvents)
import Application.Helper.FrontendContract.Surface.DependencyPlanner (SurfaceInvalidationTarget (..),
                                                                      planFrontendSurfaceInvalidations)
import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceMountedFragment,
                                                            frontendSurfaceMountedFragmentsToKeys)
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
setActorLiveResourcesRefresh scope touchedResources mountedFragments = do
    let fragmentKeys = actorLiveFragmentsRefreshKeys scope touchedResources mountedFragments
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
        , subscriptionFragmentKeys = frontendSurfaceMountedFragmentsToKeys (surfaceScopeKind scope) mountedFragments
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
