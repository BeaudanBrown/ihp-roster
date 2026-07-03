module Test.InteractionSpec where

import qualified Application.Helper.Frontend.Dto.Interaction as InteractionDto
import qualified Application.Helper.Frontend.Generic as Frontend
import Application.Helper.Interaction
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate.Runtime (LiveFragmentKey (..),
                                              LiveUpdateScope (..))
import qualified Data.Text as Text
import qualified Data.UUID as UUID
import Generated.Types
import IHP.Prelude
import Test.Hspec
import qualified Text.Blaze.Html.Renderer.Text as HtmlRenderer
import qualified Text.Blaze.Html5 as Html5
import Web.RosterWeeks.FrontendSurface (RosterMountedFragmentPlan (..),
                                        RosterWeekScopeValue (..),
                                        renderRosterFrontendSurfaceInteractionShell,
                                        rosterDragSessionKindName,
                                        rosterLayoutModeIntentFieldName,
                                        rosterLayoutModeIntentName,
                                        rosterMoveShiftIntentName,
                                        rosterSurfaceImpl)


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

    it "models scope-free static concepts separately from runtime HTMX intent forms" do
        let staticSchema = typedInteractionStaticSchemaFor testLiveSurfaceDefinition
        let capability = testInteractionCapability ()

        map (.serverLayerName) staticSchema.interactionStaticServerLayers
            `shouldBe` ["server"]
        map (.disposableLayerKind) staticSchema.interactionStaticDisposableLayers
            `shouldBe` [DragPreviewLayer]
        map (.sessionKind) staticSchema.interactionStaticSessionKinds
            `shouldBe` [DragSession]
        map (.interactionIntentSchemaIntent) staticSchema.interactionStaticIntents
            `shouldBe` [MoveCardIntent]
        map (.interactionIntentSchemaFields) staticSchema.interactionStaticIntents
            `shouldBe` [[IntentFieldSchema (IntentFieldName "cardId") IntentFieldRequired Nothing, IntentFieldSchema (IntentFieldName "targetSlotId") IntentFieldRequired Nothing]]
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
        staticSchema.interactionStaticConflictPolicies
            `shouldBe`
                [ InteractionConflictPolicy
                    { conflictPolicySession = InteractionSessionKind DragSession
                    , conflictPolicyFragment = InteractionFragment TestInteractionContent
                    , conflictPolicyResolution = DeferLiveFragmentUntilSessionEnds
                    , conflictPolicyTimeoutMs = Just 1500
                    }
                ]
        interactionCapabilityStaticSchema capability `shouldBe` staticSchema

    it "enumerates roster interaction concepts from FrontendSurface-generated schemas" do
        let schema = InteractionDto.interactionStaticSchemasDto.roster

        map (.name) schema.disposableLayers
            `shouldBe` [InteractionDto.InteractionDisposableLayerName "drag-preview"]
        map (.kind) schema.sessionKinds
            `shouldBe` [InteractionDto.InteractionSessionKindName rosterDragSessionKindName]
        map (.effects) schema.sessionKinds
            `shouldBe`
                [ InteractionDto.InteractionSessionEffects
                    { InteractionDto.global =
                        [ InteractionDto.CloneShadow
                            { layer = InteractionDto.InteractionDisposableLayerName "drag-preview"
                            , source = InteractionDto.InteractionEffectSource "pointer-marker"
                            , className = "bepis-pointer-clone-shadow"
                            , preserveGrabOffset = True
                            }
                        ]
                    , InteractionDto.contextual =
                        [ InteractionDto.DropzoneHighlight
                            { className = "bepis-dropzone-highlight"
                            }
                        ]
                    }
                ]
        map (.name) schema.intents
            `shouldBe` [InteractionDto.InteractionIntentName rosterLayoutModeIntentName, InteractionDto.InteractionIntentName rosterMoveShiftIntentName]
        map (.name) (concatMap (.fields) schema.intents)
            `shouldContain` [InteractionDto.InteractionIntentFieldName rosterLayoutModeIntentFieldName]
        schema.conflictPolicies
            `shouldBe`
                [ InteractionDto.InteractionConflictPolicy
                    { session = InteractionDto.Session { session = InteractionDto.InteractionSessionKindName rosterDragSessionKindName }
                    , fragment = InteractionDto.AnyFragment
                    , resolution = InteractionDto.Defer
                    , timeoutMs = Frontend.FrontendOptional (Just (Frontend.FrontendNullable (Just 5000)))
                    }
                ]

    it "renders roster interaction shell and forms from FrontendSurface runtime metadata" do
        let venueId = expectUuid "11111111-1111-1111-1111-111111111111"
        let rosterGroupId = "22222222-2222-2222-2222-222222222222" :: Id RosterGroup
        let surface = rosterSurfaceImpl
                RosterWeekScopeValue { rosterWeekVenueId = venueId, rosterWeekGroupId = rosterGroupId, rosterWeekWeekOffset = 0 }
                RosterMountedFragmentPlan { rosterMountedDayIds = [], rosterMountedRows = [] }
        let html = renderText do
                renderRosterFrontendSurfaceInteractionShell surface do
                    Html5.toHtml ("Roster" :: Text)

        html `shouldContainText` "data-bepis-surface=\"true\""
        html `shouldContainText` "data-bepis-surface-family=\"roster\""
        html `shouldContainText` "data-bepis-disposable-layer=\"drag-preview\""
        html `shouldContainText` "data-bepis-conflict-policies=\""
        html `shouldContainText` "&quot;session&quot;:&quot;drag&quot;"
        html `shouldContainText` "&quot;resolution&quot;:&quot;defer&quot;"
        html `shouldContainText` "data-bepis-intent-form=\"set-roster-layout-mode\""
        html `shouldContainText` "data-bepis-intent-form=\"move-roster-shift-to-slot\""
        html `shouldContainText` "hx-trigger=\"bepis:intent-submit\""
        html `shouldContainText` "hx-target=\"#roster-content\""
        html `shouldContainText` "name=\"rosterLayoutMode\" value=\"day_rows\" data-bepis-intent-field=\"rosterLayoutMode\" data-bepis-field-presence=\"required\""
        html `shouldContainText` "name=\"sessionKind\" value=\"\" data-bepis-intent-field=\"sessionKind\" data-bepis-field-presence=\"optional\""

    it "renders mount, layers, markers, and HTMX intent forms from typed contracts" do
        let mount = mkInteractionSurfaceMount () (InteractionMountKey "primary")
        let html = renderText do
                renderInteractionCapabilityShell testLiveSurfaceDefinition mount do
                    renderInteractionItemMarker "card-1" (Html5.toHtml ("Card 1" :: Text))

        html `shouldContainText` "id=\"bepis-surface--test-interaction--support-platform--primary\""
        html `shouldNotContainText` "data-live-update-surface"
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
        , typedSurfaceInteractionSchema = testInteractionStaticSchema
        , typedSurfaceInteraction = testInteractionCapability
        }

emptyTestLiveSurfaceDefinition :: TypedLiveSurfaceDefinition TestInteractionSurface () TestInteractionFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
emptyTestLiveSurfaceDefinition =
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
        , typedSurfaceInteractionSchema = emptyInteractionStaticSchema
        , typedSurfaceInteraction = const emptyInteractionCapability
        }

testInteractionStaticSchema :: InteractionStaticSchema TestInteractionFragment TestDisposableLayer TestInteractionSession TestInteractionIntent
testInteractionStaticSchema =
    emptyInteractionStaticSchema
        { interactionStaticServerLayers =
            [ ServerLayerDefinition
                { serverLayerName = "server"
                , serverLayerDomIdSuffix = "server"
                }
            ]
        , interactionStaticDisposableLayers =
            [ DisposableLayerDefinition
                { disposableLayerKind = DragPreviewLayer
                , disposableLayerName = "drag-preview"
                , disposableLayerDomIdSuffix = "drag-preview"
                }
            ]
        , interactionStaticSessionKinds =
            [ SessionKindDefinition
                { sessionKind = DragSession
                , sessionKindName = "drag"
                , sessionDescription = "Local drag preview session"
                , sessionEffects = emptyInteractionSessionEffects
                }
            ]
        , interactionStaticIntents =
            [ InteractionIntentSchema
                { interactionIntentSchemaIntent = MoveCardIntent
                , interactionIntentSchemaName = "move-card"
                , interactionIntentSchemaFields =
                    [ IntentFieldSchema (IntentFieldName "cardId") IntentFieldRequired Nothing
                    , IntentFieldSchema (IntentFieldName "targetSlotId") IntentFieldRequired Nothing
                    ]
                }
            ]
        , interactionStaticConflictPolicies =
            [ InteractionConflictPolicy
                { conflictPolicySession = InteractionSessionKind DragSession
                , conflictPolicyFragment = InteractionFragment TestInteractionContent
                , conflictPolicyResolution = DeferLiveFragmentUntilSessionEnds
                , conflictPolicyTimeoutMs = Just 1500
                }
            ]
        }

testInteractionCapability :: () -> InteractionCapability (SurfaceFragmentRef TestInteractionSurface) TestInteractionFragment TestDisposableLayer TestInteractionSession TestInteractionIntent
testInteractionCapability () =
    emptyInteractionCapability
        { interactionStaticSchema = testInteractionStaticSchema
        , interactionServerLayers = testInteractionStaticSchema.interactionStaticServerLayers
        , interactionDisposableLayers = testInteractionStaticSchema.interactionStaticDisposableLayers
        , interactionSessionKinds = testInteractionStaticSchema.interactionStaticSessionKinds
        , interactionIntentForms = [moveIntentForm (testFragmentRef TestInteractionContent)]
        , interactionConflictPolicies = testInteractionStaticSchema.interactionStaticConflictPolicies
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

expectUuid :: Text -> UUID.UUID
expectUuid value =
    fromMaybe (error ("invalid test UUID: " <> cs value)) (UUID.fromString (cs value))

shouldContainText :: Text -> Text -> Expectation
shouldContainText haystack needle =
    unless (needle `Text.isInfixOf` haystack) do
        expectationFailure (cs ("Expected rendered HTML to contain: " <> needle <> "\nRendered HTML:\n" <> haystack :: Text))

shouldNotContainText :: Text -> Text -> Expectation
shouldNotContainText haystack needle =
    when (needle `Text.isInfixOf` haystack) do
        expectationFailure (cs ("Expected rendered HTML not to contain: " <> needle <> "\nRendered HTML:\n" <> haystack :: Text))
