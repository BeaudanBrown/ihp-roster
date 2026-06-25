module Application.Helper.Frontend.Contracts
( OverlayLane(..)
, TypeScriptDeclaration(..)
, frontendContractDeclarations
, frontendContractsTypeScript
)
where

import Application.Helper.Frontend.AesonTypeScriptSpike (aesonTypeScriptSpikeTypeScript)
import Application.Helper.Interaction (htmxMethodValues, htmxSwapValues,
                                       interactionActivationTriggerValues,
                                       interactionConflictResolutionValues,
                                       interactionFieldPresenceValues)
import qualified Data.Text as Text
import IHP.Prelude

data OverlayLane
    = DialogLane
    | PickerLane
    | ToastLane
    deriving (Eq, Show)

overlayLaneTypeName :: Text
overlayLaneTypeName = "OverlayLane"

overlayLaneValues :: [(OverlayLane, Text)]
overlayLaneValues =
    [ (DialogLane, "dialog")
    , (PickerLane, "picker")
    , (ToastLane, "toast")
    ]

data TypeScriptDeclaration = TypeScriptDeclaration
    { name   :: Text
    , source :: Text
    } deriving (Eq, Show)

stringUnionDeclaration :: Text -> [Text] -> TypeScriptDeclaration
stringUnionDeclaration name values = TypeScriptDeclaration
    { name
    , source = Text.unlines $
        [ "export type " <> name <> " =" ]
        <> unionLines
    }
    where
        quotedValues = fmap (\value -> "\"" <> value <> "\"") values
        unionLines = case reverse quotedValues of
            [] -> [ "    never;" ]
            lastValue : reversedPrefix ->
                fmap ("    | " <>) (reverse reversedPrefix)
                <> [ "    | " <> lastValue <> ";" ]

liveUpdateContracts :: TypeScriptDeclaration
liveUpdateContracts = TypeScriptDeclaration
    { name = "LiveUpdateContracts"
    , source = Text.unlines
        [ "export type LiveUpdateScope ="
        , "    | { kind: \"roster_week\"; venueId: string; rosterGroupId: string; weekOffset: number }"
        , "    | { kind: \"admin_venue_config\"; venueId: string }"
        , "    | { kind: \"admin_shift_types\"; venueId: string }"
        , "    | { kind: \"admin_roster_groups\"; venueId: string }"
        , "    | { kind: \"admin_invites\"; venueId: string }"
        , "    | { kind: \"admin_exports\"; venueId: string }"
        , "    | { kind: \"admin_xero\"; venueId: string }"
        , "    | { kind: \"billing\"; venueId: string }"
        , "    | { kind: \"leave_requests\"; venueId: string }"
        , "    | { kind: \"timesheet_week\"; venueId: string; weekOffset: number }"
        , "    | { kind: \"profile\"; venueId: string; staffId: string }"
        , "    | { kind: \"support_platform\" };"
        , ""
        , "export type LiveFragmentKey ="
        , "    | { kind: \"roster_content\" }"
        , "    | { kind: \"roster_grid_toolbar\" }"
        , "    | { kind: \"roster_grid_frame\" }"
        , "    | { kind: \"roster_day_columns\" }"
        , "    | { kind: \"roster_day_rail\" }"
        , "    | { kind: \"roster_wage_rail\" }"
        , "    | { kind: \"roster_slots_grid\" }"
        , "    | { kind: \"roster_staff_panel\" }"
        , "    | { kind: \"roster_day_section\"; rosterDayId: string }"
        , "    | { kind: \"roster_row\"; rosterDayId: string; rowIndex: number }"
        , "    | { kind: \"leave_requests_content\" }"
        , "    | { kind: \"timesheet_toolbar\" }"
        , "    | { kind: \"timesheet_day_columns\" }"
        , "    | { kind: \"timesheet_day_section\"; dayOffset: number }"
        , "    | { kind: \"admin_venue_config\" }"
        , "    | { kind: \"admin_invites\" }"
        , "    | { kind: \"admin_exports\" }"
        , "    | { kind: \"admin_shift_types\" }"
        , "    | { kind: \"admin_roster_groups\" }"
        , "    | { kind: \"admin_xero\" }"
        , "    | { kind: \"admin_xero_staff_mappings\" }"
        , "    | { kind: \"admin_xero_pay_items\" }"
        , "    | { kind: \"admin_xero_timesheets\" }"
        , "    | { kind: \"billing_status\" }"
        , "    | { kind: \"profile_content\" }"
        , "    | { kind: \"profile_leave_requests_content\" }"
        , "    | { kind: \"support_award_rates_section\" }"
        , "    | { kind: \"support_public_holidays_section\" };"
        , ""
        , "export type LiveFragmentProtection = null | { kind: \"focused_field\"; activeSelector: string; fieldKeyAttr: string; fieldNameFallback: boolean; containerSelector?: string | null };"
        , ""
        , "export type LiveUpdateWireFragment = {"
        , "    fragmentKey: LiveFragmentKey;"
        , "    targetId: string;"
        , "    url: string;"
        , "    deferUntilBlur: boolean;"
        , "    protectionPolicy?: LiveFragmentProtection;"
        , "};"
        , ""
        , "export type LiveUpdateCommand ="
        , "    | { type: \"subscribe\"; scope: LiveUpdateScope; clientId: string; lastSeenVersion?: number | null }"
        , "    | { type: \"unsubscribe\"; scope: LiveUpdateScope };"
        , ""
        , "export type LiveUpdateMessage ="
        , "    | { type: \"subscribed\"; scope: LiveUpdateScope; scopeKey: string; currentVersion: number; resync: boolean }"
        , "    | { type: \"invalidate\"; scope: LiveUpdateScope; scopeKey: string; version: number; fragments: LiveUpdateWireFragment[]; sourceClientId?: string | null }"
        , "    | { type: \"error\"; message: string };"
        ]
    }

interactionContracts :: TypeScriptDeclaration
interactionContracts = TypeScriptDeclaration
    { name = "InteractionContracts"
    , source = Text.unlines
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
    }

stringUnionSource :: Text -> [Text] -> Text
stringUnionSource name values =
    (stringUnionDeclaration name values).source

frontendContractDeclarations :: [TypeScriptDeclaration]
frontendContractDeclarations =
    [ stringUnionDeclaration overlayLaneTypeName (fmap snd overlayLaneValues)
    , liveUpdateContracts
    , interactionContracts
    , TypeScriptDeclaration
        { name = "AesonTypeScriptSpike"
        , source = Text.unlines
            [ "// Spike proof-of-viability for aeson-typescript-generated browser wire contracts."
            , "// Keep this narrow until the live-update/interaction protocol migrates in later tickets."
            , aesonTypeScriptSpikeTypeScript
            ]
        }
    ]

frontendContractsTypeScript :: Text
frontendContractsTypeScript = Text.unlines $
    [ "// @generated by Application.Helper.Frontend.Contracts"
    , "// Do not edit by hand. Run: bash ./bin/in-env frontend-contracts"
    , ""
    ]
    <> fmap source frontendContractDeclarations
