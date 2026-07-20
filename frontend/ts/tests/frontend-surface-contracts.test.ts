import {
    FrontendSurfaceCompleteSetSortRegistry,
    FrontendSurfaceFragmentRegistry,
    FrontendSurfaceInteractionRegistry,
    FrontendSurfaceLinkedHighlightRegistry,
    FrontendSurfaceTabSetRegistry,
    isFrontendSurfaceLiveFragmentName,
    isFrontendSurfaceName,
    rosterContentDomToken,
    rosterDayTimelineShiftGroupHighlightMemberDomAttr,
    rosterShiftGroupHighlightMemberDomAttr,
    rosterStaffHighlightMemberDomAttr,
    rosterStaffHighlightOrderDomAttr,
    rosterStaffHighlightPinDomAttr,
    rosterStaffHighlightSourceDomAttr,
    rosterStaffPanelSortControlDomAttr,
    rosterStaffPanelSortRootDomAttr,
    rosterStaffPanelSortRowDomAttr,
    rosterStaffPanelTabDomAttr,
    parseRosterStaffPanelSortRow,
    rosterWeekShellDomToken,
    timesheetWeekShellDomToken,
    type TimesheetsSurfaceFragmentKey,
} from "../generated/contracts";
import { assertDeepEqual, assertEqual, assertThrows, test } from "./harness";

test("generated live fragment registry contains only production semantic live fragment names", () => {
    assertEqual(isFrontendSurfaceName("surface-lab"), false);
    assertEqual(isFrontendSurfaceName("contract-fixture"), false);
    assertEqual(isFrontendSurfaceName("timesheets"), true);
    assertEqual(isFrontendSurfaceName("legacy-roster"), false);

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
    assertDeepEqual(roster.sourceRefs[1]?.compatibleDropzones, ["existing-shift-dropzone", "shift-slot-dropzone", "staff-create-dropzone"]);
    assertDeepEqual(roster.activationRefs.map((activation) => activation.ref), ["roster-layout-mode-activation"]);
    assertDeepEqual(roster.sessionKinds.map((session) => session.kind), ["drag"]);
    assertDeepEqual(Object.keys(roster).sort(), ["activationRefs", "dropzoneRefs", "sessionKinds", "sourceRefs"]);
});

test("generated linked-highlight registry owns roster roles and closed behavior", () => {
    const [staffHighlight, shiftGroupHighlight] = FrontendSurfaceLinkedHighlightRegistry.roster;
    assertDeepEqual(staffHighlight, {
        name: "staff-shifts-highlight",
        sourceRoleAttribute: rosterStaffHighlightSourceDomAttr,
        memberRoleAttribute: rosterStaffHighlightMemberDomAttr,
        pinRoleAttribute: rosterStaffHighlightPinDomAttr,
        orderStateAttribute: rosterStaffHighlightOrderDomAttr,
        activations: ["hover", "focus", "keyboard", "pin"],
        effects: ["matching-source", "matching-member", "ordered-member-bounds"],
    });
    assertEqual(shiftGroupHighlight?.memberRoleAttribute, rosterShiftGroupHighlightMemberDomAttr);
    assertEqual(
        FrontendSurfaceLinkedHighlightRegistry["roster-day-timeline"][0]?.memberRoleAttribute,
        rosterDayTimelineShiftGroupHighlightMemberDomAttr,
    );
});

test("generated complete-set sort registry owns roster row parsing and comparator policy", () => {
    const [definition] = FrontendSurfaceCompleteSetSortRegistry.roster;
    assertEqual(definition?.rootRoleAttribute, rosterStaffPanelSortRootDomAttr);
    assertEqual(definition?.rowRoleAttribute, rosterStaffPanelSortRowDomAttr);
    assertEqual(definition?.controlRoleAttribute, rosterStaffPanelSortControlDomAttr);
    assertEqual(definition?.defaultKey, "name");
    assertEqual(definition?.defaultDirection, "ascending");
    assertDeepEqual(definition?.keys.map((key) => ({
        key: key.key,
        comparators: key.comparators.map(({ field, valueType, direction }) => ({ field, valueType, direction })),
    })), [
        { key: "name", comparators: [
            { field: "staffName", valueType: "text", direction: "selected" },
            { field: "staffRowKey", valueType: "opaque", direction: "ascending" },
        ] },
        { key: "role", comparators: [
            { field: "staffRole", valueType: "text", direction: "selected" },
            { field: "staffName", valueType: "text", direction: "ascending" },
            { field: "staffRowKey", valueType: "opaque", direction: "ascending" },
        ] },
        { key: "shifts", comparators: [
            { field: "assignedShifts", valueType: "integer", direction: "selected" },
            { field: "idealShifts", valueType: "integer", direction: "selected" },
            { field: "staffName", valueType: "text", direction: "ascending" },
            { field: "staffRowKey", valueType: "opaque", direction: "ascending" },
        ] },
    ]);
    assertDeepEqual(parseRosterStaffPanelSortRow({
        staffRowKey: "opaque:staff",
        staffName: "Alpha",
        staffRole: "Worker",
        assignedShifts: 2,
        idealShifts: 3,
    }), {
        staffRowKey: "opaque:staff",
        staffName: "Alpha",
        staffRole: "Worker",
        assignedShifts: 2,
        idealShifts: 3,
    });
    assertThrows(() => parseRosterStaffPanelSortRow({
        staffRowKey: "opaque:staff",
        staffName: "Alpha",
        staffRole: "Worker",
        assignedShifts: "2",
        idealShifts: 3,
    }), "Invalid RosterStaffPanelSortRow");
    assertThrows(() => parseRosterStaffPanelSortRow({
        staffRowKey: "opaque:staff",
        staffName: "Alpha",
        staffRole: "Worker",
        assignedShifts: 2,
        idealShifts: 3,
        extra: true,
    }), "Invalid RosterStaffPanelSortRow");
});

test("generated tab-set registry owns roster tab keys and default", () => {
    const [definition] = FrontendSurfaceTabSetRegistry.roster;
    assertEqual(definition?.tabRoleAttribute, rosterStaffPanelTabDomAttr);
    assertDeepEqual(definition?.keys, ["staff", "settings"]);
    assertEqual(definition?.defaultKey, "staff");
});

test("surface DOM tokens are generated as tree-shakeable feature constants", () => {
    assertEqual(rosterContentDomToken, "roster-content");
    assertEqual(rosterWeekShellDomToken, "roster-week-shell");
    assertEqual(timesheetWeekShellDomToken, "timesheet-week-shell");
});

test("browser-reachable production surface fragment types remain consumable", () => {
    const timesheetFragment: TimesheetsSurfaceFragmentKey = { kind: "timesheet-day-section", params: { dayOffset: 2 } };

    assertEqual(timesheetFragment.params.dayOffset, 2);
});
