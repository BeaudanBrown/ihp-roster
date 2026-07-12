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
    , setActorLiveFragmentsRefresh
    , setActorLiveResourcesRefresh
    ) where

import Application.Helper.FrontendContract.AppValues (AppEvents (..),
                                                      canonicalAppEvents)
import Application.Helper.FrontendContract.Surface.DependencyPlanner (planFrontendSurfaceInvalidation)
import Application.Helper.FrontendContract.Surface.Resource (SurfaceResourceValue)
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceMountedFragment,
                                                            frontendSurfaceMountedFragmentsToKeys)
import qualified Application.Helper.FrontendContract.Wire.LiveUpdate as Wire
import Application.Helper.LiveUpdate.Internal
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Set as Set
import IHP.ControllerPrelude

setActorLiveFragmentsRefresh :: (?context :: ControllerContext, ?request :: Request) => SurfaceScope -> [SurfaceFragmentKey] -> IO ()
setActorLiveFragmentsRefresh scope fragments =
    setHeader
        ( "HX-Trigger"
        , cs (Aeson.encode (actorLiveFragmentsRefreshTriggerPayload scope fragments))
        )

setActorLiveResourcesRefresh :: (?context :: ControllerContext, ?request :: Request) => SurfaceScope -> Set.Set SurfaceResourceValue -> [FrontendSurfaceMountedFragment] -> IO ()
setActorLiveResourcesRefresh scope touchedResources candidates =
    setActorLiveFragmentsRefresh scope (actorLiveFragmentsRefreshKeys scope touchedResources candidates)

actorLiveFragmentsRefreshKeys :: SurfaceScope -> Set.Set SurfaceResourceValue -> [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
actorLiveFragmentsRefreshKeys scope touchedResources candidates =
    candidates
        |> planFrontendSurfaceInvalidation touchedResources scope
        |> frontendSurfaceMountedFragmentsToKeys (surfaceScopeKind scope)

actorLiveFragmentsRefreshTriggerPayload :: SurfaceScope -> [SurfaceFragmentKey] -> Aeson.Value
actorLiveFragmentsRefreshTriggerPayload scope fragmentKeys =
    Aeson.object
        [ AesonKey.fromText canonicalAppEvents.appLiveFragmentsRefreshEventName Aeson..= Wire.LiveFragmentsRefreshEventDetail
            { Wire.scope = surfaceScopeToWire scope
            , Wire.scopeKey = surfaceScopeKey scope
            , Wire.fragments = map surfaceFragmentKeyToWire (coalesceSurfaceFragmentKeys fragmentKeys)
            }
        ]
