module Test.CompileFail.FrontendSurfaceWrongIntentOperation where

import qualified Application.Helper.FrontendContract.Surface.Roster.Intent as RosterIntent
import Application.Helper.FrontendContract.Surface.Runtime (FrontendSurfaceHtmxRequest,
                                                            FrontendSurfaceIntentForm)
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
