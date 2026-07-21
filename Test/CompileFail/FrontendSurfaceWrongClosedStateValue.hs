{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceWrongClosedStateValue where

import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

badFullscreenStateValue :: Text
badFullscreenStateValue =
    surfaceBrowserClosedStateLiteral
        @Roster.RosterSurface
        @Roster.FullscreenState
        @Roster.Active
