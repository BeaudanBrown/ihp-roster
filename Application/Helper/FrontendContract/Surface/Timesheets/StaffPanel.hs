{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.Timesheets.StaffPanel
    ( TimesheetStaffPanelSortKey (..)
    , TimesheetSidePanelTab (..)
    , timesheetStaffPanelSortControlAttrs
    , timesheetStaffPanelSortRootAttrs
    , timesheetStaffPanelSortRowAttrs
    , timesheetSidePanelTabAttrs
    ) where

import Application.Helper.FrontendContract.Surface.CompleteSetSort
import Application.Helper.FrontendContract.Surface.TabSet
import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

data TimesheetStaffPanelSortKey
    = TimesheetStaffSortByName
    | TimesheetStaffSortByRole
    | TimesheetStaffSortByCount
    deriving (Eq, Show)

data TimesheetSidePanelTab
    = TimesheetStaffTab
    | TimesheetSettingsTab
    deriving (Eq, Show)

timesheetStaffPanelSortRootAttrs :: [(Text, Text)]
timesheetStaffPanelSortRootAttrs =
    surfaceCompleteSetSortRootAttrs @Timesheets.TimesheetsSurface @Timesheets.TimesheetStaffPanelSort

timesheetStaffPanelSortControlAttrs :: TimesheetStaffPanelSortKey -> [(Text, Text)]
timesheetStaffPanelSortControlAttrs = \case
    TimesheetStaffSortByName ->
        surfaceCompleteSetSortControlAttrs @Timesheets.TimesheetsSurface @Timesheets.TimesheetStaffPanelSort @Timesheets.NameSortKey
    TimesheetStaffSortByRole ->
        surfaceCompleteSetSortControlAttrs @Timesheets.TimesheetsSurface @Timesheets.TimesheetStaffPanelSort @Timesheets.RoleSortKey
    TimesheetStaffSortByCount ->
        surfaceCompleteSetSortControlAttrs @Timesheets.TimesheetsSurface @Timesheets.TimesheetStaffPanelSort @Timesheets.CountSortKey

timesheetStaffPanelSortRowAttrs :: Text -> Text -> Text -> Int -> Int -> [(Text, Text)]
timesheetStaffPanelSortRowAttrs staffRowKey staffName staffRole entryCount approvedCount =
    surfaceCompleteSetSortRowAttrs
        @Timesheets.TimesheetsSurface
        @Timesheets.TimesheetStaffPanelSort
        ( surfaceField @Timesheets.StaffRowKey staffRowKey
            &: surfaceField @Timesheets.StaffName staffName
            &: surfaceField @Timesheets.StaffRole staffRole
            &: surfaceField @Timesheets.EntryCount entryCount
            &: surfaceField @Timesheets.ApprovedCount approvedCount
            &: noSurfaceFields
        )

timesheetSidePanelTabAttrs :: TimesheetSidePanelTab -> [(Text, Text)]
timesheetSidePanelTabAttrs = \case
    TimesheetStaffTab ->
        surfaceTabSetAttrs @Timesheets.TimesheetsSurface @Timesheets.TimesheetSidePanelTabs @Timesheets.StaffTabKey
    TimesheetSettingsTab ->
        surfaceTabSetAttrs @Timesheets.TimesheetsSurface @Timesheets.TimesheetSidePanelTabs @Timesheets.SettingsTabKey
