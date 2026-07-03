{-# LANGUAGE TypeApplications #-}

module Web.Support.FrontendSurfaceLab
    ( frontendSurfaceLabPanelId
    , renderSurfaceLabMount
    , renderSurfaceLabPanelFragment
    , surfaceLabImpl
    ) where

import Application.Helper.FrontendSurface.Lab (LabPanel, LabScope, LabShell,
                                               LabViewState, MoveLabCard,
                                               PanelId, RefreshPanel,
                                               SourceItemKey, SurfaceLabSurface,
                                               TargetDropzoneKey)
import Application.Helper.FrontendSurface.Runtime
import qualified Data.Aeson as Aeson
import Web.View.Prelude

frontendSurfaceLabPanelId :: Text
frontendSurfaceLabPanelId = "surface-lab-panel"

surfaceLabImpl :: (?context :: ControllerContext) => SurfaceImpl SurfaceLabSurface
surfaceLabImpl =
    mkSurfaceImpl "surface-lab" surfaceLabMountConfig surfaceLabHandlers

surfaceLabHandlers :: (?context :: ControllerContext) => SurfaceImplHandlers SurfaceLabSurface
surfaceLabHandlers =
    SurfaceImplHandlers
        { surfaceScopeHandlers =
            FrontendSurfaceScopeHandler
                { scopeHandlerDefaultValue = frontendSurfaceFieldValues (Aeson.object
                    [ "venueId" Aeson..= ("current-support-venue" :: Text)
                    , "weekOffset" Aeson..= (0 :: Int)
                    ])
                , scopeHandlerKey = const "surface-lab:current-support-venue:0"
                }
                `HandlerCons` HandlerNil
        , surfaceMountStateHandlers =
            FrontendSurfaceMountStateHandler
                { mountStateHandlerDefaultValue = frontendSurfaceFieldValues (Aeson.object
                    [ "showArchived" Aeson..= False
                    ])
                }
                `HandlerCons` HandlerNil
        , surfaceFragmentHandlers =
            FrontendSurfaceFragmentHandler
                { fragmentHandlerDefaultParams = frontendSurfaceFieldValues Aeson.Null
                , fragmentHandlerMountedFragment = const surfaceLabShellFragment
                , fragmentHandlerRender = const mempty
                }
                `HandlerCons` FrontendSurfaceFragmentHandler
                    { fragmentHandlerDefaultParams = frontendSurfaceFieldValues (Aeson.object ["panelId" Aeson..= labPanelUuid])
                    , fragmentHandlerMountedFragment = \params ->
                        surfaceLabPanelFragmentFor (fromMaybe labPanelUuid (getSurfaceField @PanelId params))
                    , fragmentHandlerRender = const mempty
                    }
                `HandlerCons` HandlerNil
        , surfaceActionHandlers =
            FrontendSurfaceActionHandler
                { actionHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object ["panelId" Aeson..= labPanelUuid])
                , actionHandlerRequest = \fields ->
                    refreshPanelActionFor (fromMaybe labPanelUuid (getSurfaceField @PanelId fields))
                }
                `HandlerCons` HandlerNil
        , surfaceIntentHandlers =
            FrontendSurfaceIntentHandler
                { intentHandlerDefaultFields = frontendSurfaceFieldValues (Aeson.object
                    [ "sourceItemKey" Aeson..= ("card-a" :: Text)
                    , "targetDropzoneKey" Aeson..= ("dropzone-b" :: Text)
                    ])
                , intentHandlerForm = \fields ->
                    moveCardIntentFor
                        (fromMaybe "card-a" (getSurfaceField @SourceItemKey fields))
                        (fromMaybe "dropzone-b" (getSurfaceField @TargetDropzoneKey fields))
                }
                `HandlerCons` HandlerNil
        }

surfaceLabMountConfig :: (?context :: ControllerContext) => FrontendSurfaceMountConfig
surfaceLabMountConfig =
    FrontendSurfaceMountConfig
        { mountSurfaceName = "surface-lab"
        , mountScopeKey = "surface-lab:current-support-venue:0"
        , mountKey = "primary"
        , mountScope = Aeson.Null
        , mountSubscription = Nothing
        , mountState = Aeson.object
            [ "showArchived" Aeson..= False
            ]
        , mountFragments =
            [ surfaceLabShellFragment
            , surfaceLabPanelFragment
            ]
        }

surfaceLabShellFragment :: (?context :: ControllerContext) => FrontendSurfaceMountedFragment
surfaceLabShellFragment =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "lab-shell" Aeson.Null
        , mountedFragmentTargetId = "surface-lab-shell"
        , mountedFragmentUrl = pathTo FrontendSurfaceLabAction
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "eager"
        }

surfaceLabPanelFragment :: (?context :: ControllerContext) => FrontendSurfaceMountedFragment
surfaceLabPanelFragment =
    surfaceLabPanelFragmentFor labPanelUuid

surfaceLabPanelFragmentFor :: (?context :: ControllerContext) => Text -> FrontendSurfaceMountedFragment
surfaceLabPanelFragmentFor panelIdValue =
    FrontendSurfaceMountedFragment
        { mountedFragmentKey = FrontendSurfaceFragmentKey "lab-panel" (Aeson.object ["panelId" Aeson..= panelIdValue])
        , mountedFragmentTargetId = frontendSurfaceLabPanelId
        , mountedFragmentUrl = pathTo ShowFrontendSurfaceLabPanelFragmentAction { panelId = panelIdValue }
        , mountedFragmentProtection = FrontendSurfaceReplace
        , mountedFragmentLoadPolicy = "lazy"
        }

refreshPanelAction :: (?context :: ControllerContext) => FrontendSurfaceHtmxRequest
refreshPanelAction =
    refreshPanelActionFor labPanelUuid

refreshPanelActionFor :: (?context :: ControllerContext) => Text -> FrontendSurfaceHtmxRequest
refreshPanelActionFor panelIdValue =
    FrontendSurfaceHtmxRequest
        { htmxRequestName = "refresh-panel"
        , htmxRequestMethod = FrontendSurfacePost
        , htmxRequestUrl = pathTo RefreshFrontendSurfaceLabPanelAction
        , htmxRequestTarget = "#" <> frontendSurfaceLabPanelId
        , htmxRequestSwap = "outerHTML"
        , htmxRequestFields = [FrontendSurfaceFieldValue "panelId" panelIdValue]
        }

moveCardIntent :: (?context :: ControllerContext) => FrontendSurfaceIntentForm
moveCardIntent =
    moveCardIntentFor "card-a" "dropzone-b"

moveCardIntentFor :: (?context :: ControllerContext) => Text -> Text -> FrontendSurfaceIntentForm
moveCardIntentFor sourceItemKey targetDropzoneKey =
    FrontendSurfaceIntentForm
        { intentFormName = "move-lab-card"
        , intentFormSubmit = FrontendSurfaceHtmxRequest
            { htmxRequestName = "move-lab-card"
            , htmxRequestMethod = FrontendSurfacePost
            , htmxRequestUrl = pathTo MoveFrontendSurfaceLabCardAction
            , htmxRequestTarget = "#" <> frontendSurfaceLabPanelId
            , htmxRequestSwap = "outerHTML"
            , htmxRequestFields =
                [ FrontendSurfaceFieldValue "sourceItemKey" sourceItemKey
                , FrontendSurfaceFieldValue "targetDropzoneKey" targetDropzoneKey
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
