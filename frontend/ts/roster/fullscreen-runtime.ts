import {
    isRosterFullscreenState,
    rosterFullscreenDomAttr,
    rosterFullscreenLabelDomAttr,
    rosterFullscreenRootDomAttr,
    rosterFullscreenStates,
    rosterFullscreenToggleDomAttr,
    type RosterFullscreenState,
} from "../generated/contracts";
import { detailRoot, onAppPageReady } from "../shared/lifecycle";
import { rosterFullscreenLabels } from "./fullscreen";

export type RosterFullscreenDiagnostic = {
    code: "invalid-root-role" | "invalid-state" | "invalid-toggle-role" | "invalid-label-role";
    elementId: string | null;
    message: string;
};

export type RosterFullscreenDiagnosticReporter = (diagnostic: RosterFullscreenDiagnostic) => void;

export type RosterFullscreenController = {
    reconcile: (root: Element) => boolean;
    toggle: (target: Element) => boolean;
    collapse: (root: Element) => boolean;
};

const rootSelector = `[${rosterFullscreenRootDomAttr}]`;
const toggleSelector = `[${rosterFullscreenToggleDomAttr}]`;
const labelSelector = `[${rosterFullscreenLabelDomAttr}]`;

function defaultDiagnosticReporter(diagnostic: RosterFullscreenDiagnostic): void {
    console.error?.("Invalid generated roster fullscreen boundary", diagnostic);
}

function diagnostic(element: Element, code: RosterFullscreenDiagnostic["code"], message: string): RosterFullscreenDiagnostic {
    return { code, elementId: element.id || null, message };
}

function closestRoot(target: Element): Element | null {
    return target.closest(rootSelector);
}

function ownedToggles(root: Element): Element[] {
    return Array.from(root.querySelectorAll(toggleSelector)).filter((toggle) => closestRoot(toggle) === root);
}

function stateFor(root: Element, report: RosterFullscreenDiagnosticReporter): RosterFullscreenState | null {
    if (root.getAttribute(rosterFullscreenRootDomAttr) !== "true") {
        report(diagnostic(root, "invalid-root-role", "Roster fullscreen root role must equal true"));
        return null;
    }
    const state = root.getAttribute(rosterFullscreenDomAttr);
    if (!isRosterFullscreenState(state)) {
        report(diagnostic(root, "invalid-state", "Roster fullscreen state is not declared by the Surface contract"));
        return null;
    }
    return state;
}

type ValidatedToggle = { toggle: Element; label: Element };

function validateToggle(toggle: Element, report: RosterFullscreenDiagnosticReporter): ValidatedToggle | null {
    if (toggle.getAttribute(rosterFullscreenToggleDomAttr) !== "true") {
        report(diagnostic(toggle, "invalid-toggle-role", "Roster fullscreen toggle role must equal true"));
        return null;
    }
    const labels = Array.from(toggle.querySelectorAll(labelSelector))
        .filter((label) => label.closest(toggleSelector) === toggle);
    if (labels.length !== 1 || labels[0]?.getAttribute(rosterFullscreenLabelDomAttr) !== "true") {
        report(diagnostic(toggle, "invalid-label-role", "Roster fullscreen toggle must own one label role equal to true"));
        return null;
    }
    return { toggle, label: labels[0] };
}

function updateToggle(validated: ValidatedToggle, state: RosterFullscreenState): void {
    const expanded = state === rosterFullscreenStates.expanded;
    const labels = rosterFullscreenLabels(expanded);
    validated.toggle.setAttribute("aria-pressed", labels.pressed);
    validated.toggle.setAttribute("aria-label", labels.label);
    validated.toggle.setAttribute("title", labels.label);
    validated.label.textContent = labels.label;

    const icon = validated.toggle.querySelector(".bi");
    if (icon) {
        icon.classList.toggle(labels.iconRemove, false);
        icon.classList.toggle(labels.iconAdd, true);
    }
}

export function createRosterFullscreenController(
    report: RosterFullscreenDiagnosticReporter = defaultDiagnosticReporter,
): RosterFullscreenController {
    function validatedToggles(root: Element): ValidatedToggle[] | null {
        const toggles = ownedToggles(root);
        const validated = toggles.map((toggle) => validateToggle(toggle, report));
        return validated.some((toggle) => toggle === null) ? null : validated as ValidatedToggle[];
    }

    function reconcile(root: Element): boolean {
        const state = stateFor(root, report);
        const toggles = validatedToggles(root);
        if (!state || !toggles) return false;
        toggles.forEach((toggle) => updateToggle(toggle, state));
        return true;
    }

    function setState(root: Element, state: RosterFullscreenState, focusToggle: Element | null): boolean {
        if (!stateFor(root, report)) return false;
        const toggles = validatedToggles(root);
        if (!toggles) return false;
        root.setAttribute(rosterFullscreenDomAttr, state);
        toggles.forEach((toggle) => updateToggle(toggle, state));
        if (state === rosterFullscreenStates.expanded && focusToggle) {
            const focus = (focusToggle as HTMLElement).focus;
            if (typeof focus === "function") focus.call(focusToggle, { preventScroll: true });
        }
        return true;
    }

    function toggle(target: Element): boolean {
        const toggleElement = target.closest(toggleSelector);
        if (!toggleElement || !validateToggle(toggleElement, report)) return false;
        const root = closestRoot(toggleElement);
        if (!root) return false;
        const state = stateFor(root, report);
        if (!state) return false;
        const nextState = state === rosterFullscreenStates.expanded
            ? rosterFullscreenStates.collapsed
            : rosterFullscreenStates.expanded;
        return setState(root, nextState, toggleElement);
    }

    function collapse(root: Element): boolean {
        return setState(root, rosterFullscreenStates.collapsed, null);
    }

    return { reconcile, toggle, collapse };
}

function fullscreenRootsWithin(root: Document | DocumentFragment | Element): Element[] {
    const roots = Array.from(root.querySelectorAll(rootSelector));
    if (root instanceof Element) {
        if (root.matches(rootSelector)) roots.unshift(root);
        const owner = closestRoot(root);
        if (owner && !roots.includes(owner)) roots.unshift(owner);
    }
    return roots;
}

export function enableRosterFullscreenToggle(): void {
    if (typeof window === "undefined") return;
    const controller = createRosterFullscreenController();
    const reconcileWithin = (root: Document | DocumentFragment | Element) => fullscreenRootsWithin(root).forEach(controller.reconcile);

    document.addEventListener("click", (event) => {
        if (!(event.target instanceof Element)) return;
        controller.toggle(event.target);
    });

    document.addEventListener("keydown", (event) => {
        if (event.key !== "Escape") return;
        const focusedRoot = document.activeElement instanceof Element
            ? closestRoot(document.activeElement)
            : null;
        const expandedRoot = focusedRoot?.getAttribute(rosterFullscreenDomAttr) === rosterFullscreenStates.expanded
            ? focusedRoot
            : document.querySelector(`${rootSelector}[${rosterFullscreenDomAttr}="${rosterFullscreenStates.expanded}"]`);
        if (expandedRoot) controller.collapse(expandedRoot);
    });

    onAppPageReady((event) => reconcileWithin(detailRoot(event, "target")));
    document.addEventListener("htmx:afterSwap", (event) => reconcileWithin(detailRoot(event, "target")));
    if (document.readyState !== "loading") reconcileWithin(document);
}
