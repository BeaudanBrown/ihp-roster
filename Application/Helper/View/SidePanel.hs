{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

module Application.Helper.View.SidePanel
    ( SidePanelRenderAttrs (..)
    , SidePanelRegionConfig (..)
    , sidePanelRenderAttrs
    , renderSidePanelLayout
    , renderSidePanelMainRegion
    , renderSidePanelPanelRegion
    , renderSidePanelHeaderToggle
    , renderSidePanelToggle
    ) where

import Application.Helper.FrontendContract.Surface.Reflect (ReflectPrimitive,
                                                            ReflectSurfaceSpec)
import Application.Helper.FrontendContract.Surface.SidePanel
import Application.Helper.FrontendContract.Surface.Values (SurfaceSidePanelPrimitive)
import IHP.ViewPrelude

-- | Resolved generated marker attributes supplied by a feature adapter.
data SidePanelRenderAttrs = SidePanelRenderAttrs
    { sidePanelRootAttrs   :: ![(Text, Text)]
    , sidePanelMainAttrs   :: ![(Text, Text)]
    , sidePanelPanelAttrs  :: ![(Text, Text)]
    , sidePanelToggleAttrs :: ![(Text, Text)]
    , sidePanelLabelAttrs  :: ![(Text, Text)]
    }

data SidePanelRegionConfig = SidePanelRegionConfig
    { sidePanelRegionId         :: !(Maybe Text)
    , sidePanelRegionClass      :: !Text
    , sidePanelRegionExtraAttrs :: ![(Text, Text)]
    }

sidePanelRenderAttrs :: forall spec marker.
    ( ReflectSurfaceSpec spec
    , ReflectPrimitive (SurfaceSidePanelPrimitive spec marker)
    ) => SidePanelRenderAttrs
sidePanelRenderAttrs = SidePanelRenderAttrs
    { sidePanelRootAttrs = surfaceSidePanelRootAttrs @spec @marker
    , sidePanelMainAttrs = surfaceSidePanelMainAttrs @spec @marker
    , sidePanelPanelAttrs = surfaceSidePanelPanelAttrs @spec @marker
    , sidePanelToggleAttrs = surfaceSidePanelToggleAttrs @spec @marker
    , sidePanelLabelAttrs = surfaceSidePanelLabelAttrs @spec @marker
    }

renderSidePanelLayout :: SidePanelRenderAttrs -> SidePanelRegionConfig -> Html -> Html
renderSidePanelLayout attrs config body = [hsx|
    <div id={config.sidePanelRegionId}
         class={"app-side-panel-layout " <> config.sidePanelRegionClass}
         {...attrs.sidePanelRootAttrs}
         {...config.sidePanelRegionExtraAttrs}>
        {body}
    </div>
|]

renderSidePanelMainRegion :: SidePanelRenderAttrs -> SidePanelRegionConfig -> Html -> Html
renderSidePanelMainRegion attrs config body = [hsx|
    <div id={config.sidePanelRegionId}
         class={"app-side-panel-main " <> config.sidePanelRegionClass}
         {...attrs.sidePanelMainAttrs}
         {...config.sidePanelRegionExtraAttrs}>
        {body}
    </div>
|]

renderSidePanelPanelRegion :: SidePanelRenderAttrs -> SidePanelRegionConfig -> Html -> Html
renderSidePanelPanelRegion attrs config body = [hsx|
    <aside id={config.sidePanelRegionId}
           class={"app-side-panel-region " <> config.sidePanelRegionClass}
           {...attrs.sidePanelPanelAttrs}
           {...config.sidePanelRegionExtraAttrs}>
        {body}
    </aside>
|]

renderSidePanelHeaderToggle :: SidePanelRenderAttrs -> Html
renderSidePanelHeaderToggle attrs = [hsx|
    <div class="app-panel-header app-side-panel-header">
        {renderSidePanelToggle attrs}
    </div>
|]

renderSidePanelToggle :: SidePanelRenderAttrs -> Html
renderSidePanelToggle attrs = [hsx|
    <button type="button"
            class="btn btn-outline-secondary btn-sm app-side-panel-toggle"
            {...attrs.sidePanelToggleAttrs}
            aria-pressed="false"
            aria-label="Expand main content"
            title="Expand main content">
        <i class="bi bi-fullscreen" aria-hidden="true"></i>
        <span class="visually-hidden" {...attrs.sidePanelLabelAttrs}>Expand main content</span>
    </button>
|]
