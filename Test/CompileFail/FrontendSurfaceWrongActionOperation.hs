module Test.CompileFail.FrontendSurfaceWrongActionOperation where

import Application.Helper.FrontendContract.Surface.Request.Runtime (FrontendSurfaceAction)
import qualified Application.Helper.FrontendContract.Surface.Timesheets.Action as TimesheetsAction
import IHP.Prelude

wrongActionOperation :: FrontendSurfaceAction
wrongActionOperation =
    TimesheetsAction.approveTimesheetEntryAction
        ( TimesheetsAction.navigateTimesheetWeekActionFields
            (fromGregorian 2025 1 6)
            Nothing
            Nothing
            Nothing
        )
