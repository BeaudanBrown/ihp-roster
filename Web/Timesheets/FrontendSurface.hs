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
import Application.Helper.Url (appendQueryParams)
import Data.Time.Calendar (Day, addDays)
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
    { timesheetWeekVenueId      :: !UUID.UUID
    , timesheetWeekWeekOffset   :: !Int
    , timesheetWindowStart      :: !Day
    , timesheetWindowEnd        :: !Day
    , timesheetCalendarRevision :: !Int
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
    timesheetsSurfaceImplWithFragments scope mountState
        [ withTimesheetCalendarRevision scope.timesheetCalendarRevision
            (timesheetDaySectionMountedFragment mountState scope.timesheetWindowStart (addDays (toInteger dayOffset) scope.timesheetWindowStart))
        ]

timesheetsSurfaceImplWithFragments :: TimesheetWeekScopeValue -> TimesheetsMountStateValue -> [FrontendSurfaceMountedFragment] -> SurfaceImpl Surface.TimesheetsSurface
timesheetsSurfaceImplWithFragments scope mountState fragments =
    mkSurfaceImplFromValues @Surface.TimesheetsSurface @Surface.TimesheetWeek
        "primary"
        (timesheetWeekScopeFields scope)
        (timesheetsMountStateFields mountState)
        fragments

timesheetsSurfaceScope :: TimesheetWeekScopeValue -> SurfaceScope
timesheetsSurfaceScope scope =
    SurfaceLive.timesheetWeekLiveScope
        scope.timesheetWeekVenueId
        scope.timesheetWindowStart
        scope.timesheetWindowEnd
        scope.timesheetCalendarRevision

timesheetsSurfaceFragmentKeys :: [FrontendSurfaceMountedFragment] -> [SurfaceFragmentKey]
timesheetsSurfaceFragmentKeys = map (.mountedFragmentKey)

timesheetStaffCardsLinkedHighlight :: SurfaceIR.LinkedHighlightIR
timesheetStaffCardsLinkedHighlight =
    surfaceLinkedHighlightValue @Surface.TimesheetsSurface @Surface.TimesheetStaffCardsHighlight

timesheetsCandidateMountedFragments :: TimesheetWeekScopeValue -> TimesheetsMountStateValue -> [FrontendSurfaceMountedFragment]
timesheetsCandidateMountedFragments scope mountState =
    map (withTimesheetCalendarRevision scope.timesheetCalendarRevision) $
        [ timesheetToolbarMountedFragment mountState scope.timesheetWindowStart
        , timesheetDayColumnsMountedFragment mountState scope.timesheetWindowStart
        , timesheetSidePanelMountedFragment mountState scope.timesheetWindowStart
        ] <> map (\dayOffset -> timesheetDaySectionMountedFragment mountState scope.timesheetWindowStart (addDays dayOffset scope.timesheetWindowStart)) [0 .. 6]

withTimesheetCalendarRevision :: Int -> FrontendSurfaceMountedFragment -> FrontendSurfaceMountedFragment
withTimesheetCalendarRevision calendarRevision fragment =
    fragment
        { mountedFragmentUrl = appendQueryParams fragment.mountedFragmentUrl [("rosterCalendarRevision", tshow calendarRevision)]
        }

timesheetWeekScopeFields :: TimesheetWeekScopeValue -> SurfaceFields (SurfaceScopeFieldSpecs Surface.TimesheetsSurface Surface.TimesheetWeek)
timesheetWeekScopeFields scope =
    surfaceField @Surface.VenueId scope.timesheetWeekVenueId
        &: surfaceField @Surface.WindowStartDate scope.timesheetWindowStart
        &: surfaceField @Surface.WindowEndDate scope.timesheetWindowEnd
        &: surfaceField @Surface.RosterCalendarRevision scope.timesheetCalendarRevision
        &: noSurfaceFields

timesheetsMountStateFields :: TimesheetsMountStateValue -> SurfaceFields (SurfaceMountStateFieldSpecs Surface.TimesheetsSurface)
timesheetsMountStateFields mountState =
    surfaceField @Surface.StaffFilterId mountState.timesheetsMountStaffFilterId
        &: noSurfaceFields

timesheetToolbarMountedFragment :: TimesheetsMountStateValue -> Day -> FrontendSurfaceMountedFragment
timesheetToolbarMountedFragment mountState scopeStart =
    frontendSurfaceMountedFragmentFor @Surface.TimesheetsSurface @Surface.TimesheetToolbar
        noSurfaceFields
        noSurfaceFields
        (timesheetToolbarFragmentUrl scopeStart mountState.timesheetsMountStaffFilterId)
        FrontendSurfaceReplace

timesheetDayColumnsMountedFragment :: TimesheetsMountStateValue -> Day -> FrontendSurfaceMountedFragment
timesheetDayColumnsMountedFragment mountState scopeStart =
    frontendSurfaceMountedFragmentFor @Surface.TimesheetsSurface @Surface.TimesheetDayColumns
        noSurfaceFields
        noSurfaceFields
        (timesheetDayColumnsFragmentUrl scopeStart mountState.timesheetsMountStaffFilterId)
        FrontendSurfaceReplace

timesheetSidePanelMountedFragment :: TimesheetsMountStateValue -> Day -> FrontendSurfaceMountedFragment
timesheetSidePanelMountedFragment mountState scopeStart =
    frontendSurfaceMountedFragmentFor @Surface.TimesheetsSurface @Surface.TimesheetSidePanelContent
        noSurfaceFields
        noSurfaceFields
        (timesheetSidePanelFragmentUrl scopeStart mountState.timesheetsMountStaffFilterId)
        FrontendSurfaceReplace

timesheetDaySectionMountedFragment :: TimesheetsMountStateValue -> Day -> Day -> FrontendSurfaceMountedFragment
timesheetDaySectionMountedFragment mountState windowStart operationalDate =
    frontendSurfaceMountedFragmentFor @Surface.TimesheetsSurface @Surface.TimesheetDaySection
        (surfaceField @Surface.OperationalDate operationalDate &: noSurfaceFields)
        (surfaceField @Surface.OperationalDate operationalDate &: noSurfaceFields)
        (timesheetDaySectionFragmentUrl windowStart operationalDate mountState.timesheetsMountStaffFilterId)
        FrontendSurfaceReplace
