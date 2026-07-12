{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Web.Support.FrontendSurfaceLab
    ( frontendSurfaceLabPanelId
    , renderSurfaceLabMount
    , renderSurfaceLabPanelFragment
    , surfaceLabImpl
    ) where

import qualified Application.Helper.FrontendContract.Surface.Lab as Surface
import Application.Helper.FrontendContract.Surface.Runtime
import Application.Helper.FrontendContract.Surface.Values
import qualified Data.UUID as UUID
import Web.View.Prelude

frontendSurfaceLabPanelId :: Text
frontendSurfaceLabPanelId = "surface-lab-panel"

surfaceLabImpl :: (?context :: ControllerContext) => SurfaceImpl Surface.SurfaceLabSurface
surfaceLabImpl =
    mkSurfaceImplFromValues @Surface.SurfaceLabSurface @Surface.LabScope
        "primary"
        labScopeFields
        labMountStateFields
        [ surfaceLabShellFragment
        , surfaceLabPanelFragment
        ]

labScopeFields :: SurfaceFields (SurfaceScopeFieldSpecs Surface.SurfaceLabSurface Surface.LabScope)
labScopeFields =
    surfaceField @Surface.VenueId labScopeVenueId
        :& surfaceField @Surface.WeekOffset (0 :: Int)
        :& NoSurfaceFields

labMountStateFields :: SurfaceFields (SurfaceMountStateFieldSpecs Surface.SurfaceLabSurface)
labMountStateFields =
    surfaceField @Surface.ShowArchived False
        :& surfaceOptionalField @Surface.StaffFilterId Nothing
        :& NoSurfaceFields

surfaceLabShellFragment :: (?context :: ControllerContext) => FrontendSurfaceMountedFragment
surfaceLabShellFragment =
    frontendSurfaceMountedFragmentFor @Surface.SurfaceLabSurface @Surface.LabShell
        NoSurfaceFields
        "surface-lab-shell"
        (pathTo FrontendSurfaceLabAction)
        FrontendSurfaceReplace

surfaceLabPanelFragment :: (?context :: ControllerContext) => FrontendSurfaceMountedFragment
surfaceLabPanelFragment =
    surfaceLabPanelFragmentFor labPanelUuid

surfaceLabPanelFragmentFor :: (?context :: ControllerContext) => UUID.UUID -> FrontendSurfaceMountedFragment
surfaceLabPanelFragmentFor panelIdValue =
    frontendSurfaceMountedFragmentFor @Surface.SurfaceLabSurface @Surface.LabPanel
        (surfaceField @Surface.PanelId panelIdValue :& NoSurfaceFields)
        frontendSurfaceLabPanelId
        (pathTo ShowFrontendSurfaceLabPanelFragmentAction { panelId = UUID.toText panelIdValue })
        FrontendSurfaceReplace

refreshPanelAction :: (?context :: ControllerContext) => FrontendSurfaceHtmxRequest
refreshPanelAction =
    refreshPanelActionFor labPanelUuid

refreshPanelActionFor :: (?context :: ControllerContext) => UUID.UUID -> FrontendSurfaceHtmxRequest
refreshPanelActionFor panelIdValue =
    FrontendSurfaceHtmxRequest
        { htmxRequestName = surfaceActionNameValue @Surface.SurfaceLabSurface @Surface.RefreshPanel
        , htmxRequestMethod = FrontendSurfacePost
        , htmxRequestUrl = pathTo RefreshFrontendSurfaceLabPanelAction
        , htmxRequestTarget = "#" <> frontendSurfaceLabPanelId
        , htmxRequestSwap = "outerHTML"
        , htmxRequestFields = frontendSurfaceActionFields @Surface.SurfaceLabSurface @Surface.RefreshPanel
            (surfaceField @Surface.PanelId panelIdValue :& NoSurfaceFields)
        }

moveCardIntent :: (?context :: ControllerContext) => FrontendSurfaceIntentForm
moveCardIntent =
    moveCardIntentFor "card-a" "dropzone-b"

moveCardIntentFor :: (?context :: ControllerContext) => Text -> Text -> FrontendSurfaceIntentForm
moveCardIntentFor sourceItemKey targetDropzoneKey =
    FrontendSurfaceIntentForm
        { intentFormName = surfaceIntentNameValue @Surface.SurfaceLabSurface @Surface.MoveLabCard
        , intentFormSubmit = FrontendSurfaceHtmxRequest
            { htmxRequestName = surfaceIntentNameValue @Surface.SurfaceLabSurface @Surface.MoveLabCard
            , htmxRequestMethod = FrontendSurfacePost
            , htmxRequestUrl = pathTo MoveFrontendSurfaceLabCardAction
            , htmxRequestTarget = "#" <> frontendSurfaceLabPanelId
            , htmxRequestSwap = "outerHTML"
            , htmxRequestFields = frontendSurfaceIntentFieldValues @Surface.SurfaceLabSurface @Surface.MoveLabCard
                ( surfaceField @Surface.SourceItemKey sourceItemKey
                    :& surfaceField @Surface.TargetDropzoneKey targetDropzoneKey
                    :& NoSurfaceFields
                )
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

labScopeVenueId :: UUID.UUID
labScopeVenueId = expectLabUuid "22222222-2222-2222-2222-222222222222"

labPanelUuid :: UUID.UUID
labPanelUuid = expectLabUuid "11111111-1111-1111-1111-111111111111"

expectLabUuid :: Text -> UUID.UUID
expectLabUuid value =
    fromMaybe (error ("Invalid FrontendSurface lab UUID: " <> value)) (UUID.fromText value)
