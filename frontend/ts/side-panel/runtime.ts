import {
    FrontendSurfaceSidePanelRegistry,
    type FrontendSurfaceSidePanelDefinition,
} from "../generated/contracts";
import { detailRoot, onAppPageReady } from "../shared/lifecycle";
import {
    closestOwnedSurfaceRole,
    closestSurfaceMount,
    isSurfaceElementLike,
    ownedSurfaceRoleElements,
    surfaceDefinitionsForMount,
    surfaceMountsWithin,
    type SurfaceElementLike,
} from "../shared/surface-mount";

export type SidePanelDiagnosticCode =
    | "invalid-root-role"
    | "invalid-state"
    | "invalid-main-role"
    | "invalid-panel-role"
    | "invalid-toggle-role"
    | "invalid-label-role";

export type SidePanelDiagnostic = {
    code: SidePanelDiagnosticCode;
    elementId: string | null;
    message: string;
};

export type SidePanelDiagnosticReporter = (diagnostic: SidePanelDiagnostic) => void;

export type SidePanelController = {
    reconcile: (root: Element) => boolean;
    toggle: (target: Element) => boolean;
    collapse: (root: Element) => boolean;
    dispose: (root: Element) => void;
};

type ElementLike = SurfaceElementLike;
type ResolvedRoot = { mount: ElementLike; root: ElementLike; definition: FrontendSurfaceSidePanelDefinition };
type ValidatedToggle = { toggle: ElementLike; label: ElementLike };

function defaultDiagnosticReporter(diagnostic: SidePanelDiagnostic): void {
    console.error?.("Invalid generated Surface side-panel boundary", diagnostic);
}

function diagnostic(element: ElementLike, code: SidePanelDiagnosticCode, message: string): SidePanelDiagnostic {
    return { code, elementId: element.id || null, message };
}

function definitionRoots(mount: ElementLike, definition: FrontendSurfaceSidePanelDefinition): ElementLike[] {
    return ownedSurfaceRoleElements(mount, mount, definition.rootRoleAttribute);
}

function resolveRoot(root: ElementLike): ResolvedRoot | null {
    const mount = closestSurfaceMount(root);
    if (!mount) return null;
    for (const definition of surfaceDefinitionsForMount(mount, FrontendSurfaceSidePanelRegistry)) {
        const candidate = closestOwnedSurfaceRole(root, mount, definition.rootRoleAttribute);
        if (candidate) return { mount, root: candidate, definition };
    }
    return null;
}

function resolveToggle(target: ElementLike): { resolved: ResolvedRoot; toggle: ElementLike } | null {
    const mount = closestSurfaceMount(target);
    if (!mount) return null;
    for (const definition of surfaceDefinitionsForMount(mount, FrontendSurfaceSidePanelRegistry)) {
        const toggle = closestOwnedSurfaceRole(target, mount, definition.toggleRoleAttribute);
        if (!toggle) continue;
        const root = closestOwnedSurfaceRole(toggle, mount, definition.rootRoleAttribute);
        if (root) return { resolved: { mount, root, definition }, toggle };
    }
    return null;
}

function ownedElements(resolved: ResolvedRoot, attribute: string): ElementLike[] {
    return ownedSurfaceRoleElements(resolved.root, resolved.mount, attribute)
        .filter((element) => closestOwnedSurfaceRole(element, resolved.mount, resolved.definition.rootRoleAttribute) === resolved.root);
}

function validateStructure(resolved: ResolvedRoot, report: SidePanelDiagnosticReporter): boolean {
    if (resolved.root.getAttribute(resolved.definition.rootRoleAttribute) !== "true") {
        report(diagnostic(resolved.root, "invalid-root-role", "Side-panel root role must equal true"));
        return false;
    }
    const required: Array<[string, SidePanelDiagnosticCode]> = [
        [resolved.definition.mainRoleAttribute, "invalid-main-role"],
        [resolved.definition.panelRoleAttribute, "invalid-panel-role"],
    ];
    for (const [attribute, code] of required) {
        const elements = ownedElements(resolved, attribute);
        if (elements.length !== 1 || elements[0]?.getAttribute(attribute) !== "true") {
            report(diagnostic(resolved.root, code, "Side-panel root must own exactly one generated region role"));
            return false;
        }
    }
    return true;
}

function stateFor(resolved: ResolvedRoot, report: SidePanelDiagnosticReporter): string | null {
    if (!validateStructure(resolved, report)) return null;
    const state = resolved.root.getAttribute(resolved.definition.stateAttribute);
    if (!resolved.definition.isState(state)) {
        report(diagnostic(resolved.root, "invalid-state", "Side-panel state is not declared by the Surface contract"));
        return null;
    }
    return state;
}

function validateToggle(
    resolved: ResolvedRoot,
    toggle: ElementLike,
    report: SidePanelDiagnosticReporter,
): ValidatedToggle | null {
    if (toggle.getAttribute(resolved.definition.toggleRoleAttribute) !== "true") {
        report(diagnostic(toggle, "invalid-toggle-role", "Side-panel toggle role must equal true"));
        return null;
    }
    const labels = Array.from(toggle.querySelectorAll(`[${resolved.definition.labelRoleAttribute}]`))
        .filter(isSurfaceElementLike)
        .filter((label) => closestOwnedSurfaceRole(label, resolved.mount, resolved.definition.toggleRoleAttribute) === toggle);
    if (labels.length !== 1 || labels[0]?.getAttribute(resolved.definition.labelRoleAttribute) !== "true") {
        report(diagnostic(toggle, "invalid-label-role", "Side-panel toggle must own one generated label role"));
        return null;
    }
    return { toggle, label: labels[0] };
}

function updateToggle(validated: ValidatedToggle, resolved: ResolvedRoot, state: string): void {
    const expanded = state === resolved.definition.expandedValue;
    const rootClassList = (resolved.root as unknown as { classList?: { toggle: (name: string, force?: boolean) => boolean } }).classList;
    rootClassList?.toggle("is-side-panel-expanded", expanded);
    const label = expanded ? "Show side panel" : "Expand main content";
    validated.toggle.setAttribute("aria-pressed", expanded ? "true" : "false");
    validated.toggle.setAttribute("aria-label", label);
    validated.toggle.setAttribute("title", label);
    (validated.label as unknown as { textContent: string | null }).textContent = label;

    const icon = Array.from(validated.toggle.querySelectorAll(".bi"))[0];
    if ((typeof Element !== "undefined" && icon instanceof Element) || isSurfaceElementLike(icon)) {
        const classList = (icon as unknown as { classList?: { toggle: (name: string, force?: boolean) => boolean } }).classList;
        classList?.toggle("bi-fullscreen", !expanded);
        classList?.toggle("bi-fullscreen-exit", expanded);
    }
}

export function createSidePanelController(
    report: SidePanelDiagnosticReporter = defaultDiagnosticReporter,
): SidePanelController {
    function validatedToggles(resolved: ResolvedRoot): ValidatedToggle[] | null {
        const toggles = ownedElements(resolved, resolved.definition.toggleRoleAttribute);
        const validated = toggles.map((toggle) => validateToggle(resolved, toggle, report));
        return validated.some((toggle) => toggle === null) ? null : validated as ValidatedToggle[];
    }

    function reconcile(root: Element): boolean {
        if (!isSurfaceElementLike(root)) return false;
        const resolved = resolveRoot(root);
        if (!resolved) return false;
        const state = stateFor(resolved, report);
        const toggles = validatedToggles(resolved);
        if (!state || !toggles) return false;
        toggles.forEach((toggle) => updateToggle(toggle, resolved, state));
        return true;
    }

    function setState(resolved: ResolvedRoot, state: string, focusToggle: ElementLike | null): boolean {
        if (!stateFor(resolved, report)) return false;
        const toggles = validatedToggles(resolved);
        if (!toggles) return false;
        resolved.root.setAttribute(resolved.definition.stateAttribute, state);
        toggles.forEach((toggle) => updateToggle(toggle, resolved, state));
        if (focusToggle) {
            const focus = (focusToggle as unknown as { focus?: (options?: FocusOptions) => void }).focus;
            if (typeof focus === "function") focus.call(focusToggle, { preventScroll: true });
        }
        return true;
    }

    function toggle(target: Element): boolean {
        if (!isSurfaceElementLike(target)) return false;
        const match = resolveToggle(target);
        if (!match || !validateToggle(match.resolved, match.toggle, report)) return false;
        const state = stateFor(match.resolved, report);
        if (!state) return false;
        const nextState = state === match.resolved.definition.expandedValue
            ? match.resolved.definition.collapsedValue
            : match.resolved.definition.expandedValue;
        return setState(match.resolved, nextState, match.toggle);
    }

    function collapse(root: Element): boolean {
        if (!isSurfaceElementLike(root)) return false;
        const resolved = resolveRoot(root);
        return resolved ? setState(resolved, resolved.definition.collapsedValue, null) : false;
    }

    function dispose(root: Element): void {
        if (!isSurfaceElementLike(root)) return;
        const resolved = resolveRoot(root);
        if (resolved?.root === root) collapse(root);
    }

    return { reconcile, toggle, collapse, dispose };
}

export function expandedSidePanelRootForEscape(target: Element | null): Element | null {
    if (!target || !isSurfaceElementLike(target)) return null;
    const focused = resolveRoot(target);
    if (!focused) return null;
    return focused.root.getAttribute(focused.definition.stateAttribute) === focused.definition.expandedValue
        ? focused.root as unknown as Element
        : null;
}

function rootsWithin(root: Document | DocumentFragment | Element): ElementLike[] {
    const roots: ElementLike[] = [];
    for (const mount of surfaceMountsWithin(root as Document | Element)) {
        for (const definition of surfaceDefinitionsForMount(mount, FrontendSurfaceSidePanelRegistry)) {
            for (const sidePanelRoot of definitionRoots(mount, definition)) {
                if (!roots.includes(sidePanelRoot)) roots.push(sidePanelRoot);
            }
        }
    }
    return roots;
}

let browserRuntimeEnabled = false;

export function enableSidePanels(): void {
    if (browserRuntimeEnabled || typeof document === "undefined") return;
    browserRuntimeEnabled = true;
    const controller = createSidePanelController();
    const reconcileWithin = (root: Document | DocumentFragment | Element) => rootsWithin(root).forEach((panelRoot) => controller.reconcile(panelRoot as unknown as Element));

    document.addEventListener("click", (event) => {
        if (event.target instanceof Element) controller.toggle(event.target);
    });
    document.addEventListener("keydown", (event) => {
        if (event.key !== "Escape") return;
        const focused = document.activeElement instanceof Element
            ? expandedSidePanelRootForEscape(document.activeElement)
            : null;
        if (focused) controller.collapse(focused);
    });
    onAppPageReady((event) => reconcileWithin(detailRoot(event, "target")));
    document.addEventListener("htmx:afterSwap", (event) => reconcileWithin(detailRoot(event, "target")));
    document.addEventListener("htmx:beforeCleanupElement", (event) => {
        const root = detailRoot(event, "target");
        if (root instanceof Element) controller.dispose(root);
    });
    if (document.readyState !== "loading") reconcileWithin(document);
}
