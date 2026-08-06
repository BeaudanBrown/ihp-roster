{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendAppShellWrongActionField where

import qualified Application.Helper.FrontendContract.AppShell as AppShell
import Application.Helper.FrontendContract.AppShell.Request
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

periodFields :: AppShellActionFields AppShell.SelectXeroTimesheetPreparationPeriodOverlay
periodFields =
    appShellActionFields @AppShell.SelectXeroTimesheetPreparationPeriodOverlay
        (surfaceField @AppShell.PeriodKeyField "calendar:period")
        noSurfaceFields

-- A field name can only be obtained from the nominal operation that owns it.
wrongFieldName = surfaceFieldNameFrom @AppShell.AccountCodeField periodFields
