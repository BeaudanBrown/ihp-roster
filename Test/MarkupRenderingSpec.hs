{-# LANGUAGE QuasiQuotes #-}
{-# LANGUAGE TypeApplications #-}

module Test.MarkupRenderingSpec (tests) where

import Application.Helper.FrontendContract.AppShell (CreateTrialStaffInvitationOverlay, OpenRosterShiftDialog)
import Application.Helper.FrontendContract.AppShell.Runtime
import Application.Helper.FrontendContract.Surface.ContractIR (InteractionDropzoneRefIR (..))
import Application.Helper.FrontendContract.Surface.Interaction
import qualified Data.Text as Text
import IHP.HSX.Markup (renderMarkupText)
import IHP.HSX.MarkupQQ (hsx)
import IHP.Prelude
import Test.Hspec

-- These tests exercise the same construction-time spread seam used by views,
-- without needing a model context or the application controller graph.
tests :: Spec
tests = describe "Markup rendering" do
    it "escapes dynamic body and attribute values once, preserving Unicode" do
        let value = "<script>&\" café 🐈" :: Text
        let attributes = [("title", value)]
        renderMarkupText [hsx|<button {...attributes}>{value}</button>|]
            `shouldBe` "<button title=\"&lt;script&gt;&amp;&quot; café 🐈\">&lt;script&gt;&amp;&quot; café 🐈</button>"

    it "omits false native booleans but retains false data and aria state" do
        renderMarkupText [hsx|<input disabled={False} checked={False} data-enabled={False} aria-disabled={Just ("false" :: Text)}/>|]
            `shouldBe` "<input data-enabled=\"false\" aria-disabled=\"false\">"

    it "attaches typed action attributes only to the selected root" do
        let action = appShellActionByMarker @OpenRosterShiftDialog
        let route = defaultAppShellActionRoute "/dialog?label=\"<&"
        let attributes = appShellActionAttrs action route
        let rendered = renderMarkupText [hsx|<button {...attributes}><span>Open</span></button><p>Unaffected</p>|]
        rendered `shouldSatisfy` Text.isInfixOf "hx-get=\"/dialog?label=&quot;&lt;&amp;\""
        rendered `shouldSatisfy` Text.isInfixOf "><span>Open</span></button><p>Unaffected</p>"
        Text.count "hx-get=" rendered `shouldBe` 1

    it "preserves native POST fallback and one escaped hidden field per value" do
        let action = appShellActionByMarker @CreateTrialStaffInvitationOverlay
        let route = (defaultAppShellActionRoute "/enhanced")
                { appShellActionRouteStandardUrl = Just "/native?a=1&b=2"
                , appShellActionRouteFields = [AppShellFieldValue ("invitationEmail", "a\"<&@example.test")]
                }
        let rendered = renderMarkupText (renderAppShellActionForm action route [hsx|<button type="submit">Send</button>|])
        rendered `shouldSatisfy` Text.isInfixOf "method=\"post\" action=\"/native?a=1&amp;b=2\""
        rendered `shouldSatisfy` Text.isInfixOf "hx-post=\"/enhanced\""
        rendered `shouldSatisfy` Text.isInfixOf "<input type=\"hidden\" name=\"invitationEmail\" value=\"a&quot;&lt;&amp;@example.test\">"
        Text.count "name=\"invitationEmail\"" rendered `shouldBe` 1

    it "uses identical typed dropzone attributes for wrapper and caller-owned roots" do
        let ref = InteractionDropzoneRefIR "FixtureDropzone" "fixture-dropzone" "drag" "target"
        let key = "opaque:<&\"雪"
        let attributes = frontendSurfaceDropzoneRefAttrs ref key
        let body = [hsx|<span>Target</span>|]
        renderMarkupText (renderFrontendSurfaceDropzoneRef ref key body)
            `shouldBe` renderMarkupText [hsx|<div {...attributes}>{body}</div>|]
        renderMarkupText [hsx|<section {...attributes}>{body}</section>|]
            `shouldSatisfy` Text.isInfixOf "opaque:&lt;&amp;&quot;雪"
