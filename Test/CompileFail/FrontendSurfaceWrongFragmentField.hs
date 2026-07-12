{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongFragmentField where

import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import Application.Helper.FrontendContract.Surface.Values

-- RowIndex belongs to RosterRow, not RosterDaySection. Fragment field
-- ownership must be rejected at compile time.
wrongFragmentField = surfaceFragmentFieldName @Roster.RosterSurface @Roster.RosterDaySection @Roster.RowIndex
