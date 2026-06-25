module Application.Helper.Frontend.InteractionSchema
    ( interactionSchemaDeclaration
    ) where

import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..),
                                               TypeScriptDeclarationOrigin (HaskellSchemaGenerated),
                                               stringUnionDeclaration)
import Application.Helper.Interaction
import qualified Data.Aeson as Aeson
import qualified Data.Aeson.Key as AesonKey
import qualified Data.ByteString.Lazy as LBS
import qualified Data.Text as Text
import qualified Data.Text.Encoding as TextEncoding
import IHP.Prelude
import Web.RosterWeeks.LiveSurface (rosterInteractionStaticSchema)

interactionSchemaDeclaration :: TypeScriptDeclaration
interactionSchemaDeclaration =
    TypeScriptDeclaration
        { name = "InteractionContracts"
        , origin = HaskellSchemaGenerated
        , source = Text.unlines
            [ "// Interaction contracts generated from Haskell static interaction schemas."
            , interactionDomSource
            , stringUnionSource "InteractionActivationTrigger" (fmap snd interactionActivationTriggerValues)
            , stringUnionSource "InteractionFieldPresence" (fmap snd interactionFieldPresenceValues)
            , stringUnionSource "HtmxMethod" (fmap snd htmxMethodValues)
            , stringUnionSource "HtmxSwap" (fmap snd htmxSwapValues <> ["custom"])
            , stringUnionSource "InteractionConflictResolution" (fmap snd interactionConflictResolutionValues)
            , stringUnionSource "InteractionSurfaceFamily" (fmap (.familyName) knownInteractionSchemas)
            , stringUnionSource "InteractionDisposableLayerName" (unique (concatMap (.disposableLayerNames) knownInteractionSchemas))
            , stringUnionSource "InteractionSessionKindName" (unique (concatMap (.sessionKindNames) knownInteractionSchemas))
            , stringUnionSource "InteractionIntentName" (unique (concatMap (.intentNames) knownInteractionSchemas))
            , stringUnionSource "InteractionIntentFieldName" (unique (concatMap (.intentFieldNames) knownInteractionSchemas))
            , interactionContractTypesSource
            , interactionStaticSchemasSource
            ]
        }

stringUnionSource :: Text -> [Text] -> Text
stringUnionSource name values =
    (stringUnionDeclaration name values).source

interactionStaticSchemasSource :: Text
interactionStaticSchemasSource =
    Text.unlines
        [ "export const InteractionStaticSchemas = " <> encodeJsonText (Aeson.object (fmap schemaPair knownInteractionSchemas)) <> " as const;"
        , ""
        , "export type InteractionStaticSchemaRegistry = typeof InteractionStaticSchemas;"
        ]
    where
        schemaPair schema = AesonKey.fromText schema.familyName Aeson..= schemaJson schema

interactionDomSource :: Text
interactionDomSource = Text.unlines
    [ "export const InteractionDom = {"
    , "    attributes: {"
    , "        surface: \"data-bepis-surface\","
    , "        surfaceFamily: \"data-bepis-surface-family\","
    , "        scopeKey: \"data-bepis-scope-key\","
    , "        mountKey: \"data-bepis-mount-key\","
    , "        marker: \"data-bepis-marker\","
    , "        item: \"data-bepis-item\","
    , "        dropzone: \"data-bepis-dropzone\","
    , "        activation: \"data-bepis-activation\","
    , "        activationIntent: \"data-bepis-activation-intent\","
    , "        activationTrigger: \"data-bepis-activation-trigger\","
    , "        activationValueField: \"data-bepis-activation-value-field\","
    , "        pointerSession: \"data-bepis-pointer-session\","
    , "        sessionKind: \"data-bepis-session-kind\","
    , "        sessionIntent: \"data-bepis-session-intent\","
    , "        sessionDisabled: \"data-bepis-session-disabled\","
    , "        sessionReadOnly: \"data-bepis-session-read-only\","
    , "        sessionThreshold: \"data-bepis-session-threshold\","
    , "        sessionTimeoutMs: \"data-bepis-session-timeout-ms\","
    , "        interactionActive: \"data-bepis-interaction-active\","
    , "        disposableLayer: \"data-bepis-disposable-layer\","
    , "        conflictPolicies: \"data-bepis-conflict-policies\","
    , "        intentForm: \"data-bepis-intent-form\","
    , "        intent: \"data-bepis-intent\","
    , "        intentField: \"data-bepis-intent-field\","
    , "        fieldPresence: \"data-bepis-field-presence\","
    , "        intentHiddenField: \"data-bepis-intent-hidden-field\""
    , "    },"
    , "    values: {"
    , "        enabled: \"true\","
    , "        activationMarker: \"activation\""
    , "    },"
    , "    pointerFields: {"
    , "        sessionKind: \"sessionKind\","
    , "        pointerId: \"pointerId\","
    , "        pointerType: \"pointerType\","
    , "        startClientX: \"startClientX\","
    , "        startClientY: \"startClientY\","
    , "        currentClientX: \"currentClientX\","
    , "        currentClientY: \"currentClientY\","
    , "        deltaX: \"deltaX\","
    , "        deltaY: \"deltaY\","
    , "        sourceItemKey: \"sourceItemKey\","
    , "        targetDropzoneKey: \"targetDropzoneKey\""
    , "    }"
    , "} as const;"
    , ""
    , "export type InteractionDomAttribute = typeof InteractionDom.attributes[keyof typeof InteractionDom.attributes];"
    ]

interactionContractTypesSource :: Text
interactionContractTypesSource = Text.unlines
    [ "export type InteractionMountMetadata = {"
    , "    surfaceFamily: InteractionSurfaceFamily | string;"
    , "    scopeKey: string;"
    , "    mountKey: string;"
    , "    mountId: string;"
    , "};"
    , ""
    , "export type ServerLayerContract = { name: string; domId: string };"
    , ""
    , "export type DisposableLayerContract = { kind: InteractionDisposableLayerName | string; name: string; domId: string };"
    , ""
    , "export type SessionKindContract = { kind: InteractionSessionKindName | string; description: string };"
    , ""
    , "export type IntentFieldSchema = {"
    , "    name: InteractionIntentFieldName | string;"
    , "    presence: InteractionFieldPresence;"
    , "    defaultValue?: string | null;"
    , "};"
    , ""
    , "export type IntentHiddenField = { name: string; value: string };"
    , ""
    , "export type InteractionIntentTarget ="
    , "    | { kind: \"live_fragment\"; fragment: LiveUpdateWireFragment }"
    , "    | { kind: \"mount_local\"; target: string };"
    , ""
    , "export type IntentFormContract = {"
    , "    intent: InteractionIntentName | string;"
    , "    name: InteractionIntentName | string;"
    , "    action: string;"
    , "    method: HtmxMethod;"
    , "    trigger: string;"
    , "    target: InteractionIntentTarget;"
    , "    swap: HtmxSwap | { kind: \"custom\"; value: string };"
    , "    fields: IntentFieldSchema[];"
    , "    hiddenFields: IntentHiddenField[];"
    , "    sync?: string | null;"
    , "    disabledElement?: string | null;"
    , "};"
    , ""
    , "export type InteractionConflictPolicy = {"
    , "    session: InteractionSessionKindName | \"*\" | string;"
    , "    fragment: LiveFragmentKey | \"*\";"
    , "    resolution: InteractionConflictResolution;"
    , "    timeoutMs?: number | null;"
    , "};"
    , ""
    , "export type InteractionCapabilityContract = {"
    , "    mount: InteractionMountMetadata;"
    , "    serverLayers: ServerLayerContract[];"
    , "    disposableLayers: DisposableLayerContract[];"
    , "    sessionKinds: SessionKindContract[];"
    , "    intentForms: IntentFormContract[];"
    , "    conflictPolicies: InteractionConflictPolicy[];"
    , "};"
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
    [ "session" Aeson..= sessionSelectorText policy.conflictPolicySession
    , "fragment" Aeson..= fragmentSelectorText policy.conflictPolicyFragment
    , "resolution" Aeson..= conflictResolutionText policy.conflictPolicyResolution
    , "timeoutMs" Aeson..= policy.conflictPolicyTimeoutMs
    ]
    where
        sessionSelectorText AnyInteractionSession = "*" :: Text
        sessionSelectorText (InteractionSessionKind session) =
            fromMaybe "<session-kind>" do
                matching <- find ((== session) . (.sessionKind)) schema.interactionStaticSessionKinds
                pure matching.sessionKindName
        fragmentSelectorText AnyInteractionFragment  = "*" :: Text
        fragmentSelectorText (InteractionFragment _) = "<fragment>"

fieldPresenceText :: InteractionFieldPresence -> Text
fieldPresenceText value = fromMaybe (error "Unknown interaction field presence") (lookup value interactionFieldPresenceValues)

conflictResolutionText :: InteractionConflictResolution -> Text
conflictResolutionText value = fromMaybe (error "Unknown interaction conflict resolution") (lookup value interactionConflictResolutionValues)

encodeJsonText :: Aeson.Value -> Text
encodeJsonText = TextEncoding.decodeUtf8 . LBS.toStrict . Aeson.encode

unique :: [Text] -> [Text]
unique = foldr (\value acc -> if value `elem` acc then acc else value : acc) []
