{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceExtraResourceField where

import Application.Helper.FrontendContract.Surface.Resource
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

-- TimesheetWeek declares only venueId and weekOffset. A trailing dayOffset must
-- fail with an explicit extra-field diagnostic rather than a list mismatch.
extraResourceField =
    frontendSurfaceResource @Timesheets.TimesheetsSurface @Timesheets.TimesheetWeek
        ( surfaceField @Timesheets.VenueId (error "fixture UUID")
            :& surfaceField @Timesheets.WeekOffset 0
            :& surfaceField @Timesheets.DayOffset 1
            :& NoSurfaceFields
        )
