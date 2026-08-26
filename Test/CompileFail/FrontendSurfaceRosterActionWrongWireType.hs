{-# LANGUAGE OverloadedStrings #-}
{-# LANGUAGE TypeApplications  #-}

module Test.CompileFail.FrontendSurfaceRosterActionWrongWireType where

import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Values
import Data.UUID (nil)
import IHP.Prelude

wrongWire :: ActionFields RosterAction.NavigateRosterWeekActionOperation
wrongWire =
    actionFields @RosterAction.NavigateRosterWeekActionOperation
        (surfaceField @Roster.AnchorDate ("not-a-date" :: Text))
        ( surfaceField @Roster.RosterGroupId nil
            &: noSurfaceFields
        )
