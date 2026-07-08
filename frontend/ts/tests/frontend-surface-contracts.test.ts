import {
    FrontendSurfaceContainmentTopology,
    FrontendSurfaceRegistry,
    adminPageSurfaceManifest,
    isOverlayActionManifest,
    openFeedbackDialogOverlayActionManifest,
    isFrontendSurfaceActionManifest,
    isFrontendSurfaceContainmentEdge,
    isFrontendSurfaceName,
    parseFrontendSurfaceActionManifest,
    parseFrontendSurfaceName,
    parseOverlayActionManifest,
    surfaceLabSurfaceManifest,
    timesheetsSurfaceManifest,
    type FrontendSurfaceContainmentEdge,
    type FrontendSurfaceDay,
    type LabPayload,
    type LabRelatedPayload,
    type MoveLabCardIntentFields,
    type PanelId,
    type RefreshPanelActionFields,
    type SurfaceLabFragmentKey,
    type TimesheetsFragmentKey,
    type TimesheetsMountState,
} from "../generated/contracts";
import { assertDeepEqual, assertEqual, assertThrows, test } from "./harness";

test("generated overlay action manifests expose dialog request contracts", () => {
    assertEqual(isOverlayActionManifest(openFeedbackDialogOverlayActionManifest), true);
    assertEqual(parseOverlayActionManifest(openFeedbackDialogOverlayActionManifest).name, "open-feedback-dialog");
    assertDeepEqual(openFeedbackDialogOverlayActionManifest, {
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
        swap: "outer-html",
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
    const staffFilterId = "00000000-0000-0000-0000-000000000002" as unknown as TimesheetsMountState["staffFilterId"];
    const mountState: TimesheetsMountState = { showApproved: false, showAllStaff: true, staffFilterId };
    const daySection: TimesheetsFragmentKey = { kind: "timesheet-day-section", params: { dayOffset: 2 } };

    assertDeepEqual(timesheetsSurfaceManifest.scopes, ["timesheet-week"]);
    assertDeepEqual(timesheetsSurfaceManifest.fragments, ["timesheet-toolbar", "timesheet-day-columns", "timesheet-day-section"]);
    assertEqual(mountState.showAllStaff, true);
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
        dueDay: "2026-07-02" as FrontendSurfaceDay,
        maybeRank: undefined,
        maybeMemo: null,
        relatedPayload,
    };

    assertEqual(fragmentKey.kind, "lab-panel");
    assertEqual(actionFields.panelId, fragmentKey.params.panelId);
    assertEqual(intentFields.targetDropzoneKey, "slot:b");
    assertEqual(payload.count, undefined);
});
