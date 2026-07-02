module Web.Support.FrontendSurfaceLab
    ( frontendSurfaceLabPanelId
    , renderSurfaceLabMount
    , renderSurfaceLabPanelFragment
    , surfaceLabImpl
    ) where

import Application.Helper.FrontendSurface.Lab (SurfaceLabSurface)
import Application.Helper.FrontendSurface.Runtime
import qualified Data.Aeson as Aeson
import Web.View.Prelude

frontendSurfaceLabPanelId :: Text
frontendSurfaceLabPanelId = "surface-lab-panel"

surfaceLabImpl :: (?context :: ControllerContext) => SurfaceImpl SurfaceLabSurface
surfaceLabImpl =
    SurfaceImpl
        { surfaceImplName = "surface-lab"
        , surfaceImplMountConfig = surfaceLabMountConfig
        , surfaceImplActions = [refreshPanelAction]
        , surfaceImplIntents = [moveCardIntent]
        }

surfaceLabMountConfig :: (?context :: ControllerContext) => FrontendSurfaceMountConfig
surfaceLabMountConfig =
    FrontendSurfaceMountConfig
        { mountSurfaceName = "surface-lab"
        , mountScopeKey = "surface-lab:current-support-venue:0"
        , mountKey = "primary"
        , mountState = Aeson.object
            [ "showArchived" Aeson..= False
            ]
        , mountFragments =
            [ FrontendSurfaceMountedFragment
                { mountedFragmentKey = FrontendSurfaceFragmentKey "lab-shell" Aeson.Null
                , mountedFragmentTargetId = "surface-lab-shell"
                , mountedFragmentUrl = pathTo FrontendSurfaceLabAction
                , mountedFragmentProtection = FrontendSurfaceReplace
                , mountedFragmentLoadPolicy = "eager"
                }
            , surfaceLabPanelFragment
            ]
        }

surfaceLabPanelFragment :: (?context :: ControllerContext) => FrontendSurfaceMountedFragment
surfaceLabPanelFragment =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "lab-panel" (Aeson.object ["panelId" Aeson..= labPanelUuid])
        , mountedFragmentTargetId = frontendSurfaceLabPanelId
        , mountedFragmentUrl = pathTo ShowFrontendSurfaceLabPanelFragmentAction { panelId = labPanelUuid }
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "lazy"
        }

refreshPanelAction :: (?context :: ControllerContext) => FrontendSurfaceHtmxRequest
refreshPanelAction =
    FrontendSurfaceHtmxRequest
        { htmxRequestName = "refresh-panel"
        , htmxRequestMethod = FrontendSurfacePost
        , htmxRequestUrl = pathTo RefreshFrontendSurfaceLabPanelAction
        , htmxRequestTarget = "#" <> frontendSurfaceLabPanelId
        , htmxRequestSwap = "outerHTML"
        , htmxRequestFields = [FrontendSurfaceFieldValue "panelId" labPanelUuid]
        }

moveCardIntent :: (?context :: ControllerContext) => FrontendSurfaceIntentForm
moveCardIntent =
    FrontendSurfaceIntentForm
        { intentFormName = "move-lab-card"
        , intentFormSubmit = FrontendSurfaceHtmxRequest
            { htmxRequestName = "move-lab-card"
            , htmxRequestMethod = FrontendSurfacePost
            , htmxRequestUrl = pathTo MoveFrontendSurfaceLabCardAction
            , htmxRequestTarget = "#" <> frontendSurfaceLabPanelId
            , htmxRequestSwap = "outerHTML"
            , htmxRequestFields =
                [ FrontendSurfaceFieldValue "sourceItemKey" "card-a"
                , FrontendSurfaceFieldValue "targetDropzoneKey" "dropzone-b"
                ]
            }
        }

renderSurfaceLabMount :: (?context :: ControllerContext) => Html
renderSurfaceLabMount =
    let impl = surfaceLabImpl
        refreshButton = [hsx|<button type="submit" class="btn btn-sm btn-outline-primary">Refresh lab panel</button>|]
        intentButton = [hsx|<button type="submit" class="btn btn-sm btn-outline-secondary">Submit move-card intent</button>|]
        lazyPlaceholder = [hsx|
            <div class="app-lazy-surface-skeleton" aria-label="Loading FrontendSurface lab panel">
                <div class="app-lazy-surface-row"></div>
                <div class="app-lazy-surface-row"></div>
            </div>
        |]
     in renderFrontendSurfaceMount impl [hsx|
            <section id="surface-lab-shell" class="app-surface-lab">
                <div class="d-flex align-items-start justify-content-between gap-3 mb-3">
                    <div>
                        <h2 class="h5 mb-1">FrontendSurface lab shell</h2>
                        <p class="app-muted mb-0">Support-only proof mount for the type-level surface runtime scaffold.</p>
                    </div>
                    {renderFrontendSurfaceHtmxForm refreshPanelAction refreshButton}
                </div>
                {renderFrontendSurfaceLazyFragment surfaceLabPanelFragment lazyPlaceholder}
                <div class="mt-3">
                    {renderFrontendSurfaceIntentForm moveCardIntent intentButton}
                </div>
                <details class="mt-3">
                    <summary>Mount config</summary>
                    <pre class="small mb-0"><code>{frontendSurfaceMountConfigJson impl.surfaceImplMountConfig}</code></pre>
                </details>
            </section>
        |]

renderSurfaceLabPanelFragment :: Text -> Text -> Html
renderSurfaceLabPanelFragment panelId statusMessage = [hsx|
    <section id={frontendSurfaceLabPanelId} class="app-panel app-panel-body">
        <h3 class="h6 mb-2">Lazy lab panel</h3>
        <p class="mb-2">Panel id: <code>{panelId}</code></p>
        <p class="mb-0">{statusMessage}</p>
    </section>
|]

labPanelUuid :: Text
labPanelUuid = "11111111-1111-1111-1111-111111111111"
