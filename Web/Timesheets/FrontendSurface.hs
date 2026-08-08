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
    , timesheetStaffCardsLinkedHighlight
    , timesheetsSurfaceFragmentKeys
    ) where

import qualified Application.Helper.FrontendContract.Surface.ContractIR as SurfaceIR
import Application.Helper.FrontendContract.Surface.Live (SurfaceFragmentKey,
                                                         SurfaceScope)
import Application.Helper.FrontendContract.Surface.Runtime
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Live as SurfaceLive
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.UUID as UUID
import Web.Controller.Prelude
import Web.Timesheets.Paths (timesheetDayColumnsFragmentUrl,
                             timesheetDaySectionFragmentUrl,
                             timesheetSidePanelFragmentUrl,
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
    { timesheetsMountStaffFilterId :: !(Maybe UUID.UUID) }
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

timesheetsSurfaceScope :: TimesheetWeekScopeValue -> SurfaceScope
timesheetsSurfaceScope scope =
    SurfaceLive.timesheetWeekLiveScope scope.timesheetWeekVenueId scope.timesheetWeekWeekOffset

timesheetsSurfaceFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
timesheetsSurfaceFragmentKeys = map (.mountedFragmentKey)

timesheetStaffCardsLinkedHighlight :: SurfaceIR.LinkedHighlightIR
timesheetStaffCardsLinkedHighlight =
    surfaceLinkedHighlightValue @Surface.TimesheetsSurface @Surface.TimesheetStaffCardsHighlight

timesheetsCandidateMountedFragments :: TimesheetWeekScopeValue -> TimesheetsMountStateValue -> [FrontendSurfaceMountedFragment]
timesheetsCandidateMountedFragments scope mountState =
    [ timesheetToolbarMountedFragment mountState scope.timesheetWeekWeekOffset
    , timesheetDayColumnsMountedFragment mountState scope.timesheetWeekWeekOffset
    , timesheetSidePanelMountedFragment mountState scope.timesheetWeekWeekOffset
    ] <> map (timesheetDaySectionMountedFragment mountState scope.timesheetWeekWeekOffset) [0 .. 6]

timesheetWeekScopeFields :: TimesheetWeekScopeValue -> SurfaceFields (SurfaceScopeFieldSpecs Surface.TimesheetsSurface Surface.TimesheetWeek)
timesheetWeekScopeFields scope =
    surfaceField @Surface.VenueId scope.timesheetWeekVenueId
        &: surfaceField @Surface.WeekOffset scope.timesheetWeekWeekOffset
        &: noSurfaceFields

timesheetsMountStateFields :: TimesheetsMountStateValue -> SurfaceFields (SurfaceMountStateFieldSpecs Surface.TimesheetsSurface)
timesheetsMountStateFields mountState =
    surfaceField @Surface.StaffFilterId mountState.timesheetsMountStaffFilterId
        &: noSurfaceFields

timesheetToolbarMountedFragment :: TimesheetsMountStateValue -> Int -> FrontendSurfaceMountedFragment
timesheetToolbarMountedFragment mountState weekOffset =
    frontendSurfaceMountedFragmentFor @Surface.TimesheetsSurface @Surface.TimesheetToolbar
        noSurfaceFields
        noSurfaceFields
        (timesheetToolbarFragmentUrl weekOffset mountState.timesheetsMountStaffFilterId)
        FrontendSurfaceReplace

timesheetDayColumnsMountedFragment :: TimesheetsMountStateValue -> Int -> FrontendSurfaceMountedFragment
timesheetDayColumnsMountedFragment mountState weekOffset =
    frontendSurfaceMountedFragmentFor @Surface.TimesheetsSurface @Surface.TimesheetDayColumns
        noSurfaceFields
        noSurfaceFields
        (timesheetDayColumnsFragmentUrl weekOffset mountState.timesheetsMountStaffFilterId)
        FrontendSurfaceReplace

timesheetSidePanelMountedFragment :: TimesheetsMountStateValue -> Int -> FrontendSurfaceMountedFragment
timesheetSidePanelMountedFragment mountState weekOffset =
    frontendSurfaceMountedFragmentFor @Surface.TimesheetsSurface @Surface.TimesheetSidePanelContent
        noSurfaceFields
        noSurfaceFields
        (timesheetSidePanelFragmentUrl weekOffset mountState.timesheetsMountStaffFilterId)
        FrontendSurfaceReplace

timesheetDaySectionMountedFragment :: TimesheetsMountStateValue -> Int -> Int -> FrontendSurfaceMountedFragment
timesheetDaySectionMountedFragment mountState weekOffset dayOffset =
    frontendSurfaceMountedFragmentFor @Surface.TimesheetsSurface @Surface.TimesheetDaySection
        (surfaceField @Surface.DayOffset dayOffset &: noSurfaceFields)
        (surfaceField @Surface.DayOffset dayOffset &: noSurfaceFields)
        (timesheetDaySectionFragmentUrl weekOffset dayOffset mountState.timesheetsMountStaffFilterId)
        FrontendSurfaceReplace
