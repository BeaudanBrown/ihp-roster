import { InteractionDom, InteractionStaticSchemas, type InteractionCapabilityContract, type IntentFormContract } from "../generated/contracts";
import { assertDeepEqual, assertEqual, test } from "./harness";

test("generated interaction contracts describe mount-local intent forms", () => {
    const form: IntentFormContract = {
        intent: "select-cell",
        name: "select-cell",
        action: "/SelectCell",
        method: "post",
        trigger: "bepis:intent-submit from:this",
        target: { kind: "mount_local", target: "#surface-primary" },
        swap: "outerHTML",
        fields: [{ name: "cellId", presence: "required" }],
        hiddenFields: [{ name: "intent", value: "select-cell" }],
        sync: "closest [data-bepis-surface]:queue",
        disabledElement: null,
    };

    const capability: InteractionCapabilityContract = {
        mount: {
            surfaceFamily: "roster",
            scopeKey: "roster_week:venue:group:0",
            mountKey: "primary",
            mountId: "bepis-surface--roster--primary",
        },
        serverLayers: [{ name: "server", domId: "server-layer" }],
        disposableLayers: [{ kind: "selection", name: "selection", domId: "selection-layer" }],
        sessionKinds: [{ kind: "click-select", description: "Click selection" }],
        intentForms: [form],
        conflictPolicies: [{ session: "click-select", fragment: "*", resolution: "defer", timeoutMs: 1500 }],
    };

    assertEqual(capability.intentForms[0]?.method, "post");
    assertEqual(InteractionDom.attributes.intentField, "data-bepis-intent-field");
    assertEqual(InteractionDom.attributes.item, "data-bepis-item");
    assertEqual(InteractionDom.attributes.dropzone, "data-bepis-dropzone");
    assertEqual(InteractionDom.attributes.interactionActive, "data-bepis-interaction-active");
    assertEqual(InteractionDom.pointerFields.sourceItemKey, "sourceItemKey");
    assertEqual(InteractionDom.pointerFields.targetDropzoneKey, "targetDropzoneKey");
    assertDeepEqual(capability.intentForms[0]?.fields, [{ name: "cellId", presence: "required" }]);
});

test("generated interaction static schemas expose roster intents and fields", () => {
    assertEqual(InteractionStaticSchemas.roster.sessionKinds[0]?.kind, "drag");
    assertEqual(InteractionStaticSchemas.roster.disposableLayers[0]?.name, "drag-preview");
    assertEqual(InteractionStaticSchemas.roster.intents[0]?.name, "set-roster-layout-mode");
    assertEqual(InteractionStaticSchemas.roster.intents[1]?.name, "move-roster-shift-to-slot");
    assertDeepEqual(
        InteractionStaticSchemas.roster.intents[1]?.fields.map((field) => field.name),
        [
            "sourceItemKey",
            "targetDropzoneKey",
            "sessionKind",
            "pointerId",
            "pointerType",
            "startClientX",
            "startClientY",
            "currentClientX",
            "currentClientY",
            "deltaX",
            "deltaY",
        ],
    );
});
