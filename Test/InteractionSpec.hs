module Test.InteractionSpec where

import Application.Helper.Interaction
import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate.Runtime (LiveFragmentKey (..), LiveUpdateScope (..))
import IHP.Prelude
import Test.Hspec


tests :: Spec
tests = describe "Typed interaction surface capabilities" do
    it "wraps typed live surfaces with empty interaction capabilities" do
        let definition :: TypedInteractionSurfaceDefinition TestInteractionSurface () TestInteractionFragment EmptyInteractionLayer EmptyInteractionSession EmptyInteractionIntent
            definition = emptyInteractionSurfaceDefinition testLiveSurfaceDefinition
        let mount = mkInteractionSurfaceMount () (InteractionMountKey "primary")

        interactionSurfaceLiveConfig definition mount
            `shouldBe` mkTypedDefinedLiveSurface testLiveSurfaceDefinition ()
        typedInteractionCapabilityFor definition ()
            `shouldBe` emptyInteractionCapability

    it "uses concrete mount keys to derive distinct mount-local ids" do
        let definition = emptyInteractionSurfaceDefinition testLiveSurfaceDefinition
        let primaryMount = mkInteractionSurfaceMount () (InteractionMountKey "primary")
        let duplicateMount = mkInteractionSurfaceMount () (InteractionMountKey "duplicate")
        let layer = DisposableLayerDefinition DragPreviewLayer "drag-preview" "drag-preview"
        let form = moveIntentForm (testFragmentRef TestInteractionContent)

        interactionMountDomId definition primaryMount
            `shouldBe` "bepis-surface--test-interaction--support-platform--primary"
        interactionMountDomId definition duplicateMount
            `shouldBe` "bepis-surface--test-interaction--support-platform--duplicate"
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


data TestInteractionSurface

data TestInteractionFragment = TestInteractionContent deriving (Eq, Show)

data TestDisposableLayer = DragPreviewLayer deriving (Eq, Show)

data TestInteractionSession = DragSession deriving (Eq, Show)

data TestInteractionIntent = MoveCardIntent deriving (Eq, Show)

testLiveSurfaceDefinition :: TypedLiveSurfaceDefinition TestInteractionSurface () TestInteractionFragment
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
        }

testInteractionCapability :: () -> InteractionCapability TestInteractionSurface TestInteractionFragment TestDisposableLayer TestInteractionSession TestInteractionIntent
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

moveIntentForm :: SurfaceFragmentRef TestInteractionSurface -> IntentFormContract TestInteractionSurface TestInteractionIntent
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
