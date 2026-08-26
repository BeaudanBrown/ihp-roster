{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongResourceFieldOrder where

import Application.Helper.FrontendContract.Surface.Resource
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

-- TimesheetDay declares venueId before operationalDate. Reversing them
-- isolates declaration ordering from Haskell value typing.
wrongResourceFieldOrder =
    frontendSurfaceResource @Timesheets.TimesheetsSurface @Timesheets.TimesheetDay
        ( surfaceField @Timesheets.OperationalDate (error "fixture date")
            &: surfaceField @Timesheets.VenueId (error "fixture UUID")
            &: noSurfaceFields
        )
