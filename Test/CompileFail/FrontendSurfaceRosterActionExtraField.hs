{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceRosterActionExtraField where

import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

extraField :: ActionFields RosterAction.AddRosterRowActionOperation
extraField =
    actionFields @RosterAction.AddRosterRowActionOperation
        (surfaceField @Roster.RosterCalendarRevision 1)
        (surfaceField @Roster.AnchorDate (error "extra date") &: noSurfaceFields)
