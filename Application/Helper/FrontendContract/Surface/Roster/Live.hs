{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.Roster.Live
    ( activeRosterWeekScopes
    , activeRosterWeekScopesWithBus
    , matchRosterWeekLiveScope
    , rosterContentLiveFragment
    , rosterDayColumnsLiveFragment
    , rosterDayRailLiveFragment
    , rosterDaySectionLiveFragment
    , rosterDayTimelineContentLiveFragment
    , rosterDayTimelineLiveScope
    , rosterGridFrameLiveFragment
    , rosterGridToolbarLiveFragment
    , rosterRowLiveFragment
    , rosterSlotsGridLiveFragment
    , rosterStaffPanelLiveFragment
    , rosterStaffSelfServiceLeaveFormLiveFragment
    , rosterWageRailLiveFragment
    , rosterWeekLiveScope
    ) where

import Application.Helper.FrontendContract.Surface.Live
import qualified Application.Helper.FrontendContract.Surface.Roster as Surface
import Application.Helper.FrontendContract.Surface.Values
import Application.Helper.LiveUpdate.Runtime (LiveBus,
                                              activeSurfaceScopeMatches,
                                              activeSurfaceScopeMatchesWithBus)
import qualified Data.UUID as UUID
import IHP.Prelude

rosterWeekLiveScope :: UUID.UUID -> UUID.UUID -> Int -> SurfaceScope
rosterWeekLiveScope venueId rosterGroupId weekOffset =
    frontendSurfaceScope @Surface.RosterSurface @Surface.RosterWeek
        ( surfaceField @Surface.VenueId venueId
            :& surfaceField @Surface.RosterGroupId rosterGroupId
            :& surfaceField @Surface.WeekOffset weekOffset
            :& NoSurfaceFields
        )

matchRosterWeekLiveScope :: SurfaceScope -> Maybe (UUID.UUID, UUID.UUID, Int)
matchRosterWeekLiveScope scope = do
    (venueId, (rosterGroupId, (weekOffset, ()))) <-
        matchFrontendSurfaceScope @Surface.RosterSurface @Surface.RosterWeek scope
    pure (venueId, rosterGroupId, weekOffset)

activeRosterWeekScopes :: IO [(UUID.UUID, UUID.UUID, Int)]
activeRosterWeekScopes = activeSurfaceScopeMatches matchRosterWeekLiveScope

activeRosterWeekScopesWithBus :: LiveBus -> IO [(UUID.UUID, UUID.UUID, Int)]
activeRosterWeekScopesWithBus bus =
    activeSurfaceScopeMatchesWithBus bus matchRosterWeekLiveScope

rosterDayTimelineLiveScope :: UUID.UUID -> UUID.UUID -> Int -> UUID.UUID -> SurfaceScope
rosterDayTimelineLiveScope venueId rosterGroupId weekOffset rosterDayId =
    frontendSurfaceScope @Surface.RosterDayTimelineSurface @Surface.RosterDayTimeline
        ( surfaceField @Surface.VenueId venueId
            :& surfaceField @Surface.RosterGroupId rosterGroupId
            :& surfaceField @Surface.WeekOffset weekOffset
            :& surfaceField @Surface.RosterDayId rosterDayId
            :& NoSurfaceFields
        )

rosterContentLiveFragment, rosterGridToolbarLiveFragment, rosterGridFrameLiveFragment, rosterDayColumnsLiveFragment, rosterDayRailLiveFragment, rosterWageRailLiveFragment, rosterSlotsGridLiveFragment, rosterStaffPanelLiveFragment, rosterStaffSelfServiceLeaveFormLiveFragment :: SurfaceFragmentKey
rosterContentLiveFragment = frontendSurfaceFragmentKey @Surface.RosterSurface @Surface.RosterContent NoSurfaceFields
rosterGridToolbarLiveFragment = frontendSurfaceFragmentKey @Surface.RosterSurface @Surface.RosterGridToolbar NoSurfaceFields
rosterGridFrameLiveFragment = frontendSurfaceFragmentKey @Surface.RosterSurface @Surface.RosterGridFrame NoSurfaceFields
rosterDayColumnsLiveFragment = frontendSurfaceFragmentKey @Surface.RosterSurface @Surface.RosterDayColumns NoSurfaceFields
rosterDayRailLiveFragment = frontendSurfaceFragmentKey @Surface.RosterSurface @Surface.RosterDayRail NoSurfaceFields
rosterWageRailLiveFragment = frontendSurfaceFragmentKey @Surface.RosterSurface @Surface.RosterWageRail NoSurfaceFields
rosterSlotsGridLiveFragment = frontendSurfaceFragmentKey @Surface.RosterSurface @Surface.RosterSlotsGrid NoSurfaceFields
rosterStaffPanelLiveFragment = frontendSurfaceFragmentKey @Surface.RosterSurface @Surface.RosterStaffPanel NoSurfaceFields
rosterStaffSelfServiceLeaveFormLiveFragment = frontendSurfaceFragmentKey @Surface.RosterSurface @Surface.RosterStaffSelfServiceLeaveFormFragment NoSurfaceFields

rosterDaySectionLiveFragment :: UUID.UUID -> SurfaceFragmentKey
rosterDaySectionLiveFragment rosterDayId =
    frontendSurfaceFragmentKey @Surface.RosterSurface @Surface.RosterDaySection
        (surfaceField @Surface.RosterDayId rosterDayId :& NoSurfaceFields)

rosterRowLiveFragment :: UUID.UUID -> Int -> SurfaceFragmentKey
rosterRowLiveFragment rosterDayId rowIndex =
    frontendSurfaceFragmentKey @Surface.RosterSurface @Surface.RosterRow
        ( surfaceField @Surface.RosterDayId rosterDayId
            :& surfaceField @Surface.RowIndex rowIndex
            :& NoSurfaceFields
        )

rosterDayTimelineContentLiveFragment :: UUID.UUID -> SurfaceFragmentKey
rosterDayTimelineContentLiveFragment rosterDayId =
    frontendSurfaceFragmentKey @Surface.RosterDayTimelineSurface @Surface.RosterDayTimelineContent
        (surfaceField @Surface.RosterDayId rosterDayId :& NoSurfaceFields)
