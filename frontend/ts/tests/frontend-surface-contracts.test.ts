import {
    FrontendSurfaceContainmentTopology,
    FrontendSurfaceRegistry,
    adminPageSurfaceManifest,
    isAppShellActionManifest,
    openFeedbackDialogAppShellActionManifest,
    submitFeedbackAppShellActionManifest,
    isFrontendSurfaceActionManifest,
    isFrontendSurfaceContainmentEdge,
    isFrontendSurfaceName,
    parseFrontendSurfaceActionManifest,
    parseFrontendSurfaceName,
    parseAppShellActionManifest,
    surfaceLabSurfaceManifest,
    timesheetsSurfaceManifest,
    type FrontendSurfaceContainmentEdge,
    type FrontendContractDay,
    type LabPayload,
    type LabRelatedPayload,
    type MoveLabCardIntentFields,
    type PanelId,
    type RefreshPanelActionFields,
    type SurfaceLabFragmentKey,
    type TimesheetsFragmentKey,
} from "../generated/contracts";
import { assertDeepEqual, assertEqual, assertThrows, test } from "./harness";

test("generated AppShell action manifests expose dialog request contracts", () => {
    assertEqual(isAppShellActionManifest(openFeedbackDialogAppShellActionManifest), true);
    assertEqual(parseAppShellActionManifest(openFeedbackDialogAppShellActionManifest).name, "open-feedback-dialog");
    assertDeepEqual(openFeedbackDialogAppShellActionManifest, {
        name: "open-feedback-dialog",
        fields: [],
        htmx: {
            method: "get",
            trigger: null,
            include: null,
            sync: null,
            indicator: null,
            confirm: null,
            select: null,
            target: "dialog-overlay-mount",
            swap: "innerHTML",
            pushUrl: false,
            custom: [],
        },
    });
    assertEqual(isAppShellActionManifest(submitFeedbackAppShellActionManifest), true);
    assertEqual(parseAppShellActionManifest(submitFeedbackAppShellActionManifest).name, "submit-feedback");
    assertDeepEqual(submitFeedbackAppShellActionManifest.fields, ["feedbackType", "content"]);
    assertEqual(submitFeedbackAppShellActionManifest.htmx.method, "post");
});

test("generated FrontendSurface registry exposes lab surface primitives", () => {
    assertEqual(isFrontendSurfaceName("surface-lab"), true);
    assertEqual(isFrontendSurfaceName("timesheets"), true);
    assertEqual(isFrontendSurfaceName("legacy-roster"), false);
    assertEqual(parseFrontendSurfaceName("surface-lab"), "surface-lab");
    assertThrows(() => parseFrontendSurfaceName("legacy-roster"), "Invalid FrontendSurfaceName");

    assertDeepEqual(FrontendSurfaceRegistry["surface-lab"], surfaceLabSurfaceManifest);
    assertDeepEqual(FrontendSurfaceRegistry.timesheets, timesheetsSurfaceManifest);
    assertDeepEqual(surfaceLabSurfaceManifest.fragments, ["lab-shell", "lab-panel"]);
    assertEqual(surfaceLabSurfaceManifest.htmxActions[0].name, "refresh-panel");
    assertDeepEqual(surfaceLabSurfaceManifest.htmxActions[0].fields, ["panelId"]);
    assertDeepEqual(surfaceLabSurfaceManifest.htmxActions[0].htmx, {
        method: "post",
        trigger: null,
        include: "lab-panel-include",
        sync: null,
        indicator: null,
        confirm: null,
        select: null,
        target: "lab-panel-target",
        swap: "outerHTML",
        pushUrl: false,
        custom: [{ name: "lab-panel-custom-htmx", reason: "lab fixture covers auditable custom HTMX metadata" }],
    });
    assertEqual(isFrontendSurfaceActionManifest(surfaceLabSurfaceManifest.htmxActions[0]), true);
    assertEqual(parseFrontendSurfaceActionManifest(surfaceLabSurfaceManifest.htmxActions[0]).name, "refresh-panel");
    assertDeepEqual(surfaceLabSurfaceManifest.intents, ["move-lab-card"]);
    assertDeepEqual(surfaceLabSurfaceManifest.sessions, ["drag"]);
    assertDeepEqual(surfaceLabSurfaceManifest.layers, ["drag-preview"]);
    assertDeepEqual(surfaceLabSurfaceManifest.domTokens, ["lab-root", "lab-dropzone", "lab-panel-target", "lab-panel-include"]);
});

test("generated FrontendSurface registry exposes Admin page containment topology", () => {
    assertDeepEqual(adminPageSurfaceManifest.containedSurfaces["admin-page-content"], [
        "admin-invites",
        "admin-venue-config",
        "admin-exports",
        "admin-shift-types",
        "admin-roster-groups",
    ]);
    assertDeepEqual(FrontendSurfaceRegistry["admin-page"], adminPageSurfaceManifest);
    const topology: ReadonlyArray<FrontendSurfaceContainmentEdge> = FrontendSurfaceContainmentTopology;
    assertEqual(isFrontendSurfaceContainmentEdge(topology[0]), true);
    assertDeepEqual(topology.filter((edge) => String(edge.parentSurface) === "admin-page").map((edge) => edge.childSurface), [
        "admin-invites",
        "admin-venue-config",
        "admin-exports",
        "admin-shift-types",
        "admin-roster-groups",
    ]);
    assertDeepEqual(topology.filter((edge) => String(edge.parentSurface) === "admin-xero-page").map((edge) => edge.childSurface), ["admin-xero"]);
});

test("generated FrontendSurface registry exposes timesheets surface primitives", () => {
    const daySection: TimesheetsFragmentKey = { kind: "timesheet-day-section", params: { dayOffset: 2 } };

    assertDeepEqual(timesheetsSurfaceManifest.scopes, ["timesheet-week"]);
    assertDeepEqual(timesheetsSurfaceManifest.fragments, ["timesheet-toolbar", "timesheet-day-columns", "timesheet-day-section"]);
    assertEqual(daySection.params.dayOffset, 2);
});

test("generated FrontendSurface lab DTOs are consumable by TypeScript", () => {
    const panelId = "00000000-0000-0000-0000-000000000001" as PanelId;
    const fragmentKey: SurfaceLabFragmentKey = { kind: "lab-panel", params: { panelId } };
    const actionFields: RefreshPanelActionFields = fragmentKey.params;
    const intentFields: MoveLabCardIntentFields = { sourceItemKey: "card:a", targetDropzoneKey: "slot:b" };
    const relatedPayload: LabRelatedPayload = { label: "Related" };
    const payload: LabPayload = {
        label: "Lab",
        note: null,
        tags: ["alpha"],
        dueDay: "2026-07-02" as FrontendContractDay,
        maybeRank: undefined,
        maybeMemo: null,
        relatedPayload,
    };

    assertEqual(fragmentKey.kind, "lab-panel");
    assertEqual(actionFields.panelId, fragmentKey.params.panelId);
    assertEqual(intentFields.targetDropzoneKey, "slot:b");
    assertEqual(payload.count, undefined);
});
