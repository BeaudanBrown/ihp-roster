{-# LANGUAGE TypeApplications #-}

-- | Roster adapter for the reusable generated SidePanel presentation capability.
module Application.Helper.FrontendContract.Surface.Roster.SidePanel
    ( rosterSidePanelRenderAttrs
    ) where

import qualified Application.Helper.FrontendContract.Surface.Roster as Roster
import Application.Helper.View.SidePanel

rosterSidePanelRenderAttrs :: SidePanelRenderAttrs
rosterSidePanelRenderAttrs = sidePanelRenderAttrs @Roster.RosterSurface @Roster.RosterSidePanel
