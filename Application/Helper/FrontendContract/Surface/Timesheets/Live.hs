{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.Timesheets.Live
    ( matchTimesheetWeekLiveScope
    , timesheetDayColumnsLiveFragment
    , timesheetDaySectionLiveFragment
    , timesheetToolbarLiveFragment
    , timesheetWeekLiveScope
    ) where

import Application.Helper.FrontendContract.Surface.Live
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.UUID as UUID
import IHP.Prelude

timesheetWeekLiveScope :: UUID.UUID -> Int -> SurfaceScope
timesheetWeekLiveScope venueId weekOffset =
    frontendSurfaceScope @Surface.TimesheetsSurface @Surface.TimesheetWeek
        ( surfaceField @Surface.VenueId venueId
            :& surfaceField @Surface.WeekOffset weekOffset
            :& NoSurfaceFields
        )

matchTimesheetWeekLiveScope :: SurfaceScope -> Maybe (UUID.UUID, Int)
matchTimesheetWeekLiveScope scope = do
    (venueId, (weekOffset, ())) <-
        matchFrontendSurfaceScope @Surface.TimesheetsSurface @Surface.TimesheetWeek scope
    pure (venueId, weekOffset)

timesheetToolbarLiveFragment, timesheetDayColumnsLiveFragment :: SurfaceFragmentKey
timesheetToolbarLiveFragment = frontendSurfaceFragmentKey @Surface.TimesheetsSurface @Surface.TimesheetToolbar NoSurfaceFields
timesheetDayColumnsLiveFragment = frontendSurfaceFragmentKey @Surface.TimesheetsSurface @Surface.TimesheetDayColumns NoSurfaceFields

timesheetDaySectionLiveFragment :: Int -> SurfaceFragmentKey
timesheetDaySectionLiveFragment dayOffset =
    frontendSurfaceFragmentKey @Surface.TimesheetsSurface @Surface.TimesheetDaySection
        (surfaceField @Surface.DayOffset dayOffset :& NoSurfaceFields)
