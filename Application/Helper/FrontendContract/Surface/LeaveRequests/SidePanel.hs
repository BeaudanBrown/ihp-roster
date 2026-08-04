{-# LANGUAGE TypeApplications #-}

module Application.Helper.FrontendContract.Surface.LeaveRequests.SidePanel
    ( leaveSidePanelRenderAttrs
    ) where

import qualified Application.Helper.FrontendContract.Surface.LeaveRequests as LeaveRequests
import Application.Helper.View.SidePanel

leaveSidePanelRenderAttrs :: SidePanelRenderAttrs
leaveSidePanelRenderAttrs = sidePanelRenderAttrs @LeaveRequests.LeaveRequestsSurface @LeaveRequests.LeaveSidePanel
