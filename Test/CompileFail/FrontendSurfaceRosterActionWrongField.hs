{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceRosterActionWrongField where

import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Values
import Data.UUID (nil)

fields :: ActionFields RosterAction.NavigateRosterWeekActionOperation
fields = RosterAction.navigateRosterWeekActionFields 2 nil

wrongField = surfaceFieldNameFrom @Roster.NotificationRosterWeekId fields
