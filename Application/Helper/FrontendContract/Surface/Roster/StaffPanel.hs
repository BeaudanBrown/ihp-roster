{-# LANGUAGE TypeApplications #-}

-- | Curated Haskell rendering interface for the roster staff-panel browser
-- contract. Domain projection remains in the roster view; this module fixes
-- every cross-language role, key, field shape, comparator choice, and default
-- to the checked Roster Surface declaration.
module Application.Helper.FrontendContract.Surface.Roster.StaffPanel
    ( RosterStaffPanelSortKey (..)
    , RosterStaffPanelTab (..)
    , rosterStaffPanelSortControlAttrs
    , rosterStaffPanelSortRootAttrs
    , rosterStaffPanelSortRowAttrs
    , rosterStaffPanelTabAttrs
    ) where

import Application.Helper.FrontendContract.Surface.CompleteSetSort
import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import Application.Helper.FrontendContract.Surface.TabSet
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

data RosterStaffPanelSortKey
    = RosterStaffSortByName
    | RosterStaffSortByRole
    | RosterStaffSortByShifts
    deriving (Eq, Show)

data RosterStaffPanelTab
    = RosterStaffTab
    | RosterSettingsTab
    deriving (Eq, Show)

rosterStaffPanelSortRootAttrs :: [(Text, Text)]
rosterStaffPanelSortRootAttrs =
    surfaceCompleteSetSortRootAttrs @Roster.RosterSurface @Roster.RosterStaffPanelSort

rosterStaffPanelSortControlAttrs :: RosterStaffPanelSortKey -> [(Text, Text)]
rosterStaffPanelSortControlAttrs = \case
    RosterStaffSortByName ->
        surfaceCompleteSetSortControlAttrs @Roster.RosterSurface @Roster.RosterStaffPanelSort @Roster.NameSortKey
    RosterStaffSortByRole ->
        surfaceCompleteSetSortControlAttrs @Roster.RosterSurface @Roster.RosterStaffPanelSort @Roster.RoleSortKey
    RosterStaffSortByShifts ->
        surfaceCompleteSetSortControlAttrs @Roster.RosterSurface @Roster.RosterStaffPanelSort @Roster.ShiftsSortKey

rosterStaffPanelSortRowAttrs :: Text -> Text -> Text -> Int -> Int -> [(Text, Text)]
rosterStaffPanelSortRowAttrs staffRowKey staffName staffRole assignedShifts idealShifts =
    surfaceCompleteSetSortRowAttrs
        @Roster.RosterSurface
        @Roster.RosterStaffPanelSort
        ( surfaceField @Roster.StaffRowKey staffRowKey
            &: surfaceField @Roster.StaffName staffName
            &: surfaceField @Roster.StaffRole staffRole
            &: surfaceField @Roster.AssignedShifts assignedShifts
            &: surfaceField @Roster.IdealShifts idealShifts
            &: noSurfaceFields
        )

rosterStaffPanelTabAttrs :: RosterStaffPanelTab -> [(Text, Text)]
rosterStaffPanelTabAttrs = \case
    RosterStaffTab ->
        surfaceTabSetAttrs @Roster.RosterSurface @Roster.RosterStaffPanelTabs @Roster.StaffTabKey
    RosterSettingsTab ->
        surfaceTabSetAttrs @Roster.RosterSurface @Roster.RosterStaffPanelTabs @Roster.SettingsTabKey
