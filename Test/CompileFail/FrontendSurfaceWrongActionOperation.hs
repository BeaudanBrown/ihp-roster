module Test.CompileFail.FrontendSurfaceWrongActionOperation where

import Application.Helper.FrontendContract.Surface.Request.Runtime (FrontendSurfaceAction)
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Action as TimesheetsAction
import IHP.Prelude

wrongActionOperation :: FrontendSurfaceAction
wrongActionOperation =
    TimesheetsAction.approveTimesheetEntryAction
        ( TimesheetsAction.navigateTimesheetWeekActionFields
            0
            False
            True
            True
            Nothing
        )
