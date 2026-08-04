{-# LANGUAGE TypeApplications #-}

-- | Timesheets adapter for the reusable generated SidePanel capability.
module Application.Helper.FrontendContract.Surface.Timesheets.SidePanel
    ( timesheetSidePanelRenderAttrs
    ) where

import qualified Application.Helper.FrontendContract.Surface.Timesheets as Timesheets
import Application.Helper.View.SidePanel

timesheetSidePanelRenderAttrs :: SidePanelRenderAttrs
timesheetSidePanelRenderAttrs = sidePanelRenderAttrs @Timesheets.TimesheetsSurface @Timesheets.TimesheetSidePanel
