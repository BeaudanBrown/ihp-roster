{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceIncompleteAction where

import Application.Helper.FrontendContract.Surface.Runtime (frontendSurfaceAction)
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

-- NavigateTimesheetWeek owns a complete five-field state bundle. Omitting even
-- its final optional field must fail before rendering.
incompleteAction =
    frontendSurfaceAction @Timesheets.TimesheetsSurface @Timesheets.NavigateTimesheetWeek
        ( surfaceField @Timesheets.WeekOffset 0
            :& surfaceField @Timesheets.ShowApproved False
            :& surfaceField @Timesheets.ShowAllStaff True
            :& surfaceField @Timesheets.ShowSuggestions True
            :& NoSurfaceFields
        )
