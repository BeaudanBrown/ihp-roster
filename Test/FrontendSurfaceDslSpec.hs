{-# LANGUAGE DataKinds        #-}
{-# LANGUAGE TypeApplications #-}

module Test.FrontendSurfaceDslSpec
    ( tests
    ) where

import Application.Helper.FrontendSurface.Lab (SurfaceLabSurface)
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
        let impl = (SurfaceImpl
                { surfaceImplName = "surface-lab"
                , surfaceImplMountConfig = config
                , surfaceImplActions = []
                , surfaceImplIntents = []
                } :: SurfaceImpl SurfaceLabSurface)
        let html = cs (HtmlRenderer.renderHtml (renderFrontendSurfaceMount impl (Html5.toHtml ("body" :: Text))))

        html `shouldContainText` "data-bepis-surface=\"surface-lab\""
        html `shouldContainText` "data-bepis-surface-config="
        html `shouldNotContainText` "data-live-update-surface"
        frontendSurfaceMountConfigJson config `shouldContainText` "\"mountKey\":\"primary\""
        frontendSurfaceMountConfigJson config `shouldContainText` "\"targetId\":\"surface-lab-panel\""

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

shouldContainText :: Text -> Text -> Expectation
shouldContainText actual expected =
    actual `shouldSatisfy` Text.isInfixOf expected

shouldNotContainText :: Text -> Text -> Expectation
shouldNotContainText actual expected =
    actual `shouldSatisfy` (not . Text.isInfixOf expected)
