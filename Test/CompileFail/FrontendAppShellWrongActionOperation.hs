{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendAppShellWrongActionOperation where

import qualified Application.Helper.FrontendContract.AppShell as AppShell
import Application.Helper.FrontendContract.AppShell.Request
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.UUID as UUID
import IHP.Prelude

periodConsumer :: AppShellActionFields AppShell.SelectXeroTimesheetPreparationPeriodOverlay -> ()
periodConsumer _ = ()

staffDecisionFields :: AppShellActionFields AppShell.ApplyXeroTimesheetPreparationStaffDecisionOverlay
staffDecisionFields =
    appShellActionFields @AppShell.ApplyXeroTimesheetPreparationStaffDecisionOverlay
        (surfaceField @AppShell.StaffIdField staffUuid)
        ( surfaceField @AppShell.XeroEmployeeSelectionField "employee-1"
            &: noSurfaceFields
        )

staffUuid :: UUID.UUID
staffUuid = fromMaybe (error "invalid UUID fixture") (UUID.fromText "11111111-1111-1111-1111-111111111111")

-- Structurally similar payloads retain their nominal operation owner.
wrongOperation = periodConsumer staffDecisionFields
