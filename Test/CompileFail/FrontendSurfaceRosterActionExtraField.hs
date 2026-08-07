{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceRosterActionExtraField where

import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Values

extraField :: ActionFields RosterAction.AddRosterRowActionOperation
extraField =
    actionFields @RosterAction.AddRosterRowActionOperation
        (surfaceField @Roster.WeekOffset 2)
        noSurfaceFields
