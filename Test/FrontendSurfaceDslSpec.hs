{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}
{-# LANGUAGE TypeOperators    #-}

module Test.FrontendSurfaceDslSpec
    ( tests
    ) where

import Application.Helper.FrontendSurface.ContractIR
import Application.Helper.FrontendSurface.Contracts
import Application.Helper.FrontendSurface.DSL
import Application.Helper.FrontendSurface.Lab (SurfaceLabSurface)
import Application.Helper.FrontendSurface.Reflect
import Application.Helper.FrontendSurface.Registry (RegisteredFrontendSurfaces)
import Application.Helper.FrontendSurface.Runtime
import qualified Data.Aeson as Aeson
import Data.Proxy (Proxy (..))
import qualified Data.Text as Text
import IHP.Prelude
import Test.Hspec
import qualified Text.Blaze.Html.Renderer.Text as HtmlRenderer
import qualified Text.Blaze.Html5 as Html5

tests :: Spec
tests = describe "FrontendSurface DSL foundation" do
    it "kind-checks the support lab surface and root registry" do
        let _lab = Proxy @SurfaceLabSurface
        let _registry = Proxy @RegisteredFrontendSurfaces
        True `shouldBe` True

    it "renders minimal mount-local runtime metadata without legacy live-surface config" do
        let fragment = FrontendSurfaceMountedFragment
                { mountedFragmentKey = FrontendSurfaceFragmentKey "lab-panel" (Aeson.object ["panelId" Aeson..= ("panel-1" :: Text)])
                , mountedFragmentTargetId = "surface-lab-panel"
                , mountedFragmentUrl = "/ShowFrontendSurfaceLabPanelFragment?panelId=panel-1"
                , mountedFragmentProtection = FrontendSurfaceReplace
                , mountedFragmentLoadPolicy = "lazy"
                }
        let config = FrontendSurfaceMountConfig
                { mountSurfaceName = "surface-lab"
                , mountScopeKey = "surface-lab:scope"
                , mountKey = "primary"
                , mountState = Aeson.object ["showArchived" Aeson..= False]
                , mountFragments = [fragment]
                }
        let minimalRequest = FrontendSurfaceHtmxRequest
                { htmxRequestName = "refresh-panel"
                , htmxRequestMethod = FrontendSurfacePost
                , htmxRequestUrl = "/RefreshFrontendSurfaceLabPanel"
                , htmxRequestTarget = "#surface-lab-panel"
                , htmxRequestSwap = "outerHTML"
                , htmxRequestFields = []
                }
        let handlers = SurfaceImplHandlers
                { surfaceScopeHandlers = FrontendSurfaceScopeHandler "surface-lab:scope" `HandlerCons` HandlerNil
                , surfaceMountStateHandlers = FrontendSurfaceMountStateHandler (Aeson.object ["showArchived" Aeson..= False]) `HandlerCons` HandlerNil
                , surfaceFragmentHandlers =
                    FrontendSurfaceFragmentHandler fragment mempty
                        `HandlerCons` FrontendSurfaceFragmentHandler fragment mempty
                        `HandlerCons` HandlerNil
                , surfaceActionHandlers = FrontendSurfaceActionHandler minimalRequest `HandlerCons` HandlerNil
                , surfaceIntentHandlers = FrontendSurfaceIntentHandler (FrontendSurfaceIntentForm "move-lab-card" minimalRequest) `HandlerCons` HandlerNil
                }
        let impl = (mkSurfaceImpl "surface-lab" config handlers :: SurfaceImpl SurfaceLabSurface)
        let html = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceMount impl (Html5.toHtml ("body" :: Text))))

        impl.surfaceImplActions |> map (.htmxRequestName) `shouldBe` ["refresh-panel"]
        impl.surfaceImplIntents |> map (.intentFormName) `shouldBe` ["move-lab-card"]
        html `shouldContainText` "data-bepis-surface=\"surface-lab\""
        html `shouldContainText` "data-bepis-surface-config="
        html `shouldNotContainText` "data-live-update-surface"
        frontendSurfaceMountConfigJson config `shouldContainText` "\"mountKey\":\"primary\""
        frontendSurfaceMountConfigJson config `shouldContainText` "\"targetId\":\"surface-lab-panel\""

    it "extracts the registered lab surface into checked contract IR" do
        let SurfaceContractIR { contractSurfaces = [surface] } = registeredFrontendSurfaceContractIR

        surface.surfaceName `shouldBe` "surface-lab"
        map (.scopeName) surface.surfaceScopes `shouldBe` ["lab"]
        map (.fragmentName) surface.surfaceFragments `shouldBe` ["lab-shell", "lab-panel"]
        map (.htmxActionName) surface.surfaceHtmxActions `shouldBe` ["refresh-panel"]
        map (.intentName) surface.surfaceIntents `shouldBe` ["move-lab-card"]
        surface.surfaceSessions `shouldBe` ["drag"]
        surface.surfaceLayers `shouldBe` ["drag-preview"]
        surface.surfaceDomTokens `shouldBe` ["lab-root", "lab-dropzone"]
        map fst surface.surfaceDtos `shouldBe` ["lab-payload", "lab-related-payload"]
        surface.surfaceFragments
            |> find (\fragment -> fragment.fragmentName == "lab-panel")
            |> fmap (.fragmentOptions)
            `shouldBe` Just [LazyOption [TriggerOption "load", PlaceholderOption "panel"]]

    it "renders generated TypeScript contracts for every lab primitive family" do
        frontendSurfaceContractsTypeScript `shouldContainText` "export type SurfaceLabFragmentKey ="
        frontendSurfaceContractsTypeScript `shouldContainText` "{ kind: \"lab-panel\"; params: { panelId: PanelId } }"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type RefreshPanelActionFields = { panelId: PanelId };"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type MoveLabCardIntentFields = { sourceItemKey: string; targetDropzoneKey: string };"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type LabPayload = { label: string; count?: number; note: string | null; tags: ReadonlyArray<string>; dueDay: FrontendSurfaceDay; maybeRank: number | undefined; maybeMemo: string | null; relatedPayload: LabRelatedPayload };"
        frontendSurfaceContractsTypeScript `shouldContainText` "export type LabRelatedPayload = { label: string };"
        frontendSurfaceContractsTypeScript `shouldContainText` "export const surfaceLabSurfaceManifest"
        frontendSurfaceContractsTypeScript `shouldContainText` "export function parseFrontendSurfaceName"

    it "reports stable diagnostics for malformed reflected specs" do
        let duplicateFields = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[DuplicateFieldSurface]))
        let missingReference = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[MissingReferenceSurface]))
        let conflictingShared = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[SharedScopeA, SharedScopeB]))
        let missingDtoRef = checkedSurfaceContractIR (SurfaceContractIR (reflectSurfaceRegistry @'[MissingDtoRefSurface]))

        diagnosticMessages duplicateFields `shouldContain` ["surface duplicate has duplicate scope field panelId"]
        diagnosticMessages missingReference `shouldContain` ["htmx action bad references missing fragment missing on surface missing-reference"]
        diagnosticMessages conflictingShared `shouldContain` ["conflicting shared declaration: scope shared"]
        diagnosticMessages missingDtoRef `shouldContain` ["field missingPayload references missing dto missing-payload on surface missing-dto-ref"]

    it "renders minimal HTMX action and intent forms from SurfaceImpl metadata" do
        let request = FrontendSurfaceHtmxRequest
                { htmxRequestName = "refresh-panel"
                , htmxRequestMethod = FrontendSurfacePost
                , htmxRequestUrl = "/RefreshFrontendSurfaceLabPanel"
                , htmxRequestTarget = "#surface-lab-panel"
                , htmxRequestSwap = "outerHTML"
                , htmxRequestFields = [FrontendSurfaceFieldValue "panelId" "panel-1"]
                }
        let intent = FrontendSurfaceIntentForm "move-lab-card" request
        let actionHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceHtmxForm request (Html5.toHtml ("refresh" :: Text))))
        let intentHtml = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceIntentForm intent (Html5.toHtml ("move" :: Text))))

        actionHtml `shouldContainText` "hx-post=\"/RefreshFrontendSurfaceLabPanel\""
        actionHtml `shouldContainText` "data-bepis-surface-action=\"refresh-panel\""
        actionHtml `shouldContainText` "name=\"panelId\""
        intentHtml `shouldContainText` "data-bepis-intent-form=\"move-lab-card\""
        intentHtml `shouldContainText` "hx-target=\"#surface-lab-panel\""

diagnosticMessages :: Either [ContractDiagnostic] SurfaceContractIR -> [Text]
diagnosticMessages = \case
    Right _ -> []
    Left diagnostics -> map (.diagnosticMessage) diagnostics

data Duplicate
data DuplicateScope
data MissingReference
data SharedA
data SharedB
data Shared
data Bad
data MissingFragment
data MissingDtoRef
data MissingPayload
data PanelId
data VenueId
data WeekOffset
data LabScope

type DuplicateFieldSurface =
    Surface Duplicate
        '[ Scope DuplicateScope
            '[ Field PanelId 'WireUUID
             , Field PanelId 'WireText
             ]
         ]

type MissingReferenceSurface =
    Surface MissingReference
        '[ Scope LabScope '[ Field VenueId 'WireUUID ]
         , HtmxAction Bad '[] '[ 'Target MissingFragment ]
         ]

type MissingDtoRefSurface =
    Surface MissingDtoRef
        '[ Scope LabScope '[ Field VenueId 'WireUUID ]
         , Dto Bad '[ Field MissingPayload ('WireRef MissingPayload) ]
         ]

type SharedScopeA =
    Surface SharedA
        '[ Scope Shared '[ Field VenueId 'WireUUID ]
         ]

type SharedScopeB =
    Surface SharedB
        '[ Scope Shared '[ Field WeekOffset 'WireInt ]
         ]

shouldContainText :: Text -> Text -> Expectation
shouldContainText actual expected =
    actual `shouldSatisfy` Text.isInfixOf expected

shouldNotContainText :: Text -> Text -> Expectation
shouldNotContainText actual expected =
    actual `shouldSatisfy` (not . Text.isInfixOf expected)
