{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceIncompleteResource where

import Application.Helper.FrontendContract.Surface.Resource
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

-- TimesheetDay declares venueId, weekOffset, and dayOffset. Omitting dayOffset
-- must fail rather than producing a partial dependency resource.
incompleteResource =
    frontendSurfaceResource @Timesheets.TimesheetsSurface @Timesheets.TimesheetDay
        ( surfaceField @Timesheets.VenueId (error "fixture UUID")
            :& surfaceField @Timesheets.WeekOffset 0
            :& NoSurfaceFields
        )
