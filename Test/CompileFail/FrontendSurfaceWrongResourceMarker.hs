{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongResourceMarker where

import Application.Helper.FrontendContract.Surface.Resource
import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values

-- A resource marker is owned by the Surface declaration that references it.
-- Timesheets cannot construct Roster's RosterWeek resource marker.
wrongResourceMarker =
    frontendSurfaceResource @Timesheets.TimesheetsSurface @Roster.RosterWeek noSurfaceFields
