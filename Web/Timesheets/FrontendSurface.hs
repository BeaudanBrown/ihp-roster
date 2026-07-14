{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.Timesheets.FrontendSurface
    ( TimesheetWeekScopeValue (..)
    , TimesheetsMountStateValue (..)
    , timesheetsCandidateMountedFragments
    , timesheetsSurfaceScope
    , timesheetsDaySurfaceImpl
    , timesheetsSurfaceImpl
    , timesheetsSurfaceMountConfig
    , timesheetsSurfaceScopeKey
    , timesheetsSurfaceFragmentKeys
    ) where

import Application.Helper.FrontendContract.Surface.Runtime
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.LiveUpdate.Runtime
import qualified Data.UUID as UUID
import qualified IHP.Prelude as Prelude
import Web.Controller.Prelude
import Web.Timesheets.Paths (timesheetDayColumnsFragmentUrl,
                             timesheetDaySectionFragmentUrl,
                             timesheetToolbarFragmentUrl)

-- | Logical live invalidation scope. Filter/query state intentionally lives in
-- 'TimesheetsMountStateValue' instead of the scope so a future mount-state store
-- can replace query params without changing the surface identity.
data TimesheetWeekScopeValue = TimesheetWeekScopeValue
    { timesheetWeekVenueId    :: !UUID.UUID
    , timesheetWeekWeekOffset :: !Int
    }
    deriving (Eq, Show)

data TimesheetsMountStateValue = TimesheetsMountStateValue
    { timesheetsMountShowApproved    :: !Bool
    , timesheetsMountShowAllStaff    :: !Bool
    , timesheetsMountShowSuggestions :: !Bool
    , timesheetsMountStaffFilterId   :: !(Maybe UUID.UUID)
    }
    deriving (Eq, Show)

timesheetsSurfaceImpl :: TimesheetWeekScopeValue -> TimesheetsMountStateValue -> SurfaceImpl Surface.TimesheetsSurface
timesheetsSurfaceImpl scope mountState =
    timesheetsSurfaceImplWithFragments scope mountState (timesheetsCandidateMountedFragments scope mountState)

timesheetsDaySurfaceImpl :: TimesheetWeekScopeValue -> TimesheetsMountStateValue -> Int -> SurfaceImpl Surface.TimesheetsSurface
timesheetsDaySurfaceImpl scope mountState dayOffset =
    timesheetsSurfaceImplWithFragments scope mountState [timesheetDaySectionMountedFragment mountState scope.timesheetWeekWeekOffset dayOffset]

timesheetsSurfaceImplWithFragments :: TimesheetWeekScopeValue -> TimesheetsMountStateValue -> [FrontendSurfaceMountedFragment] -> SurfaceImpl Surface.TimesheetsSurface
timesheetsSurfaceImplWithFragments scope mountState fragments =
    mkSurfaceImplFromValues @Surface.TimesheetsSurface @Surface.TimesheetWeek
        "primary"
        (timesheetWeekScopeFields scope)
        (timesheetsMountStateFields mountState)
        fragments

timesheetsSurfaceMountConfig :: TimesheetWeekScopeValue -> TimesheetsMountStateValue -> FrontendSurfaceMountConfig
timesheetsSurfaceMountConfig scope mountState =
    (timesheetsSurfaceImpl scope mountState).surfaceImplMountConfig

timesheetsSurfaceScopeKey :: TimesheetWeekScopeValue -> Text
timesheetsSurfaceScopeKey scope =
    frontendSurfaceScopeKeyFor @Surface.TimesheetsSurface @Surface.TimesheetWeek (timesheetWeekScopeFields scope)
        |> either (error . ("Typed Timesheets scope invariant failed: " <>)) Prelude.id

timesheetsSurfaceScope :: TimesheetWeekScopeValue -> SurfaceScope
timesheetsSurfaceScope scope =
    timesheetWeekLiveScope scope.timesheetWeekVenueId scope.timesheetWeekWeekOffset

timesheetsSurfaceFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
timesheetsSurfaceFragmentKeys =
    frontendSurfaceMountedFragmentsToKeysFor @Surface.TimesheetsSurface

timesheetsCandidateMountedFragments :: TimesheetWeekScopeValue -> TimesheetsMountStateValue -> [FrontendSurfaceMountedFragment]
timesheetsCandidateMountedFragments scope mountState =
    [ timesheetToolbarMountedFragment mountState scope.timesheetWeekWeekOffset
    , timesheetDayColumnsMountedFragment mountState scope.timesheetWeekWeekOffset
    ] <> map (timesheetDaySectionMountedFragment mountState scope.timesheetWeekWeekOffset) [0 .. 6]

timesheetWeekScopeFields :: TimesheetWeekScopeValue -> SurfaceFields (SurfaceScopeFieldSpecs Surface.TimesheetsSurface Surface.TimesheetWeek)
timesheetWeekScopeFields scope =
    surfaceField @Surface.VenueId scope.timesheetWeekVenueId
        :& surfaceField @Surface.WeekOffset scope.timesheetWeekWeekOffset
        :& NoSurfaceFields

timesheetsMountStateFields :: TimesheetsMountStateValue -> SurfaceFields (SurfaceMountStateFieldSpecs Surface.TimesheetsSurface)
timesheetsMountStateFields mountState =
    surfaceField @Surface.ShowApproved mountState.timesheetsMountShowApproved
        :& surfaceField @Surface.ShowAllStaff mountState.timesheetsMountShowAllStaff
        :& surfaceField @Surface.ShowSuggestions mountState.timesheetsMountShowSuggestions
        :& surfaceField @Surface.StaffFilterId mountState.timesheetsMountStaffFilterId
        :& NoSurfaceFields

timesheetToolbarMountedFragment :: TimesheetsMountStateValue -> Int -> FrontendSurfaceMountedFragment
timesheetToolbarMountedFragment mountState weekOffset =
    frontendSurfaceMountedFragmentFor @Surface.TimesheetsSurface @Surface.TimesheetToolbar
        NoSurfaceFields
        NoSurfaceFields
        (timesheetToolbarFragmentUrl weekOffset mountState.timesheetsMountShowApproved mountState.timesheetsMountShowAllStaff mountState.timesheetsMountShowSuggestions mountState.timesheetsMountStaffFilterId)
        FrontendSurfaceReplace

timesheetDayColumnsMountedFragment :: TimesheetsMountStateValue -> Int -> FrontendSurfaceMountedFragment
timesheetDayColumnsMountedFragment mountState weekOffset =
    frontendSurfaceMountedFragmentFor @Surface.TimesheetsSurface @Surface.TimesheetDayColumns
        NoSurfaceFields
        NoSurfaceFields
        (timesheetDayColumnsFragmentUrl weekOffset mountState.timesheetsMountShowApproved mountState.timesheetsMountShowAllStaff mountState.timesheetsMountShowSuggestions mountState.timesheetsMountStaffFilterId)
        FrontendSurfaceReplace

timesheetDaySectionMountedFragment :: TimesheetsMountStateValue -> Int -> Int -> FrontendSurfaceMountedFragment
timesheetDaySectionMountedFragment mountState weekOffset dayOffset =
    frontendSurfaceMountedFragmentFor @Surface.TimesheetsSurface @Surface.TimesheetDaySection
        (surfaceField @Surface.DayOffset dayOffset :& NoSurfaceFields)
        (surfaceField @Surface.DayOffset dayOffset :& NoSurfaceFields)
        (timesheetDaySectionFragmentUrl weekOffset dayOffset mountState.timesheetsMountShowApproved mountState.timesheetsMountShowAllStaff mountState.timesheetsMountShowSuggestions mountState.timesheetsMountStaffFilterId)
        FrontendSurfaceReplace
