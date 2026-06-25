module Application.Helper.Interaction
    ( EmptyInteractionIntent
    , EmptyInteractionLayer
    , EmptyInteractionSession
    , HtmxMethod (..)
    , HtmxSwap (..)
    , InteractionCapability (..)
    , InteractionConflictPolicy (..)
    , InteractionConflictResolution (..)
    , InteractionFieldPresence (..)
    , InteractionFragmentSelector (..)
    , InteractionIntentTarget (..)
    , InteractionMountKey (..)
    , InteractionMountLocalTarget (..)
    , InteractionSessionSelector (..)
    , InteractionSurfaceMount (..)
    , IntentFieldName (..)
    , IntentFieldSchema (..)
    , IntentFormContract (..)
    , IntentHiddenField (..)
    , ServerLayerDefinition (..)
    , DisposableLayerDefinition (..)
    , SessionKindDefinition (..)
    , TypedInteractionSurfaceDefinition (..)
    , disposableLayerDomId
    , emptyInteractionCapability
    , htmxMethodValues
    , htmxSwapValues
    , interactionConflictResolutionValues
    , interactionFieldPresenceValues
    , emptyInteractionSurfaceDefinition
    , htmxMethodAttribute
    , htmxSwapAttribute
    , interactionFormDomId
    , interactionSurfaceLiveConfig
    , interactionMountDomId
    , mkInteractionSurfaceMount
    , typedInteractionCapabilityFor
    ) where

import Application.Helper.LiveSurface
import Application.Helper.LiveUpdate (liveUpdateScopeKey)
import qualified Data.Char as Char
import qualified Data.Text as Text
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

data InteractionSurfaceMount scope = InteractionSurfaceMount
    { interactionMountScope :: !scope
    , interactionMountKey   :: !InteractionMountKey
    }
    deriving (Eq, Show)

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

data InteractionIntentTarget surface
    = IntentTargetLiveFragment !(SurfaceFragmentRef surface)
    | IntentTargetMountLocal !InteractionMountLocalTarget
    deriving (Eq, Show)

data IntentFormContract surface intent = IntentFormContract
    { intentFormIntent          :: !intent
    , intentFormName            :: !Text
    , intentFormAction          :: !Text
    , intentFormMethod          :: !HtmxMethod
    , intentFormTrigger         :: !Text
    , intentFormTarget          :: !(InteractionIntentTarget surface)
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
    { conflictPolicySession   :: !(InteractionSessionSelector session)
    , conflictPolicyFragment  :: !(InteractionFragmentSelector fragment)
    , conflictPolicyResolution :: !InteractionConflictResolution
    , conflictPolicyTimeoutMs :: !(Maybe Int)
    }
    deriving (Eq, Show)

data InteractionCapability surface fragment layer session intent = InteractionCapability
    { interactionServerLayers     :: ![ServerLayerDefinition]
    , interactionDisposableLayers :: ![DisposableLayerDefinition layer]
    , interactionSessionKinds     :: ![SessionKindDefinition session]
    , interactionIntentForms      :: ![IntentFormContract surface intent]
    , interactionConflictPolicies :: ![InteractionConflictPolicy fragment session]
    }
    deriving (Eq, Show)

-- | Interaction metadata attached to the same typed live-surface origin as live
-- fragments. The live definition remains the source for family/scope/fragments;
-- the capability adds optional mount-local layers, sessions, intents, forms,
-- and conflict policy for each scope.
data TypedInteractionSurfaceDefinition surface scope fragment layer session intent = TypedInteractionSurfaceDefinition
    { interactionSurfaceLiveDefinition :: !(TypedLiveSurfaceDefinition surface scope fragment)
    , interactionSurfaceCapability     :: scope -> InteractionCapability surface fragment layer session intent
    }

mkInteractionSurfaceMount :: scope -> InteractionMountKey -> InteractionSurfaceMount scope
mkInteractionSurfaceMount interactionMountScope interactionMountKey =
    InteractionSurfaceMount { interactionMountScope, interactionMountKey }

emptyInteractionCapability :: InteractionCapability surface fragment layer session intent
emptyInteractionCapability =
    InteractionCapability
        { interactionServerLayers = []
        , interactionDisposableLayers = []
        , interactionSessionKinds = []
        , interactionIntentForms = []
        , interactionConflictPolicies = []
        }

emptyInteractionSurfaceDefinition ::
    TypedLiveSurfaceDefinition surface scope fragment ->
    TypedInteractionSurfaceDefinition surface scope fragment layer session intent
emptyInteractionSurfaceDefinition interactionSurfaceLiveDefinition =
    TypedInteractionSurfaceDefinition
        { interactionSurfaceLiveDefinition
        , interactionSurfaceCapability = const emptyInteractionCapability
        }

typedInteractionCapabilityFor ::
    TypedInteractionSurfaceDefinition surface scope fragment layer session intent ->
    scope ->
    InteractionCapability surface fragment layer session intent
typedInteractionCapabilityFor definition scope =
    definition.interactionSurfaceCapability scope

interactionSurfaceLiveConfig ::
    TypedInteractionSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    LiveSurfaceConfig
interactionSurfaceLiveConfig definition mount =
    mkTypedDefinedLiveSurface definition.interactionSurfaceLiveDefinition mount.interactionMountScope

interactionMountDomId ::
    TypedInteractionSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    Text
interactionMountDomId definition mount =
    let surfaceScope = unSurfaceScope (definition.interactionSurfaceLiveDefinition.typedSurfaceScope mount.interactionMountScope)
     in Text.intercalate
            "--"
            [ "bepis-surface"
            , domIdSegment definition.interactionSurfaceLiveDefinition.typedSurfaceFeature
            , domIdSegment (liveUpdateScopeKey surfaceScope)
            , domIdSegment mount.interactionMountKey.unInteractionMountKey
            ]

interactionFormDomId ::
    TypedInteractionSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    IntentFormContract surface intent ->
    Text
interactionFormDomId definition mount form =
    interactionMountDomId definition mount <> "--intent-form--" <> domIdSegment form.intentFormName

disposableLayerDomId ::
    TypedInteractionSurfaceDefinition surface scope fragment layer session intent ->
    InteractionSurfaceMount scope ->
    DisposableLayerDefinition layer ->
    Text
disposableLayerDomId definition mount layer =
    interactionMountDomId definition mount <> "--disposable-layer--" <> domIdSegment layer.disposableLayerDomIdSuffix

interactionFieldPresenceValues :: [(InteractionFieldPresence, Text)]
interactionFieldPresenceValues =
    [ (IntentFieldRequired, "required")
    , (IntentFieldOptional, "optional")
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

htmxMethodAttribute :: HtmxMethod -> Text
htmxMethodAttribute method =
    fromMaybe (error "Unknown HTMX method") (lookup method htmxMethodValues)

htmxSwapAttribute :: HtmxSwap -> Text
htmxSwapAttribute (HtmxSwapCustom value) = value
htmxSwapAttribute swap =
    fromMaybe (error "Unknown HTMX swap") (lookup swap htmxSwapValues)

domIdSegment :: Text -> Text
domIdSegment value =
    value
        |> Text.map normalizeChar
        |> Text.dropAround (== '-')
        |> \normalized -> if Text.null normalized then "surface" else normalized
    where
        normalizeChar char
            | Char.isAlphaNum char = char
            | otherwise = '-'
