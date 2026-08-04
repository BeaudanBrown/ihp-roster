{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceIncompleteAction where

import Application.Helper.FrontendContract.Surface.Request.Runtime (frontendSurfaceAction)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

-- NavigateTimesheetWeek owns a complete week/staff-filter state bundle.
-- Omitting even its final optional field must fail before rendering.
incompleteAction =
    frontendSurfaceAction @Timesheets.TimesheetsSurface @Timesheets.NavigateTimesheetWeek
        ( surfaceActionFields
            (surfaceField @Timesheets.WeekOffset 0)
            noSurfaceFields
        )
