{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongFragmentMarker where

import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values

-- A fragment marker is owned by exactly one Surface. Asking Timesheets for a
-- Roster fragment must fail before any protocol-name lookup is possible.
wrongFragmentMarker = surfaceFragmentValue @Timesheets.TimesheetsSurface @Roster.RosterContent
