import {
    FrontendSurfaceSidePanelRegistry,
    rosterSidePanelDomAttr,
    rosterSidePanelLabelDomAttr,
    rosterSidePanelMainDomAttr,
    rosterSidePanelPanelDomAttr,
    rosterSidePanelRootDomAttr,
    rosterSidePanelStates,
    rosterSidePanelToggleDomAttr,
    surfaceDomAttr,
    type FrontendSurfaceName,
} from "../generated/contracts";
import {
    createSidePanelController,
    expandedSidePanelRootForEscape,
    installSidePanelEventListeners,
    type SidePanelDiagnostic,
} from "../side-panel/runtime";
import { assertDeepEqual, assertEqual, test } from "./harness";
import { MiniElement } from "./mini-dom";

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

function registeredSidePanelMount(surface: FrontendSurfaceName, id: string) {
    const definition = FrontendSurfaceSidePanelRegistry[surface][0];
    if (!definition) throw new Error(`missing SidePanel definition for ${surface}`);
    const mount = new MiniElement({ [surfaceDomAttr]: surface }, `${id}-mount`);
    const root = mount.append(new MiniElement({
        [definition.rootRoleAttribute]: "true",
        [definition.stateAttribute]: definition.collapsedValue,
    }, `${id}-root`));
    const main = root.append(new MiniElement({ [definition.mainRoleAttribute]: "true" }, `${id}-main`));
    const panel = root.append(new MiniElement({ [definition.panelRoleAttribute]: "true" }, `${id}-panel`));
    const toggle = main.append(new MiniElement({ [definition.toggleRoleAttribute]: "true" }, `${id}-toggle`));
    toggle.append(new MiniElement({}, `${id}-icon`, ["bi", "bi-fullscreen"]));
    const label = toggle.append(new MiniElement({ [definition.labelRoleAttribute]: "true" }, `${id}-label`));
    label.textContent = "Expand main content";
    return { definition, mount, root, main, panel, toggle };
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

test("Roster, Timesheets, and Unavailability share transient generated SidePanel behavior", () => {
    const surfaces: FrontendSurfaceName[] = ["roster", "timesheets", "leave-requests"];
    const fixtures = surfaces.map((surface) => registeredSidePanelMount(surface, surface));
    const controller = createSidePanelController();

    fixtures.forEach((fixture) => controller.reconcile(fixture.mount as unknown as Element));
    assertEqual(controller.toggle(fixtures[1]!.toggle as unknown as Element), true);

    fixtures.forEach((fixture, index) => {
        assertEqual(
            fixture.root.getAttribute(fixture.definition.stateAttribute),
            index === 1 ? fixture.definition.expandedValue : fixture.definition.collapsedValue,
            `${surfaces[index]} transient state`,
        );
    });

    controller.dispose(fixtures[1]!.root as unknown as Element);
    assertEqual(
        fixtures[1]!.root.getAttribute(fixtures[1]!.definition.stateAttribute),
        fixtures[1]!.definition.collapsedValue,
        "Timesheets state after mount disposal",
    );
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
