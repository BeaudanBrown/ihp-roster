{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Test.CompileFail.FrontendSurfaceWrongActionField where

import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

-- This fixture intentionally asks a complete Timesheets action bundle for a
-- Roster-only field marker. Field ownership must fail at compile time.
fields :: SurfaceFields (SurfaceActionFieldSpecs Timesheets.TimesheetsSurface Timesheets.NavigateTimesheetWeek)
fields =
    surfaceField @Timesheets.WeekOffset 0
        &: surfaceField @Timesheets.ShowApproved False
        &: surfaceField @Timesheets.ShowAllStaff True
        &: surfaceField @Timesheets.ShowSuggestions True
        &: surfaceOptionalField @Timesheets.StaffFilterId Nothing
        &: noSurfaceFields

wrongActionField = surfaceFieldNameFrom @Roster.RosterGroupId fields
