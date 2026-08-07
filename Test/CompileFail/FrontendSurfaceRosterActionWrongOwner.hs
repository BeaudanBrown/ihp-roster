{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceRosterActionWrongOwner where

import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Values (ActionSurface)
import Data.Proxy (Proxy (..))

data OtherSurfaceOwner

wrongOwner :: Proxy OtherSurfaceOwner
wrongOwner = Proxy @(ActionSurface RosterAction.NavigateRosterWeekActionOperation)
