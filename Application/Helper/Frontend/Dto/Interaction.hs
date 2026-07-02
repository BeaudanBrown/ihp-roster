{-# LANGUAGE TypeApplications #-}

module Application.Helper.Frontend.Dto.Interaction
    ( DisposableLayerContract (..)
    , HtmxMethod (..)
    , HtmxSwap (..)
    , IntentFieldSchema (..)
    , IntentFormContract (..)
    , IntentHiddenField (..)
    , InteractionActivationTrigger (..)
    , InteractionCapabilityContract (..)
    , InteractionConflictPolicy (..)
    , InteractionConflictResolution (..)
    , InteractionDisposableLayerName (..)
    , InteractionDom (..)
    , InteractionDomAttribute (..)
    , InteractionDomAttributes (..)
    , InteractionDomValues (..)
    , InteractionEffectSource (..)
    , InteractionFieldPresence (..)
    , InteractionFragmentSelector (..)
    , InteractionIntentFieldName (..)
    , InteractionIntentName (..)
    , InteractionIntentTarget (..)
    , InteractionMountMetadata (..)
    , InteractionPointerFields (..)
    , InteractionSessionEffect (..)
    , InteractionSessionEffects (..)
    , InteractionSessionKindName (..)
    , InteractionSessionSelector (..)
    , InteractionStaticDisposableLayer (..)
    , InteractionStaticIntent (..)
    , InteractionStaticSchema (..)
    , InteractionStaticSchemaRegistry (..)
    , InteractionStaticServerLayer (..)
    , InteractionStaticSessionKind (..)
    , InteractionSurfaceFamily (..)
    , ServerLayerContract (..)
    , SessionKindContract (..)
    , canonicalInteractionDomDto
    , interactionDomAttributeValues
    , interactionStaticSchemasDto
    , interactionSurfaceFamilyValues
    , interactionDisposableLayerNameValues
    , interactionSessionKindNameValues
    , interactionIntentNameValues
    , interactionIntentFieldNameValues
    ) where

import Application.Helper.Frontend.Codec (FrontendCodec (..),
                                          FrontendSchema (..),
                                          HasFrontendCodec (..))
import Application.Helper.Frontend.Dto.LiveUpdate (LiveFragmentKey,
                                                   LiveUpdateWireFragment)
import Application.Helper.Frontend.Generic (FrontendNullable (..),
                                            FrontendOptional (..),
                                            genericFrontendCodecWith)
import Application.Helper.Frontend.Options (FrontendCodecOptions (..),
                                            camelToKebabLower,
                                            defaultFrontendCodecOptions)
import qualified Application.Helper.FrontendSurface.ContractIR as SurfaceIR
import Application.Helper.FrontendSurface.Contracts (registeredFrontendSurfaceContractIR)
import qualified Application.Helper.Interaction as Interaction
import qualified Data.Aeson as Aeson
import GHC.Generics (Generic)
import IHP.Prelude

newtype InteractionDomAttribute = InteractionDomAttribute { unInteractionDomAttribute :: Text }
    deriving (Eq, Show)

newtype InteractionSurfaceFamily = InteractionSurfaceFamily { unInteractionSurfaceFamily :: Text }
    deriving (Eq, Show)

newtype InteractionDisposableLayerName = InteractionDisposableLayerName { unInteractionDisposableLayerName :: Text }
    deriving (Eq, Show)

newtype InteractionSessionKindName = InteractionSessionKindName { unInteractionSessionKindName :: Text }
    deriving (Eq, Show)

newtype InteractionIntentName = InteractionIntentName { unInteractionIntentName :: Text }
    deriving (Eq, Show)

newtype InteractionIntentFieldName = InteractionIntentFieldName { unInteractionIntentFieldName :: Text }
    deriving (Eq, Show)

newtype HtmxSwap = HtmxSwap { unHtmxSwap :: Text }
    deriving (Eq, Show)

data HtmxMethod
    = Get
    | Post
    | Put
    | Patch
    | Delete
    deriving (Eq, Show, Generic)

data InteractionActivationTrigger
    = Click
    | Change
    | KeydownEnter
    | KeydownSpace
    deriving (Eq, Show, Generic)

data InteractionFieldPresence
    = Required
    | Optional
    deriving (Eq, Show, Generic)

data InteractionConflictResolution
    = Apply
    | Defer
    | Cancel
    deriving (Eq, Show, Generic)

newtype InteractionEffectSource = InteractionEffectSource { unInteractionEffectSource :: Text }
    deriving (Eq, Show)

data InteractionSessionEffect
    = CloneShadow
        { layer              :: !InteractionDisposableLayerName
        , source             :: !InteractionEffectSource
        , className          :: !Text
        , preserveGrabOffset :: !Bool
        }
    | DropzoneHighlight
        { className :: !Text
        }
    deriving (Eq, Show, Generic)

data InteractionSessionEffects = InteractionSessionEffects
    { global     :: ![InteractionSessionEffect]
    , contextual :: ![InteractionSessionEffect]
    }
    deriving (Eq, Show, Generic)

data InteractionDomAttributes = InteractionDomAttributes
    { surface              :: !Text
    , surfaceFamily        :: !Text
    , scopeKey             :: !Text
    , mountKey             :: !Text
    , marker               :: !Text
    , item                 :: !Text
    , container            :: !Text
    , slot                 :: !Text
    , dropzone             :: !Text
    , resizeHandle         :: !Text
    , activation           :: !Text
    , activationIntent     :: !Text
    , activationTrigger    :: !Text
    , activationValueField :: !Text
    , pointerSession       :: !Text
    , sessionKind          :: !Text
    , sessionIntent        :: !Text
    , sessionDisabled      :: !Text
    , sessionReadOnly      :: !Text
    , sessionThreshold     :: !Text
    , sessionTimeoutMs     :: !Text
    , interactionActive    :: !Text
    , serverLayer          :: !Text
    , disposableLayer      :: !Text
    , layer                :: !Text
    , conflictPolicies     :: !Text
    , intentForm           :: !Text
    , intent               :: !Text
    , intentField          :: !Text
    , fieldPresence        :: !Text
    , intentHiddenField    :: !Text
    }
    deriving (Eq, Show, Generic)

data InteractionDomValues = InteractionDomValues
    { enabled            :: !Text
    , itemMarker         :: !Text
    , containerMarker    :: !Text
    , slotMarker         :: !Text
    , dropzoneMarker     :: !Text
    , resizeHandleMarker :: !Text
    , activationMarker   :: !Text
    }
    deriving (Eq, Show, Generic)

data InteractionPointerFields = InteractionPointerFields
    { sessionKind       :: !Text
    , pointerId         :: !Text
    , pointerType       :: !Text
    , startClientX      :: !Text
    , startClientY      :: !Text
    , currentClientX    :: !Text
    , currentClientY    :: !Text
    , deltaX            :: !Text
    , deltaY            :: !Text
    , sourceItemKey     :: !Text
    , targetDropzoneKey :: !Text
    }
    deriving (Eq, Show, Generic)

data InteractionDom = InteractionDom
    { attributes    :: !InteractionDomAttributes
    , values        :: !InteractionDomValues
    , pointerFields :: !InteractionPointerFields
    }
    deriving (Eq, Show, Generic)

data InteractionSessionSelector
    = Any
    | Session
        { session :: !InteractionSessionKindName
        }
    deriving (Eq, Show, Generic)

data InteractionFragmentSelector
    = AnyFragment
    | LiveFragment
        { fragment :: !LiveFragmentKey
        }
    deriving (Eq, Show, Generic)

data InteractionMountMetadata = InteractionMountMetadata
    { surfaceFamily :: !InteractionSurfaceFamily
    , scopeKey      :: !Text
    , mountKey      :: !Text
    , mountId       :: !Text
    }
    deriving (Eq, Show, Generic)

data ServerLayerContract = ServerLayerContract
    { name  :: !Text
    , domId :: !Text
    }
    deriving (Eq, Show, Generic)

data DisposableLayerContract = DisposableLayerContract
    { kind  :: !InteractionDisposableLayerName
    , name  :: !Text
    , domId :: !Text
    }
    deriving (Eq, Show, Generic)

data SessionKindContract = SessionKindContract
    { kind        :: !InteractionSessionKindName
    , description :: !Text
    }
    deriving (Eq, Show, Generic)

data IntentFieldSchema = IntentFieldSchema
    { name         :: !InteractionIntentFieldName
    , presence     :: !InteractionFieldPresence
    , defaultValue :: !(FrontendOptional (FrontendNullable Text))
    }
    deriving (Eq, Show, Generic)

data IntentHiddenField = IntentHiddenField
    { name  :: !Text
    , value :: !Text
    }
    deriving (Eq, Show, Generic)

data InteractionIntentTarget
    = TargetLiveFragment
        { fragment :: !LiveUpdateWireFragment
        }
    | TargetMountLocal
        { target :: !Text
        }
    deriving (Eq, Show, Generic)

data IntentFormContract = IntentFormContract
    { intent          :: !InteractionIntentName
    , name            :: !InteractionIntentName
    , action          :: !Text
    , method          :: !HtmxMethod
    , trigger         :: !Text
    , target          :: !InteractionIntentTarget
    , swap            :: !HtmxSwap
    , fields          :: ![IntentFieldSchema]
    , hiddenFields    :: ![IntentHiddenField]
    , sync            :: !(FrontendOptional (FrontendNullable Text))
    , disabledElement :: !(FrontendOptional (FrontendNullable Text))
    }
    deriving (Eq, Show, Generic)

data InteractionConflictPolicy = InteractionConflictPolicy
    { session    :: !InteractionSessionSelector
    , fragment   :: !InteractionFragmentSelector
    , resolution :: !InteractionConflictResolution
    , timeoutMs  :: !(FrontendOptional (FrontendNullable Int))
    }
    deriving (Eq, Show, Generic)

data InteractionCapabilityContract = InteractionCapabilityContract
    { mount            :: !InteractionMountMetadata
    , serverLayers     :: ![ServerLayerContract]
    , disposableLayers :: ![DisposableLayerContract]
    , sessionKinds     :: ![SessionKindContract]
    , intentForms      :: ![IntentFormContract]
    , conflictPolicies :: ![InteractionConflictPolicy]
    }
    deriving (Eq, Show, Generic)

data InteractionStaticServerLayer = InteractionStaticServerLayer
    { name        :: !Text
    , domIdSuffix :: !Text
    }
    deriving (Eq, Show, Generic)

data InteractionStaticDisposableLayer = InteractionStaticDisposableLayer
    { name        :: !InteractionDisposableLayerName
    , domIdSuffix :: !Text
    }
    deriving (Eq, Show, Generic)

data InteractionStaticSessionKind = InteractionStaticSessionKind
    { kind        :: !InteractionSessionKindName
    , description :: !Text
    , effects     :: !InteractionSessionEffects
    }
    deriving (Eq, Show, Generic)

data InteractionStaticIntent = InteractionStaticIntent
    { name   :: !InteractionIntentName
    , fields :: ![IntentFieldSchema]
    }
    deriving (Eq, Show, Generic)

data InteractionStaticSchema = InteractionStaticSchema
    { serverLayers     :: ![InteractionStaticServerLayer]
    , disposableLayers :: ![InteractionStaticDisposableLayer]
    , sessionKinds     :: ![InteractionStaticSessionKind]
    , intents          :: ![InteractionStaticIntent]
    , conflictPolicies :: ![InteractionConflictPolicy]
    }
    deriving (Eq, Show, Generic)

data InteractionStaticSchemaRegistry = InteractionStaticSchemaRegistry
    { roster :: !InteractionStaticSchema
    }
    deriving (Eq, Show, Generic)

instance HasFrontendCodec InteractionDomAttribute where
    frontendCodec = textNewtypeEnumCodec "InteractionDomAttribute" interactionDomAttributeValues InteractionDomAttribute unInteractionDomAttribute

instance HasFrontendCodec InteractionSurfaceFamily where
    frontendCodec = textNewtypeEnumCodec "InteractionSurfaceFamily" interactionSurfaceFamilyValues InteractionSurfaceFamily unInteractionSurfaceFamily

instance HasFrontendCodec InteractionDisposableLayerName where
    frontendCodec = textNewtypeEnumCodec "InteractionDisposableLayerName" interactionDisposableLayerNameValues InteractionDisposableLayerName unInteractionDisposableLayerName

instance HasFrontendCodec InteractionSessionKindName where
    frontendCodec = textNewtypeEnumCodec "InteractionSessionKindName" interactionSessionKindNameValues InteractionSessionKindName unInteractionSessionKindName

instance HasFrontendCodec InteractionIntentName where
    frontendCodec = textNewtypeEnumCodec "InteractionIntentName" interactionIntentNameValues InteractionIntentName unInteractionIntentName

instance HasFrontendCodec InteractionIntentFieldName where
    frontendCodec = textNewtypeEnumCodec "InteractionIntentFieldName" interactionIntentFieldNameValues InteractionIntentFieldName unInteractionIntentFieldName

instance HasFrontendCodec HtmxSwap where
    frontendCodec = textNewtypeEnumCodec "HtmxSwap" (fmap snd Interaction.htmxSwapValues) HtmxSwap unHtmxSwap

instance HasFrontendCodec HtmxMethod where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "HtmxMethod" }

instance HasFrontendCodec InteractionActivationTrigger where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionActivationTrigger"
        , frontendConstructorTagModifier = camelToKebabLower
        }

instance HasFrontendCodec InteractionFieldPresence where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionFieldPresence" }

instance HasFrontendCodec InteractionConflictResolution where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionConflictResolution" }

instance HasFrontendCodec InteractionEffectSource where
    frontendCodec = textNewtypeEnumCodec "InteractionEffectSource" ["pointer-marker"] InteractionEffectSource unInteractionEffectSource

instance HasFrontendCodec InteractionSessionEffect where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionSessionEffect"
        , frontendConstructorTagModifier = \case
            "CloneShadow" -> "clone-shadow"
            "DropzoneHighlight" -> "dropzone-highlight"
            constructorName -> camelToKebabLower constructorName
        }

instance HasFrontendCodec InteractionSessionEffects where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionSessionEffects" }

instance HasFrontendCodec InteractionDomAttributes where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionDomAttributes" }

instance HasFrontendCodec InteractionDomValues where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionDomValues" }

instance HasFrontendCodec InteractionPointerFields where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionPointerFields" }

instance HasFrontendCodec InteractionDom where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionDom" }

instance HasFrontendCodec InteractionSessionSelector where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionSessionSelector" }

instance HasFrontendCodec InteractionFragmentSelector where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionFragmentSelector"
        , frontendConstructorTagModifier = \case
            "AnyFragment" -> "any"
            "LiveFragment" -> "live_fragment"
            constructorName -> camelToKebabLower constructorName
        }

instance HasFrontendCodec InteractionMountMetadata where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionMountMetadata" }

instance HasFrontendCodec ServerLayerContract where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "ServerLayerContract" }

instance HasFrontendCodec DisposableLayerContract where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "DisposableLayerContract" }

instance HasFrontendCodec SessionKindContract where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "SessionKindContract" }

instance HasFrontendCodec IntentFieldSchema where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "IntentFieldSchema" }

instance HasFrontendCodec IntentHiddenField where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "IntentHiddenField" }

instance HasFrontendCodec InteractionIntentTarget where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionIntentTarget"
        , frontendConstructorTagModifier = \case
            "TargetLiveFragment" -> "live_fragment"
            "TargetMountLocal" -> "mount_local"
            constructorName -> camelToKebabLower constructorName
        }

instance HasFrontendCodec IntentFormContract where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "IntentFormContract" }

instance HasFrontendCodec InteractionConflictPolicy where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionConflictPolicy" }

instance HasFrontendCodec InteractionCapabilityContract where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionCapabilityContract" }

instance HasFrontendCodec InteractionStaticServerLayer where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionStaticServerLayer" }

instance HasFrontendCodec InteractionStaticDisposableLayer where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionStaticDisposableLayer" }

instance HasFrontendCodec InteractionStaticSessionKind where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionStaticSessionKind" }

instance HasFrontendCodec InteractionStaticIntent where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionStaticIntent" }

instance HasFrontendCodec InteractionStaticSchema where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionStaticSchema" }

instance HasFrontendCodec InteractionStaticSchemaRegistry where
    frontendCodec = genericFrontendCodecWith defaultFrontendCodecOptions
        { frontendTypeNameOverride = Just "InteractionStaticSchemaRegistry" }

canonicalInteractionDomDto :: InteractionDom
canonicalInteractionDomDto = interactionDomDto Interaction.canonicalInteractionDom

interactionStaticSchemasDto :: InteractionStaticSchemaRegistry
interactionStaticSchemasDto = InteractionStaticSchemaRegistry
    { roster = frontendSurfaceInteractionStaticSchemaDto (expectFrontendSurface "roster") }

interactionDomDto :: Interaction.InteractionDom -> InteractionDom
interactionDomDto dom = InteractionDom
    { attributes = interactionDomAttributesDto dom.interactionDomAttributes
    , values = interactionDomValuesDto dom.interactionDomValues
    , pointerFields = interactionPointerFieldsDto dom.interactionDomPointerFields
    }

interactionDomAttributesDto :: Interaction.InteractionDomAttributes -> InteractionDomAttributes
interactionDomAttributesDto attrs = InteractionDomAttributes
    { surface = attrs.interactionDomSurfaceAttribute
    , surfaceFamily = attrs.interactionDomSurfaceFamilyAttribute
    , scopeKey = attrs.interactionDomScopeKeyAttribute
    , mountKey = attrs.interactionDomMountKeyAttribute
    , marker = attrs.interactionDomMarkerAttribute
    , item = attrs.interactionDomItemAttribute
    , container = attrs.interactionDomContainerAttribute
    , slot = attrs.interactionDomSlotAttribute
    , dropzone = attrs.interactionDomDropzoneAttribute
    , resizeHandle = attrs.interactionDomResizeHandleAttribute
    , activation = attrs.interactionDomActivationAttribute
    , activationIntent = attrs.interactionDomActivationIntentAttribute
    , activationTrigger = attrs.interactionDomActivationTriggerAttribute
    , activationValueField = attrs.interactionDomActivationValueFieldAttribute
    , pointerSession = attrs.interactionDomPointerSessionAttribute
    , sessionKind = attrs.interactionDomSessionKindAttribute
    , sessionIntent = attrs.interactionDomSessionIntentAttribute
    , sessionDisabled = attrs.interactionDomSessionDisabledAttribute
    , sessionReadOnly = attrs.interactionDomSessionReadOnlyAttribute
    , sessionThreshold = attrs.interactionDomSessionThresholdAttribute
    , sessionTimeoutMs = attrs.interactionDomSessionTimeoutMsAttribute
    , interactionActive = attrs.interactionDomInteractionActiveAttribute
    , serverLayer = attrs.interactionDomServerLayerAttribute
    , disposableLayer = attrs.interactionDomDisposableLayerAttribute
    , layer = attrs.interactionDomLayerAttribute
    , conflictPolicies = attrs.interactionDomConflictPoliciesAttribute
    , intentForm = attrs.interactionDomIntentFormAttribute
    , intent = attrs.interactionDomIntentAttribute
    , intentField = attrs.interactionDomIntentFieldAttribute
    , fieldPresence = attrs.interactionDomFieldPresenceAttribute
    , intentHiddenField = attrs.interactionDomIntentHiddenFieldAttribute
    }

interactionDomValuesDto :: Interaction.InteractionDomValues -> InteractionDomValues
interactionDomValuesDto values = InteractionDomValues
    { enabled = values.interactionDomEnabledValue
    , itemMarker = values.interactionDomItemMarkerValue
    , containerMarker = values.interactionDomContainerMarkerValue
    , slotMarker = values.interactionDomSlotMarkerValue
    , dropzoneMarker = values.interactionDomDropzoneMarkerValue
    , resizeHandleMarker = values.interactionDomResizeHandleMarkerValue
    , activationMarker = values.interactionDomActivationMarkerValue
    }

interactionPointerFieldsDto :: Interaction.InteractionPointerFields -> InteractionPointerFields
interactionPointerFieldsDto fields = InteractionPointerFields
    { sessionKind = fields.interactionPointerSessionKindField
    , pointerId = fields.interactionPointerIdField
    , pointerType = fields.interactionPointerTypeField
    , startClientX = fields.interactionPointerStartClientXField
    , startClientY = fields.interactionPointerStartClientYField
    , currentClientX = fields.interactionPointerCurrentClientXField
    , currentClientY = fields.interactionPointerCurrentClientYField
    , deltaX = fields.interactionPointerDeltaXField
    , deltaY = fields.interactionPointerDeltaYField
    , sourceItemKey = fields.interactionPointerSourceItemKeyField
    , targetDropzoneKey = fields.interactionPointerTargetDropzoneKeyField
    }

frontendSurfaceInteractionStaticSchemaDto :: SurfaceIR.SurfaceIR -> InteractionStaticSchema
frontendSurfaceInteractionStaticSchemaDto surface = InteractionStaticSchema
    { serverLayers = []
    , disposableLayers = fmap surfaceDisposableLayerDto surface.surfaceLayers
    , sessionKinds = fmap (surfaceSessionKindDto surface) surface.surfaceSessions
    , intents = fmap surfaceIntentDto surface.surfaceIntents
    , conflictPolicies = fmap surfaceConflictPolicyDto surface.surfacePolicies
    }

surfaceDisposableLayerDto :: Text -> InteractionStaticDisposableLayer
surfaceDisposableLayerDto name = InteractionStaticDisposableLayer
    { name = InteractionDisposableLayerName name
    , domIdSuffix = name
    }

surfaceSessionKindDto :: SurfaceIR.SurfaceIR -> Text -> InteractionStaticSessionKind
surfaceSessionKindDto surface sessionName = InteractionStaticSessionKind
    { kind = InteractionSessionKindName sessionName
    , description = surfaceSessionDescription surface.surfaceName sessionName
    , effects = surfaceSessionEffectsDto surface.surfaceEffects
    }

surfaceSessionDescription :: Text -> Text -> Text
surfaceSessionDescription "roster" "drag" = "Roster drag/drop prototype"
surfaceSessionDescription surfaceName sessionName = surfaceName <> " " <> sessionName <> " interaction session"

surfaceSessionEffectsDto :: [(Text, [SurfaceIR.OptionIR])] -> InteractionSessionEffects
surfaceSessionEffectsDto effects = InteractionSessionEffects
    { global = mapMaybe surfaceGlobalEffectDto effects
    , contextual = mapMaybe surfaceContextualEffectDto effects
    }

surfaceGlobalEffectDto :: (Text, [SurfaceIR.OptionIR]) -> Maybe InteractionSessionEffect
surfaceGlobalEffectDto ("clone-shadow", options) = Just CloneShadow
    { layer = InteractionDisposableLayerName (fromMaybe "drag-preview" (firstLayerOption options))
    , source = InteractionEffectSource "pointer-marker"
    , className = "bepis-pointer-clone-shadow"
    , preserveGrabOffset = True
    }
surfaceGlobalEffectDto _ = Nothing

surfaceContextualEffectDto :: (Text, [SurfaceIR.OptionIR]) -> Maybe InteractionSessionEffect
surfaceContextualEffectDto ("dropzone-highlight", _) = Just DropzoneHighlight
    { className = "bepis-dropzone-highlight"
    }
surfaceContextualEffectDto _ = Nothing

firstLayerOption :: [SurfaceIR.OptionIR] -> Maybe Text
firstLayerOption options = listToMaybe (mapMaybe layerName options)
    where
        layerName = \case
            SurfaceIR.LayerOption layer -> Just layer
            _ -> Nothing

surfaceIntentDto :: SurfaceIR.IntentIR -> InteractionStaticIntent
surfaceIntentDto intent = InteractionStaticIntent
    { name = InteractionIntentName intent.intentName
    , fields = fmap surfaceIntentFieldDto intent.intentFields
    }

surfaceIntentFieldDto :: SurfaceIR.FieldIR -> IntentFieldSchema
surfaceIntentFieldDto field = IntentFieldSchema
    { name = InteractionIntentFieldName field.fieldName
    , presence = surfaceFieldPresenceDto field.fieldPresence
    , defaultValue = FrontendOptional (Just (FrontendNullable Nothing))
    }

surfaceFieldPresenceDto :: SurfaceIR.FieldPresence -> InteractionFieldPresence
surfaceFieldPresenceDto SurfaceIR.RequiredField         = Required
surfaceFieldPresenceDto SurfaceIR.OptionalFieldPresence = Optional
surfaceFieldPresenceDto SurfaceIR.NullableFieldPresence = Optional

surfaceConflictPolicyDto :: SurfaceIR.ConflictPolicyIR -> InteractionConflictPolicy
surfaceConflictPolicyDto policy = InteractionConflictPolicy
    { session = surfaceSessionSelectorDto policy.conflictPolicySession
    , fragment = surfaceFragmentSelectorDto policy.conflictPolicyFragment
    , resolution = surfaceConflictResolutionDto policy.conflictPolicyResolution
    , timeoutMs = FrontendOptional (Just (FrontendNullable (surfaceConflictPolicyTimeout policy)))
    }

surfaceSessionSelectorDto :: SurfaceIR.SessionSelectorIR -> InteractionSessionSelector
surfaceSessionSelectorDto SurfaceIR.AnySessionIR = Any
surfaceSessionSelectorDto (SurfaceIR.SessionKindIR sessionName) = Session
    { session = InteractionSessionKindName sessionName
    }

surfaceFragmentSelectorDto :: SurfaceIR.FragmentSelectorIR -> InteractionFragmentSelector
surfaceFragmentSelectorDto SurfaceIR.AnyFragmentIR        = AnyFragment
surfaceFragmentSelectorDto SurfaceIR.FragmentKindIR {}    = AnyFragment
surfaceFragmentSelectorDto SurfaceIR.FragmentSubtreeIR {} = AnyFragment

surfaceConflictResolutionDto :: SurfaceIR.ConflictResolutionIR -> InteractionConflictResolution
surfaceConflictResolutionDto SurfaceIR.ApplyIR  = Apply
surfaceConflictResolutionDto SurfaceIR.DeferIR  = Defer
surfaceConflictResolutionDto SurfaceIR.CancelIR = Cancel

surfaceConflictPolicyTimeout :: SurfaceIR.ConflictPolicyIR -> Maybe Int
surfaceConflictPolicyTimeout policy =
    case policy.conflictPolicyResolution of
        SurfaceIR.DeferIR -> Just 5000
        _                 -> Nothing

interactionStaticSchemaDto :: Eq session => Interaction.InteractionStaticSchema fragment layer session intent -> InteractionStaticSchema
interactionStaticSchemaDto schema = InteractionStaticSchema
    { serverLayers = fmap staticServerLayerDto schema.interactionStaticServerLayers
    , disposableLayers = fmap staticDisposableLayerDto schema.interactionStaticDisposableLayers
    , sessionKinds = fmap staticSessionKindDto schema.interactionStaticSessionKinds
    , intents = fmap staticIntentDto schema.interactionStaticIntents
    , conflictPolicies = fmap (conflictPolicyDto schema) schema.interactionStaticConflictPolicies
    }

staticServerLayerDto :: Interaction.ServerLayerDefinition -> InteractionStaticServerLayer
staticServerLayerDto layer = InteractionStaticServerLayer
    { name = layer.serverLayerName
    , domIdSuffix = layer.serverLayerDomIdSuffix
    }

staticDisposableLayerDto :: Interaction.DisposableLayerDefinition layer -> InteractionStaticDisposableLayer
staticDisposableLayerDto layer = InteractionStaticDisposableLayer
    { name = InteractionDisposableLayerName layer.disposableLayerName
    , domIdSuffix = layer.disposableLayerDomIdSuffix
    }

staticSessionKindDto :: Interaction.SessionKindDefinition session -> InteractionStaticSessionKind
staticSessionKindDto session = InteractionStaticSessionKind
    { kind = InteractionSessionKindName session.sessionKindName
    , description = session.sessionDescription
    , effects = sessionEffectsDto session.sessionEffects
    }

sessionEffectsDto :: Interaction.InteractionSessionEffects -> InteractionSessionEffects
sessionEffectsDto effects = InteractionSessionEffects
    { global = fmap sessionGlobalEffectDto effects.interactionSessionGlobalEffects
    , contextual = fmap sessionContextualEffectDto effects.interactionSessionContextualEffects
    }

sessionGlobalEffectDto :: Interaction.InteractionSessionGlobalEffect -> InteractionSessionEffect
sessionGlobalEffectDto Interaction.InteractionCloneShadowEffect { cloneShadowLayerName, cloneShadowSource, cloneShadowClassName, cloneShadowPreserveGrabOffset } = CloneShadow
    { layer = InteractionDisposableLayerName cloneShadowLayerName
    , source = effectSourceDto cloneShadowSource
    , className = cloneShadowClassName
    , preserveGrabOffset = cloneShadowPreserveGrabOffset
    }

sessionContextualEffectDto :: Interaction.InteractionSessionContextualEffect -> InteractionSessionEffect
sessionContextualEffectDto Interaction.InteractionDropzoneHighlightEffect { dropzoneHighlightClassName } = DropzoneHighlight
    { className = dropzoneHighlightClassName
    }

effectSourceDto :: Interaction.InteractionEffectSource -> InteractionEffectSource
effectSourceDto Interaction.InteractionEffectPointerMarker = InteractionEffectSource "pointer-marker"

staticIntentDto :: Interaction.InteractionIntentSchema intent -> InteractionStaticIntent
staticIntentDto intent = InteractionStaticIntent
    { name = InteractionIntentName intent.interactionIntentSchemaName
    , fields = fmap intentFieldDto intent.interactionIntentSchemaFields
    }

intentFieldDto :: Interaction.IntentFieldSchema -> IntentFieldSchema
intentFieldDto field = IntentFieldSchema
    { name = InteractionIntentFieldName field.intentFieldName.unIntentFieldName
    , presence = fieldPresenceDto field.intentFieldPresence
    , defaultValue = FrontendOptional (Just (FrontendNullable field.intentFieldDefaultValue))
    }

conflictPolicyDto :: Eq session => Interaction.InteractionStaticSchema fragment layer session intent -> Interaction.InteractionConflictPolicy fragment session -> InteractionConflictPolicy
conflictPolicyDto schema policy = InteractionConflictPolicy
    { session = sessionSelectorDto schema policy.conflictPolicySession
    , fragment = fragmentSelectorDto policy.conflictPolicyFragment
    , resolution = conflictResolutionDto policy.conflictPolicyResolution
    , timeoutMs = FrontendOptional (Just (FrontendNullable policy.conflictPolicyTimeoutMs))
    }

sessionSelectorDto :: Eq session => Interaction.InteractionStaticSchema fragment layer session intent -> Interaction.InteractionSessionSelector session -> InteractionSessionSelector
sessionSelectorDto _ Interaction.AnyInteractionSession = Any
sessionSelectorDto schema (Interaction.InteractionSessionKind session) = Session
    { session = InteractionSessionKindName $ fromMaybe "<session-kind>" do
        matching <- find ((== session) . (.sessionKind)) schema.interactionStaticSessionKinds
        pure matching.sessionKindName
    }

fragmentSelectorDto :: Interaction.InteractionFragmentSelector fragment -> InteractionFragmentSelector
fragmentSelectorDto Interaction.AnyInteractionFragment = AnyFragment
fragmentSelectorDto (Interaction.InteractionFragment _) = error "Static interaction schema cannot encode an opaque fragment selector"

fieldPresenceDto :: Interaction.InteractionFieldPresence -> InteractionFieldPresence
fieldPresenceDto Interaction.IntentFieldRequired = Required
fieldPresenceDto Interaction.IntentFieldOptional = Optional

conflictResolutionDto :: Interaction.InteractionConflictResolution -> InteractionConflictResolution
conflictResolutionDto Interaction.ApplyLiveFragmentImmediately      = Apply
conflictResolutionDto Interaction.DeferLiveFragmentUntilSessionEnds = Defer
conflictResolutionDto Interaction.CancelSessionAndApplyLiveFragment = Cancel

interactionDomAttributeValues :: [Text]
interactionDomAttributeValues =
    let attrs = Interaction.canonicalInteractionDom.interactionDomAttributes
     in [ attrs.interactionDomSurfaceAttribute
        , attrs.interactionDomSurfaceFamilyAttribute
        , attrs.interactionDomScopeKeyAttribute
        , attrs.interactionDomMountKeyAttribute
        , attrs.interactionDomMarkerAttribute
        , attrs.interactionDomItemAttribute
        , attrs.interactionDomContainerAttribute
        , attrs.interactionDomSlotAttribute
        , attrs.interactionDomDropzoneAttribute
        , attrs.interactionDomResizeHandleAttribute
        , attrs.interactionDomActivationAttribute
        , attrs.interactionDomActivationIntentAttribute
        , attrs.interactionDomActivationTriggerAttribute
        , attrs.interactionDomActivationValueFieldAttribute
        , attrs.interactionDomPointerSessionAttribute
        , attrs.interactionDomSessionKindAttribute
        , attrs.interactionDomSessionIntentAttribute
        , attrs.interactionDomSessionDisabledAttribute
        , attrs.interactionDomSessionReadOnlyAttribute
        , attrs.interactionDomSessionThresholdAttribute
        , attrs.interactionDomSessionTimeoutMsAttribute
        , attrs.interactionDomInteractionActiveAttribute
        , attrs.interactionDomServerLayerAttribute
        , attrs.interactionDomDisposableLayerAttribute
        , attrs.interactionDomLayerAttribute
        , attrs.interactionDomConflictPoliciesAttribute
        , attrs.interactionDomIntentFormAttribute
        , attrs.interactionDomIntentAttribute
        , attrs.interactionDomIntentFieldAttribute
        , attrs.interactionDomFieldPresenceAttribute
        , attrs.interactionDomIntentHiddenFieldAttribute
        ]

interactionSurfaceFamilyValues :: [Text]
interactionSurfaceFamilyValues = fmap (.familyName) knownInteractionSchemas

interactionDisposableLayerNameValues :: [Text]
interactionDisposableLayerNameValues = unique (concatMap (.disposableLayerNames) knownInteractionSchemas)

interactionSessionKindNameValues :: [Text]
interactionSessionKindNameValues = unique (concatMap (.sessionKindNames) knownInteractionSchemas)

interactionIntentNameValues :: [Text]
interactionIntentNameValues = unique (concatMap (.intentNames) knownInteractionSchemas)

interactionIntentFieldNameValues :: [Text]
interactionIntentFieldNameValues = unique (concatMap (.intentFieldNames) knownInteractionSchemas)

data KnownInteractionSchema = KnownInteractionSchema
    { familyName           :: !Text
    , disposableLayerNames :: ![Text]
    , sessionKindNames     :: ![Text]
    , intentNames          :: ![Text]
    , intentFieldNames     :: ![Text]
    }

expectFrontendSurface :: Text -> SurfaceIR.SurfaceIR
expectFrontendSurface surfaceName =
    registeredFrontendSurfaceContractIR.contractSurfaces
        |> find (\surface -> surface.surfaceName == surfaceName)
        |> fromMaybe (error ("Missing FrontendSurface interaction schema for " <> cs surfaceName))

knownInteractionSchemas :: [KnownInteractionSchema]
knownInteractionSchemas =
    [knownFrontendSurfaceSchema (expectFrontendSurface "roster")]

knownFrontendSurfaceSchema :: SurfaceIR.SurfaceIR -> KnownInteractionSchema
knownFrontendSurfaceSchema surface = KnownInteractionSchema
    { familyName = surface.surfaceName
    , disposableLayerNames = surface.surfaceLayers
    , sessionKindNames = surface.surfaceSessions
    , intentNames = fmap (.intentName) surface.surfaceIntents
    , intentFieldNames = unique (concatMap (fmap (.fieldName) . (.intentFields)) surface.surfaceIntents)
    }

textNewtypeEnumCodec :: Text -> [Text] -> (Text -> a) -> (a -> Text) -> FrontendCodec a
textNewtypeEnumCodec name values construct unwrap = FrontendCodec
    { codecName = Just name
    , codecSchema = SchemaStringEnum name values
    , codecEncode = Aeson.String . unwrap
    , codecParse = Aeson.withText (cs name) \value ->
        if value `elem` values
            then pure (construct value)
            else fail ("Unknown " <> cs name <> ": " <> cs value)
    }

unique :: [Text] -> [Text]
unique = foldr (\value acc -> if value `elem` acc then acc else value : acc) []
