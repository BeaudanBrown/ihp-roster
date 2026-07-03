{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.Timesheets.FrontendSurface
    ( TimesheetWeekScopeValue (..)
    , TimesheetsMountStateValue (..)
    , TimesheetSurfaceFragment (..)
    , timesheetsAffectedMountedFragments
    , timesheetsCandidateMountedFragments
    , timesheetsFragmentDependencies
    , timesheetsLegacyLiveSurfaceConfig
    , timesheetsLiveUpdateScope
    , timesheetsSurfaceImpl
    , timesheetsSurfaceMountConfig
    , timesheetsSurfaceScopeKey
    , timesheetsSurfaceWireFragments
    ) where

import Application.Helper.FrontendSurface.DSL
import Application.Helper.FrontendSurface.Runtime
import qualified Application.Helper.FrontendSurface.Timesheets as Surface
import Application.Helper.LiveResource
import Application.Helper.LiveSurface (LiveSurfaceConfig (..))
import Application.Helper.LiveUpdate.Runtime (LiveUpdateScope (..),
                                              LiveUpdateWireFragment,
                                              liveUpdateScopeKey)
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Types as Aeson
import qualified Data.Set as Set
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.Timesheets.Paths (timesheetDayColumnsFragmentUrl,
                             timesheetDaySectionFragmentUrl,
                             timesheetToolbarFragmentUrl)
import Web.View.Timesheets.Index (timesheetDayColumnsId,
                                  timesheetDaySectionDomId,
                                  timesheetWeekToolbarId)

data TimesheetSurfaceFragment
    = TimesheetSurfaceToolbar
    | TimesheetSurfaceDayColumns
    | TimesheetSurfaceDaySection !Int
    deriving (Eq, Show)

-- | Logical live invalidation scope. Filter/query state intentionally lives in
-- 'TimesheetsMountStateValue' instead of the scope so a future mount-state store
-- can replace query params without changing the surface identity.
data TimesheetWeekScopeValue = TimesheetWeekScopeValue
    { timesheetWeekVenueId    :: !UUID.UUID
    , timesheetWeekWeekOffset :: !Int
    }
    deriving (Eq, Show)

data TimesheetsMountStateValue = TimesheetsMountStateValue
    { timesheetsMountShowApproved  :: !Bool
    , timesheetsMountShowAllStaff  :: !Bool
    , timesheetsMountStaffFilterId :: !(Maybe UUID.UUID)
    }
    deriving (Eq, Show)

timesheetsSurfaceImpl :: TimesheetWeekScopeValue -> TimesheetsMountStateValue -> SurfaceImpl Surface.TimesheetsSurface
timesheetsSurfaceImpl scope mountState =
    let impl = mkSurfaceImpl "timesheets" (timesheetsSurfaceMountConfig scope mountState) (timesheetsSurfaceHandlers scope mountState)
     in impl { surfaceImplMountConfig = impl.surfaceImplMountConfig { mountFragments = timesheetsCandidateMountedFragments scope mountState } }

timesheetsSurfaceMountConfig :: TimesheetWeekScopeValue -> TimesheetsMountStateValue -> FrontendSurfaceMountConfig
timesheetsSurfaceMountConfig scope mountState =
    FrontendSurfaceMountConfig
        { mountSurfaceName = "timesheets"
        , mountScopeKey = timesheetsSurfaceScopeKey scope
        , mountKey = "primary"
        , mountScope = Aeson.Null
        , mountSubscription = Nothing
        , mountState = timesheetsMountStateJson mountState
        , mountFragments = timesheetsCandidateMountedFragments scope mountState
        }

timesheetsSurfaceScopeKey :: TimesheetWeekScopeValue -> Text
timesheetsSurfaceScopeKey scope =
    "timesheets:" <> tshow scope.timesheetWeekVenueId <> ":" <> tshow scope.timesheetWeekWeekOffset

timesheetsLiveUpdateScope :: TimesheetWeekScopeValue -> LiveUpdateScope
timesheetsLiveUpdateScope scope =
    TimesheetWeekScope
        { venueId = scope.timesheetWeekVenueId
        , weekOffset = scope.timesheetWeekWeekOffset
        }

timesheetsLegacyLiveSurfaceConfig :: SurfaceImpl Surface.TimesheetsSurface -> TimesheetWeekScopeValue -> LiveSurfaceConfig
timesheetsLegacyLiveSurfaceConfig impl scope =
    let wireScope = timesheetsLiveUpdateScope scope
     in LiveSurfaceConfig
            { feature = "timesheets"
            , socketPath = "/live-updates"
            , scope = wireScope
            , scopeKey = liveUpdateScopeKey wireScope
            , resyncFragments = timesheetsSurfaceWireFragments impl.surfaceImplMountConfig.mountFragments
            , decorateRequestsWithin = ["#" <> timesheetDayColumnsId, "#roster-staff-self-service-timesheet-live-surface"]
            }

timesheetsSurfaceWireFragments :: [FrontendSurfaceMountedFragment] -> [LiveUpdateWireFragment]
timesheetsSurfaceWireFragments =
    frontendSurfaceMountedFragmentsToWire "timesheets"

timesheetsCandidateMountedFragments :: TimesheetWeekScopeValue -> TimesheetsMountStateValue -> [FrontendSurfaceMountedFragment]
timesheetsCandidateMountedFragments scope mountState =
    [ timesheetToolbarMountedFragment mountState scope.timesheetWeekWeekOffset
    , timesheetDayColumnsMountedFragment mountState scope.timesheetWeekWeekOffset
    ] <> map (timesheetDaySectionMountedFragment mountState scope.timesheetWeekWeekOffset) [0 .. 6]

timesheetsAffectedMountedFragments :: TimesheetWeekScopeValue -> TimesheetsMountStateValue -> Set.Set LiveResource -> [FrontendSurfaceMountedFragment]
timesheetsAffectedMountedFragments scope mountState touchedResources =
    timesheetsCandidateMountedFragments scope mountState
        |> filter (fragmentDependsOnTouchedResource scope touchedResources . mountedFragmentToSurfaceFragment)

mountedFragmentToSurfaceFragment :: FrontendSurfaceMountedFragment -> TimesheetSurfaceFragment
mountedFragmentToSurfaceFragment fragment =
    case fragment.mountedFragmentKey.fragmentKind of
        "timesheet-toolbar" -> TimesheetSurfaceToolbar
        "timesheet-day-columns" -> TimesheetSurfaceDayColumns
        "timesheet-day-section" ->
            TimesheetSurfaceDaySection (fromMaybe 0 (parseFragmentDayOffset fragment.mountedFragmentKey.fragmentParams))
        _ -> TimesheetSurfaceDayColumns

parseFragmentDayOffset :: Aeson.Value -> Maybe Int
parseFragmentDayOffset value =
    Aeson.parseMaybe (Aeson.withObject "TimesheetDaySectionFragment" (.: "dayOffset")) value

fragmentDependsOnTouchedResource :: TimesheetWeekScopeValue -> Set.Set LiveResource -> TimesheetSurfaceFragment -> Bool
fragmentDependsOnTouchedResource scope touchedResources fragment =
    not (Set.null (Set.intersection touchedResources (Set.fromList (timesheetsFragmentDependencies scope fragment))))

timesheetsFragmentDependencies :: TimesheetWeekScopeValue -> TimesheetSurfaceFragment -> [LiveResource]
timesheetsFragmentDependencies scope TimesheetSurfaceToolbar =
    [ timesheetWeekResource scope.timesheetWeekVenueId scope.timesheetWeekWeekOffset
    , timesheetWeekBoundaryConfigResource scope.timesheetWeekVenueId
    ]
timesheetsFragmentDependencies scope TimesheetSurfaceDayColumns =
    [ timesheetWeekResource scope.timesheetWeekVenueId scope.timesheetWeekWeekOffset
    , timesheetWeekBoundaryConfigResource scope.timesheetWeekVenueId
    ]
timesheetsFragmentDependencies scope (TimesheetSurfaceDaySection dayOffset) =
    [ timesheetDayResource scope.timesheetWeekVenueId scope.timesheetWeekWeekOffset dayOffset
    , timesheetWeekBoundaryConfigResource scope.timesheetWeekVenueId
    ]

timesheetsSurfaceHandlers :: TimesheetWeekScopeValue -> TimesheetsMountStateValue -> SurfaceImplHandlers Surface.TimesheetsSurface
timesheetsSurfaceHandlers scope mountState =
    SurfaceImplHandlers
        { surfaceScopeHandlers =
            FrontendSurfaceScopeHandler
                { scopeHandlerDefaultValue = timesheetWeekScopeFields scope
                , scopeHandlerKey = \fields ->
                    let venueId = fromMaybe (tshow scope.timesheetWeekVenueId) (getSurfaceField @Surface.VenueId fields)
                        weekOffset = fromMaybe scope.timesheetWeekWeekOffset (getSurfaceField @Surface.WeekOffset fields)
                     in "timesheets:" <> venueId <> ":" <> tshow weekOffset
                }
                `HandlerCons` HandlerNil
        , surfaceMountStateHandlers =
            FrontendSurfaceMountStateHandler
                { mountStateHandlerDefaultValue = timesheetsMountStateFields mountState
                }
                `HandlerCons` HandlerNil
        , surfaceFragmentHandlers =
            FrontendSurfaceFragmentHandler
                { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                , fragmentHandlerMountedFragment = const (timesheetToolbarMountedFragment mountState scope.timesheetWeekWeekOffset)
                , fragmentHandlerRender = const mempty
                }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                    , fragmentHandlerMountedFragment = const (timesheetDayColumnsMountedFragment mountState scope.timesheetWeekWeekOffset)
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues (Aeson.object ["dayOffset" Aeson..= (0 :: Int)])
                    , fragmentHandlerMountedFragment = \fields ->
                        timesheetDaySectionMountedFragment mountState scope.timesheetWeekWeekOffset (fromMaybe 0 (getSurfaceField @Surface.DayOffset fields))
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` HandlerNil
        , surfaceActionHandlers = HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

timesheetWeekScopeFields :: TimesheetWeekScopeValue -> FrontendSurfaceFieldValues '[ 'Field Surface.VenueId 'WireUUID, 'Field Surface.WeekOffset 'WireInt]
timesheetWeekScopeFields scope =
    frontendSurfaceFieldValues (Aeson.object
        [ "venueId" Aeson..= tshow scope.timesheetWeekVenueId
        , "weekOffset" Aeson..= scope.timesheetWeekWeekOffset
        ])

timesheetsMountStateFields :: TimesheetsMountStateValue -> FrontendSurfaceFieldValues '[ 'Field Surface.ShowApproved 'WireBool, 'Field Surface.ShowAllStaff 'WireBool, 'Field Surface.StaffFilterId ('WireOptional 'WireUUID)]
timesheetsMountStateFields mountState =
    frontendSurfaceFieldValues (timesheetsMountStateJson mountState)

timesheetsMountStateJson :: TimesheetsMountStateValue -> Aeson.Value
timesheetsMountStateJson mountState =
    Aeson.object
        [ "showApproved" Aeson..= mountState.timesheetsMountShowApproved
        , "showAllStaff" Aeson..= mountState.timesheetsMountShowAllStaff
        , "staffFilterId" Aeson..= fmap tshow mountState.timesheetsMountStaffFilterId
        ]

timesheetToolbarMountedFragment :: TimesheetsMountStateValue -> Int -> FrontendSurfaceMountedFragment
timesheetToolbarMountedFragment mountState weekOffset =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "timesheet-toolbar" Aeson.Null
        , mountedFragmentTargetId = timesheetWeekToolbarId
        , mountedFragmentUrl = timesheetToolbarFragmentUrl weekOffset mountState.timesheetsMountShowApproved mountState.timesheetsMountShowAllStaff mountState.timesheetsMountStaffFilterId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

timesheetDayColumnsMountedFragment :: TimesheetsMountStateValue -> Int -> FrontendSurfaceMountedFragment
timesheetDayColumnsMountedFragment mountState weekOffset =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "timesheet-day-columns" Aeson.Null
        , mountedFragmentTargetId = timesheetDayColumnsId
        , mountedFragmentUrl = timesheetDayColumnsFragmentUrl weekOffset mountState.timesheetsMountShowApproved mountState.timesheetsMountShowAllStaff mountState.timesheetsMountStaffFilterId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

timesheetDaySectionMountedFragment :: TimesheetsMountStateValue -> Int -> Int -> FrontendSurfaceMountedFragment
timesheetDaySectionMountedFragment mountState weekOffset dayOffset =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "timesheet-day-section" (Aeson.object ["dayOffset" Aeson..= dayOffset])
        , mountedFragmentTargetId = timesheetDaySectionDomId dayOffset
        , mountedFragmentUrl = timesheetDaySectionFragmentUrl weekOffset dayOffset mountState.timesheetsMountShowApproved mountState.timesheetsMountShowAllStaff mountState.timesheetsMountStaffFilterId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "lazy"
        }
