{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongResourceWireType where

import Application.Helper.FrontendContract.Surface.Resource
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

-- venueId is declared WireUUID. Supplying Text must fail at the marker-indexed
-- construction boundary.
wrongResourceWireType =
    frontendSurfaceResource @Timesheets.TimesheetsSurface @Timesheets.TimesheetWeek
        ( surfaceField @Timesheets.VenueId ("not-a-uuid" :: Text)
            &: surfaceField @Timesheets.WindowStartDate (error "fixture date")
            &: surfaceField @Timesheets.WindowEndDate (error "fixture date")
            &: noSurfaceFields
        )
