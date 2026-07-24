{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongResourceFieldOrder where

import Application.Helper.FrontendContract.Surface.Resource
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

-- TimesheetDay declares weekOffset before dayOffset. Both fields use WireInt,
-- so this fixture isolates declaration ordering from Haskell value typing.
wrongResourceFieldOrder =
    frontendSurfaceResource @Timesheets.TimesheetsSurface @Timesheets.TimesheetDay
        ( surfaceField @Timesheets.VenueId (error "fixture UUID")
            &: surfaceField @Timesheets.DayOffset 1
            &: surfaceField @Timesheets.WeekOffset 0
            &: noSurfaceFields
        )
