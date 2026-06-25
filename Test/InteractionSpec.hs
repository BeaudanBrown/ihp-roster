module Test.InteractionSpec where

import Application.Helper.Interaction
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate.Runtime (LiveFragmentKey (..),
                                              LiveUpdateScope (..))
import qualified Data.Text as Text
import IHP.Prelude
import Test.Hspec
import qualified Text.Blaze.Html.Renderer.Text as HtmlRenderer
import qualified Text.Blaze.Html5 as Html5


tests :: Spec
tests = describe "Typed interaction surface capabilities" do
    it "wraps typed live surfaces with empty interaction capabilities" do
        let definition :: TypedInteractionSurfaceDefinition TestInteractionSurface () TestInteractionFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
            definition = emptyInteractionSurfaceDefinition emptyTestLiveSurfaceDefinition
        let mount = mkInteractionSurfaceMount () (InteractionMountKey "primary")

        interactionSurfaceLiveConfig definition mount
            `shouldBe` mkTypedDefinedLiveSurface emptyTestLiveSurfaceDefinition ()
        typedInteractionCapabilityFor definition ()
            `shouldBe` emptyInteractionCapability

    it "uses concrete mount keys to derive distinct mount-local ids" do
        let definition = testLiveSurfaceDefinition
        let primaryMount = mkInteractionSurfaceMount () (InteractionMountKey "primary")
        let duplicateMount = mkInteractionSurfaceMount () (InteractionMountKey "duplicate")
        let layer = DisposableLayerDefinition DragPreviewLayer "drag-preview" "drag-preview"
        let form = moveIntentForm (testFragmentRef TestInteractionContent)

        interactionMountDomId definition primaryMount
            `shouldBe` "bepis-surface--test-interaction--support-platform--primary"
        interactionMountDomId definition duplicateMount
            `shouldBe` "bepis-surface--test-interaction--support-platform--duplicate"
        serverLayerDomId definition primaryMount ServerLayerDefinition { serverLayerName = "server", serverLayerDomIdSuffix = "server" }
            `shouldBe` "bepis-surface--test-interaction--support-platform--primary--server-layer--server"
        disposableLayerDomId definition primaryMount layer
            `shouldBe` "bepis-surface--test-interaction--support-platform--primary--disposable-layer--drag-preview"
        interactionFormDomId definition duplicateMount form
            `shouldBe` "bepis-surface--test-interaction--support-platform--duplicate--intent-form--move-card"

    it "models server-owned HTMX intent form contracts and typed live-fragment conflict policy" do
        let capability = testInteractionCapability ()

        map (.serverLayerName) capability.interactionServerLayers
            `shouldBe` ["server"]
        map (.disposableLayerKind) capability.interactionDisposableLayers
            `shouldBe` [DragPreviewLayer]
        map (.sessionKind) capability.interactionSessionKinds
            `shouldBe` [DragSession]
        map (.intentFormIntent) capability.interactionIntentForms
            `shouldBe` [MoveCardIntent]
        case capability.interactionIntentForms of
            [form] -> do
                map (.intentFieldName) form.intentFormFields
                    `shouldBe` [IntentFieldName "cardId", IntentFieldName "targetSlotId"]
                map (.intentHiddenFieldName) form.intentFormHiddenFields
                    `shouldBe` [IntentFieldName "intent"]
                htmxMethodAttribute form.intentFormMethod
                    `shouldBe` "post"
                htmxSwapAttribute form.intentFormSwap
                    `shouldBe` "outerHTML"
            forms -> expectationFailure (cs ("Expected one intent form, got " <> show (length forms) :: Text))
        capability.interactionConflictPolicies
            `shouldBe`
                [ InteractionConflictPolicy
                    { conflictPolicySession = InteractionSessionKind DragSession
                    , conflictPolicyFragment = InteractionFragment TestInteractionContent
                    , conflictPolicyResolution = DeferLiveFragmentUntilSessionEnds
                    , conflictPolicyTimeoutMs = Just 1500
                    }
                ]

    it "renders mount, layers, markers, and HTMX intent forms from typed contracts" do
        let mount = mkInteractionSurfaceMount () (InteractionMountKey "primary")
        let html = renderText do
                renderInteractionCapabilityShell testLiveSurfaceDefinition mount do
                    renderInteractionItemMarker "card-1" (Html5.toHtml ("Card 1" :: Text))

        html `shouldContainText` "id=\"bepis-surface--test-interaction--support-platform--primary\""
        html `shouldContainText` "data-live-update-surface=\"{&quot;decorateRequestsWithin&quot;:[],&quot;feature&quot;:&quot;test-interaction&quot;"
        html `shouldContainText` "data-bepis-surface=\"true\""
        html `shouldContainText` "id=\"bepis-surface--test-interaction--support-platform--primary--server-layer--server\""
        html `shouldContainText` "data-bepis-server-layer=\"server\""
        html `shouldContainText` "data-bepis-marker=\"item\" data-bepis-item=\"card-1\""
        html `shouldContainText` "data-bepis-disposable-layer=\"drag-preview\""
        html `shouldContainText` "data-bepis-conflict-policies=\""
        html `shouldContainText` "&quot;session&quot;:&quot;drag&quot;"
        html `shouldContainText` "&quot;targetId&quot;:&quot;test-interaction-content&quot;"
        html `shouldContainText` "&quot;resolution&quot;:&quot;defer&quot;"
        html `shouldContainText` "data-bepis-intent-form=\"move-card\""
        html `shouldContainText` "action=\"/MoveCard\" hx-post=\"/MoveCard\""
        html `shouldContainText` "hx-trigger=\"bepis:intent-submit from:this\""
        html `shouldContainText` "hx-target=\"#test-interaction-content\""
        html `shouldContainText` "hx-swap=\"outerHTML\""
        html `shouldContainText` "hx-sync=\"closest [data-bepis-surface]:queue\""
        html `shouldContainText` "hx-disabled-elt=\"find button\""
        html `shouldContainText` "name=\"cardId\" value=\"\" data-bepis-intent-field=\"cardId\" data-bepis-field-presence=\"required\""
        html `shouldContainText` "name=\"intent\" value=\"move-card\" data-bepis-intent-hidden-field=\"intent\""

    it "renders generic activation intent markers from typed helpers" do
        let html = renderText do
                renderInteractionActivationIntentMarker "layout-day-columns" "set-roster-layout-mode" InteractionActivationChange (Just (IntentFieldName "rosterLayoutMode")) do
                    Html5.toHtml ("Day columns" :: Text)

        html `shouldContainText` "data-bepis-marker=\"activation\""
        html `shouldContainText` "data-bepis-activation=\"layout-day-columns\""
        html `shouldContainText` "data-bepis-activation-intent=\"set-roster-layout-mode\""
        html `shouldContainText` "data-bepis-activation-trigger=\"change\""
        html `shouldContainText` "data-bepis-activation-value-field=\"rosterLayoutMode\""

    it "renders generic pointer session markers from typed helpers" do
        let html = renderText do
                renderInteractionPointerSessionMarker "card-1" "drag" "move-card" do
                    Html5.toHtml ("Card 1" :: Text)

        html `shouldContainText` "data-bepis-marker=\"item\""
        html `shouldContainText` "data-bepis-item=\"card-1\""
        html `shouldContainText` "data-bepis-pointer-session=\"true\""
        html `shouldContainText` "data-bepis-session-kind=\"drag\""
        html `shouldContainText` "data-bepis-session-intent=\"move-card\""
        renderText (withInteractionDropzoneMarker "slot-1" (Html5.div (Html5.toHtml ("Slot 1" :: Text))))
            `shouldContainText` "data-bepis-marker=\"dropzone\" data-bepis-dropzone=\"slot-1\""

    it "derives mount-local intent targets for duplicate mounts" do
        let form = (moveIntentForm (testFragmentRef TestInteractionContent))
                { intentFormTarget = IntentTargetMountLocal (InteractionMountLocalTarget "selection-panel")
                }
        let primaryMount = mkInteractionSurfaceMount () (InteractionMountKey "primary")
        let duplicateMount = mkInteractionSurfaceMount () (InteractionMountKey "duplicate")

        interactionIntentTargetSelector testLiveSurfaceDefinition primaryMount form.intentFormTarget
            `shouldBe` "#bepis-surface--test-interaction--support-platform--primary--selection-panel"
        renderText (renderInteractionIntentForm testLiveSurfaceDefinition duplicateMount form)
            `shouldContainText` "hx-target=\"#bepis-surface--test-interaction--support-platform--duplicate--selection-panel\""


data TestInteractionSurface

data TestInteractionFragment = TestInteractionContent deriving (Eq, Show)

data TestDisposableLayer = DragPreviewLayer deriving (Eq, Show)

data TestInteractionSession = DragSession deriving (Eq, Show)

data TestInteractionIntent = MoveCardIntent deriving (Eq, Show)

testLiveSurfaceDefinition :: TypedLiveSurfaceDefinition TestInteractionSurface () TestInteractionFragment TestDisposableLayer TestInteractionSession TestInteractionIntent
testLiveSurfaceDefinition =
    TypedLiveSurfaceDefinition
        { typedSurfaceFeature = "test-interaction"
        , typedSurfaceScope = const (SurfaceScope SupportPlatformScope)
        , typedSurfaceScopeFromWire = const (Just ())
        , typedSurfaceDefaultFragments = const [TestInteractionContent]
        , typedSurfaceFragmentContract = \() fragment ->
            mkSurfaceFragmentContract
                (testFragmentRef fragment)
                (liveFragmentResyncOnly "test interaction fragment")
        , typedSurfaceDecorateRequestsWithin = const []
        , typedSurfaceAuthorize = LiveSurfaceAuthorization { authorizeLiveSurfaceScope = const (pure True) }
        , typedSurfaceInteraction = testInteractionCapability
        }

emptyTestLiveSurfaceDefinition :: TypedLiveSurfaceDefinition TestInteractionSurface () TestInteractionFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
emptyTestLiveSurfaceDefinition =
    testLiveSurfaceDefinition { typedSurfaceInteraction = const emptyInteractionCapability }

testInteractionCapability :: () -> InteractionCapability (SurfaceFragmentRef TestInteractionSurface) TestInteractionFragment TestDisposableLayer TestInteractionSession TestInteractionIntent
testInteractionCapability () =
    InteractionCapability
        { interactionServerLayers =
            [ ServerLayerDefinition
                { serverLayerName = "server"
                , serverLayerDomIdSuffix = "server"
                }
            ]
        , interactionDisposableLayers =
            [ DisposableLayerDefinition
                { disposableLayerKind = DragPreviewLayer
                , disposableLayerName = "drag-preview"
                , disposableLayerDomIdSuffix = "drag-preview"
                }
            ]
        , interactionSessionKinds =
            [ SessionKindDefinition
                { sessionKind = DragSession
                , sessionKindName = "drag"
                , sessionDescription = "Local drag preview session"
                }
            ]
        , interactionIntentForms = [moveIntentForm (testFragmentRef TestInteractionContent)]
        , interactionConflictPolicies =
            [ InteractionConflictPolicy
                { conflictPolicySession = InteractionSessionKind DragSession
                , conflictPolicyFragment = InteractionFragment TestInteractionContent
                , conflictPolicyResolution = DeferLiveFragmentUntilSessionEnds
                , conflictPolicyTimeoutMs = Just 1500
                }
            ]
        }

moveIntentForm :: SurfaceFragmentRef TestInteractionSurface -> IntentFormContract (SurfaceFragmentRef TestInteractionSurface) TestInteractionIntent
moveIntentForm targetRef =
    IntentFormContract
        { intentFormIntent = MoveCardIntent
        , intentFormName = "move-card"
        , intentFormAction = "/MoveCard"
        , intentFormMethod = HtmxPost
        , intentFormTrigger = "bepis:intent-submit from:this"
        , intentFormTarget = IntentTargetLiveFragment targetRef
        , intentFormSwap = HtmxSwapOuterHtml
        , intentFormFields =
            [ IntentFieldSchema (IntentFieldName "cardId") IntentFieldRequired Nothing
            , IntentFieldSchema (IntentFieldName "targetSlotId") IntentFieldRequired Nothing
            ]
        , intentFormHiddenFields = [IntentHiddenField (IntentFieldName "intent") "move-card"]
        , intentFormSync = Just "closest [data-bepis-surface]:queue"
        , intentFormDisabledElement = Just "find button"
        }

testFragmentRef :: TestInteractionFragment -> SurfaceFragmentRef TestInteractionSurface
testFragmentRef TestInteractionContent =
    mkSurfaceFragmentRef RosterContentFragment "test-interaction-content" "/test-interaction-content"

renderText :: Html5.Html -> Text
renderText =
    cs . HtmlRenderer.renderHtml

shouldContainText :: Text -> Text -> Expectation
shouldContainText haystack needle =
    unless (needle `Text.isInfixOf` haystack) do
        expectationFailure (cs ("Expected rendered HTML to contain: " <> needle <> "\nRendered HTML:\n" <> haystack :: Text))
