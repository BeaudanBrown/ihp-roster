{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.Timesheets.Resource
    ( timesheetDayResource
    , timesheetWeekBoundaryConfigResource
    , timesheetWeekResource
    ) where

import Application.Helper.FrontendContract.Surface.Resource
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Surface
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.UUID as UUID
import IHP.Prelude

timesheetWeekResource :: UUID.UUID -> Int -> SurfaceResourceValue
timesheetWeekResource venueId weekOffset =
    frontendSurfaceResource @Surface.TimesheetsSurface @Surface.TimesheetWeek
        ( surfaceField @Surface.VenueId venueId
            :& surfaceField @Surface.WeekOffset weekOffset
            :& NoSurfaceFields
        )

timesheetDayResource :: UUID.UUID -> Int -> Int -> SurfaceResourceValue
timesheetDayResource venueId weekOffset dayOffset =
    frontendSurfaceResource @Surface.TimesheetsSurface @Surface.TimesheetDay
        ( surfaceField @Surface.VenueId venueId
            :& surfaceField @Surface.WeekOffset weekOffset
            :& surfaceField @Surface.DayOffset dayOffset
            :& NoSurfaceFields
        )

timesheetWeekBoundaryConfigResource :: UUID.UUID -> SurfaceResourceValue
timesheetWeekBoundaryConfigResource venueId =
    frontendSurfaceResource @Surface.TimesheetsSurface @Surface.TimesheetWeekBoundaryConfig
        (surfaceField @Surface.VenueId venueId :& NoSurfaceFields)
