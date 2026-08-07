{-# LANGUAGE TypeApplications #-}

module Test.CompileFail.FrontendSurfaceRosterActionWrongFieldOrder where

import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import qualified Application.Helper.FrontendContract.Surface.Roster.Action as RosterAction
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

wrongOrder :: ActionFields RosterAction.ToggleRosterAssignmentFiltersActionOperation
wrongOrder =
    actionFields @RosterAction.ToggleRosterAssignmentFiltersActionOperation
        (surfaceField @Roster.HideStaffUnavailable True)
        ( surfaceField @Roster.HideStaffUnavailable False
            &: surfaceField @Roster.HideStaffOnApprovedLeave False
            &: surfaceField @Roster.HideStaffAlreadyAssignedToday False
            &: noSurfaceFields
        )
