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
    , renderSidePanelLocateIcon
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
    { sidePanelCardClass :: !Text
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
        <div class="app-panel-body">
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

renderSidePanelLocateIcon :: Html
renderSidePanelLocateIcon = [hsx|
    <svg class="app-side-panel-locate-icon" aria-hidden="true" viewBox="0 0 24 24" width="16" height="16">
        <path d="M12 5.25c-4.55 0-8.2 3.95-9.55 6.15a1.15 1.15 0 0 0 0 1.2c1.35 2.2 5 6.15 9.55 6.15s8.2-3.95 9.55-6.15a1.15 1.15 0 0 0 0-1.2c-1.35-2.2-5-6.15-9.55-6.15Zm0 11a4.25 4.25 0 1 1 0-8.5 4.25 4.25 0 0 1 0 8.5Zm0-1.75a2.5 2.5 0 1 0 0-5 2.5 2.5 0 0 0 0 5Z" fill="currentColor"></path>
    </svg>
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
