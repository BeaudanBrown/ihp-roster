module Web.View.Support.FrontendSurfaceLab where

import Web.Support.FrontendSurfaceLab (renderSurfaceLabMount)
import Web.View.Prelude

data FrontendSurfaceLabView = FrontendSurfaceLabView

instance View FrontendSurfaceLabView where
    html FrontendSurfaceLabView =
        renderAppPage AppPageConfig
            { appPageTitle = "FrontendSurface lab"
            , appPageDescription = Just "Support-only type-level surface runtime scaffold."
            , appPageActions = [hsx|<a href={SupportAction} class="btn btn-sm btn-outline-secondary">Back to support</a>|]
            , appPageWidthClass = "app-page-narrow"
            , appPageBody = renderAppPanel (defaultAppPanelConfig renderSurfaceLabMount)
                { appPanelTitle = Just "Surface lab"
                , appPanelDescription = Just "Exercises eager/lazy fragments, HTMX action metadata, and an intent form without legacy surface authoring."
                }
            }
