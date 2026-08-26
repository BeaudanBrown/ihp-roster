{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceExtraResourceField where

import Application.Helper.FrontendContract.Surface.Resource
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

-- TimesheetWeek declares venueId and window bounds. A trailing operationalDate
-- must fail with an explicit extra-field diagnostic rather than a list mismatch.
extraResourceField =
    frontendSurfaceResource @Timesheets.TimesheetsSurface @Timesheets.TimesheetWeek
        ( surfaceField @Timesheets.VenueId (error "fixture UUID")
            &: surfaceField @Timesheets.WindowStartDate (error "fixture date")
            &: surfaceField @Timesheets.WindowEndDate (error "fixture date")
            &: surfaceField @Timesheets.OperationalDate (error "extra date")
            &: noSurfaceFields
        )
