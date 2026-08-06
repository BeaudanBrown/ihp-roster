module Test.CompileFail.FrontendSurfaceWrongClosedScalarDomain where

import qualified Application.Helper.FrontendContract.Surface.Roster.Intent as RosterIntent
import Generated.Types (StaffEmploymentBasisEnum (Casual))
import IHP.Prelude

wrongClosedScalarDomain =
    RosterIntent.setRosterLayoutModeIntentFields Casual
