import {
    rosterStaffPanelSortControlDomAttr,
    rosterStaffPanelSortRootDomAttr,
    rosterStaffPanelSortRowDomAttr,
    surfaceDomAttr,
    type RosterStaffPanelSortRow,
} from "../generated/contracts";
import {
    createCompleteSetSortController,
    type CompleteSetSortDiagnostic,
} from "../complete-set-sort/runtime";
import { assertDeepEqual, assertEqual, test } from "./harness";
import { MiniElement as SharedMiniElement } from "./mini-dom";

class MiniElement extends SharedMiniElement {
    constructor(tagName: string, attrs: Record<string, string> = {}, id = "") {
        super(attrs, id, [], tagName);
    }
}

type SortFixture = {
    mount: MiniElement;
    root: MiniElement;
    body: MiniElement;
    controls: Record<"name" | "role" | "shifts", MiniElement>;
};

function sortFixture(rows: ReadonlyArray<RosterStaffPanelSortRow>): SortFixture {
    const mount = new MiniElement("section", { [surfaceDomAttr]: "roster" });
    const root = mount.append(new MiniElement("table", { [rosterStaffPanelSortRootDomAttr]: "true" }));
    const head = root.append(new MiniElement("thead"));
    const headRow = head.append(new MiniElement("tr"));
    const controls = Object.fromEntries(["name", "role", "shifts"].map((key) => {
        const header = headRow.append(new MiniElement("th", { "aria-sort": "none" }));
        const control = header.append(new MiniElement("button", { [rosterStaffPanelSortControlDomAttr]: key }));
        return [key, control];
    })) as SortFixture["controls"];
    const body = root.append(new MiniElement("tbody"));
    rows.forEach((row) => body.append(new MiniElement("tr", {
        [rosterStaffPanelSortRowDomAttr]: JSON.stringify(row),
    }, row.staffRowKey)));
    return { mount, root, body, controls };
}

function rowKeys(fixture: SortFixture): string[] {
    return fixture.body.children.map((row) => row.id);
}

const rows: RosterStaffPanelSortRow[] = [
    { staffRowKey: "opaque:b", staffName: "Alpha", staffRole: "Worker", assignedShifts: 4, idealShifts: 5 },
    { staffRowKey: "opaque:c", staffName: "Blair", staffRole: "Manager", assignedShifts: 2, idealShifts: 5 },
    { staffRowKey: "opaque:a", staffName: "alpha", staffRole: "Manager", assignedShifts: 4, idealShifts: 5 },
];

test("complete-set sorting applies generated defaults, comparator order, and stable ties", () => {
    const fixture = sortFixture(rows);
    const controller = createCompleteSetSortController();

    controller.reconcile(fixture.root as unknown as Element);
    assertDeepEqual(rowKeys(fixture), ["opaque:a", "opaque:b", "opaque:c"]);
    assertEqual(fixture.controls.name.getAttribute("aria-sort"), "ascending");

    assertEqual(controller.activate(fixture.controls.role as unknown as Element), true);
    assertDeepEqual(rowKeys(fixture), ["opaque:a", "opaque:c", "opaque:b"]);
    assertEqual(fixture.controls.role.getAttribute("aria-sort"), "ascending");

    assertEqual(controller.activate(fixture.controls.shifts as unknown as Element), true);
    assertDeepEqual(rowKeys(fixture), ["opaque:c", "opaque:a", "opaque:b"]);
    assertEqual(controller.activate(fixture.controls.shifts as unknown as Element), true);
    assertDeepEqual(rowKeys(fixture), ["opaque:a", "opaque:b", "opaque:c"]);
    assertEqual(fixture.controls.shifts.getAttribute("aria-sort"), "descending");
});

test("complete-set sorting stays mount-local and rejects malformed rows before mutation", () => {
    const first = sortFixture(rows);
    const second = sortFixture([...rows].reverse());
    const diagnostics: CompleteSetSortDiagnostic[] = [];
    const controller = createCompleteSetSortController((diagnostic) => diagnostics.push(diagnostic));

    controller.reconcile(first.mount as unknown as Element);
    assertDeepEqual(rowKeys(second), ["opaque:a", "opaque:c", "opaque:b"]);

    second.body.children[0]?.setAttribute(rosterStaffPanelSortRowDomAttr, JSON.stringify({ staffName: "missing exact fields" }));
    const before = rowKeys(second);
    controller.reconcile(second.mount as unknown as Element);
    assertDeepEqual(rowKeys(second), before);
    assertEqual(diagnostics[0]?.code, "invalid-row-payload");
});
