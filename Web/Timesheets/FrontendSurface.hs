{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.Timesheets.FrontendSurface
    ( TimesheetWeekScopeValue (..)
    , TimesheetsMountStateValue (..)
    , timesheetsCandidateMountedFragments
    , timesheetsSurfaceScope
    , timesheetsSurfaceImpl
    , timesheetsSurfaceMountConfig
    , timesheetsSurfaceScopeKey
    , timesheetsSurfaceWireFragments
    ) where

import Application.Helper.FrontendContract.Surface.DSL
import Application.Helper.FrontendContract.Surface.Runtime
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import Application.Helper.LiveUpdate.Runtime
import qualified Data.Aeson as Aeson
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.Timesheets.Paths (timesheetDayColumnsFragmentUrl,
                             timesheetDaySectionFragmentUrl,
                             timesheetToolbarFragmentUrl)
import Web.View.Timesheets.Index (timesheetDayColumnsId,
                                  timesheetDaySectionDomId,
                                  timesheetWeekToolbarId)

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

timesheetsSurfaceScope :: TimesheetWeekScopeValue -> SurfaceScope
timesheetsSurfaceScope scope =
    timesheetWeekLiveScope scope.timesheetWeekVenueId scope.timesheetWeekWeekOffset

timesheetsSurfaceWireFragments :: [FrontendSurfaceMountedFragment] -> [SurfaceWireFragment]
timesheetsSurfaceWireFragments =
    frontendSurfaceMountedFragmentsToWire "timesheets"

timesheetsCandidateMountedFragments :: TimesheetWeekScopeValue -> TimesheetsMountStateValue -> [FrontendSurfaceMountedFragment]
timesheetsCandidateMountedFragments scope mountState =
    [ timesheetToolbarMountedFragment mountState scope.timesheetWeekWeekOffset
    , timesheetDayColumnsMountedFragment mountState scope.timesheetWeekWeekOffset
    ] <> map (timesheetDaySectionMountedFragment mountState scope.timesheetWeekWeekOffset) [0 .. 6]

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
        , mountedFragmentLazyTrigger = Nothing
        , mountedFragmentPlaceholderKind = Nothing
        }

timesheetDayColumnsMountedFragment :: TimesheetsMountStateValue -> Int -> FrontendSurfaceMountedFragment
timesheetDayColumnsMountedFragment mountState weekOffset =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "timesheet-day-columns" Aeson.Null
        , mountedFragmentTargetId = timesheetDayColumnsId
        , mountedFragmentUrl = timesheetDayColumnsFragmentUrl weekOffset mountState.timesheetsMountShowApproved mountState.timesheetsMountShowAllStaff mountState.timesheetsMountStaffFilterId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        , mountedFragmentLazyTrigger = Nothing
        , mountedFragmentPlaceholderKind = Nothing
        }

timesheetDaySectionMountedFragment :: TimesheetsMountStateValue -> Int -> Int -> FrontendSurfaceMountedFragment
timesheetDaySectionMountedFragment mountState weekOffset dayOffset =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "timesheet-day-section" (Aeson.object ["dayOffset" Aeson..= dayOffset])
        , mountedFragmentTargetId = timesheetDaySectionDomId dayOffset
        , mountedFragmentUrl = timesheetDaySectionFragmentUrl weekOffset dayOffset mountState.timesheetsMountShowApproved mountState.timesheetsMountShowAllStaff mountState.timesheetsMountStaffFilterId
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "lazy"
        , mountedFragmentLazyTrigger = Nothing
        , mountedFragmentPlaceholderKind = Nothing
        }
