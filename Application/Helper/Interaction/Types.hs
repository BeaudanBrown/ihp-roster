module Application.Helper.Interaction.Types
    ( EmptyInteractionIntent
    , EmptyInteractionLayer
    , EmptyInteractionSession
    , HtmxMethod (..)
    , HtmxSwap (..)
    , InteractionActivationTrigger (..)
    , InteractionCapability (..)
    , InteractionConflictPolicy (..)
    , InteractionConflictResolution (..)
    , InteractionFieldPresence (..)
    , InteractionFragmentSelector (..)
    , InteractionIntentTarget (..)
    , InteractionMarkerKind (..)
    , InteractionMountKey (..)
    , InteractionMountLocalTarget (..)
    , InteractionSessionSelector (..)
    , IntentFieldName (..)
    , IntentFieldSchema (..)
    , IntentFormContract (..)
    , IntentHiddenField (..)
    , ServerLayerDefinition (..)
    , DisposableLayerDefinition (..)
    , SessionKindDefinition (..)
    , emptyInteractionCapability
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

data SessionKindDefinition session = SessionKindDefinition
    { sessionKind        :: !session
    , sessionKindName    :: !Text
    , sessionDescription :: !Text
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

data InteractionMarkerKind
    = InteractionItemMarker
    | InteractionContainerMarker
    | InteractionSlotMarker
    | InteractionDropzoneMarker
    | InteractionResizeHandleMarker
    | InteractionActivationMarker
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

data InteractionCapability fragmentRef fragment layer session intent = InteractionCapability
    { interactionServerLayers     :: ![ServerLayerDefinition]
    , interactionDisposableLayers :: ![DisposableLayerDefinition layer]
    , interactionSessionKinds     :: ![SessionKindDefinition session]
    , interactionIntentForms      :: ![IntentFormContract fragmentRef intent]
    , interactionConflictPolicies :: ![InteractionConflictPolicy fragment session]
    }
    deriving (Eq, Show)

emptyInteractionCapability :: InteractionCapability fragmentRef fragment layer session intent
emptyInteractionCapability =
    InteractionCapability
        { interactionServerLayers = []
        , interactionDisposableLayers = []
        , interactionSessionKinds = []
        , interactionIntentForms = []
        , interactionConflictPolicies = []
        }

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
