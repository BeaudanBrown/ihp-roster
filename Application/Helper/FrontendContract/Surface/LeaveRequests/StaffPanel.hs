{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.LeaveRequests.StaffPanel
    ( LeaveStaffPanelSortKey (..)
    , LeaveSidePanelTab (..)
    , leaveStaffPanelSortControlAttrs
    , leaveStaffPanelSortRootAttrs
    , leaveStaffPanelSortRowAttrs
    , leaveSidePanelTabAttrs
    ) where

import Application.Helper.FrontendContract.Surface.CompleteSetSort
import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as LeaveRequests
import Application.Helper.FrontendContract.Surface.TabSet
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

data LeaveStaffPanelSortKey
    = LeaveStaffSortByName
    | LeaveStaffSortByRole
    | LeaveStaffSortByCount
    deriving (Eq, Show)

data LeaveSidePanelTab
    = LeaveStaffTab
    | LeaveSettingsTab
    deriving (Eq, Show)

leaveStaffPanelSortRootAttrs :: [(Text, Text)]
leaveStaffPanelSortRootAttrs =
    surfaceCompleteSetSortRootAttrs @LeaveRequests.LeaveRequestsSurface @LeaveRequests.LeaveStaffPanelSort

leaveStaffPanelSortControlAttrs :: LeaveStaffPanelSortKey -> [(Text, Text)]
leaveStaffPanelSortControlAttrs = \case
    LeaveStaffSortByName ->
        surfaceCompleteSetSortControlAttrs @LeaveRequests.LeaveRequestsSurface @LeaveRequests.LeaveStaffPanelSort @LeaveRequests.NameSortKey
    LeaveStaffSortByRole ->
        surfaceCompleteSetSortControlAttrs @LeaveRequests.LeaveRequestsSurface @LeaveRequests.LeaveStaffPanelSort @LeaveRequests.RoleSortKey
    LeaveStaffSortByCount ->
        surfaceCompleteSetSortControlAttrs @LeaveRequests.LeaveRequestsSurface @LeaveRequests.LeaveStaffPanelSort @LeaveRequests.CountSortKey

leaveStaffPanelSortRowAttrs :: Text -> Text -> Text -> Int -> Int -> [(Text, Text)]
leaveStaffPanelSortRowAttrs staffRowKey staffName staffRole periodCount pendingCount =
    surfaceCompleteSetSortRowAttrs
        @LeaveRequests.LeaveRequestsSurface
        @LeaveRequests.LeaveStaffPanelSort
        ( surfaceField @LeaveRequests.StaffRowKey staffRowKey
            &: surfaceField @LeaveRequests.StaffName staffName
            &: surfaceField @LeaveRequests.StaffRole staffRole
            &: surfaceField @LeaveRequests.PeriodCount periodCount
            &: surfaceField @LeaveRequests.PendingCount pendingCount
            &: noSurfaceFields
        )

leaveSidePanelTabAttrs :: LeaveSidePanelTab -> [(Text, Text)]
leaveSidePanelTabAttrs = \case
    LeaveStaffTab ->
        surfaceTabSetAttrs @LeaveRequests.LeaveRequestsSurface @LeaveRequests.LeaveSidePanelTabs @LeaveRequests.StaffTabKey
    LeaveSettingsTab ->
        surfaceTabSetAttrs @LeaveRequests.LeaveRequestsSurface @LeaveRequests.LeaveSidePanelTabs @LeaveRequests.SettingsTabKey
