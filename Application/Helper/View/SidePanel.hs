{-# LANGUAGE AllowAmbiguousTypes #-}
{-# LANGUAGE FlexibleContexts    #-}
{-# LANGUAGE TypeApplications    #-}
{-# LANGUAGE TypeFamilies        #-}

module Application.Helper.View.SidePanel
    ( SidePanelRenderAttrs (..)
    , SidePanelRegionConfig (..)
    , SidePanelCardConfig (..)
    , SidePanelTabConfig (..)
    , sidePanelRenderAttrs
    , renderSidePanelLayout
    , renderSidePanelMainRegion
    , renderSidePanelPanelRegion
    , renderSidePanelCard
    , renderSidePanelTabs
    , renderSidePanelHeaderToggle
    , renderSidePanelToggle
    ) where

import Application.Helper.FrontendContract.Surface.Reflect (ReflectPrimitive,
                                                            ReflectSurfaceSpec)
import Application.Helper.FrontendContract.Surface.SidePanel
import Application.Helper.FrontendContract.Surface.Values (SurfaceSidePanelPrimitive)
import qualified Data.Text as Text
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

data SidePanelCardConfig = SidePanelCardConfig
    { sidePanelCardClass     :: !Text
    , sidePanelCardBodyClass :: !Text
    }

data SidePanelTabConfig = SidePanelTabConfig
    { sidePanelTabId         :: !Text
    , sidePanelTabPaneId     :: !Text
    , sidePanelTabLabel      :: !Text
    , sidePanelTabIconClass  :: !Text
    , sidePanelTabIsSelected :: !Bool
    , sidePanelTabClass      :: !Text
    , sidePanelTabAttrs      :: ![(Text, Text)]
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

renderSidePanelCard :: SidePanelCardConfig -> Html -> Html
renderSidePanelCard config body = [hsx|
    <div class={"app-panel app-side-panel-card app-side-panel-scroll " <> config.sidePanelCardClass}>
        <div class={"app-panel-body " <> config.sidePanelCardBodyClass}>
            {body}
        </div>
    </div>
|]

renderSidePanelTabs :: Text -> [SidePanelTabConfig] -> Html
renderSidePanelTabs ariaLabel tabs = [hsx|
    <div class="nav nav-pills app-side-panel-tabs" role="tablist" aria-label={ariaLabel}>
        {forEach tabs renderTab}
    </div>
|]
  where
    renderTab tab = [hsx|
        <button class={classes [ ("nav-link", True), ("active", tab.sidePanelTabIsSelected), ("app-side-panel-tab", True), (tab.sidePanelTabClass, not (Text.null tab.sidePanelTabClass)) ]}
                id={tab.sidePanelTabId}
                type="button"
                role="tab"
                data-bs-toggle="tab"
                data-bs-target={"#" <> tab.sidePanelTabPaneId}
                aria-controls={tab.sidePanelTabPaneId}
                aria-selected={if tab.sidePanelTabIsSelected then ("true" :: Text) else "false"}
                {...tab.sidePanelTabAttrs}>
            <i class={tab.sidePanelTabIconClass} aria-hidden="true"></i>
            <span>{tab.sidePanelTabLabel}</span>
        </button>
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
