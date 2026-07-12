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
    , timesheetsSurfaceFragmentKeys
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
    mkSurfaceImpl "timesheets" (timesheetsSurfaceMountConfig scope mountState) (timesheetsSurfaceHandlers scope mountState)
        |> surfaceImplWithMountedFragments (timesheetsCandidateMountedFragments scope mountState)

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

timesheetsSurfaceFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
timesheetsSurfaceFragmentKeys =
    frontendSurfaceMountedFragmentsToKeys "timesheets"

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
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValuesFromPairs ["dayOffset" Aeson..= (0 :: Int)]
                    , fragmentHandlerMountedFragment = \fields ->
                        timesheetDaySectionMountedFragment mountState scope.timesheetWeekWeekOffset (fromMaybe 0 (getSurfaceField @Surface.DayOffset fields))
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` HandlerNil
        , surfaceActionHandlers =
            timesheetActionHandler "navigate-timesheet-week" (pathTo (ShowTimesheetWeekAction scope.timesheetWeekWeekOffset)) `HandlerCons`
            timesheetActionHandler "update-timesheet-filters" (pathTo (ShowTimesheetWeekAction scope.timesheetWeekWeekOffset)) `HandlerCons`
            timesheetActionHandler "approve-timesheet-entry" (pathTo (ApproveTimesheetEntryAction (Id UUID.nil))) `HandlerCons`
            timesheetActionHandler "unapprove-timesheet-entry" (pathTo (UnapproveTimesheetEntryAction (Id UUID.nil))) `HandlerCons`
            HandlerNil
        , surfaceIntentHandlers = HandlerNil
        }

timesheetActionHandler :: Text -> Text -> FrontendSurfaceActionHandler ('Action marker fields options)
timesheetActionHandler actionName actionUrl = FrontendSurfaceActionHandler
    { actionHandlerDefaultFields = frontendSurfaceFieldValues Aeson.Null
    , actionHandlerRequest = const FrontendSurfaceHtmxRequest
        { htmxRequestName = actionName
        , htmxRequestMethod = FrontendSurfacePost
        , htmxRequestUrl = actionUrl
        , htmxRequestTarget = ""
        , htmxRequestSwap = "none"
        , htmxRequestFields = []
        }
    }

timesheetWeekScopeFields :: TimesheetWeekScopeValue -> FrontendSurfaceFieldValues '[ 'Field Surface.VenueId 'WireUUID, 'Field Surface.WeekOffset 'WireInt]
timesheetWeekScopeFields scope =
    frontendSurfaceFieldValuesFromPairs
        [ "venueId" Aeson..= tshow scope.timesheetWeekVenueId
        , "weekOffset" Aeson..= scope.timesheetWeekWeekOffset
        ]

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
    frontendSurfaceMountedFragment
        "timesheet-toolbar"
        Aeson.Null
        timesheetWeekToolbarId
        (timesheetToolbarFragmentUrl weekOffset mountState.timesheetsMountShowApproved mountState.timesheetsMountShowAllStaff mountState.timesheetsMountStaffFilterId)
        FrontendSurfaceReplace

timesheetDayColumnsMountedFragment :: TimesheetsMountStateValue -> Int -> FrontendSurfaceMountedFragment
timesheetDayColumnsMountedFragment mountState weekOffset =
    frontendSurfaceMountedFragment
        "timesheet-day-columns"
        Aeson.Null
        timesheetDayColumnsId
        (timesheetDayColumnsFragmentUrl weekOffset mountState.timesheetsMountShowApproved mountState.timesheetsMountShowAllStaff mountState.timesheetsMountStaffFilterId)
        FrontendSurfaceReplace

timesheetDaySectionMountedFragment :: TimesheetsMountStateValue -> Int -> Int -> FrontendSurfaceMountedFragment
timesheetDaySectionMountedFragment mountState weekOffset dayOffset =
    frontendSurfaceMountedFragment
        "timesheet-day-section"
        (Aeson.object ["dayOffset" Aeson..= dayOffset])
        (timesheetDaySectionDomId dayOffset)
        (timesheetDaySectionFragmentUrl weekOffset dayOffset mountState.timesheetsMountShowApproved mountState.timesheetsMountShowAllStaff mountState.timesheetsMountStaffFilterId)
        FrontendSurfaceReplace
