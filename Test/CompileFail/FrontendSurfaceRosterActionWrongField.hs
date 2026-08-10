{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceRosterActionWrongField where

import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Values
import Data.Time.Calendar (fromGregorian)
import Data.UUID (nil)

fields :: ActionFields RosterAction.NavigateRosterWeekActionOperation
fields = RosterAction.navigateRosterWeekActionFields (fromGregorian 2026 8 10) nil

wrongField = surfaceFieldNameFrom @Roster.TemplateId fields
