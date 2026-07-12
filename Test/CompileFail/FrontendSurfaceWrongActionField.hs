{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongActionField where

import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values

-- This fixture intentionally asks a Timesheets action for a Roster-only field
-- marker. Field ownership must fail at compile time.
wrongActionField = surfaceActionFieldName @Timesheets.TimesheetsSurface @Timesheets.NavigateTimesheetWeek @Roster.RosterGroupId
