module Test.CompileFail.FrontendSurfaceRosterActionWrongOperation where

import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Values (ActionFields)
import Data.UUID (nil)

wrongOperation :: ActionFields RosterAction.ToggleRosterWarningsActionOperation
wrongOperation = RosterAction.navigateRosterWeekActionFields 2 nil
