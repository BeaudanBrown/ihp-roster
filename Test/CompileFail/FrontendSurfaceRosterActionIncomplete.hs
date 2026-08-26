{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceRosterActionIncomplete where

import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

incomplete :: ActionFields RosterAction.NavigateRosterWeekActionOperation
incomplete =
    actionFields @RosterAction.NavigateRosterWeekActionOperation
        (surfaceField @Roster.AnchorDate (error "fixture date"))
        noSurfaceFields
