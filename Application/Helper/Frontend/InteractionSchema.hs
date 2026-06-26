module Application.Helper.Frontend.InteractionSchema
    ( interactionSchemaDeclaration
    ) where

import Application.Helper.Frontend.Codec (FrontendCodec (..),
                                          FrontendField (..),
                                          FrontendSchema (..),
                                          FrontendVariant (..),
                                          SomeFrontendCodec (..),
                                          renderFrontendContracts,
                                          renderTypedConstant, stringEnumCodec)
import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..),
                                               TypeScriptDeclarationOrigin (HaskellSchemaGenerated))
import Application.Helper.Interaction
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.Text as Text
import IHP.Prelude
import Web.RosterWeeks.LiveSurface (rosterInteractionStaticSchema)

interactionSchemaDeclaration :: TypeScriptDeclaration
interactionSchemaDeclaration =
    TypeScriptDeclaration
        { name = "InteractionContracts"
        , origin = HaskellSchemaGenerated
        , source = Text.unlines
            [ "// Interaction contracts generated from Haskell static interaction schemas."
            , interactionContractTypesSource
            , interactionDomConstantSource
            , interactionStaticSchemasSource
            ]
        }

interactionContractTypesSource :: Text
interactionContractTypesSource =
    case renderFrontendContracts interactionContractCodecs of
        Right source -> source
        Left message -> error ("Unable to render interaction contracts: " <> cs message)

interactionDomConstantSource :: Text
interactionDomConstantSource =
    renderTypedConstant "InteractionDom" interactionDomCodec interactionDomJson

interactionStaticSchemasSource :: Text
interactionStaticSchemasSource =
    renderTypedConstant "InteractionStaticSchemas" interactionStaticSchemaRegistryCodec interactionStaticSchemasJson

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

interactionDomAttributesCodec :: FrontendCodec Aeson.Value
interactionDomAttributesCodec = valueCodec "InteractionDomAttributes" $ SchemaRecord "InteractionDomAttributes"
    [ FrontendField "surface" SchemaString
    , FrontendField "surfaceFamily" SchemaString
    , FrontendField "scopeKey" SchemaString
    , FrontendField "mountKey" SchemaString
    , FrontendField "marker" SchemaString
    , FrontendField "item" SchemaString
    , FrontendField "dropzone" SchemaString
    , FrontendField "activation" SchemaString
    , FrontendField "activationIntent" SchemaString
    , FrontendField "activationTrigger" SchemaString
    , FrontendField "activationValueField" SchemaString
    , FrontendField "pointerSession" SchemaString
    , FrontendField "sessionKind" SchemaString
    , FrontendField "sessionIntent" SchemaString
    , FrontendField "sessionDisabled" SchemaString
    , FrontendField "sessionReadOnly" SchemaString
    , FrontendField "sessionThreshold" SchemaString
    , FrontendField "sessionTimeoutMs" SchemaString
    , FrontendField "interactionActive" SchemaString
    , FrontendField "disposableLayer" SchemaString
    , FrontendField "conflictPolicies" SchemaString
    , FrontendField "intentForm" SchemaString
    , FrontendField "intent" SchemaString
    , FrontendField "intentField" SchemaString
    , FrontendField "fieldPresence" SchemaString
    , FrontendField "intentHiddenField" SchemaString
    ]

interactionDomValuesCodec :: FrontendCodec Aeson.Value
interactionDomValuesCodec = valueCodec "InteractionDomValues" $ SchemaRecord "InteractionDomValues"
    [ FrontendField "enabled" SchemaString
    , FrontendField "activationMarker" SchemaString
    ]

interactionPointerFieldsCodec :: FrontendCodec Aeson.Value
interactionPointerFieldsCodec = valueCodec "InteractionPointerFields" $ SchemaRecord "InteractionPointerFields"
    [ FrontendField "sessionKind" SchemaString
    , FrontendField "pointerId" SchemaString
    , FrontendField "pointerType" SchemaString
    , FrontendField "startClientX" SchemaString
    , FrontendField "startClientY" SchemaString
    , FrontendField "currentClientX" SchemaString
    , FrontendField "currentClientY" SchemaString
    , FrontendField "deltaX" SchemaString
    , FrontendField "deltaY" SchemaString
    , FrontendField "sourceItemKey" SchemaString
    , FrontendField "targetDropzoneKey" SchemaString
    ]

interactionDomCodec :: FrontendCodec Aeson.Value
interactionDomCodec = FrontendCodec
    { codecName = Just "InteractionDom"
    , codecSchema = SchemaRecord "InteractionDom"
        [ FrontendField "attributes" (SchemaRef "InteractionDomAttributes")
        , FrontendField "values" (SchemaRef "InteractionDomValues")
        , FrontendField "pointerFields" (SchemaRef "InteractionPointerFields")
        ]
    , codecEncode = const interactionDomJson
    , codecParse = pure
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
interactionSessionSelectorCodec = valueCodec "InteractionSessionSelector" $ SchemaTaggedUnion "InteractionSessionSelector" "kind"
    [ FrontendVariant "any" []
    , FrontendVariant "session" [FrontendField "session" (SchemaRef "InteractionSessionKindName")]
    ]

interactionFragmentSelectorCodec :: FrontendCodec Aeson.Value
interactionFragmentSelectorCodec = valueCodec "InteractionFragmentSelector" $ SchemaTaggedUnion "InteractionFragmentSelector" "kind"
    [ FrontendVariant "any" []
    , FrontendVariant "live_fragment" [FrontendField "fragment" (SchemaRef "LiveFragmentKey")]
    ]

interactionMountMetadataCodec :: FrontendCodec Aeson.Value
interactionMountMetadataCodec = valueCodec "InteractionMountMetadata" $ SchemaRecord "InteractionMountMetadata"
    [ FrontendField "surfaceFamily" (SchemaRef "InteractionSurfaceFamily")
    , FrontendField "scopeKey" SchemaString
    , FrontendField "mountKey" SchemaString
    , FrontendField "mountId" SchemaString
    ]

serverLayerContractCodec :: FrontendCodec Aeson.Value
serverLayerContractCodec = valueCodec "ServerLayerContract" $ SchemaRecord "ServerLayerContract"
    [ FrontendField "name" SchemaString
    , FrontendField "domId" SchemaString
    ]

disposableLayerContractCodec :: FrontendCodec Aeson.Value
disposableLayerContractCodec = valueCodec "DisposableLayerContract" $ SchemaRecord "DisposableLayerContract"
    [ FrontendField "kind" (SchemaRef "InteractionDisposableLayerName")
    , FrontendField "name" SchemaString
    , FrontendField "domId" SchemaString
    ]

sessionKindContractCodec :: FrontendCodec Aeson.Value
sessionKindContractCodec = valueCodec "SessionKindContract" $ SchemaRecord "SessionKindContract"
    [ FrontendField "kind" (SchemaRef "InteractionSessionKindName")
    , FrontendField "description" SchemaString
    ]

intentFieldSchemaCodec :: FrontendCodec Aeson.Value
intentFieldSchemaCodec = valueCodec "IntentFieldSchema" $ SchemaRecord "IntentFieldSchema"
    [ FrontendField "name" (SchemaRef "InteractionIntentFieldName")
    , FrontendField "presence" (SchemaRef "InteractionFieldPresence")
    , FrontendField "defaultValue" (SchemaOptional (SchemaNullable SchemaString))
    ]

intentHiddenFieldCodec :: FrontendCodec Aeson.Value
intentHiddenFieldCodec = valueCodec "IntentHiddenField" $ SchemaRecord "IntentHiddenField"
    [ FrontendField "name" SchemaString
    , FrontendField "value" SchemaString
    ]

interactionIntentTargetCodec :: FrontendCodec Aeson.Value
interactionIntentTargetCodec = valueCodec "InteractionIntentTarget" $ SchemaTaggedUnion "InteractionIntentTarget" "kind"
    [ FrontendVariant "live_fragment" [FrontendField "fragment" (SchemaRef "LiveUpdateWireFragment")]
    , FrontendVariant "mount_local" [FrontendField "target" SchemaString]
    ]

intentFormContractCodec :: FrontendCodec Aeson.Value
intentFormContractCodec = valueCodec "IntentFormContract" $ SchemaRecord "IntentFormContract"
    [ FrontendField "intent" (SchemaRef "InteractionIntentName")
    , FrontendField "name" (SchemaRef "InteractionIntentName")
    , FrontendField "action" SchemaString
    , FrontendField "method" (SchemaRef "HtmxMethod")
    , FrontendField "trigger" SchemaString
    , FrontendField "target" (SchemaRef "InteractionIntentTarget")
    , FrontendField "swap" (SchemaRef "HtmxSwap")
    , FrontendField "fields" (SchemaArray (SchemaRef "IntentFieldSchema"))
    , FrontendField "hiddenFields" (SchemaArray (SchemaRef "IntentHiddenField"))
    , FrontendField "sync" (SchemaOptional (SchemaNullable SchemaString))
    , FrontendField "disabledElement" (SchemaOptional (SchemaNullable SchemaString))
    ]

interactionConflictPolicyCodec :: FrontendCodec Aeson.Value
interactionConflictPolicyCodec = valueCodec "InteractionConflictPolicy" $ SchemaRecord "InteractionConflictPolicy"
    [ FrontendField "session" (SchemaRef "InteractionSessionSelector")
    , FrontendField "fragment" (SchemaRef "InteractionFragmentSelector")
    , FrontendField "resolution" (SchemaRef "InteractionConflictResolution")
    , FrontendField "timeoutMs" (SchemaOptional (SchemaNullable SchemaInt))
    ]

interactionCapabilityContractCodec :: FrontendCodec Aeson.Value
interactionCapabilityContractCodec = valueCodec "InteractionCapabilityContract" $ SchemaRecord "InteractionCapabilityContract"
    [ FrontendField "mount" (SchemaRef "InteractionMountMetadata")
    , FrontendField "serverLayers" (SchemaArray (SchemaRef "ServerLayerContract"))
    , FrontendField "disposableLayers" (SchemaArray (SchemaRef "DisposableLayerContract"))
    , FrontendField "sessionKinds" (SchemaArray (SchemaRef "SessionKindContract"))
    , FrontendField "intentForms" (SchemaArray (SchemaRef "IntentFormContract"))
    , FrontendField "conflictPolicies" (SchemaArray (SchemaRef "InteractionConflictPolicy"))
    ]

interactionStaticServerLayerCodec :: FrontendCodec Aeson.Value
interactionStaticServerLayerCodec = valueCodec "InteractionStaticServerLayer" $ SchemaRecord "InteractionStaticServerLayer"
    [ FrontendField "name" SchemaString
    , FrontendField "domIdSuffix" SchemaString
    ]

interactionStaticDisposableLayerCodec :: FrontendCodec Aeson.Value
interactionStaticDisposableLayerCodec = valueCodec "InteractionStaticDisposableLayer" $ SchemaRecord "InteractionStaticDisposableLayer"
    [ FrontendField "name" (SchemaRef "InteractionDisposableLayerName")
    , FrontendField "domIdSuffix" SchemaString
    ]

interactionStaticSessionKindCodec :: FrontendCodec Aeson.Value
interactionStaticSessionKindCodec = valueCodec "InteractionStaticSessionKind" $ SchemaRecord "InteractionStaticSessionKind"
    [ FrontendField "kind" (SchemaRef "InteractionSessionKindName")
    , FrontendField "description" SchemaString
    ]

interactionStaticIntentCodec :: FrontendCodec Aeson.Value
interactionStaticIntentCodec = valueCodec "InteractionStaticIntent" $ SchemaRecord "InteractionStaticIntent"
    [ FrontendField "name" (SchemaRef "InteractionIntentName")
    , FrontendField "fields" (SchemaArray (SchemaRef "IntentFieldSchema"))
    ]

interactionStaticSchemaCodec :: FrontendCodec Aeson.Value
interactionStaticSchemaCodec = valueCodec "InteractionStaticSchema" $ SchemaRecord "InteractionStaticSchema"
    [ FrontendField "serverLayers" (SchemaArray (SchemaRef "InteractionStaticServerLayer"))
    , FrontendField "disposableLayers" (SchemaArray (SchemaRef "InteractionStaticDisposableLayer"))
    , FrontendField "sessionKinds" (SchemaArray (SchemaRef "InteractionStaticSessionKind"))
    , FrontendField "intents" (SchemaArray (SchemaRef "InteractionStaticIntent"))
    , FrontendField "conflictPolicies" (SchemaArray (SchemaRef "InteractionConflictPolicy"))
    ]

interactionStaticSchemaRegistryCodec :: FrontendCodec Aeson.Value
interactionStaticSchemaRegistryCodec = valueCodec "InteractionStaticSchemaRegistry" $ SchemaRecord "InteractionStaticSchemaRegistry"
    [ FrontendField schema.familyName (SchemaRef "InteractionStaticSchema")
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

interactionDomJson :: Aeson.Value
interactionDomJson = Aeson.object
    [ "attributes" Aeson..= Aeson.object
        [ "surface" Aeson..= ("data-bepis-surface" :: Text)
        , "surfaceFamily" Aeson..= ("data-bepis-surface-family" :: Text)
        , "scopeKey" Aeson..= ("data-bepis-scope-key" :: Text)
        , "mountKey" Aeson..= ("data-bepis-mount-key" :: Text)
        , "marker" Aeson..= ("data-bepis-marker" :: Text)
        , "item" Aeson..= ("data-bepis-item" :: Text)
        , "dropzone" Aeson..= ("data-bepis-dropzone" :: Text)
        , "activation" Aeson..= ("data-bepis-activation" :: Text)
        , "activationIntent" Aeson..= ("data-bepis-activation-intent" :: Text)
        , "activationTrigger" Aeson..= ("data-bepis-activation-trigger" :: Text)
        , "activationValueField" Aeson..= ("data-bepis-activation-value-field" :: Text)
        , "pointerSession" Aeson..= ("data-bepis-pointer-session" :: Text)
        , "sessionKind" Aeson..= ("data-bepis-session-kind" :: Text)
        , "sessionIntent" Aeson..= ("data-bepis-session-intent" :: Text)
        , "sessionDisabled" Aeson..= ("data-bepis-session-disabled" :: Text)
        , "sessionReadOnly" Aeson..= ("data-bepis-session-read-only" :: Text)
        , "sessionThreshold" Aeson..= ("data-bepis-session-threshold" :: Text)
        , "sessionTimeoutMs" Aeson..= ("data-bepis-session-timeout-ms" :: Text)
        , "interactionActive" Aeson..= ("data-bepis-interaction-active" :: Text)
        , "disposableLayer" Aeson..= ("data-bepis-disposable-layer" :: Text)
        , "conflictPolicies" Aeson..= ("data-bepis-conflict-policies" :: Text)
        , "intentForm" Aeson..= ("data-bepis-intent-form" :: Text)
        , "intent" Aeson..= ("data-bepis-intent" :: Text)
        , "intentField" Aeson..= ("data-bepis-intent-field" :: Text)
        , "fieldPresence" Aeson..= ("data-bepis-field-presence" :: Text)
        , "intentHiddenField" Aeson..= ("data-bepis-intent-hidden-field" :: Text)
        ]
    , "values" Aeson..= Aeson.object
        [ "enabled" Aeson..= ("true" :: Text)
        , "activationMarker" Aeson..= ("activation" :: Text)
        ]
    , "pointerFields" Aeson..= Aeson.object
        [ "sessionKind" Aeson..= ("sessionKind" :: Text)
        , "pointerId" Aeson..= ("pointerId" :: Text)
        , "pointerType" Aeson..= ("pointerType" :: Text)
        , "startClientX" Aeson..= ("startClientX" :: Text)
        , "startClientY" Aeson..= ("startClientY" :: Text)
        , "currentClientX" Aeson..= ("currentClientX" :: Text)
        , "currentClientY" Aeson..= ("currentClientY" :: Text)
        , "deltaX" Aeson..= ("deltaX" :: Text)
        , "deltaY" Aeson..= ("deltaY" :: Text)
        , "sourceItemKey" Aeson..= ("sourceItemKey" :: Text)
        , "targetDropzoneKey" Aeson..= ("targetDropzoneKey" :: Text)
        ]
    ]

interactionDomAttributeValues :: [Text]
interactionDomAttributeValues =
    [ "data-bepis-surface"
    , "data-bepis-surface-family"
    , "data-bepis-scope-key"
    , "data-bepis-mount-key"
    , "data-bepis-marker"
    , "data-bepis-item"
    , "data-bepis-dropzone"
    , "data-bepis-activation"
    , "data-bepis-activation-intent"
    , "data-bepis-activation-trigger"
    , "data-bepis-activation-value-field"
    , "data-bepis-pointer-session"
    , "data-bepis-session-kind"
    , "data-bepis-session-intent"
    , "data-bepis-session-disabled"
    , "data-bepis-session-read-only"
    , "data-bepis-session-threshold"
    , "data-bepis-session-timeout-ms"
    , "data-bepis-interaction-active"
    , "data-bepis-disposable-layer"
    , "data-bepis-conflict-policies"
    , "data-bepis-intent-form"
    , "data-bepis-intent"
    , "data-bepis-intent-field"
    , "data-bepis-field-presence"
    , "data-bepis-intent-hidden-field"
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
