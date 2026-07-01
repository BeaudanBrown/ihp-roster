import { AppEvents, InteractionDom, InteractionStaticSchemas, LiveSurfaceManifest, type InteractionCapabilityContract, type IntentFormContract } from "../generated/contracts";
import { assertDeepEqual, assertEqual, test } from "./harness";

test("generated interaction contracts describe mount-local intent forms", () => {
    const form: IntentFormContract = {
        intent: "move-roster-shift-to-slot",
        name: "move-roster-shift-to-slot",
        action: "/MoveRosterShiftToSlot",
        method: "post",
        trigger: `${AppEvents.interactionIntentSubmit} from:this`,
        target: { kind: "mount_local", target: "#surface-primary" },
        swap: "outerHTML",
        fields: [{ name: "sourceItemKey", presence: "required" }],
        hiddenFields: [{ name: "intent", value: "move-roster-shift-to-slot" }],
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
        disposableLayers: [{ kind: "drag-preview", name: "drag-preview", domId: "drag-preview-layer" }],
        sessionKinds: [{ kind: "drag", description: "Drag" }],
        intentForms: [form],
        conflictPolicies: [{ session: { kind: "session", session: "drag" }, fragment: { kind: "any" }, resolution: "defer", timeoutMs: 1500 }],
    };

    assertEqual(capability.intentForms[0]?.method, "post");
    assertEqual(InteractionDom.attributes.intentField, "data-bepis-intent-field");
    assertEqual(InteractionDom.attributes.item, "data-bepis-item");
    assertEqual(InteractionDom.attributes.dropzone, "data-bepis-dropzone");
    assertEqual(InteractionDom.attributes.interactionActive, "data-bepis-interaction-active");
    assertEqual(InteractionDom.pointerFields.sourceItemKey, "sourceItemKey");
    assertEqual(InteractionDom.pointerFields.targetDropzoneKey, "targetDropzoneKey");
    assertDeepEqual(capability.intentForms[0]?.fields, [{ name: "sourceItemKey", presence: "required" }]);
});

test("generated live surface manifest exposes registered surface schemas without runtime urls", () => {
    const rosterManifest = LiveSurfaceManifest.roster;
    const timesheetManifest = LiveSurfaceManifest.timesheets;
    if (!rosterManifest || !timesheetManifest) throw new Error("Expected registered roster and timesheets surface manifests");

    assertEqual(rosterManifest.interactionSchema, "roster");
    assertDeepEqual(rosterManifest.scopeKinds, ["roster_week"]);
    assertEqual(rosterManifest.fragmentKinds.includes("roster_day_section"), true);
    assertEqual(timesheetManifest.scopeKinds[0], "timesheet_week");
    assertEqual(JSON.stringify(LiveSurfaceManifest).includes("/ShowRosterWeek"), false);
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
