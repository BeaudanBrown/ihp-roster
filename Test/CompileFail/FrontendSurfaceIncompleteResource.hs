{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceIncompleteResource where

import Application.Helper.FrontendContract.Surface.Resource
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

-- TimesheetWeek declares venueId and window bounds. Omitting the end date
-- must fail rather than producing a partial resource.
incompleteResource =
    frontendSurfaceResource @Timesheets.TimesheetsSurface @Timesheets.TimesheetWeek
        ( surfaceField @Timesheets.VenueId (error "fixture UUID")
            &: surfaceField @Timesheets.WindowStartDate (error "fixture date")
            &: noSurfaceFields
        )
