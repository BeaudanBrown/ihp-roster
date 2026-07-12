import {
    FrontendSurfaceFragmentRegistry,
    FrontendSurfaceInteractionRegistry,
    isFrontendSurfaceLiveFragmentName,
    isFrontendSurfaceName,
    rosterContentDomToken,
    rosterWeekShellDomToken,
    timesheetWeekShellDomToken,
    type SurfaceLabSurfaceFragmentKey,
    type TimesheetsSurfaceFragmentKey,
} from "../generated/contracts";
import { assertDeepEqual, assertEqual, test } from "./harness";

test("generated live fragment registry contains only semantic live fragment names", () => {
    assertEqual(isFrontendSurfaceName("surface-lab"), true);
    assertEqual(isFrontendSurfaceName("timesheets"), true);
    assertEqual(isFrontendSurfaceName("legacy-roster"), false);

    assertDeepEqual(FrontendSurfaceFragmentRegistry["surface-lab"], []);
    assertDeepEqual(FrontendSurfaceFragmentRegistry.timesheets, [
        "timesheet-toolbar",
        "timesheet-day-columns",
        "timesheet-day-section",
    ]);
    assertEqual(isFrontendSurfaceLiveFragmentName("timesheets", "timesheet-day-section"), true);
    assertEqual(isFrontendSurfaceLiveFragmentName("timesheets", "missing"), false);
});

test("generated interaction registry contains only runtime-consumed interaction fields", () => {
    const roster = FrontendSurfaceInteractionRegistry.roster;
    assertDeepEqual(roster.sourceRefs.map((source) => source.ref), ["shift-drag-source", "staff-drag-source"]);
    assertDeepEqual(roster.dropzoneRefs.map((dropzone) => dropzone.ref), [
        "shift-slot-dropzone",
        "staff-create-dropzone",
        "day-column-dropzone",
        "existing-shift-dropzone",
        "delete-shift-dropzone",
    ]);
    assertDeepEqual(roster.activationRefs.map((activation) => activation.ref), ["roster-layout-mode-activation"]);
    assertDeepEqual(roster.sessionKinds.map((session) => session.kind), ["drag"]);
    assertDeepEqual(Object.keys(roster).sort(), ["activationRefs", "dropzoneRefs", "sessionKinds", "sourceRefs"]);
});

test("surface DOM tokens are generated as tree-shakeable feature constants", () => {
    assertEqual(rosterContentDomToken, "roster-content");
    assertEqual(rosterWeekShellDomToken, "roster-week-shell");
    assertEqual(timesheetWeekShellDomToken, "timesheet-week-shell");
});

test("browser-reachable surface fragment types remain consumable", () => {
    const panelId = "00000000-0000-0000-0000-000000000001";
    const labFragment: SurfaceLabSurfaceFragmentKey = { kind: "lab-panel", params: { panelId } };
    const timesheetFragment: TimesheetsSurfaceFragmentKey = { kind: "timesheet-day-section", params: { dayOffset: 2 } };

    assertEqual(labFragment.kind, "lab-panel");
    assertEqual(timesheetFragment.params.dayOffset, 2);
});
