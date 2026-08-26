{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceRosterActionWrongFieldPresence where

import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Values
import Data.UUID (nil)
import IHP.Prelude

wrongPresence :: ActionFields RosterAction.NavigateRosterWeekActionOperation
wrongPresence =
    actionFields @RosterAction.NavigateRosterWeekActionOperation
        (surfaceOptionalField @Roster.AnchorDate Nothing)
        ( surfaceField @Roster.RosterGroupId nil
            &: noSurfaceFields
        )
