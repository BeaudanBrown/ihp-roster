module Test.OverlaySpec where

import Application.Helper.View.Overlay
import Application.Helper.View.Toast
import Config
import qualified Data.Text as Text
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import Text.Blaze.Html (Html)
import qualified Text.Blaze.Html.Renderer.Text as HtmlRenderer
import qualified Text.Blaze.Html5 as Html5

tests :: Spec
tests = beforeAll testContext do
    describe "Overlay render helpers" do
        it "renders generated dialog roles and exact submit config with native accessibility state" $ withContext do
            withCurrentControllerContext do
                let html = renderText (renderDialogOverlay dialogConfig)

                html `shouldSatisfy` Text.isInfixOf "data-bepis-dialog-mount=\"true\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-dialog-backdrop=\"true\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-dialog-close=\"true\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-dialog-submit=\"true\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-dialog-submit-config=\"{&quot;loadingLabel&quot;:&quot;Working...&quot;}\""
                html `shouldSatisfy` Text.isInfixOf "role=\"dialog\""
                html `shouldSatisfy` Text.isInfixOf "aria-modal=\"true\""
                html `shouldSatisfy` Text.isInfixOf "aria-labelledby=\"dialog-overlay-title\""
                html `shouldSatisfy` not . Text.isInfixOf "data-dialog-overlay"
                html `shouldSatisfy` not . Text.isInfixOf "data-loading-label"

        it "renders generated toast roles and exact auto-hide config with an accessible close control" $ withContext do
            withCurrentControllerContext do
                let html = renderText (renderToastOverlayHost ToastBottomCenter [successToast "Saved"])

                html `shouldSatisfy` Text.isInfixOf "id=\"toast-overlay-mount\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-toast-mount=\"true\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-toast-config=\"{&quot;autoHideMs&quot;:3200}\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-toast-close=\"true\""
                html `shouldSatisfy` Text.isInfixOf "aria-label=\"Dismiss\""
                html `shouldSatisfy` not . Text.isInfixOf "data-overlay-toast"
                html `shouldSatisfy` not . Text.isInfixOf "data-auto-hide-ms"
                html `shouldSatisfy` not . Text.isInfixOf "data-toast-close"
  where
    dialogConfig = DialogOverlayConfig
        { dialogOverlayTitle = "Generated overlay"
        , dialogOverlayBody = Html5.toHtml ("Body" :: Text)
        , dialogOverlayStartButtons = []
        , dialogOverlayButtons = defaultOverlayButtons "generated-overlay-form"
        , dialogOverlayDialogClass = ""
        }

renderText :: Html -> Text
renderText = cs . HtmlRenderer.renderHtml
