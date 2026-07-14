{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongLiveScopeMarker where

import Application.Helper.FrontendContract.Surface.Live
import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values

-- A scope marker is owned by exactly one Surface. Asking Timesheets to build a
-- Roster scope must fail before transport identity can be constructed.
wrongLiveScopeMarker =
    frontendSurfaceScope @Timesheets.TimesheetsSurface @Roster.RosterWeek NoSurfaceFields
