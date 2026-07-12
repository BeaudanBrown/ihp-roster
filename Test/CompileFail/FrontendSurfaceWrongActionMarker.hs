{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongActionMarker where

import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values

-- This fixture intentionally asks the Timesheets Surface for a Roster-owned
-- action marker. Ownership must fail at compile time rather than becoming a
-- runtime protocol-name lookup.
wrongActionMarker = surfaceActionValue @Timesheets.TimesheetsSurface @Roster.NavigateRosterWeek
