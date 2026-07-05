import { FrontendSurfaceInteractionDom, FrontendSurfaceRegistry, InteractionDom, InteractionStaticSchemas, isInteractionSessionEffect, parseInteractionSessionEffect, encodeInteractionSessionEffect, type InteractionCapabilityContract, type IntentFormContract, intentSubmitEvent } from "../generated/contracts";
import { assertDeepEqual, assertEqual, test } from "./harness";

test("generated interaction contracts describe mount-local intent forms", () => {
    const form: IntentFormContract = {
        intent: "move-roster-shift-to-slot",
        name: "move-roster-shift-to-slot",
        action: "/MoveRosterShiftToSlot",
        method: "post",
        trigger: `${intentSubmitEvent} from:this`,
        target: { kind: "mount-local", target: "#surface-primary" },
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
    assertEqual(FrontendSurfaceInteractionDom.sourceKey, "data-bepis-source-key");
    assertEqual(FrontendSurfaceInteractionDom.dropzoneKey, "data-bepis-dropzone-key");
    assertEqual(InteractionDom.attributes.interactionActive, "data-bepis-interaction-active");
    assertEqual(InteractionDom.pointerFields.sourceItemKey, "sourceItemKey");
    assertEqual(InteractionDom.pointerFields.targetDropzoneKey, "targetDropzoneKey");
    assertDeepEqual(capability.intentForms[0]?.fields, [{ name: "sourceItemKey", presence: "required" }]);
});

test("generated FrontendSurface registry exposes registered surface schemas without runtime urls", () => {
    const rosterManifest = FrontendSurfaceRegistry.roster;
    const timesheetManifest = FrontendSurfaceRegistry.timesheets;

    assertDeepEqual(rosterManifest.scopes, ["roster-week"]);
    assertEqual(rosterManifest.liveFragments.includes("roster-day-section"), true);
    assertEqual(timesheetManifest.scopes[0], "timesheet-week");
    assertEqual(JSON.stringify(FrontendSurfaceRegistry).includes("/ShowRosterWeek"), false);
});

test("generated interaction static schemas expose roster intents and fields", () => {
    assertEqual(InteractionStaticSchemas.roster.sessionKinds[0]?.kind, "drag");
    assertEqual(InteractionStaticSchemas.roster.disposableLayers[0]?.name, "drag-preview");
    assertDeepEqual(InteractionStaticSchemas.roster.sessionKinds[0]?.effects.global, [
        { className: "bepis-pointer-clone-shadow", kind: "clone-shadow", layer: "drag-preview", preserveGrabOffset: true, source: "pointer-marker" },
    ]);
    assertDeepEqual(InteractionStaticSchemas.roster.sessionKinds[0]?.effects.contextual, [
        { className: "bepis-dropzone-highlight", kind: "dropzone-highlight" },
    ]);
    assertEqual(isInteractionSessionEffect(InteractionStaticSchemas.roster.sessionKinds[0]?.effects.global[0]), true);
    assertDeepEqual(parseInteractionSessionEffect(InteractionStaticSchemas.roster.sessionKinds[0]?.effects.contextual[0]), { className: "bepis-dropzone-highlight", kind: "dropzone-highlight" });
    assertDeepEqual(encodeInteractionSessionEffect({ kind: "dropzone-highlight", className: "bepis-dropzone-highlight" }), { kind: "dropzone-highlight", className: "bepis-dropzone-highlight" });
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
