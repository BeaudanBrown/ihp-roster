import {
    FrontendSurfaceSidePanelRegistry,
    FrontendSurfaceLinkedHighlightRegistry,
    appNavigationHeaderDomAttr,
    appPageContentDomAttr,
    surfaceDomAttr,
    dialogMountDomAttr,
    dialogDismissedEvent,
    type FrontendSurfaceSidePanelDefinition,
} from "../generated/contracts";
import { detailRoot, detailTarget, onAppPageReady } from "../shared/lifecycle";
import { dialogDismissedDetail } from "../dialog-overlays/lifecycle";
import { setPageOverlay } from "../shared/page-overlay";
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
    | "invalid-label-role"
    | "invalid-shelf-role"
    | "invalid-shelf-state";

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

type SidePanelEventSource = {
    activeElement: unknown;
    addEventListener: (name: string, listener: (event: Event) => void) => void;
};

type SidePanelLifecycleEvent = Event & {
    key?: string;
    detail?: { target?: unknown };
};

export function installSidePanelEventListeners(
    source: SidePanelEventSource,
    controller: SidePanelController,
    reconcileWithin: (root: Document | DocumentFragment | Element) => void,
): void {
    source.addEventListener("click", (event) => {
        if (isSurfaceElementLike(event.target)) controller.toggle(event.target as unknown as Element);
    });
    source.addEventListener("keydown", (event) => {
        if ((event as SidePanelLifecycleEvent).key !== "Escape" || event.defaultPrevented || !isSurfaceElementLike(source.activeElement)) return;
        if (typeof window !== "undefined" && window.matchMedia("(max-width: 1199.98px)").matches) return;
        const focused = expandedSidePanelRootForEscape(source.activeElement as unknown as Element);
        if (focused) controller.collapse(focused);
    });
    source.addEventListener("htmx:afterSwap", (event) => {
        const target = (event as SidePanelLifecycleEvent).detail?.target;
        if (target && typeof (target as { querySelectorAll?: unknown }).querySelectorAll === "function") {
            reconcileWithin(target as Document | DocumentFragment | Element);
        }
    });
    source.addEventListener("htmx:beforeCleanupElement", (event) => {
        const target = (event as SidePanelLifecycleEvent).detail?.target;
        if (isSurfaceElementLike(target)) controller.dispose(target as unknown as Element);
    });
}

let browserRuntimeEnabled = false;

export function enableSidePanels(): void {
    if (browserRuntimeEnabled || typeof document === "undefined") return;
    browserRuntimeEnabled = true;
    const controller = createSidePanelController();
    const reconcileWithin = (root: Document | DocumentFragment | Element) => rootsWithin(root).forEach((panelRoot) => controller.reconcile(panelRoot as unknown as Element));

    installSidePanelEventListeners(document, controller, reconcileWithin);
    installResponsiveShelves();
    onAppPageReady((event) => reconcileWithin(detailRoot(event, "target")));
    if (document.readyState !== "loading") reconcileWithin(document);
}

// Responsive presentation of the existing Surface-owned panel. No business DOM
// is moved or copied: nested mounts, forms and live fragment targets stay put.
function installResponsiveShelves(): void {
    const mobile = window.matchMedia("(max-width: 1199.98px)");
    type Shelf = { resolved: ResolvedRoot; root: HTMLElement; panel: HTMLElement; content: HTMLElement; bar: HTMLButtonElement };
    type ScrollPosition = { id: string; path: number[]; tag: string; top: number; left: number };
    type Snapshot = { root: HTMLElement; surface: string; name: string; scrolls: ScrollPosition[] };
    const pending = new WeakMap<object, Snapshot>();
    const pendingOob = new Map<string, Snapshot>();
    const overlayOwner = {};
    let active: Shelf | null = null;
    let shelfFocus: HTMLElement | null = null;
    let header: HTMLElement | null = null;
    let headerObserver: ResizeObserver | null = null;
    let shelfAnimation: Animation | null = null;

    function cancelSlide(): void {
        shelfAnimation?.cancel();
        shelfAnimation = null;
    }

    function shelves(): Shelf[] {
        return rootsWithin(document).flatMap((candidate) => {
            if (!(candidate instanceof HTMLElement)) return [];
            const resolved = resolveRoot(candidate);
            if (!resolved || !stateFor(resolved, defaultDiagnosticReporter)) return [];
            const definition = resolved.definition;
            if (!definition.isShelfState(candidate.getAttribute(definition.shelfStateAttribute))) {
                defaultDiagnosticReporter(diagnostic(candidate, "invalid-shelf-state", "Shelf state is not declared by the Surface contract"));
                return [];
            }
            const panels = ownedElements(resolved, definition.panelRoleAttribute);
            const contents = ownedElements(resolved, definition.shelfRoleAttribute);
            const bars = ownedElements(resolved, definition.shelfToggleRoleAttribute);
            const panel = panels[0];
            const content = contents[0];
            const bar = bars[0];
            if (panels.length !== 1 || contents.length !== 1 || bars.length !== 1
                || !(panel instanceof HTMLElement) || !(content instanceof HTMLElement) || !(bar instanceof HTMLButtonElement)
                || content.getAttribute(definition.shelfRoleAttribute) !== "true"
                || bar.getAttribute(definition.shelfToggleRoleAttribute) !== "true"
                || !panel.contains(content) || !panel.contains(bar)) {
                defaultDiagnosticReporter(diagnostic(candidate, "invalid-shelf-role", "SidePanel must own one shelf content region and one toggle inside its panel"));
                return [];
            }
            return [{ resolved, root: candidate, panel, content, bar }];
        });
    }

    function isOpen(shelf: Shelf): boolean {
        return mobile.matches && shelf.root.getAttribute(shelf.resolved.definition.shelfStateAttribute) === shelf.resolved.definition.shelfOpenValue;
    }

    function setOpen(shelf: Shelf, open: boolean): void {
        const definition = shelf.resolved.definition;
        shelf.root.setAttribute(definition.shelfStateAttribute, open ? definition.shelfOpenValue : definition.shelfClosedValue);
    }

    function lockBackground(shelf: Shelf): void {
        // The shelf leaves navigation usable; a dialog above it isolates the
        // entire body instead. Both retain their own shared scroll-lock claim.
        const page = shelf.panel.closest<HTMLElement>(`[${appPageContentDomAttr}]`);
        setPageOverlay(overlayOwner, page ? { element: shelf.panel, boundary: page, priority: 0 } : null);
        document.body.classList.add("app-shelf-scroll-locked");
    }

    function unlockBackground(): void {
        setPageOverlay(overlayOwner, null);
        document.body?.classList.remove("app-shelf-scroll-locked");
    }

    function updateGeometry(): void {
        const top = header ? Math.max(0, header.getBoundingClientRect().bottom) : 0;
        const viewport = window.visualViewport;
        const bottom = viewport ? viewport.offsetTop + viewport.height : window.innerHeight;
        const style = document.documentElement.style;
        const height = `${Math.max(0, bottom - top)}px`;
        const bottomInset = `${Math.max(0, window.innerHeight - bottom)}px`;
        if (style.getPropertyValue("--app-shelf-height") !== height || style.getPropertyValue("--app-shelf-bottom") !== bottomInset) {
            // Toolbar/keyboard changes snap to current geometry; only deliberate
            // visibility changes animate. The closed bar never uses this geometry.
            cancelSlide();
        }
        style.setProperty("--app-shelf-height", height);
        style.setProperty("--app-shelf-bottom", bottomInset);
    }

    function reconcile(): void {
        if (document.body === null) return;
        const all = shelves();
        const enabled = mobile.matches && all.length > 0;
        document.body.classList.toggle("app-has-mobile-shelf", enabled);
        const nextHeader = document.querySelector<HTMLElement>(`[${appNavigationHeaderDomAttr}]`);
        if (nextHeader !== header) {
            headerObserver?.disconnect();
            header = nextHeader;
            headerObserver = header ? new ResizeObserver(updateGeometry) : null;
            if (header) headerObserver?.observe(header);
        }
        active = null;
        for (const shelf of all) {
            if (!mobile.matches) setOpen(shelf, false);
            // A page has one active shelf, even if independent nested mounts exist.
            if (active && isOpen(shelf)) setOpen(shelf, false);
            const open = isOpen(shelf);
            shelf.root.classList.toggle("is-shelf-open", open);
            shelf.bar.setAttribute("aria-expanded", String(open));
            shelf.content.inert = mobile.matches && !open;
            if (open) active = shelf;
        }
        if (active) lockBackground(active);
        else unlockBackground();
        updateGeometry();
    }

    function changeVisibility(shelf: Shelf, open: boolean): void {
        const before = shelf.panel.getBoundingClientRect().height;
        const beforeBottom = getComputedStyle(shelf.panel).bottom;
        cancelSlide();
        setOpen(shelf, open);
        reconcile();
        if (!mobile.matches || window.matchMedia("(prefers-reduced-motion: reduce)").matches) return;
        const after = shelf.panel.getBoundingClientRect().height;
        const afterBottom = getComputedStyle(shelf.panel).bottom;
        if (before === after && beforeBottom === afterBottom) return;
        const animation = shelf.panel.animate([
            { height: `${before}px`, bottom: beforeBottom },
            { height: `${after}px`, bottom: afterBottom },
        ], {
            duration: 220,
            easing: "ease",
        });
        shelfAnimation = animation;
        void animation.finished.then(() => {
            if (shelfAnimation === animation) shelfAnimation = null;
        }, () => { /* Geometry changes or a subsequent toggle cancelled it. */ });
    }

    function close(shelf: Shelf, returnFocus = true): void {
        changeVisibility(shelf, false);
        if (returnFocus && shelf.bar.isConnected) shelf.bar.focus({ preventScroll: true });
    }

    function hasDialog(): boolean {
        return document.querySelector(`[${dialogMountDomAttr}], .modal.show, .offcanvas.show, .offcanvas.showing`) !== null;
    }

    document.addEventListener("click", (event) => {
        const target = event.target;
        if (!(target instanceof Element)) return;
        const shelf = shelves().find((item) => item.bar.contains(target));
        if (shelf && mobile.matches) {
            if (isOpen(shelf)) close(shelf);
            else {
                changeVisibility(shelf, true);
                const tab = shelf.content.querySelector<HTMLElement>('[role="tab"][aria-selected="true"]');
                (tab ?? shelf.bar).focus({ preventScroll: true });
            }
        }
    });

    document.addEventListener("focusin", (event) => {
        if (active && event.target instanceof HTMLElement && active.panel.contains(event.target)) shelfFocus = event.target;
    });
    document.addEventListener(dialogDismissedEvent, (event) => {
        const detail = dialogDismissedDetail(event);
        if (!detail || detail.replacement !== null) return;
        requestAnimationFrame(() => {
            if (!active || hasDialog()) return;
            // Do not steal focus if another control already received it.
            if (document.activeElement !== document.body && document.activeElement?.isConnected) return;
            const target = shelfFocus?.isConnected && active.panel.contains(shelfFocus) ? shelfFocus : active.bar;
            target.focus({ preventScroll: true });
        });
    });

    document.addEventListener("keydown", (event) => {
        if (event.key !== "Escape" || event.defaultPrevented || !active || hasDialog()) return;
        event.preventDefault();
        close(active);
    });

    // Compose generated linked-highlight semantics without feature names or
    // presentation-class inference. Capture before its handler stops propagation.
    document.addEventListener("click", (event) => {
        if (!active || !(event.target instanceof Element) || !active.content.contains(event.target)) return;
        const mount = closestSurfaceMount(event.target);
        if (!mount) return;
        for (const definition of surfaceDefinitionsForMount(mount, FrontendSurfaceLinkedHighlightRegistry)) {
            if (!definition.pinRoleAttribute) continue;
            const pin = event.target.closest(`[${definition.pinRoleAttribute}]`);
            if (!pin) continue;
            const shelf = active;
            queueMicrotask(() => {
                if (pin.getAttribute("aria-pressed") === "true" && active?.root === shelf.root) close(shelf);
            });
        }
    }, true);

    function capture(target: Node): Snapshot | null {
        if (!active || (!target.contains(active.root) && !active.panel.contains(target))) return null;
        const content = active.content;
        const scrolls: ScrollPosition[] = [];
        content.querySelectorAll<HTMLElement>("*").forEach((element) => {
            if (!element.scrollTop && !element.scrollLeft) return;
            const path: number[] = [];
            let child: Element = element;
            while (child !== content && child.parentElement) {
                path.unshift(Array.from(child.parentElement.children).indexOf(child));
                child = child.parentElement;
            }
            scrolls.push({ id: element.id, path, tag: element.tagName, top: element.scrollTop, left: element.scrollLeft });
        });
        return { root: active.root, surface: active.resolved.mount.getAttribute(surfaceDomAttr) ?? "", name: active.resolved.definition.name, scrolls };
    }

    function restore(snapshot: Snapshot): void {
        // A surviving root is matched by object identity. A replaced root must
        // have the same unique server-rendered target ID, not merely the same
        // Surface type. Scope may deliberately change during group navigation.
        const target = snapshot.root.isConnected ? snapshot.root : snapshot.root.id ? document.getElementById(snapshot.root.id) : null;
        const replacement = shelves().find((item) => item.root === target && item.resolved.definition.name === snapshot.name
            && item.resolved.mount.getAttribute(surfaceDomAttr) === snapshot.surface);
        if (!replacement || !mobile.matches) return;
        setOpen(replacement, true);
        reconcile();
        requestAnimationFrame(() => snapshot.scrolls.forEach((position) => {
            let element: Element | null = replacement.content;
            if (position.id) element = document.getElementById(position.id);
            else for (const index of position.path) element = element?.children[index] ?? null;
            if (element instanceof HTMLElement && element.tagName === position.tag && replacement.content.contains(element)) {
                element.scrollTop = position.top;
                element.scrollLeft = position.left;
            }
        }));
    }

    document.addEventListener("htmx:beforeSwap", (event) => {
        const request = detailTarget(event, "xhr");
        if (request === null || typeof request !== "object") return;
        const snapshot = capture(detailRoot(event, "target"));
        if (snapshot) pending.set(request, snapshot);
    });
    document.addEventListener("htmx:afterSwap", (event) => {
        const request = detailTarget(event, "xhr");
        const snapshot = request !== null && typeof request === "object" ? pending.get(request) : undefined;
        if (snapshot) {
            restore(snapshot);
            pending.delete(request as object);
        }
        reconcile();
    });
    document.addEventListener("htmx:oobBeforeSwap", (event) => {
        const target = detailTarget(event, "target");
        if (!(target instanceof Element) || !target.id) return;
        const snapshot = capture(target);
        if (snapshot) pendingOob.set(target.id, snapshot);
    });
    document.addEventListener("htmx:oobAfterSwap", (event) => {
        const target = detailTarget(event, "target");
        if (target instanceof Element) {
            const snapshot = pendingOob.get(target.id);
            if (snapshot) restore(snapshot);
            pendingOob.delete(target.id);
        }
        reconcile();
    });
    document.addEventListener("htmx:beforeCleanupElement", (event) => {
        const target = detailTarget(event, "elt") ?? detailTarget(event, "target") ?? event.target;
        if (shelfFocus && target instanceof Element && target.contains(shelfFocus)) shelfFocus = null;
        if (active && target instanceof Element && target.contains(active.root)) {
            active = null;
            unlockBackground();
        }
    });
    document.addEventListener("htmx:afterSettle", () => { pendingOob.clear(); reconcile(); });
    onAppPageReady(reconcile);
    mobile.addEventListener("change", () => {
        cancelSlide();
        const previous = active;
        reconcile();
        if (previous && !mobile.matches && previous.bar === document.activeElement) {
            previous.content.querySelector<HTMLElement>('[role="tab"][aria-selected="true"]')?.focus({ preventScroll: true });
        }
    });
    window.addEventListener("resize", updateGeometry);
    window.visualViewport?.addEventListener("resize", updateGeometry);
    window.visualViewport?.addEventListener("scroll", updateGeometry);
    window.addEventListener("pagehide", () => { cancelSlide(); active = null; shelfFocus = null; unlockBackground(); });
    window.addEventListener("pageshow", reconcile);
    if (document.readyState !== "loading") reconcile();
}
