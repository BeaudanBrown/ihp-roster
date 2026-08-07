module Test.CompileFail.FrontendSurfaceRosterActionRawRebinding where

import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Values (ActionFields)

rebindRaw ::
    ActionFields RosterAction.NavigateRosterWeekActionOperation ->
    ActionFields RosterAction.ToggleRosterWarningsActionOperation
rebindRaw (ActionFields rawFields) = ActionFields rawFields
