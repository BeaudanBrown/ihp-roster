{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongActionWireType where

import Application.Helper.FrontendContract.Surface.Request.Runtime (frontendSurfaceAction)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

-- WeekOffset is declared WireInt. A Text value must fail at construction.
wrongActionWireType =
    frontendSurfaceAction @Timesheets.TimesheetsSurface @Timesheets.NavigateTimesheetWeek
        ( surfaceActionFields
            (surfaceField @Timesheets.WeekOffset ("two" :: Text))
            ( surfaceOptionalField @Timesheets.StaffFilterId Nothing
                &: noSurfaceFields
            )
        )
