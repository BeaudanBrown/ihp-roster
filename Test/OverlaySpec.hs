{-# LANGUAGE TypeApplications #-}

module Test.OverlaySpec where

import Application.Helper.FrontendContract.AppShell (DeleteTimesheetEntryOverlay)
import Application.Helper.FrontendContract.AppShell.Runtime
import Application.Helper.FrontendContract.Overlay.Runtime (navigationLoadingAttrs)
import qualified Application.Helper.FrontendContract.Passkey as Passkey
import Application.Helper.View.Overlay
import Application.Helper.View.Toast
import Config
import qualified Data.Text as Text
import qualified Data.List as List
import qualified IHP.HSX.Parser as Hsx
import IHP.Prelude
import IHP.Test.Mocking
import Test.Hspec
import Test.Support
import IHP.HSX.Markup (Html)
import qualified IHP.HSX.Markup as HtmlRenderer
import Text.Megaparsec.Pos (initialPos)

pureTests :: Spec
pureTests = do
    describe "Overlay contract attributes" do
        it "renders exact generated navigation-loading configuration" do
            navigationLoadingAttrs "Opening Stripe" "Please wait while Bepis opens Stripe's secure billing page."
                `shouldBe`
                    [ ("data-bepis-navigation-loading", "true")
                    , ("data-bepis-navigation-loading-config", "{\"loadingMessage\":\"Please wait while Bepis opens Stripe's secure billing page.\",\"loadingTitle\":\"Opening Stripe\"}")
                    ]

-- Literal expectations deliberately do not call the production attribute builders.
buttonCases :: Bool -> [(Text, OverlayButtonAction, Text, [(Text, Text)], [[(Text, Text)]], [(Text, Text)])]
buttonCases page =
    [ ("close", OverlayCloseAction, if page then "a" else "button", if page then [("href", "/close")] else [("type", "button"), ("data-bepis-dialog-close", "true")], [], [])
    , ("submit", OverlaySubmitFormAction "edit-form", "button", submitAttrs "Working...", [], [])
    , ("loading submit", OverlaySubmitFormLoadingAction "edit-form" "Saving", "button", submitAttrs "Saving", [], [])
    , ("navigate", OverlayNavigateAction "/next", "a", [("href", "/next")], [], [])
    , ("native form", DialogFormAction "DELETE" "/delete" fields (Just "Really delete?"), "button", [("type", "submit")], [nativeFormAttrs], ("_method", "DELETE") : fields)
    , ("navigation loading form", DialogNavigationLoadingFormAction "DELETE" "/delete" fields (Just "Really delete?") "Opening" "Please wait", "button", [("type", "submit")], [nativeFormAttrs <> [("data-bepis-navigation-loading", "true"), ("data-bepis-navigation-loading-config", "{&quot;loadingMessage&quot;:&quot;Please wait&quot;,&quot;loadingTitle&quot;:&quot;Opening&quot;}")]], ("_method", "DELETE") : fields)
    , ("generated form", GeneratedDialogFormAction (appShellActionByMarker @DeleteTimesheetEntryOverlay) route (("_method", "DELETE") : fields) (Just "Really delete?"), "button", [("type", "submit")], [generatedFormAttrs], ("routeField", "route-value") : ("_method", "DELETE") : fields)
    ]
  where
    fields = [("csrfToken", "token-value"), ("entryId", "entry-value")]
    route = (defaultAppShellActionRoute "/htmx-delete")
        { appShellActionRouteStandardUrl = Just "/native-delete"
        , appShellActionRouteFields = [AppShellFieldValue ("routeField", "route-value")]
        }
    submitAttrs loadingLabel =
        [("type", "submit"), ("form", "edit-form"), ("data-bepis-dialog-submit", "true"), ("data-bepis-dialog-submit-config", "{&quot;loadingLabel&quot;:&quot;" <> loadingLabel <> "&quot;}")]
    nativeFormAttrs = [("method", "POST"), ("action", "/delete"), ("class", "app-modal-footer-form"), ("onsubmit", "return window.confirm(&quot;Really delete?&quot;);")]
    generatedFormAttrs =
        [("method", if page then "POST" else "post"), ("action", "/native-delete"), ("class", "app-modal-footer-form")]
            <> if page
                then [("onsubmit", "return window.confirm(&quot;Really delete?&quot;);")]
                else [("hx-delete", "/htmx-delete"), ("hx-target", "#dialog-overlay-mount"), ("hx-swap", "innerHTML"), ("hx-push-url", "false"), ("hx-confirm", "Delete this timesheet entry? This cannot be undone.")]

-- Use IHP's existing markup parser rather than a parallel attribute scanner.
parseRenderedOverlay :: Html -> IO Hsx.Node
parseRenderedOverlay html =
    case Hsx.parseHsx (Hsx.HsxSettings False mempty mempty) (initialPos "rendered-overlay") [] (renderText html) of
        Left failure -> expectationFailure (cs (show failure)) >> pure (Hsx.Children [])
        Right tree -> pure tree

elementNodes :: Hsx.Node -> [Hsx.Node]
elementNodes node@(Hsx.Node _ _ children _) = node : concatMap elementNodes children
elementNodes (Hsx.Children children) = concatMap elementNodes children
elementNodes _ = []

nodeName :: Hsx.Node -> Text
nodeName (Hsx.Node name _ _ _) = name
nodeName _ = ""

nodeAttrs :: Hsx.Node -> [(Text, Text)]
nodeAttrs (Hsx.Node _ attrs _ _) = List.sort [(name, value) | Hsx.StaticAttribute name (Hsx.TextValue value) <- attrs]
nodeAttrs _ = []

nodeText :: Hsx.Node -> Text
nodeText (Hsx.Node _ _ children _) = Text.strip (mconcat (map nodeText children))
nodeText (Hsx.TextNode value) = value
nodeText _ = ""

databaseTests :: Spec
databaseTests = aroundAll withDatabaseTestContext do
    describe "Overlay render helpers" do
        forM_ [("mounted", Nothing), ("page", Just "/close")] \(contextName, closeUrl) -> do
            forM_ (buttonCases (isJust closeUrl)) \(caseName, action, expectedTag, expectedAttrs, expectedForms, expectedFields) ->
                it (cs (contextName <> " " <> caseName <> " retains exact control and form attributes")) $ withContext do
                    withCurrentControllerContext do
                        let config = defaultDialogOverlayConfig "Buttons" mempty [OverlayButton "Action" "contract-button" action]
                        tree <- parseRenderedOverlay (case closeUrl of
                            Nothing -> renderDialogOverlay config
                            Just url -> renderPageDialogModal url config)
                        let controls = filter (\node -> lookup "class" (nodeAttrs node) == Just "contract-button") (elementNodes tree)
                        map (\node -> (nodeName node, nodeAttrs node, nodeText node)) controls
                            `shouldBe` [(expectedTag, List.sort (("class", "contract-button") : expectedAttrs), "Action")]
                        let forms = filter ((== "form") . nodeName) (elementNodes tree)
                        map nodeAttrs forms `shouldBe` map List.sort expectedForms
                        map (\node -> (lookup "name" (nodeAttrs node), lookup "value" (nodeAttrs node)))
                            (concatMap (filter ((== "input") . nodeName) . elementNodes) forms)
                            `shouldBe` map (\(name, value) -> (Just name, Just value)) expectedFields

            it (cs (contextName <> " retains start/end button order and empty-footer behavior")) $ withContext do
                withCurrentControllerContext do
                    let config = (defaultDialogOverlayConfig "Buttons" mempty
                            [OverlayButton "Cancel" "contract-button" OverlayCloseAction, OverlayButton "Save" "contract-button" (OverlaySubmitFormAction "edit-form")])
                            { dialogOverlayStartButtons = [OverlayButton "First" "contract-button" (OverlayNavigateAction "/first"), OverlayButton "Second" "contract-button" (OverlayNavigateAction "/second")] }
                    tree <- parseRenderedOverlay (case closeUrl of
                        Nothing -> renderDialogOverlay config
                        Just url -> renderPageDialogModal url config)
                    map nodeText (filter (\node -> lookup "class" (nodeAttrs node) == Just "contract-button") (elementNodes tree))
                        `shouldBe` ["First", "Second", "Cancel", "Save"]
                    let emptyConfig = defaultDialogOverlayConfig "Empty" mempty []
                    emptyTree <- parseRenderedOverlay (case closeUrl of
                        Nothing -> renderDialogOverlay emptyConfig
                        Just url -> renderPageDialogModal url emptyConfig)
                    filter (\node -> maybe False (Text.isInfixOf "app-modal-footer") (lookup "class" (nodeAttrs node))) (elementNodes emptyTree)
                        `shouldBe` []

        it "owns the exact dialog mount clear OOB fragment" $ withContext do
            withCurrentControllerContext do
                let html = renderText renderDialogOverlayClearOob

                html `shouldSatisfy` Text.isInfixOf "id=\"dialog-overlay-mount\""
                html `shouldSatisfy` Text.isInfixOf "hx-swap-oob=\"innerHTML\""
                Text.count "dialog-overlay-mount" html `shouldBe` 1

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

        it "opts keyboard dialogs into one generated content focus region" $ withContext do
            withCurrentControllerContext do
                let html = renderText (renderKeyboardDialogOverlay dialogConfig)

                html `shouldSatisfy` Text.isInfixOf "data-bepis-dialog-keyboard=\"true\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-dialog-focus-region=\"true\""
                renderText (renderDialogOverlay dialogConfig) `shouldSatisfy` not . Text.isInfixOf "data-bepis-dialog-keyboard"

        it "composes a supplemental generated close role without exposing raw attributes" $ withContext do
            withCurrentControllerContext do
                let html = renderText (renderDialogOverlayWithCloseRole @Passkey.PasskeyDismissal dialogConfig)

                html `shouldSatisfy` Text.isInfixOf "data-bepis-dialog-close=\"true\""
                html `shouldSatisfy` Text.isInfixOf "data-bepis-passkey-dismissal=\"true\""

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
    dialogConfig = defaultDialogOverlayConfig
            "Generated overlay"
            (HtmlRenderer.toHtml ("Body" :: Text))
            (defaultOverlayButtons "generated-overlay-form")

renderText :: Html -> Text
renderText = cs . HtmlRenderer.renderMarkupLazyText
