import {
    rosterStaffPanelTabDomAttr,
    surfaceDomAttr,
} from "../generated/contracts";
import {
    createSurfaceTabSetController,
    type SurfaceTabSetDiagnostic,
} from "../surface-tab-set/runtime";
import { assertDeepEqual, assertEqual, test } from "./harness";

class MiniElement {
    readonly children: MiniElement[] = [];
    parentElement: MiniElement | null = null;
    readonly id: string;
    private readonly attrs = new Map<string, string>();

    constructor(attrs: Record<string, string> = {}, id = "") {
        this.id = id;
        Object.entries(attrs).forEach(([name, value]) => this.attrs.set(name, value));
    }

    appendChild(child: MiniElement): MiniElement {
        child.parentElement = this;
        this.children.push(child);
        return child;
    }

    append(child: MiniElement): MiniElement {
        return this.appendChild(child);
    }

    replaceChildren(...children: MiniElement[]): void {
        this.children.splice(0, this.children.length);
        children.forEach((child) => this.append(child));
    }

    getAttribute(name: string): string | null {
        return this.attrs.get(name) ?? null;
    }

    setAttribute(name: string, value: string): void {
        this.attrs.set(name, value);
    }

    closest(selector: string): MiniElement | null {
        let current: MiniElement | null = this;
        while (current) {
            const attribute = selector.match(/^\[([^\]]+)\]$/)?.[1];
            if (attribute && current.getAttribute(attribute) !== null) return current;
            current = current.parentElement;
        }
        return null;
    }

    querySelectorAll(selector: string): MiniElement[] {
        const attribute = selector.match(/^\[([^\]]+)\]$/)?.[1];
        const found: MiniElement[] = [];
        const visit = (owner: MiniElement) => {
            for (const child of owner.children) {
                if (attribute && child.getAttribute(attribute) !== null) found.push(child);
                visit(child);
            }
        };
        visit(this);
        return found;
    }
}

function tab(key: "staff" | "settings", selected: boolean): MiniElement {
    return new MiniElement({
        [rosterStaffPanelTabDomAttr]: key,
        "aria-selected": selected ? "true" : "false",
    }, `${key}-tab`);
}

function mountWithTabs(): { mount: MiniElement; staff: MiniElement; settings: MiniElement } {
    const mount = new MiniElement({ [surfaceDomAttr]: "roster" });
    const staff = mount.append(tab("staff", true));
    const settings = mount.append(tab("settings", false));
    return { mount, staff, settings };
}

test("surface tab sets restore remembered generated keys within one mount", () => {
    const first = mountWithTabs();
    const duplicate = mountWithTabs();
    const shown: string[] = [];
    const controller = createSurfaceTabSetController((element) => {
        const selected = element as unknown as MiniElement;
        selected.parentElement?.children.forEach((sibling) => sibling.setAttribute("aria-selected", sibling === selected ? "true" : "false"));
        shown.push(selected.id);
    });

    controller.reconcile(first.mount as unknown as Element);
    assertDeepEqual(shown, []);
    assertEqual(controller.remember(first.settings as unknown as Element), true);
    first.settings.setAttribute("aria-selected", "true");
    first.staff.setAttribute("aria-selected", "false");

    const replacementStaff = tab("staff", true);
    const replacementSettings = tab("settings", false);
    first.mount.replaceChildren(replacementStaff, replacementSettings);
    controller.reconcile(replacementSettings as unknown as Element);

    assertDeepEqual(shown, ["settings-tab"]);
    assertEqual(replacementSettings.getAttribute("aria-selected"), "true");
    assertEqual(duplicate.staff.getAttribute("aria-selected"), "true");
});

test("surface tab sets fall back to the generated default when a remembered tab disappears", () => {
    const fixture = mountWithTabs();
    const diagnostics: SurfaceTabSetDiagnostic[] = [];
    const shown: string[] = [];
    const controller = createSurfaceTabSetController(
        (element) => shown.push((element as unknown as MiniElement).id),
        (diagnostic) => diagnostics.push(diagnostic),
    );

    assertEqual(controller.remember(fixture.settings as unknown as Element), true);
    const replacementStaff = tab("staff", true);
    fixture.mount.replaceChildren(replacementStaff);
    controller.reconcile(replacementStaff as unknown as Element);

    assertDeepEqual(shown, []);
    assertEqual(replacementStaff.getAttribute("aria-selected"), "true");
    assertEqual(diagnostics[0]?.code, "missing-tab-key");
});

test("surface tab sets reject duplicate generated keys before activation", () => {
    const fixture = mountWithTabs();
    const diagnostics: SurfaceTabSetDiagnostic[] = [];
    const shown: string[] = [];
    const controller = createSurfaceTabSetController(
        (element) => shown.push((element as unknown as MiniElement).id),
        (diagnostic) => diagnostics.push(diagnostic),
    );
    fixture.mount.append(tab("settings", false));

    controller.reconcile(fixture.mount as unknown as Element);

    assertDeepEqual(shown, []);
    assertEqual(fixture.staff.getAttribute("aria-selected"), "true");
    assertEqual(diagnostics[0]?.code, "duplicate-tab-key");
});

test("surface tab sets reject undeclared keys without replacing server state", () => {
    const fixture = mountWithTabs();
    const diagnostics: SurfaceTabSetDiagnostic[] = [];
    const shown: string[] = [];
    const controller = createSurfaceTabSetController(
        (element) => shown.push((element as unknown as MiniElement).id),
        (diagnostic) => diagnostics.push(diagnostic),
    );
    fixture.settings.setAttribute(rosterStaffPanelTabDomAttr, "unknown");

    assertEqual(controller.remember(fixture.settings as unknown as Element), false);
    controller.reconcile(fixture.mount as unknown as Element);
    assertDeepEqual(shown, []);
    assertEqual(fixture.staff.getAttribute("aria-selected"), "true");
    assertEqual(diagnostics[0]?.code, "invalid-tab-key");
});
