module Application.Helper.Frontend.LegacyManualContracts
    ( interactionContracts
    ) where

import Application.Helper.Frontend.TypeScript (TypeScriptDeclaration (..),
                                               legacyManualDeclaration,
                                               stringUnionDeclaration)
import Application.Helper.Interaction (htmxMethodValues, htmxSwapValues,
                                       interactionActivationTriggerValues,
                                       interactionConflictResolutionValues,
                                       interactionFieldPresenceValues)
import qualified Data.Text as Text
import IHP.Prelude

-- Temporary compatibility block for pre-existing handwritten interaction
-- contracts. Do not add new Haskell-owned DTOs here; migrate them through
-- Application.Helper.Frontend.TypeScript/aeson-typescript instead.

interactionContracts :: TypeScriptDeclaration
interactionContracts = legacyManualDeclaration "InteractionContracts" $ Text.unlines
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
        , ""
        , stringUnionSource "InteractionActivationTrigger" (fmap snd interactionActivationTriggerValues)
        , stringUnionSource "InteractionFieldPresence" (fmap snd interactionFieldPresenceValues)
        , stringUnionSource "HtmxMethod" (fmap snd htmxMethodValues)
        , stringUnionSource "HtmxSwap" (fmap snd htmxSwapValues <> ["custom"])
        , stringUnionSource "InteractionConflictResolution" (fmap snd interactionConflictResolutionValues)
        , "export type InteractionMountMetadata = {"
        , "    surfaceFamily: string;"
        , "    scopeKey: string;"
        , "    mountKey: string;"
        , "    mountId: string;"
        , "};"
        , ""
        , "export type ServerLayerContract = { name: string; domId: string };"
        , ""
        , "export type DisposableLayerContract = { kind: string; name: string; domId: string };"
        , ""
        , "export type SessionKindContract = { kind: string; description: string };"
        , ""
        , "export type IntentFieldSchema = {"
        , "    name: string;"
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
        , "    intent: string;"
        , "    name: string;"
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
        , "    session: string | \"*\";"
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

stringUnionSource :: Text -> [Text] -> Text
stringUnionSource name values =
    (stringUnionDeclaration name values).source

