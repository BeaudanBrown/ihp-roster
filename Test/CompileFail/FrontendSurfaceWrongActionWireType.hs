{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongActionWireType where

import Application.Helper.FrontendContract.Surface.Runtime (frontendSurfaceAction)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

-- WeekOffset is declared WireInt. A Text value must fail at construction.
wrongActionWireType =
    frontendSurfaceAction @Timesheets.TimesheetsSurface @Timesheets.NavigateTimesheetWeek
        ( surfaceField @Timesheets.WeekOffset ("two" :: Text)
            :& surfaceField @Timesheets.ShowApproved False
            :& surfaceField @Timesheets.ShowAllStaff True
            :& surfaceField @Timesheets.ShowSuggestions True
            :& surfaceOptionalField @Timesheets.StaffFilterId Nothing
            :& NoSurfaceFields
        )
