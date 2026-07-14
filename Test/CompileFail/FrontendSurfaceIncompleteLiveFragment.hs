{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceIncompleteLiveFragment where

import Application.Helper.FrontendContract.Surface.Live
import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

-- RosterRow declares both RosterDayId and RowIndex. Omitting RowIndex must fail
-- at compile time rather than producing a partial fragment params object.
incompleteLiveFragment =
    frontendSurfaceFragmentKey @Roster.RosterSurface @Roster.RosterRow
        (surfaceField @Roster.RosterDayId (error "fixture UUID") :& NoSurfaceFields)
