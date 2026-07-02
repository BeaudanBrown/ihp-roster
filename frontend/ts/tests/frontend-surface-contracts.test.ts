import {
    FrontendSurfaceRegistry,
    isFrontendSurfaceName,
    parseFrontendSurfaceName,
    surfaceLabSurfaceManifest,
    timesheetsSurfaceManifest,
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

test("generated FrontendSurface registry exposes lab surface primitives", () => {
    assertEqual(isFrontendSurfaceName("surface-lab"), true);
    assertEqual(isFrontendSurfaceName("timesheets"), true);
    assertEqual(isFrontendSurfaceName("legacy-roster"), false);
    assertEqual(parseFrontendSurfaceName("surface-lab"), "surface-lab");
    assertThrows(() => parseFrontendSurfaceName("legacy-roster"), "Invalid FrontendSurfaceName");

    assertDeepEqual(FrontendSurfaceRegistry["surface-lab"], surfaceLabSurfaceManifest);
    assertDeepEqual(FrontendSurfaceRegistry.timesheets, timesheetsSurfaceManifest);
    assertDeepEqual(surfaceLabSurfaceManifest.fragments, ["lab-shell", "lab-panel"]);
    assertDeepEqual(surfaceLabSurfaceManifest.htmxActions, ["refresh-panel"]);
    assertDeepEqual(surfaceLabSurfaceManifest.intents, ["move-lab-card"]);
    assertDeepEqual(surfaceLabSurfaceManifest.sessions, ["drag"]);
    assertDeepEqual(surfaceLabSurfaceManifest.layers, ["drag-preview"]);
    assertDeepEqual(surfaceLabSurfaceManifest.domTokens, ["lab-root", "lab-dropzone"]);
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
