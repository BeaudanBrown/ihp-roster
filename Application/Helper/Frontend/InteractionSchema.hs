{-# LANGUAGE RecordWildCards #-}

module Application.Helper.Frontend.InteractionSchema
    ( interactionSchemaDeclaration
    ) where

import Application.Helper.Frontend.Codec (FrontendCodec (..),
                                          FrontendSchema (..),
                                          SomeFrontendCodec (..), field,
                                          recordSchema, stringEnumCodec,
                                          taggedUnionSchema, variant)
import Application.Helper.Frontend.ContractGroup (FrontendContractGroup (..),
                                                  renderFrontendContractGroup,
                                                  typedConstant)
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..))
import Application.Helper.Interaction
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Aeson.Types as AesonTypes
import IHP.Prelude
import Web.RosterWeeks.LiveSurface (rosterInteractionStaticSchema)

interactionSchemaDeclaration :: TypeScriptDeclaration
interactionSchemaDeclaration =
    renderFrontendContractGroup FrontendContractGroup
        { contractGroupName = "InteractionContracts"
        , contractGroupComment = Just "Interaction contracts generated from Haskell static interaction schemas."
        , contractGroupCodecs = interactionContractCodecs
        , contractGroupConstants =
            [ typedConstant "InteractionDom" interactionDomCodec canonicalInteractionDom
            , typedConstant "InteractionStaticSchemas" interactionStaticSchemaRegistryCodec interactionStaticSchemasJson
            ]
        }

interactionStaticSchemasJson :: Aeson.Value
interactionStaticSchemasJson =
    Aeson.object (fmap schemaPair knownInteractionSchemas)
    where
        schemaPair schema = AesonKey.fromText schema.familyName Aeson..= schema.schemaJson

interactionContractCodecs :: [SomeFrontendCodec]
interactionContractCodecs =
    [ SomeFrontendCodec interactionDomAttributesCodec
    , SomeFrontendCodec interactionDomValuesCodec
    , SomeFrontendCodec interactionPointerFieldsCodec
    , SomeFrontendCodec interactionDomCodec
    , SomeFrontendCodec interactionDomAttributeCodec
    , SomeFrontendCodec interactionActivationTriggerCodec
    , SomeFrontendCodec interactionFieldPresenceCodec
    , SomeFrontendCodec htmxMethodCodec
    , SomeFrontendCodec htmxSwapCodec
    , SomeFrontendCodec interactionConflictResolutionCodec
    , SomeFrontendCodec interactionSurfaceFamilyCodec
    , SomeFrontendCodec interactionDisposableLayerNameCodec
    , SomeFrontendCodec interactionSessionKindNameCodec
    , SomeFrontendCodec interactionIntentNameCodec
    , SomeFrontendCodec interactionIntentFieldNameCodec
    , SomeFrontendCodec interactionSessionSelectorCodec
    , SomeFrontendCodec interactionFragmentSelectorCodec
    , SomeFrontendCodec interactionMountMetadataCodec
    , SomeFrontendCodec serverLayerContractCodec
    , SomeFrontendCodec disposableLayerContractCodec
    , SomeFrontendCodec sessionKindContractCodec
    , SomeFrontendCodec intentFieldSchemaCodec
    , SomeFrontendCodec intentHiddenFieldCodec
    , SomeFrontendCodec interactionIntentTargetCodec
    , SomeFrontendCodec intentFormContractCodec
    , SomeFrontendCodec interactionConflictPolicyCodec
    , SomeFrontendCodec interactionCapabilityContractCodec
    , SomeFrontendCodec interactionStaticServerLayerCodec
    , SomeFrontendCodec interactionStaticDisposableLayerCodec
    , SomeFrontendCodec interactionStaticSessionKindCodec
    , SomeFrontendCodec interactionStaticIntentCodec
    , SomeFrontendCodec interactionStaticSchemaCodec
    , SomeFrontendCodec interactionStaticSchemaRegistryCodec
    ]

interactionDomAttributesCodec :: FrontendCodec InteractionDomAttributes
interactionDomAttributesCodec = FrontendCodec
    { codecName = Just "InteractionDomAttributes"
    , codecSchema = interactionDomAttributesSchema
    , codecEncode = interactionDomAttributesJson
    , codecParse = parseInteractionDomAttributes
    }

interactionDomAttributesSchema :: FrontendSchema
interactionDomAttributesSchema = recordSchema "InteractionDomAttributes"
    [ field "surface" SchemaString
    , field "surfaceFamily" SchemaString
    , field "scopeKey" SchemaString
    , field "mountKey" SchemaString
    , field "marker" SchemaString
    , field "item" SchemaString
    , field "container" SchemaString
    , field "slot" SchemaString
    , field "dropzone" SchemaString
    , field "resizeHandle" SchemaString
    , field "activation" SchemaString
    , field "activationIntent" SchemaString
    , field "activationTrigger" SchemaString
    , field "activationValueField" SchemaString
    , field "pointerSession" SchemaString
    , field "sessionKind" SchemaString
    , field "sessionIntent" SchemaString
    , field "sessionDisabled" SchemaString
    , field "sessionReadOnly" SchemaString
    , field "sessionThreshold" SchemaString
    , field "sessionTimeoutMs" SchemaString
    , field "interactionActive" SchemaString
    , field "serverLayer" SchemaString
    , field "disposableLayer" SchemaString
    , field "layer" SchemaString
    , field "conflictPolicies" SchemaString
    , field "intentForm" SchemaString
    , field "intent" SchemaString
    , field "intentField" SchemaString
    , field "fieldPresence" SchemaString
    , field "intentHiddenField" SchemaString
    ]

interactionDomValuesCodec :: FrontendCodec InteractionDomValues
interactionDomValuesCodec = FrontendCodec
    { codecName = Just "InteractionDomValues"
    , codecSchema = interactionDomValuesSchema
    , codecEncode = interactionDomValuesJson
    , codecParse = parseInteractionDomValues
    }

interactionDomValuesSchema :: FrontendSchema
interactionDomValuesSchema = recordSchema "InteractionDomValues"
    [ field "enabled" SchemaString
    , field "itemMarker" SchemaString
    , field "containerMarker" SchemaString
    , field "slotMarker" SchemaString
    , field "dropzoneMarker" SchemaString
    , field "resizeHandleMarker" SchemaString
    , field "activationMarker" SchemaString
    ]

interactionPointerFieldsCodec :: FrontendCodec InteractionPointerFields
interactionPointerFieldsCodec = FrontendCodec
    { codecName = Just "InteractionPointerFields"
    , codecSchema = interactionPointerFieldsSchema
    , codecEncode = interactionPointerFieldsJson
    , codecParse = parseInteractionPointerFields
    }

interactionPointerFieldsSchema :: FrontendSchema
interactionPointerFieldsSchema = recordSchema "InteractionPointerFields"
    [ field "sessionKind" SchemaString
    , field "pointerId" SchemaString
    , field "pointerType" SchemaString
    , field "startClientX" SchemaString
    , field "startClientY" SchemaString
    , field "currentClientX" SchemaString
    , field "currentClientY" SchemaString
    , field "deltaX" SchemaString
    , field "deltaY" SchemaString
    , field "sourceItemKey" SchemaString
    , field "targetDropzoneKey" SchemaString
    ]

interactionDomCodec :: FrontendCodec InteractionDom
interactionDomCodec = FrontendCodec
    { codecName = Just "InteractionDom"
    , codecSchema = recordSchema "InteractionDom"
        [ field "attributes" (SchemaRef "InteractionDomAttributes")
        , field "values" (SchemaRef "InteractionDomValues")
        , field "pointerFields" (SchemaRef "InteractionPointerFields")
        ]
    , codecEncode = interactionDomJson
    , codecParse = parseInteractionDom
    }

interactionDomAttributeCodec :: FrontendCodec Text
interactionDomAttributeCodec = textEnumCodec "InteractionDomAttribute" interactionDomAttributeValues

interactionActivationTriggerCodec :: FrontendCodec InteractionActivationTrigger
interactionActivationTriggerCodec = stringEnumCodec "InteractionActivationTrigger" interactionActivationTriggerValues

interactionFieldPresenceCodec :: FrontendCodec InteractionFieldPresence
interactionFieldPresenceCodec = stringEnumCodec "InteractionFieldPresence" interactionFieldPresenceValues

htmxMethodCodec :: FrontendCodec HtmxMethod
htmxMethodCodec = stringEnumCodec "HtmxMethod" htmxMethodValues

htmxSwapCodec :: FrontendCodec Text
htmxSwapCodec = textEnumCodec "HtmxSwap" (fmap snd htmxSwapValues)

interactionConflictResolutionCodec :: FrontendCodec InteractionConflictResolution
interactionConflictResolutionCodec = stringEnumCodec "InteractionConflictResolution" interactionConflictResolutionValues

interactionSurfaceFamilyCodec :: FrontendCodec Text
interactionSurfaceFamilyCodec = textEnumCodec "InteractionSurfaceFamily" (fmap (.familyName) knownInteractionSchemas)

interactionDisposableLayerNameCodec :: FrontendCodec Text
interactionDisposableLayerNameCodec = textEnumCodec "InteractionDisposableLayerName" (unique (concatMap (.disposableLayerNames) knownInteractionSchemas))

interactionSessionKindNameCodec :: FrontendCodec Text
interactionSessionKindNameCodec = textEnumCodec "InteractionSessionKindName" (unique (concatMap (.sessionKindNames) knownInteractionSchemas))

interactionIntentNameCodec :: FrontendCodec Text
interactionIntentNameCodec = textEnumCodec "InteractionIntentName" (unique (concatMap (.intentNames) knownInteractionSchemas))

interactionIntentFieldNameCodec :: FrontendCodec Text
interactionIntentFieldNameCodec = textEnumCodec "InteractionIntentFieldName" (unique (concatMap (.intentFieldNames) knownInteractionSchemas))

interactionSessionSelectorCodec :: FrontendCodec Aeson.Value
interactionSessionSelectorCodec = valueCodec "InteractionSessionSelector" $ taggedUnionSchema "InteractionSessionSelector" "kind"
    [ variant "any" []
    , variant "session" [field "session" (SchemaRef "InteractionSessionKindName")]
    ]

interactionFragmentSelectorCodec :: FrontendCodec Aeson.Value
interactionFragmentSelectorCodec = valueCodec "InteractionFragmentSelector" $ taggedUnionSchema "InteractionFragmentSelector" "kind"
    [ variant "any" []
    , variant "live_fragment" [field "fragment" (SchemaRef "LiveFragmentKey")]
    ]

interactionMountMetadataCodec :: FrontendCodec Aeson.Value
interactionMountMetadataCodec = valueCodec "InteractionMountMetadata" $ recordSchema "InteractionMountMetadata"
    [ field "surfaceFamily" (SchemaRef "InteractionSurfaceFamily")
    , field "scopeKey" SchemaString
    , field "mountKey" SchemaString
    , field "mountId" SchemaString
    ]

serverLayerContractCodec :: FrontendCodec Aeson.Value
serverLayerContractCodec = valueCodec "ServerLayerContract" $ recordSchema "ServerLayerContract"
    [ field "name" SchemaString
    , field "domId" SchemaString
    ]

disposableLayerContractCodec :: FrontendCodec Aeson.Value
disposableLayerContractCodec = valueCodec "DisposableLayerContract" $ recordSchema "DisposableLayerContract"
    [ field "kind" (SchemaRef "InteractionDisposableLayerName")
    , field "name" SchemaString
    , field "domId" SchemaString
    ]

sessionKindContractCodec :: FrontendCodec Aeson.Value
sessionKindContractCodec = valueCodec "SessionKindContract" $ recordSchema "SessionKindContract"
    [ field "kind" (SchemaRef "InteractionSessionKindName")
    , field "description" SchemaString
    ]

intentFieldSchemaCodec :: FrontendCodec Aeson.Value
intentFieldSchemaCodec = valueCodec "IntentFieldSchema" $ recordSchema "IntentFieldSchema"
    [ field "name" (SchemaRef "InteractionIntentFieldName")
    , field "presence" (SchemaRef "InteractionFieldPresence")
    , field "defaultValue" (SchemaOptional (SchemaNullable SchemaString))
    ]

intentHiddenFieldCodec :: FrontendCodec Aeson.Value
intentHiddenFieldCodec = valueCodec "IntentHiddenField" $ recordSchema "IntentHiddenField"
    [ field "name" SchemaString
    , field "value" SchemaString
    ]

interactionIntentTargetCodec :: FrontendCodec Aeson.Value
interactionIntentTargetCodec = valueCodec "InteractionIntentTarget" $ taggedUnionSchema "InteractionIntentTarget" "kind"
    [ variant "live_fragment" [field "fragment" (SchemaRef "LiveUpdateWireFragment")]
    , variant "mount_local" [field "target" SchemaString]
    ]

intentFormContractCodec :: FrontendCodec Aeson.Value
intentFormContractCodec = valueCodec "IntentFormContract" $ recordSchema "IntentFormContract"
    [ field "intent" (SchemaRef "InteractionIntentName")
    , field "name" (SchemaRef "InteractionIntentName")
    , field "action" SchemaString
    , field "method" (SchemaRef "HtmxMethod")
    , field "trigger" SchemaString
    , field "target" (SchemaRef "InteractionIntentTarget")
    , field "swap" (SchemaRef "HtmxSwap")
    , field "fields" (SchemaArray (SchemaRef "IntentFieldSchema"))
    , field "hiddenFields" (SchemaArray (SchemaRef "IntentHiddenField"))
    , field "sync" (SchemaOptional (SchemaNullable SchemaString))
    , field "disabledElement" (SchemaOptional (SchemaNullable SchemaString))
    ]

interactionConflictPolicyCodec :: FrontendCodec Aeson.Value
interactionConflictPolicyCodec = valueCodec "InteractionConflictPolicy" $ recordSchema "InteractionConflictPolicy"
    [ field "session" (SchemaRef "InteractionSessionSelector")
    , field "fragment" (SchemaRef "InteractionFragmentSelector")
    , field "resolution" (SchemaRef "InteractionConflictResolution")
    , field "timeoutMs" (SchemaOptional (SchemaNullable SchemaInt))
    ]

interactionCapabilityContractCodec :: FrontendCodec Aeson.Value
interactionCapabilityContractCodec = valueCodec "InteractionCapabilityContract" $ recordSchema "InteractionCapabilityContract"
    [ field "mount" (SchemaRef "InteractionMountMetadata")
    , field "serverLayers" (SchemaArray (SchemaRef "ServerLayerContract"))
    , field "disposableLayers" (SchemaArray (SchemaRef "DisposableLayerContract"))
    , field "sessionKinds" (SchemaArray (SchemaRef "SessionKindContract"))
    , field "intentForms" (SchemaArray (SchemaRef "IntentFormContract"))
    , field "conflictPolicies" (SchemaArray (SchemaRef "InteractionConflictPolicy"))
    ]

interactionStaticServerLayerCodec :: FrontendCodec Aeson.Value
interactionStaticServerLayerCodec = valueCodec "InteractionStaticServerLayer" $ recordSchema "InteractionStaticServerLayer"
    [ field "name" SchemaString
    , field "domIdSuffix" SchemaString
    ]

interactionStaticDisposableLayerCodec :: FrontendCodec Aeson.Value
interactionStaticDisposableLayerCodec = valueCodec "InteractionStaticDisposableLayer" $ recordSchema "InteractionStaticDisposableLayer"
    [ field "name" (SchemaRef "InteractionDisposableLayerName")
    , field "domIdSuffix" SchemaString
    ]

interactionStaticSessionKindCodec :: FrontendCodec Aeson.Value
interactionStaticSessionKindCodec = valueCodec "InteractionStaticSessionKind" $ recordSchema "InteractionStaticSessionKind"
    [ field "kind" (SchemaRef "InteractionSessionKindName")
    , field "description" SchemaString
    ]

interactionStaticIntentCodec :: FrontendCodec Aeson.Value
interactionStaticIntentCodec = valueCodec "InteractionStaticIntent" $ recordSchema "InteractionStaticIntent"
    [ field "name" (SchemaRef "InteractionIntentName")
    , field "fields" (SchemaArray (SchemaRef "IntentFieldSchema"))
    ]

interactionStaticSchemaCodec :: FrontendCodec Aeson.Value
interactionStaticSchemaCodec = valueCodec "InteractionStaticSchema" $ recordSchema "InteractionStaticSchema"
    [ field "serverLayers" (SchemaArray (SchemaRef "InteractionStaticServerLayer"))
    , field "disposableLayers" (SchemaArray (SchemaRef "InteractionStaticDisposableLayer"))
    , field "sessionKinds" (SchemaArray (SchemaRef "InteractionStaticSessionKind"))
    , field "intents" (SchemaArray (SchemaRef "InteractionStaticIntent"))
    , field "conflictPolicies" (SchemaArray (SchemaRef "InteractionConflictPolicy"))
    ]

interactionStaticSchemaRegistryCodec :: FrontendCodec Aeson.Value
interactionStaticSchemaRegistryCodec = valueCodec "InteractionStaticSchemaRegistry" $ recordSchema "InteractionStaticSchemaRegistry"
    [ field schema.familyName (SchemaRef "InteractionStaticSchema")
    | schema <- knownInteractionSchemas
    ]

data KnownInteractionSchema = KnownInteractionSchema
    { familyName           :: !Text
    , serverLayerNames     :: ![Text]
    , disposableLayerNames :: ![Text]
    , sessionKindNames     :: ![Text]
    , intentNames          :: ![Text]
    , intentFieldNames     :: ![Text]
    , schemaJson           :: !Aeson.Value
    }

knownInteractionSchemas :: [KnownInteractionSchema]
knownInteractionSchemas =
    [ knownSchema "roster" rosterInteractionStaticSchema
    ]

knownSchema :: Eq session => Text -> InteractionStaticSchema fragment layer session intent -> KnownInteractionSchema
knownSchema familyName schema =
    KnownInteractionSchema
        { familyName
        , serverLayerNames = fmap (.serverLayerName) schema.interactionStaticServerLayers
        , disposableLayerNames = fmap (.disposableLayerName) schema.interactionStaticDisposableLayers
        , sessionKindNames = fmap (.sessionKindName) schema.interactionStaticSessionKinds
        , intentNames = fmap (.interactionIntentSchemaName) schema.interactionStaticIntents
        , intentFieldNames = unique (concatMap (fmap (unIntentFieldName . (.intentFieldName)) . (.interactionIntentSchemaFields)) schema.interactionStaticIntents)
        , schemaJson = Aeson.object
            [ "serverLayers" Aeson..= fmap serverLayerJson schema.interactionStaticServerLayers
            , "disposableLayers" Aeson..= fmap disposableLayerJson schema.interactionStaticDisposableLayers
            , "sessionKinds" Aeson..= fmap sessionKindJson schema.interactionStaticSessionKinds
            , "intents" Aeson..= fmap intentJson schema.interactionStaticIntents
            , "conflictPolicies" Aeson..= fmap (conflictPolicyJson schema) schema.interactionStaticConflictPolicies
            ]
        }

serverLayerJson :: ServerLayerDefinition -> Aeson.Value
serverLayerJson layer = Aeson.object
    [ "name" Aeson..= layer.serverLayerName
    , "domIdSuffix" Aeson..= layer.serverLayerDomIdSuffix
    ]

disposableLayerJson :: DisposableLayerDefinition layer -> Aeson.Value
disposableLayerJson layer = Aeson.object
    [ "name" Aeson..= layer.disposableLayerName
    , "domIdSuffix" Aeson..= layer.disposableLayerDomIdSuffix
    ]

sessionKindJson :: SessionKindDefinition session -> Aeson.Value
sessionKindJson session = Aeson.object
    [ "kind" Aeson..= session.sessionKindName
    , "description" Aeson..= session.sessionDescription
    ]

intentJson :: InteractionIntentSchema intent -> Aeson.Value
intentJson intent = Aeson.object
    [ "name" Aeson..= intent.interactionIntentSchemaName
    , "fields" Aeson..= fmap intentFieldJson intent.interactionIntentSchemaFields
    ]

intentFieldJson :: IntentFieldSchema -> Aeson.Value
intentFieldJson field = Aeson.object
    [ "name" Aeson..= field.intentFieldName.unIntentFieldName
    , "presence" Aeson..= fieldPresenceText field.intentFieldPresence
    , "defaultValue" Aeson..= field.intentFieldDefaultValue
    ]

conflictPolicyJson :: Eq session => InteractionStaticSchema fragment layer session intent -> InteractionConflictPolicy fragment session -> Aeson.Value
conflictPolicyJson schema policy = Aeson.object
    [ "session" Aeson..= sessionSelectorJson policy.conflictPolicySession
    , "fragment" Aeson..= fragmentSelectorJson policy.conflictPolicyFragment
    , "resolution" Aeson..= conflictResolutionText policy.conflictPolicyResolution
    , "timeoutMs" Aeson..= policy.conflictPolicyTimeoutMs
    ]
    where
        sessionSelectorJson AnyInteractionSession = Aeson.object ["kind" Aeson..= ("any" :: Text)]
        sessionSelectorJson (InteractionSessionKind session) = Aeson.object
            [ "kind" Aeson..= ("session" :: Text)
            , "session" Aeson..= fromMaybe "<session-kind>" do
                matching <- find ((== session) . (.sessionKind)) schema.interactionStaticSessionKinds
                pure matching.sessionKindName
            ]
        fragmentSelectorJson AnyInteractionFragment = Aeson.object ["kind" Aeson..= ("any" :: Text)]
        fragmentSelectorJson (InteractionFragment _) = error "Static interaction schema cannot encode an opaque fragment selector"

fieldPresenceText :: InteractionFieldPresence -> Text
fieldPresenceText value = fromMaybe (error "Unknown interaction field presence") (lookup value interactionFieldPresenceValues)

conflictResolutionText :: InteractionConflictResolution -> Text
conflictResolutionText value = fromMaybe (error "Unknown interaction conflict resolution") (lookup value interactionConflictResolutionValues)

interactionDomJson :: InteractionDom -> Aeson.Value
interactionDomJson dom = Aeson.object
    [ "attributes" Aeson..= interactionDomAttributesJson dom.interactionDomAttributes
    , "values" Aeson..= interactionDomValuesJson dom.interactionDomValues
    , "pointerFields" Aeson..= interactionPointerFieldsJson dom.interactionDomPointerFields
    ]

parseInteractionDom :: Aeson.Value -> AesonTypes.Parser InteractionDom
parseInteractionDom = Aeson.withObject "InteractionDom" \object -> do
    interactionDomAttributes <- (object Aeson..: "attributes") >>= parseInteractionDomAttributes
    interactionDomValues <- (object Aeson..: "values") >>= parseInteractionDomValues
    interactionDomPointerFields <- (object Aeson..: "pointerFields") >>= parseInteractionPointerFields
    pure InteractionDom { interactionDomAttributes, interactionDomValues, interactionDomPointerFields }

interactionDomAttributesJson :: InteractionDomAttributes -> Aeson.Value
interactionDomAttributesJson attrs = Aeson.object
    [ "surface" Aeson..= attrs.interactionDomSurfaceAttribute
    , "surfaceFamily" Aeson..= attrs.interactionDomSurfaceFamilyAttribute
    , "scopeKey" Aeson..= attrs.interactionDomScopeKeyAttribute
    , "mountKey" Aeson..= attrs.interactionDomMountKeyAttribute
    , "marker" Aeson..= attrs.interactionDomMarkerAttribute
    , "item" Aeson..= attrs.interactionDomItemAttribute
    , "container" Aeson..= attrs.interactionDomContainerAttribute
    , "slot" Aeson..= attrs.interactionDomSlotAttribute
    , "dropzone" Aeson..= attrs.interactionDomDropzoneAttribute
    , "resizeHandle" Aeson..= attrs.interactionDomResizeHandleAttribute
    , "activation" Aeson..= attrs.interactionDomActivationAttribute
    , "activationIntent" Aeson..= attrs.interactionDomActivationIntentAttribute
    , "activationTrigger" Aeson..= attrs.interactionDomActivationTriggerAttribute
    , "activationValueField" Aeson..= attrs.interactionDomActivationValueFieldAttribute
    , "pointerSession" Aeson..= attrs.interactionDomPointerSessionAttribute
    , "sessionKind" Aeson..= attrs.interactionDomSessionKindAttribute
    , "sessionIntent" Aeson..= attrs.interactionDomSessionIntentAttribute
    , "sessionDisabled" Aeson..= attrs.interactionDomSessionDisabledAttribute
    , "sessionReadOnly" Aeson..= attrs.interactionDomSessionReadOnlyAttribute
    , "sessionThreshold" Aeson..= attrs.interactionDomSessionThresholdAttribute
    , "sessionTimeoutMs" Aeson..= attrs.interactionDomSessionTimeoutMsAttribute
    , "interactionActive" Aeson..= attrs.interactionDomInteractionActiveAttribute
    , "serverLayer" Aeson..= attrs.interactionDomServerLayerAttribute
    , "disposableLayer" Aeson..= attrs.interactionDomDisposableLayerAttribute
    , "layer" Aeson..= attrs.interactionDomLayerAttribute
    , "conflictPolicies" Aeson..= attrs.interactionDomConflictPoliciesAttribute
    , "intentForm" Aeson..= attrs.interactionDomIntentFormAttribute
    , "intent" Aeson..= attrs.interactionDomIntentAttribute
    , "intentField" Aeson..= attrs.interactionDomIntentFieldAttribute
    , "fieldPresence" Aeson..= attrs.interactionDomFieldPresenceAttribute
    , "intentHiddenField" Aeson..= attrs.interactionDomIntentHiddenFieldAttribute
    ]

parseInteractionDomAttributes :: Aeson.Value -> AesonTypes.Parser InteractionDomAttributes
parseInteractionDomAttributes = Aeson.withObject "InteractionDomAttributes" \object -> do
    interactionDomSurfaceAttribute <- object Aeson..: "surface"
    interactionDomSurfaceFamilyAttribute <- object Aeson..: "surfaceFamily"
    interactionDomScopeKeyAttribute <- object Aeson..: "scopeKey"
    interactionDomMountKeyAttribute <- object Aeson..: "mountKey"
    interactionDomMarkerAttribute <- object Aeson..: "marker"
    interactionDomItemAttribute <- object Aeson..: "item"
    interactionDomContainerAttribute <- object Aeson..: "container"
    interactionDomSlotAttribute <- object Aeson..: "slot"
    interactionDomDropzoneAttribute <- object Aeson..: "dropzone"
    interactionDomResizeHandleAttribute <- object Aeson..: "resizeHandle"
    interactionDomActivationAttribute <- object Aeson..: "activation"
    interactionDomActivationIntentAttribute <- object Aeson..: "activationIntent"
    interactionDomActivationTriggerAttribute <- object Aeson..: "activationTrigger"
    interactionDomActivationValueFieldAttribute <- object Aeson..: "activationValueField"
    interactionDomPointerSessionAttribute <- object Aeson..: "pointerSession"
    interactionDomSessionKindAttribute <- object Aeson..: "sessionKind"
    interactionDomSessionIntentAttribute <- object Aeson..: "sessionIntent"
    interactionDomSessionDisabledAttribute <- object Aeson..: "sessionDisabled"
    interactionDomSessionReadOnlyAttribute <- object Aeson..: "sessionReadOnly"
    interactionDomSessionThresholdAttribute <- object Aeson..: "sessionThreshold"
    interactionDomSessionTimeoutMsAttribute <- object Aeson..: "sessionTimeoutMs"
    interactionDomInteractionActiveAttribute <- object Aeson..: "interactionActive"
    interactionDomServerLayerAttribute <- object Aeson..: "serverLayer"
    interactionDomDisposableLayerAttribute <- object Aeson..: "disposableLayer"
    interactionDomLayerAttribute <- object Aeson..: "layer"
    interactionDomConflictPoliciesAttribute <- object Aeson..: "conflictPolicies"
    interactionDomIntentFormAttribute <- object Aeson..: "intentForm"
    interactionDomIntentAttribute <- object Aeson..: "intent"
    interactionDomIntentFieldAttribute <- object Aeson..: "intentField"
    interactionDomFieldPresenceAttribute <- object Aeson..: "fieldPresence"
    interactionDomIntentHiddenFieldAttribute <- object Aeson..: "intentHiddenField"
    pure InteractionDomAttributes {..}

interactionDomValuesJson :: InteractionDomValues -> Aeson.Value
interactionDomValuesJson values = Aeson.object
    [ "enabled" Aeson..= values.interactionDomEnabledValue
    , "itemMarker" Aeson..= values.interactionDomItemMarkerValue
    , "containerMarker" Aeson..= values.interactionDomContainerMarkerValue
    , "slotMarker" Aeson..= values.interactionDomSlotMarkerValue
    , "dropzoneMarker" Aeson..= values.interactionDomDropzoneMarkerValue
    , "resizeHandleMarker" Aeson..= values.interactionDomResizeHandleMarkerValue
    , "activationMarker" Aeson..= values.interactionDomActivationMarkerValue
    ]

parseInteractionDomValues :: Aeson.Value -> AesonTypes.Parser InteractionDomValues
parseInteractionDomValues = Aeson.withObject "InteractionDomValues" \object -> do
    interactionDomEnabledValue <- object Aeson..: "enabled"
    interactionDomItemMarkerValue <- object Aeson..: "itemMarker"
    interactionDomContainerMarkerValue <- object Aeson..: "containerMarker"
    interactionDomSlotMarkerValue <- object Aeson..: "slotMarker"
    interactionDomDropzoneMarkerValue <- object Aeson..: "dropzoneMarker"
    interactionDomResizeHandleMarkerValue <- object Aeson..: "resizeHandleMarker"
    interactionDomActivationMarkerValue <- object Aeson..: "activationMarker"
    pure InteractionDomValues {..}

interactionPointerFieldsJson :: InteractionPointerFields -> Aeson.Value
interactionPointerFieldsJson fields = Aeson.object
    [ "sessionKind" Aeson..= fields.interactionPointerSessionKindField
    , "pointerId" Aeson..= fields.interactionPointerIdField
    , "pointerType" Aeson..= fields.interactionPointerTypeField
    , "startClientX" Aeson..= fields.interactionPointerStartClientXField
    , "startClientY" Aeson..= fields.interactionPointerStartClientYField
    , "currentClientX" Aeson..= fields.interactionPointerCurrentClientXField
    , "currentClientY" Aeson..= fields.interactionPointerCurrentClientYField
    , "deltaX" Aeson..= fields.interactionPointerDeltaXField
    , "deltaY" Aeson..= fields.interactionPointerDeltaYField
    , "sourceItemKey" Aeson..= fields.interactionPointerSourceItemKeyField
    , "targetDropzoneKey" Aeson..= fields.interactionPointerTargetDropzoneKeyField
    ]

parseInteractionPointerFields :: Aeson.Value -> AesonTypes.Parser InteractionPointerFields
parseInteractionPointerFields = Aeson.withObject "InteractionPointerFields" \object -> do
    interactionPointerSessionKindField <- object Aeson..: "sessionKind"
    interactionPointerIdField <- object Aeson..: "pointerId"
    interactionPointerTypeField <- object Aeson..: "pointerType"
    interactionPointerStartClientXField <- object Aeson..: "startClientX"
    interactionPointerStartClientYField <- object Aeson..: "startClientY"
    interactionPointerCurrentClientXField <- object Aeson..: "currentClientX"
    interactionPointerCurrentClientYField <- object Aeson..: "currentClientY"
    interactionPointerDeltaXField <- object Aeson..: "deltaX"
    interactionPointerDeltaYField <- object Aeson..: "deltaY"
    interactionPointerSourceItemKeyField <- object Aeson..: "sourceItemKey"
    interactionPointerTargetDropzoneKeyField <- object Aeson..: "targetDropzoneKey"
    pure InteractionPointerFields {..}

interactionDomAttributeValues :: [Text]
interactionDomAttributeValues =
    let attrs = canonicalInteractionDom.interactionDomAttributes
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

valueCodec :: Text -> FrontendSchema -> FrontendCodec Aeson.Value
valueCodec name schema =
    FrontendCodec
        { codecName = Just name
        , codecSchema = schema
        , codecEncode = id
        , codecParse = pure
        }

textEnumCodec :: Text -> [Text] -> FrontendCodec Text
textEnumCodec name values =
    stringEnumCodec name [(value, value) | value <- values]

unique :: [Text] -> [Text]
unique = foldr (\value acc -> if value `elem` acc then acc else value : acc) []
