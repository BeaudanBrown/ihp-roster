{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE ConstraintKinds #-}
{-# LANGUAGE FlexibleContexts #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeFamilies #-}

-- | Marker-indexed rendering helpers for the reusable mechanical side-panel
-- capability. Feature views retain ownership of panel content and tabs.
module Application.Helper.FrontendContract.Surface.SidePanel
    ( surfaceSidePanelRootAttrs
    , surfaceSidePanelMainAttrs
    , surfaceSidePanelPanelAttrs
    , surfaceSidePanelToggleAttrs
    , surfaceSidePanelLabelAttrs
    ) where

import Application.Helper.FrontendContract.Surface.Attributes (roleAttrs)
import Application.Helper.FrontendContract.Surface.ContractIR (BrowserClosedStateIR (..), SidePanelIR (..))
import Application.Helper.FrontendContract.Surface.Reflect (ReflectPrimitive, ReflectSurfaceSpec)
import Application.Helper.FrontendContract.Surface.SemanticIR (BrowserAttributeIR (..))
import Application.Helper.FrontendContract.Surface.Values
import IHP.Prelude

surfaceSidePanelRootAttrs :: forall spec marker. SidePanelConstraints spec marker => [(Text, Text)]
surfaceSidePanelRootAttrs =
    roleAttrs sidePanel.sidePanelRootRole
        <> [(sidePanel.sidePanelState.browserClosedStateAttribute.browserAttributeDomAttribute, sidePanel.sidePanelCollapsedValue)]
  where
    sidePanel = surfaceSidePanelValue @spec @marker

surfaceSidePanelMainAttrs :: forall spec marker. SidePanelConstraints spec marker => [(Text, Text)]
surfaceSidePanelMainAttrs = roleAttrs (surfaceSidePanelValue @spec @marker).sidePanelMainRole

surfaceSidePanelPanelAttrs :: forall spec marker. SidePanelConstraints spec marker => [(Text, Text)]
surfaceSidePanelPanelAttrs = roleAttrs (surfaceSidePanelValue @spec @marker).sidePanelPanelRole

surfaceSidePanelToggleAttrs :: forall spec marker. SidePanelConstraints spec marker => [(Text, Text)]
surfaceSidePanelToggleAttrs = roleAttrs (surfaceSidePanelValue @spec @marker).sidePanelToggleRole

surfaceSidePanelLabelAttrs :: forall spec marker. SidePanelConstraints spec marker => [(Text, Text)]
surfaceSidePanelLabelAttrs = roleAttrs (surfaceSidePanelValue @spec @marker).sidePanelLabelRole

type SidePanelConstraints spec marker =
    ( ReflectSurfaceSpec spec
    , ReflectPrimitive (SurfaceSidePanelPrimitive spec marker)
    )
