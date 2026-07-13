module Test.ToggleButtonSpec where

import Application.Helper.View.ToggleButton
import Config
import qualified Data.Text as Text
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import qualified Text.Blaze.Html.Renderer.Text as HtmlRenderer
import qualified Text.Blaze.Html5 as Html5

tests :: Spec
tests = beforeAll testContext do
    describe "App toggle button" do
        it "renders fixed labels without state alternatives" $ withContext do
            withCurrentControllerContext do
                let html = cs (HtmlRenderer.renderHtml (renderAppToggleButton (defaultAppToggleButtonConfig "fixed-toggle" True (Html5.toHtml ("Fixed label" :: Text))))) :: Text

                html `shouldSatisfy` Text.isInfixOf "Fixed label"
                html `shouldSatisfy` not . Text.isInfixOf "data-app-toggle-label-state"
                html `shouldSatisfy` Text.isInfixOf "aria-pressed=\"true\""

        it "renders both server-declared state labels with only the current state visible" $ withContext do
            withCurrentControllerContext do
                let html = cs (HtmlRenderer.renderHtml (renderAppToggleButton (defaultAppToggleStateButtonConfig "state-toggle" False (Html5.toHtml ("Enabled" :: Text)) (Html5.toHtml ("Disabled" :: Text))))) :: Text

                html `shouldSatisfy` Text.isInfixOf "data-app-toggle-label-state=\"checked\" hidden=\"hidden\">Enabled"
                html `shouldSatisfy` Text.isInfixOf "data-app-toggle-label-state=\"unchecked\">Disabled"
                html `shouldSatisfy` Text.isInfixOf "aria-pressed=\"false\""

                let checkedHtml = cs (HtmlRenderer.renderHtml (renderAppToggleButton ((defaultAppToggleStateButtonConfig "checked-state-toggle" True (Html5.toHtml ("Enabled" :: Text)) (Html5.toHtml ("Disabled" :: Text))) { appToggleRoleSwitch = True }))) :: Text
                checkedHtml `shouldSatisfy` Text.isInfixOf "data-app-toggle-label-state=\"checked\">Enabled"
                checkedHtml `shouldSatisfy` Text.isInfixOf "data-app-toggle-label-state=\"unchecked\" hidden=\"hidden\">Disabled"
                checkedHtml `shouldSatisfy` Text.isInfixOf "aria-pressed=\"true\""
                checkedHtml `shouldSatisfy` Text.isInfixOf "aria-checked=\"true\""
