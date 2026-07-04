module Application.Helper.Interaction.Types
    ( EmptyInteractionIntent
    , EmptyInteractionLayer
    , EmptyInteractionSession
    , HtmxMethod (..)
    , HtmxSwap (..)
    , InteractionActivationTrigger (..)
    , InteractionCapability (..)
    , InteractionConflictPolicy (..)
    , InteractionDom (..)
    , InteractionDomAttributes (..)
    , InteractionDomValues (..)
    , InteractionPointerFields (..)
    , InteractionConflictResolution (..)
    , InteractionEffectSource (..)
    , InteractionFieldPresence (..)
    , InteractionFragmentSelector (..)
    , InteractionIntentSchema (..)
    , InteractionIntentTarget (..)
    , InteractionMountKey (..)
    , InteractionMountLocalTarget (..)
    , InteractionSessionContextualEffect (..)
    , InteractionSessionEffects (..)
    , InteractionSessionGlobalEffect (..)
    , InteractionSessionSelector (..)
    , InteractionStaticSchema (..)
    , IntentFieldName (..)
    , IntentFieldSchema (..)
    , IntentFormContract (..)
    , IntentHiddenField (..)
    , ServerLayerDefinition (..)
    , DisposableLayerDefinition (..)
    , SessionKindDefinition (..)
    , canonicalInteractionDom
    , emptyInteractionCapability
    , emptyInteractionSessionEffects
    , emptyInteractionStaticSchema
    , interactionCapabilityStaticSchema
    , htmxMethodValues
    , htmxSwapValues
    , interactionActivationTriggerValues
    , interactionConflictResolutionValues
    , interactionFieldPresenceValues
    ) where

import IHP.Prelude

-- | Marker types for existing live surfaces that have no interaction behavior
-- yet. Feature modules can replace these with closed feature-local ADTs for
-- layers, sessions, and intents as they opt in incrementally.
data EmptyInteractionLayer deriving (Eq, Show)
data EmptyInteractionSession deriving (Eq, Show)
data EmptyInteractionIntent deriving (Eq, Show)

data InteractionDomAttributes = InteractionDomAttributes
    { interactionDomSurfaceAttribute              :: !Text
    , interactionDomSurfaceFamilyAttribute        :: !Text
    , interactionDomScopeKeyAttribute             :: !Text
    , interactionDomMountKeyAttribute             :: !Text
    , interactionDomMarkerAttribute               :: !Text
    , interactionDomItemAttribute                 :: !Text
    , interactionDomContainerAttribute            :: !Text
    , interactionDomSlotAttribute                 :: !Text
    , interactionDomDropzoneAttribute             :: !Text
    , interactionDomResizeHandleAttribute         :: !Text
    , interactionDomActivationAttribute           :: !Text
    , interactionDomActivationIntentAttribute     :: !Text
    , interactionDomActivationTriggerAttribute    :: !Text
    , interactionDomActivationValueFieldAttribute :: !Text
    , interactionDomPointerSessionAttribute       :: !Text
    , interactionDomSessionKindAttribute          :: !Text
    , interactionDomSessionIntentAttribute        :: !Text
    , interactionDomSessionDisabledAttribute      :: !Text
    , interactionDomSessionReadOnlyAttribute      :: !Text
    , interactionDomSessionThresholdAttribute     :: !Text
    , interactionDomSessionTimeoutMsAttribute     :: !Text
    , interactionDomInteractionActiveAttribute    :: !Text
    , interactionDomServerLayerAttribute          :: !Text
    , interactionDomDisposableLayerAttribute      :: !Text
    , interactionDomLayerAttribute                :: !Text
    , interactionDomConflictPoliciesAttribute     :: !Text
    , interactionDomIntentFormAttribute           :: !Text
    , interactionDomIntentAttribute               :: !Text
    , interactionDomIntentFieldAttribute          :: !Text
    , interactionDomFieldPresenceAttribute        :: !Text
    , interactionDomIntentHiddenFieldAttribute    :: !Text
    }
    deriving (Eq, Show)

data InteractionDomValues = InteractionDomValues
    { interactionDomEnabledValue            :: !Text
    , interactionDomItemMarkerValue         :: !Text
    , interactionDomContainerMarkerValue    :: !Text
    , interactionDomSlotMarkerValue         :: !Text
    , interactionDomDropzoneMarkerValue     :: !Text
    , interactionDomResizeHandleMarkerValue :: !Text
    , interactionDomActivationMarkerValue   :: !Text
    }
    deriving (Eq, Show)

data InteractionPointerFields = InteractionPointerFields
    { interactionPointerSessionKindField       :: !Text
    , interactionPointerIdField                :: !Text
    , interactionPointerTypeField              :: !Text
    , interactionPointerStartClientXField      :: !Text
    , interactionPointerStartClientYField      :: !Text
    , interactionPointerCurrentClientXField    :: !Text
    , interactionPointerCurrentClientYField    :: !Text
    , interactionPointerDeltaXField            :: !Text
    , interactionPointerDeltaYField            :: !Text
    , interactionPointerSourceItemKeyField     :: !Text
    , interactionPointerTargetDropzoneKeyField :: !Text
    }
    deriving (Eq, Show)

data InteractionDom = InteractionDom
    { interactionDomAttributes    :: !InteractionDomAttributes
    , interactionDomValues        :: !InteractionDomValues
    , interactionDomPointerFields :: !InteractionPointerFields
    }
    deriving (Eq, Show)

canonicalInteractionDom :: InteractionDom
canonicalInteractionDom =
    InteractionDom
        { interactionDomAttributes = InteractionDomAttributes
            { interactionDomSurfaceAttribute = "data-bepis-surface"
            , interactionDomSurfaceFamilyAttribute = "data-bepis-surface-family"
            , interactionDomScopeKeyAttribute = "data-bepis-scope-key"
            , interactionDomMountKeyAttribute = "data-bepis-mount-key"
            , interactionDomMarkerAttribute = "data-bepis-marker"
            , interactionDomItemAttribute = "data-bepis-item"
            , interactionDomContainerAttribute = "data-bepis-container"
            , interactionDomSlotAttribute = "data-bepis-slot"
            , interactionDomDropzoneAttribute = "data-bepis-dropzone"
            , interactionDomResizeHandleAttribute = "data-bepis-resize-handle"
            , interactionDomActivationAttribute = "data-bepis-activation"
            , interactionDomActivationIntentAttribute = "data-bepis-activation-intent"
            , interactionDomActivationTriggerAttribute = "data-bepis-activation-trigger"
            , interactionDomActivationValueFieldAttribute = "data-bepis-activation-value-field"
            , interactionDomPointerSessionAttribute = "data-bepis-pointer-session"
            , interactionDomSessionKindAttribute = "data-bepis-session-kind"
            , interactionDomSessionIntentAttribute = "data-bepis-session-intent"
            , interactionDomSessionDisabledAttribute = "data-bepis-session-disabled"
            , interactionDomSessionReadOnlyAttribute = "data-bepis-session-read-only"
            , interactionDomSessionThresholdAttribute = "data-bepis-session-threshold"
            , interactionDomSessionTimeoutMsAttribute = "data-bepis-session-timeout-ms"
            , interactionDomInteractionActiveAttribute = "data-bepis-interaction-active"
            , interactionDomServerLayerAttribute = "data-bepis-server-layer"
            , interactionDomDisposableLayerAttribute = "data-bepis-disposable-layer"
            , interactionDomLayerAttribute = "data-bepis-layer"
            , interactionDomConflictPoliciesAttribute = "data-bepis-conflict-policies"
            , interactionDomIntentFormAttribute = "data-bepis-intent-form"
            , interactionDomIntentAttribute = "data-bepis-intent"
            , interactionDomIntentFieldAttribute = "data-bepis-intent-field"
            , interactionDomFieldPresenceAttribute = "data-bepis-field-presence"
            , interactionDomIntentHiddenFieldAttribute = "data-bepis-intent-hidden-field"
            }
        , interactionDomValues = InteractionDomValues
            { interactionDomEnabledValue = "true"
            , interactionDomItemMarkerValue = "item"
            , interactionDomContainerMarkerValue = "container"
            , interactionDomSlotMarkerValue = "slot"
            , interactionDomDropzoneMarkerValue = "dropzone"
            , interactionDomResizeHandleMarkerValue = "resize-handle"
            , interactionDomActivationMarkerValue = "activation"
            }
        , interactionDomPointerFields = InteractionPointerFields
            { interactionPointerSessionKindField = "sessionKind"
            , interactionPointerIdField = "pointerId"
            , interactionPointerTypeField = "pointerType"
            , interactionPointerStartClientXField = "startClientX"
            , interactionPointerStartClientYField = "startClientY"
            , interactionPointerCurrentClientXField = "currentClientX"
            , interactionPointerCurrentClientYField = "currentClientY"
            , interactionPointerDeltaXField = "deltaX"
            , interactionPointerDeltaYField = "deltaY"
            , interactionPointerSourceItemKeyField = "sourceItemKey"
            , interactionPointerTargetDropzoneKeyField = "targetDropzoneKey"
            }
        }

newtype InteractionMountKey = InteractionMountKey
    { unInteractionMountKey :: Text
    }
    deriving (Eq, Ord, Show)

data ServerLayerDefinition = ServerLayerDefinition
    { serverLayerName        :: !Text
    , serverLayerDomIdSuffix :: !Text
    }
    deriving (Eq, Show)

data DisposableLayerDefinition layer = DisposableLayerDefinition
    { disposableLayerKind        :: !layer
    , disposableLayerName        :: !Text
    , disposableLayerDomIdSuffix :: !Text
    }
    deriving (Eq, Show)

data InteractionEffectSource
    = InteractionEffectPointerMarker
    deriving (Eq, Show)

data InteractionSessionGlobalEffect
    = InteractionCloneShadowEffect
        { cloneShadowLayerName          :: !Text
        , cloneShadowSource             :: !InteractionEffectSource
        , cloneShadowClassName          :: !Text
        , cloneShadowPreserveGrabOffset :: !Bool
        }
    deriving (Eq, Show)

data InteractionSessionContextualEffect
    = InteractionDropzoneHighlightEffect
        { dropzoneHighlightClassName :: !Text
        }
    deriving (Eq, Show)

data InteractionSessionEffects = InteractionSessionEffects
    { interactionSessionGlobalEffects     :: ![InteractionSessionGlobalEffect]
    , interactionSessionContextualEffects :: ![InteractionSessionContextualEffect]
    }
    deriving (Eq, Show)

data SessionKindDefinition session = SessionKindDefinition
    { sessionKind        :: !session
    , sessionKindName    :: !Text
    , sessionDescription :: !Text
    , sessionEffects     :: !InteractionSessionEffects
    }
    deriving (Eq, Show)

newtype IntentFieldName = IntentFieldName
    { unIntentFieldName :: Text
    }
    deriving (Eq, Ord, Show)

data InteractionFieldPresence
    = IntentFieldRequired
    | IntentFieldOptional
    deriving (Eq, Show)

data IntentFieldSchema = IntentFieldSchema
    { intentFieldName         :: !IntentFieldName
    , intentFieldPresence     :: !InteractionFieldPresence
    , intentFieldDefaultValue :: !(Maybe Text)
    }
    deriving (Eq, Show)

data IntentHiddenField = IntentHiddenField
    { intentHiddenFieldName  :: !IntentFieldName
    , intentHiddenFieldValue :: !Text
    }
    deriving (Eq, Show)

data InteractionIntentSchema intent = InteractionIntentSchema
    { interactionIntentSchemaIntent :: !intent
    , interactionIntentSchemaName   :: !Text
    , interactionIntentSchemaFields :: ![IntentFieldSchema]
    }
    deriving (Eq, Show)

data HtmxMethod
    = HtmxGet
    | HtmxPost
    | HtmxPut
    | HtmxPatch
    | HtmxDelete
    deriving (Eq, Show)

data HtmxSwap
    = HtmxSwapInnerHtml
    | HtmxSwapOuterHtml
    | HtmxSwapBeforeEnd
    | HtmxSwapAfterBegin
    | HtmxSwapNone
    | HtmxSwapCustom !Text
    deriving (Eq, Show)

newtype InteractionMountLocalTarget = InteractionMountLocalTarget
    { unInteractionMountLocalTarget :: Text
    }
    deriving (Eq, Show)

data InteractionActivationTrigger
    = InteractionActivationClick
    | InteractionActivationChange
    | InteractionActivationKeydownEnter
    | InteractionActivationKeydownSpace
    deriving (Eq, Show)

data InteractionIntentTarget fragmentRef
    = IntentTargetLiveFragment !fragmentRef
    | IntentTargetMountLocal !InteractionMountLocalTarget
    deriving (Eq, Show)

data IntentFormContract fragmentRef intent = IntentFormContract
    { intentFormIntent          :: !intent
    , intentFormName            :: !Text
    , intentFormAction          :: !Text
    , intentFormMethod          :: !HtmxMethod
    , intentFormTrigger         :: !Text
    , intentFormTarget          :: !(InteractionIntentTarget fragmentRef)
    , intentFormSwap            :: !HtmxSwap
    , intentFormFields          :: ![IntentFieldSchema]
    , intentFormHiddenFields    :: ![IntentHiddenField]
    , intentFormSync            :: !(Maybe Text)
    , intentFormDisabledElement :: !(Maybe Text)
    }
    deriving (Eq, Show)

data InteractionSessionSelector session
    = AnyInteractionSession
    | InteractionSessionKind !session
    deriving (Eq, Show)

data InteractionFragmentSelector fragment
    = AnyInteractionFragment
    | InteractionFragment !fragment
    deriving (Eq, Show)

data InteractionConflictResolution
    = ApplyLiveFragmentImmediately
    | DeferLiveFragmentUntilSessionEnds
    | CancelSessionAndApplyLiveFragment
    deriving (Eq, Show)

data InteractionConflictPolicy fragment session = InteractionConflictPolicy
    { conflictPolicySession    :: !(InteractionSessionSelector session)
    , conflictPolicyFragment   :: !(InteractionFragmentSelector fragment)
    , conflictPolicyResolution :: !InteractionConflictResolution
    , conflictPolicyTimeoutMs  :: !(Maybe Int)
    }
    deriving (Eq, Show)

data InteractionStaticSchema fragment layer session intent = InteractionStaticSchema
    { interactionStaticServerLayers     :: ![ServerLayerDefinition]
    , interactionStaticDisposableLayers :: ![DisposableLayerDefinition layer]
    , interactionStaticSessionKinds     :: ![SessionKindDefinition session]
    , interactionStaticIntents          :: ![InteractionIntentSchema intent]
    , interactionStaticConflictPolicies :: ![InteractionConflictPolicy fragment session]
    }
    deriving (Eq, Show)

data InteractionCapability fragmentRef fragment layer session intent = InteractionCapability
    { interactionStaticSchema     :: !(InteractionStaticSchema fragment layer session intent)
    , interactionServerLayers     :: ![ServerLayerDefinition]
    , interactionDisposableLayers :: ![DisposableLayerDefinition layer]
    , interactionSessionKinds     :: ![SessionKindDefinition session]
    , interactionIntentForms      :: ![IntentFormContract fragmentRef intent]
    , interactionConflictPolicies :: ![InteractionConflictPolicy fragment session]
    }
    deriving (Eq, Show)

emptyInteractionSessionEffects :: InteractionSessionEffects
emptyInteractionSessionEffects =
    InteractionSessionEffects
        { interactionSessionGlobalEffects = []
        , interactionSessionContextualEffects = []
        }

emptyInteractionStaticSchema :: InteractionStaticSchema fragment layer session intent
emptyInteractionStaticSchema =
    InteractionStaticSchema
        { interactionStaticServerLayers = []
        , interactionStaticDisposableLayers = []
        , interactionStaticSessionKinds = []
        , interactionStaticIntents = []
        , interactionStaticConflictPolicies = []
        }

emptyInteractionCapability :: InteractionCapability fragmentRef fragment layer session intent
emptyInteractionCapability =
    InteractionCapability
        { interactionStaticSchema = emptyInteractionStaticSchema
        , interactionServerLayers = []
        , interactionDisposableLayers = []
        , interactionSessionKinds = []
        , interactionIntentForms = []
        , interactionConflictPolicies = []
        }

interactionCapabilityStaticSchema :: InteractionCapability fragmentRef fragment layer session intent -> InteractionStaticSchema fragment layer session intent
interactionCapabilityStaticSchema capability =
    capability.interactionStaticSchema

interactionFieldPresenceValues :: [(InteractionFieldPresence, Text)]
interactionFieldPresenceValues =
    [ (IntentFieldRequired, "required")
    , (IntentFieldOptional, "optional")
    ]

interactionActivationTriggerValues :: [(InteractionActivationTrigger, Text)]
interactionActivationTriggerValues =
    [ (InteractionActivationClick, "click")
    , (InteractionActivationChange, "change")
    , (InteractionActivationKeydownEnter, "keydown-enter")
    , (InteractionActivationKeydownSpace, "keydown-space")
    ]

htmxMethodValues :: [(HtmxMethod, Text)]
htmxMethodValues =
    [ (HtmxGet, "get")
    , (HtmxPost, "post")
    , (HtmxPut, "put")
    , (HtmxPatch, "patch")
    , (HtmxDelete, "delete")
    ]

htmxSwapValues :: [(HtmxSwap, Text)]
htmxSwapValues =
    [ (HtmxSwapInnerHtml, "innerHTML")
    , (HtmxSwapOuterHtml, "outerHTML")
    , (HtmxSwapBeforeEnd, "beforeend")
    , (HtmxSwapAfterBegin, "afterbegin")
    , (HtmxSwapNone, "none")
    ]

interactionConflictResolutionValues :: [(InteractionConflictResolution, Text)]
interactionConflictResolutionValues =
    [ (ApplyLiveFragmentImmediately, "apply")
    , (DeferLiveFragmentUntilSessionEnds, "defer")
    , (CancelSessionAndApplyLiveFragment, "cancel")
    ]
