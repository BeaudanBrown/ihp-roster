module Test.CompileFail.FrontendSurfaceWrongIntentOperation where

import Application.Helper.FrontendContract.Surface.Request.Runtime (FrontendSurfaceHtmxRequest,
                                                                    FrontendSurfaceIntentForm)
import qualified Application.Helper.FrontendContract.Surface.Roster.Intent as RosterIntent
import IHP.Prelude

wrongIntentOperation :: FrontendSurfaceHtmxRequest -> FrontendSurfaceIntentForm
wrongIntentOperation =
    RosterIntent.duplicateRosterShiftToDayIntentForm
        ( RosterIntent.moveRosterShiftToSlotIntentFields
            "source"
            "target"
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
            Nothing
        )
