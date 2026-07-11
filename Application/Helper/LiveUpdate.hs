module Application.Helper.LiveUpdate
    ( SurfaceFragmentKey (..)
    , SurfaceWireFragment (..)
    , SurfaceFragmentProtection (..)
    , FocusedFieldProtectionConfig (..)
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
    , adminXeroPayItemsLiveFragment
    , adminXeroShellLiveFragment
    , adminXeroStaffMappingsLiveFragment
    , adminXeroTimesheetsLiveFragment
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
    , actorLiveFragmentsRefreshFragments
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
                                                            frontendSurfaceMountedFragmentsToWire)
import Application.Helper.LiveUpdate.Internal
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Set as Set
import IHP.ControllerPrelude

setActorLiveFragmentsRefresh :: (?context :: ControllerContext, ?request :: Request) => SurfaceScope -> [SurfaceWireFragment] -> IO ()
setActorLiveFragmentsRefresh scope fragments =
    setHeader
        ( "HX-Trigger"
        , cs (Aeson.encode (actorLiveFragmentsRefreshTriggerPayload scope fragments))
        )

setActorLiveResourcesRefresh :: (?context :: ControllerContext, ?request :: Request) => SurfaceScope -> Set.Set SurfaceResourceValue -> [FrontendSurfaceMountedFragment] -> IO ()
setActorLiveResourcesRefresh scope touchedResources candidates =
    setActorLiveFragmentsRefresh scope (actorLiveFragmentsRefreshFragments scope touchedResources candidates)

actorLiveFragmentsRefreshFragments :: SurfaceScope -> Set.Set SurfaceResourceValue -> [FrontendSurfaceMountedFragment] -> [SurfaceWireFragment]
actorLiveFragmentsRefreshFragments scope touchedResources candidates =
    candidates
        |> planFrontendSurfaceInvalidation touchedResources scope
        |> frontendSurfaceMountedFragmentsToWire (surfaceScopeKind scope)

actorLiveFragmentsRefreshTriggerPayload :: SurfaceScope -> [SurfaceWireFragment] -> Aeson.Value
actorLiveFragmentsRefreshTriggerPayload scope fragments =
    Aeson.object
        [ AesonKey.fromText canonicalAppEvents.appLiveFragmentsRefreshEventName Aeson..= Aeson.object
            [ "scope" Aeson..= scope
            , "scopeKey" Aeson..= surfaceScopeKey scope
            , "fragments" Aeson..= coalesceSurfaceWireFragments fragments
            ]
        ]
