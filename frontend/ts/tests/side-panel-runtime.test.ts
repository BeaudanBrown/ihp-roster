import {
    rosterSidePanelDomAttr,
    rosterSidePanelLabelDomAttr,
    rosterSidePanelMainDomAttr,
    rosterSidePanelPanelDomAttr,
    rosterSidePanelRootDomAttr,
    rosterSidePanelStates,
    rosterSidePanelToggleDomAttr,
    surfaceDomAttr,
} from "../generated/contracts";
import {
    createSidePanelController,
    expandedSidePanelRootForEscape,
    installSidePanelEventListeners,
    type SidePanelDiagnostic,
} from "../side-panel/runtime";
import { assertDeepEqual, assertEqual, test } from "./harness";

class MiniClassList {
    private readonly values = new Set<string>();
    constructor(initial: string[] = []) { initial.forEach((value) => this.values.add(value)); }
    toggle(value: string, force?: boolean): boolean {
        const enabled = force ?? !this.values.has(value);
        if (enabled) this.values.add(value); else this.values.delete(value);
        return enabled;
    }
    contains(value: string): boolean { return this.values.has(value); }
}

class MiniElement {
    readonly children: MiniElement[] = [];
    readonly classList: MiniClassList;
    parentElement: MiniElement | null = null;
    textContent: string | null = null;
    focusCount = 0;
    readonly id: string;
    private readonly attrs = new Map<string, string>();

    constructor(attrs: Record<string, string> = {}, id = "", classes: string[] = []) {
        this.id = id;
        this.classList = new MiniClassList(classes);
        Object.entries(attrs).forEach(([name, value]) => this.attrs.set(name, value));
    }
    appendChild(child: MiniElement): MiniElement { child.parentElement = this; this.children.push(child); return child; }
    append(child: MiniElement): MiniElement { return this.appendChild(child); }
    replaceChildren(...children: MiniElement[]): void {
        this.children.forEach((child) => { child.parentElement = null; });
        this.children.splice(0, this.children.length);
        children.forEach((child) => this.append(child));
    }
    getAttribute(name: string): string | null { return this.attrs.get(name) ?? null; }
    setAttribute(name: string, value: string): void { this.attrs.set(name, value); }
    matches(selector: string): boolean {
        const attribute = selector.match(/^\[([^\]=]+)(?:="([^"]*)")?\]$/);
        if (attribute) {
            const value = this.getAttribute(attribute[1] ?? "");
            return value !== null && (attribute[2] === undefined || value === attribute[2]);
        }
        const className = selector.match(/^\.([A-Za-z0-9_-]+)$/)?.[1];
        return className ? this.classList.contains(className) : false;
    }
    closest(selector: string): MiniElement | null {
        let current: MiniElement | null = this;
        while (current) { if (current.matches(selector)) return current; current = current.parentElement; }
        return null;
    }
    querySelectorAll(selector: string): MiniElement[] {
        const found: MiniElement[] = [];
        const visit = (owner: MiniElement) => owner.children.forEach((child) => {
            if (child.matches(selector)) found.push(child);
            visit(child);
        });
        visit(this);
        return found;
    }
    querySelector(selector: string): MiniElement | null { return this.querySelectorAll(selector)[0] ?? null; }
    focus(): void { this.focusCount += 1; }
}

class MiniEventSource {
    activeElement: unknown = null;
    private readonly listeners = new Map<string, Array<(event: Event) => void>>();

    addEventListener(name: string, listener: (event: Event) => void): void {
        this.listeners.set(name, [...(this.listeners.get(name) ?? []), listener]);
    }

    emit(name: string, event: object): void {
        this.listeners.get(name)?.forEach((listener) => listener(event as Event));
    }
}

function sidePanelMount(id: string) {
    const mount = new MiniElement({ [surfaceDomAttr]: "roster" }, `${id}-mount`);
    const root = mount.append(new MiniElement({
        [rosterSidePanelRootDomAttr]: "true",
        [rosterSidePanelDomAttr]: rosterSidePanelStates.collapsed,
    }, `${id}-root`));
    const main = root.append(new MiniElement({ [rosterSidePanelMainDomAttr]: "true" }, `${id}-main`));
    const panel = root.append(new MiniElement({ [rosterSidePanelPanelDomAttr]: "true" }, `${id}-panel`));
    const toggle = main.append(new MiniElement({ [rosterSidePanelToggleDomAttr]: "true" }, `${id}-toggle`));
    const icon = toggle.append(new MiniElement({}, `${id}-icon`, ["bi", "bi-fullscreen"]));
    const label = toggle.append(new MiniElement({ [rosterSidePanelLabelDomAttr]: "true" }, `${id}-label`));
    label.textContent = "Expand main content";
    return { mount, root, main, panel, toggle, icon, label };
}

test("side panels toggle only the nearest generated root, including nested mounts", () => {
    const outer = sidePanelMount("outer");
    const nested = sidePanelMount("nested");
    outer.panel.append(nested.mount);
    const controller = createSidePanelController();

    assertEqual(controller.toggle(nested.icon as unknown as Element), true);
    assertEqual(nested.root.getAttribute(rosterSidePanelDomAttr), rosterSidePanelStates.expanded);
    assertEqual(outer.root.getAttribute(rosterSidePanelDomAttr), rosterSidePanelStates.collapsed);
    assertEqual(nested.root.classList.contains("is-side-panel-expanded"), true);
    assertEqual(outer.root.classList.contains("is-side-panel-expanded"), false);
    assertEqual(nested.toggle.getAttribute("aria-pressed"), "true");
    assertEqual(nested.toggle.getAttribute("aria-label"), "Show side panel");
    assertEqual(nested.label.textContent, "Show side panel");
    assertEqual(nested.icon.classList.contains("bi-fullscreen-exit"), true);
    assertEqual(nested.toggle.focusCount, 1);
    assertEqual(expandedSidePanelRootForEscape(nested.icon as unknown as Element), nested.root as unknown as Element);

    controller.toggle(nested.toggle as unknown as Element);
    outer.root.setAttribute(rosterSidePanelDomAttr, rosterSidePanelStates.expanded);
    assertEqual(expandedSidePanelRootForEscape(nested.icon as unknown as Element), null);
    assertEqual(expandedSidePanelRootForEscape(outer.main as unknown as Element), outer.root as unknown as Element);
    assertEqual(expandedSidePanelRootForEscape(new MiniElement() as unknown as Element), null);
});

test("multiple sibling side-panel mounts keep state, controls, icons, and focus independent", () => {
    const first = sidePanelMount("first");
    const second = sidePanelMount("second");
    const controller = createSidePanelController();

    controller.reconcile(first.root as unknown as Element);
    controller.reconcile(second.root as unknown as Element);
    assertEqual(controller.toggle(first.icon as unknown as Element), true);

    assertEqual(first.root.getAttribute(rosterSidePanelDomAttr), rosterSidePanelStates.expanded);
    assertEqual(second.root.getAttribute(rosterSidePanelDomAttr), rosterSidePanelStates.collapsed);
    assertEqual(first.toggle.getAttribute("aria-pressed"), "true");
    assertEqual(second.toggle.getAttribute("aria-pressed"), "false");
    assertEqual(first.icon.classList.contains("bi-fullscreen-exit"), true);
    assertEqual(second.icon.classList.contains("bi-fullscreen"), true);
    assertEqual(first.toggle.focusCount, 1);
    assertEqual(second.toggle.focusCount, 0);
});

test("side-panel reconciliation restores replacement controls and rejects malformed boundaries", () => {
    const fixture = sidePanelMount("replacement");
    const diagnostics: SidePanelDiagnostic[] = [];
    const controller = createSidePanelController((diagnostic) => diagnostics.push(diagnostic));
    fixture.root.setAttribute(rosterSidePanelDomAttr, rosterSidePanelStates.expanded);

    const replacementToggle = new MiniElement({ [rosterSidePanelToggleDomAttr]: "true" }, "replacement-toggle");
    const replacementIcon = replacementToggle.append(new MiniElement({}, "replacement-icon", ["bi", "bi-fullscreen"]));
    const replacementLabel = replacementToggle.append(new MiniElement({ [rosterSidePanelLabelDomAttr]: "true" }, "replacement-label"));
    fixture.main.replaceChildren(replacementToggle);

    assertEqual(controller.reconcile(fixture.root as unknown as Element), true);
    assertEqual(replacementToggle.getAttribute("aria-pressed"), "true");
    assertEqual(replacementLabel.textContent, "Show side panel");
    assertEqual(replacementIcon.classList.contains("bi-fullscreen-exit"), true);

    fixture.root.setAttribute(rosterSidePanelDomAttr, "unknown");
    assertEqual(controller.reconcile(fixture.root as unknown as Element), false);
    assertDeepEqual(diagnostics.map((diagnostic) => diagnostic.code), ["invalid-state"]);
});

test("HTMX lifecycle listeners reconcile replacements and dispose removed roots", () => {
    const fixture = sidePanelMount("lifecycle");
    const controller = createSidePanelController();
    const source = new MiniEventSource();
    installSidePanelEventListeners(source, controller, (root) => controller.reconcile(root as unknown as Element));
    controller.toggle(fixture.toggle as unknown as Element);

    const replacementToggle = new MiniElement({ [rosterSidePanelToggleDomAttr]: "true" }, "lifecycle-toggle");
    const replacementIcon = replacementToggle.append(new MiniElement({}, "lifecycle-icon", ["bi", "bi-fullscreen"]));
    const replacementLabel = replacementToggle.append(new MiniElement({ [rosterSidePanelLabelDomAttr]: "true" }, "lifecycle-label"));
    fixture.main.replaceChildren(replacementToggle);
    source.emit("htmx:afterSwap", { detail: { target: fixture.root } });

    assertEqual(replacementToggle.getAttribute("aria-pressed"), "true");
    assertEqual(replacementLabel.textContent, "Show side panel");
    assertEqual(replacementIcon.classList.contains("bi-fullscreen-exit"), true);

    source.emit("htmx:beforeCleanupElement", { detail: { target: fixture.root } });
    assertEqual(fixture.root.getAttribute(rosterSidePanelDomAttr), rosterSidePanelStates.collapsed);
});

test("disposing a side-panel cleanup subtree restores transient visibility", () => {
    const fixture = sidePanelMount("cleanup");
    const controller = createSidePanelController();
    controller.toggle(fixture.toggle as unknown as Element);

    controller.dispose(fixture.root as unknown as Element);

    assertEqual(fixture.root.getAttribute(rosterSidePanelDomAttr), rosterSidePanelStates.collapsed);
});
