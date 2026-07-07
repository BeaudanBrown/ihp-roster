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
    , frontendSurfaceSurfaceFragmentKey
    , frontendSurfaceLiveScope
    , leaveRequestsContentLiveFragment
    , leaveRequestsLiveScope
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
    , activeRosterWeekScopes
    , actorLiveFragmentsRefreshTriggerPayload
    , currentLiveUpdateVersion
    , surfaceScopeFieldUuid
    , surfaceScopeKey
    , surfaceScopeKind
    , setActorLiveFragmentsRefresh
    ) where

import Application.Helper.FrontendContract.AppValues (AppEvents (..),
                                                      canonicalAppEvents)
import Application.Helper.LiveUpdate.Internal
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import IHP.ControllerPrelude

setActorLiveFragmentsRefresh :: (?context :: ControllerContext, ?request :: Request) => SurfaceScope -> [SurfaceWireFragment] -> IO ()
setActorLiveFragmentsRefresh scope fragments =
    setHeader
        ( "HX-Trigger"
        , cs (Aeson.encode (actorLiveFragmentsRefreshTriggerPayload scope fragments))
        )

actorLiveFragmentsRefreshTriggerPayload :: SurfaceScope -> [SurfaceWireFragment] -> Aeson.Value
actorLiveFragmentsRefreshTriggerPayload scope fragments =
    Aeson.object
        [ AesonKey.fromText canonicalAppEvents.appLiveFragmentsRefreshEventName Aeson..= Aeson.object
            [ "scope" Aeson..= scope
            , "scopeKey" Aeson..= surfaceScopeKey scope
            , "fragments" Aeson..= coalesceSurfaceWireFragments fragments
            ]
        ]
