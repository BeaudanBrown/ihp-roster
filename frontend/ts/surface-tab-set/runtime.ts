import {
    FrontendSurfaceTabSetRegistry,
    surfaceDomAttr,
    type FrontendSurfaceTabSetDefinition,
} from "../generated/contracts";
import type { DomRoot } from "../shared/dom";
import { detailRoot, detailTarget, onAppPageReady } from "../shared/lifecycle";
import {
    closestOwnedSurfaceRole as closestOwnedRole,
    closestSurfaceMount,
    isSurfaceElementLike as isElementLike,
    ownedSurfaceRoleElements as ownedRoleElements,
    surfaceDefinitionsForMount,
    surfaceMountsWithin,
    surfaceRootFromPageReadyEvent as rootFromPageReadyEvent,
    type SurfaceElementLike,
} from "../shared/surface-mount";

export type SurfaceTabSetDiagnosticCode =
    | "invalid-tab-key"
    | "missing-tab-key"
    | "duplicate-tab-key";

export type SurfaceTabSetDiagnostic = {
    code: SurfaceTabSetDiagnosticCode;
    elementId: string | null;
    message: string;
};

export type SurfaceTabSetDiagnosticReporter = (diagnostic: SurfaceTabSetDiagnostic) => void;
export type SurfaceTabShower = (element: Element) => void;

type ElementLike = SurfaceElementLike;

export type SurfaceTabSetSnapshot = {
    surface: string;
    mountIndex: number;
    tabSet: string;
    key: string;
};

export type SurfaceTabSetController = {
    remember: (target: Element) => boolean;
    capture: (root: DomRoot) => SurfaceTabSetSnapshot[];
    restore: (root: DomRoot, snapshots: ReadonlyArray<SurfaceTabSetSnapshot>) => void;
    reconcile: (root: DomRoot) => void;
};

function tabPresentationMatchesSelection(element: ElementLike): boolean {
    if (typeof HTMLElement === "undefined" || !(element instanceof HTMLElement)) {
        return element.getAttribute("aria-selected") === "true";
    }
    const paneSelector = element.getAttribute("data-bs-target");
    if (paneSelector === null || !paneSelector.startsWith("#")) return false;
    const pane = document.querySelector(paneSelector);
    return element.classList.contains("active")
        && pane?.classList.contains("active") === true
        && pane.classList.contains("show");
}

function defaultShowTab(element: Element): void {
    if (!(element instanceof HTMLElement)) return;
    if (element.getAttribute("aria-selected") === "true" && !tabPresentationMatchesSelection(element)) {
        element.classList.remove("active");
        element.setAttribute("aria-selected", "false");
    }
    window.bootstrap?.Tab?.getOrCreateInstance(element).show();
}

function defaultDiagnosticReporter(diagnostic: SurfaceTabSetDiagnostic): void {
    console.error?.("Invalid generated Surface tab-set boundary", diagnostic);
}

function diagnostic(
    element: ElementLike,
    code: SurfaceTabSetDiagnosticCode,
    message: string,
): SurfaceTabSetDiagnostic {
    return { code, elementId: element.id || null, message };
}

export function createSurfaceTabSetController(
    showTab: SurfaceTabShower = defaultShowTab,
    report: SurfaceTabSetDiagnosticReporter = defaultDiagnosticReporter,
): SurfaceTabSetController {
    const activeKeysByMount = new WeakMap<object, Map<string, string>>();

    function rememberedKey(mount: ElementLike, definition: FrontendSurfaceTabSetDefinition): string {
        return activeKeysByMount.get(mount as object)?.get(definition.name) ?? definition.defaultKey;
    }

    function setRememberedKey(mount: ElementLike, definition: FrontendSurfaceTabSetDefinition, key: string): void {
        let activeKeys = activeKeysByMount.get(mount as object);
        if (!activeKeys) {
            activeKeys = new Map();
            activeKeysByMount.set(mount as object, activeKeys);
        }
        activeKeys.set(definition.name, key);
    }

    function remember(target: Element): boolean {
        if (!isElementLike(target)) return false;
        const mount = closestSurfaceMount(target);
        if (!mount) return false;

        for (const definition of definitionsForMount(mount)) {
            const tab = closestOwnedRole(target, mount, definition.tabRoleAttribute);
            if (!tab) continue;
            const key = tab.getAttribute(definition.tabRoleAttribute);
            if (key === null || !definition.isKey(key)) {
                report(diagnostic(tab, "invalid-tab-key", "Surface tab has an undeclared key"));
                return false;
            }
            setRememberedKey(mount, definition, key);
            return true;
        }
        return false;
    }

    function capture(root: DomRoot): SurfaceTabSetSnapshot[] {
        const mountIndexes = new Map<string, number>();
        const snapshots: SurfaceTabSetSnapshot[] = [];
        for (const mount of surfaceMountsWithin(root)) {
            const surface = mount.getAttribute(surfaceDomAttr);
            if (surface === null) continue;
            const mountIndex = mountIndexes.get(surface) ?? 0;
            mountIndexes.set(surface, mountIndex + 1);
            for (const definition of definitionsForMount(mount)) {
                const selectedTab = ownedRoleElements(mount, mount, definition.tabRoleAttribute)
                    .find((tab) => tab.getAttribute("aria-selected") === "true");
                const key = selectedTab?.getAttribute(definition.tabRoleAttribute)
                    ?? rememberedKey(mount, definition);
                if (!definition.isKey(key)) continue;
                snapshots.push({ surface, mountIndex, tabSet: definition.name, key });
            }
        }
        return snapshots;
    }

    function restore(root: DomRoot, snapshots: ReadonlyArray<SurfaceTabSetSnapshot>): void {
        const mountIndexes = new Map<string, number>();
        for (const mount of surfaceMountsWithin(root)) {
            const surface = mount.getAttribute(surfaceDomAttr);
            if (surface === null) continue;
            const mountIndex = mountIndexes.get(surface) ?? 0;
            mountIndexes.set(surface, mountIndex + 1);
            for (const definition of definitionsForMount(mount)) {
                const snapshot = snapshots.find((candidate) =>
                    candidate.surface === surface
                    && candidate.mountIndex === mountIndex
                    && candidate.tabSet === definition.name
                    && definition.isKey(candidate.key));
                if (snapshot) setRememberedKey(mount, definition, snapshot.key);
            }
        }
    }

    function reconcile(root: DomRoot): void {
        for (const mount of surfaceMountsWithin(root)) {
            for (const definition of definitionsForMount(mount)) {
                const tabs = ownedRoleElements(mount, mount, definition.tabRoleAttribute);
                if (tabs.length === 0) continue;
                const tabsByKey = new Map<string, ElementLike[]>();
                let valid = true;
                for (const tab of tabs) {
                    const key = tab.getAttribute(definition.tabRoleAttribute);
                    if (key === null || !definition.isKey(key)) {
                        report(diagnostic(tab, "invalid-tab-key", "Surface tab has an undeclared key"));
                        valid = false;
                        continue;
                    }
                    const matchingTabs = tabsByKey.get(key) ?? [];
                    matchingTabs.push(tab);
                    tabsByKey.set(key, matchingTabs);
                }
                for (const [key, matchingTabs] of tabsByKey) {
                    if (matchingTabs.length <= 1) continue;
                    report(diagnostic(mount, "duplicate-tab-key", `Surface tab set renders key ${key} more than once`));
                    valid = false;
                }
                if (!valid) continue;

                const remembered = rememberedKey(mount, definition);
                const desiredKey = tabsByKey.has(remembered) ? remembered : definition.defaultKey;
                if (desiredKey !== remembered) {
                    report(diagnostic(mount, "missing-tab-key", `Surface tab set is missing rendered key ${remembered}; restoring ${desiredKey}`));
                    setRememberedKey(mount, definition, desiredKey);
                }
                const desiredTabs = tabsByKey.get(desiredKey) ?? [];
                if (desiredTabs.length === 0) {
                    report(diagnostic(mount, "missing-tab-key", `Surface tab set is missing rendered default key ${definition.defaultKey}`));
                    continue;
                }
                const desiredTab = desiredTabs[0];
                if (desiredTab && tabPresentationMatchesSelection(desiredTab)) continue;
                showTab(desiredTab as unknown as Element);
            }
        }
    }

    return { remember, capture, restore, reconcile };
}

function definitionsForMount(mount: ElementLike): ReadonlyArray<FrontendSurfaceTabSetDefinition> {
    return surfaceDefinitionsForMount(mount, FrontendSurfaceTabSetRegistry);
}

let browserRuntimeEnabled = false;

export function enableFrontendSurfaceTabSets(): void {
    if (browserRuntimeEnabled || typeof document === "undefined") return;
    browserRuntimeEnabled = true;
    const controller = createSurfaceTabSetController();

    const pendingSwapSnapshots = new WeakMap<object, SurfaceTabSetSnapshot[]>();
    document.addEventListener("shown.bs.tab", (event) => {
        if (!(event.target instanceof Element)) return;
        controller.remember(event.target);
    });
    document.addEventListener("htmx:beforeSwap", (event) => {
        const request = detailTarget(event, "xhr");
        if (request === null || typeof request !== "object") return;
        pendingSwapSnapshots.set(request, controller.capture(detailRoot(event, "target")));
    });
    document.addEventListener("htmx:afterSwap", (event) => {
        const request = detailTarget(event, "xhr");
        if (request === null || typeof request !== "object") return;
        const snapshots = pendingSwapSnapshots.get(request);
        if (snapshots === undefined) return;
        const root = detailRoot(event, "target");
        controller.restore(root, snapshots);
        controller.reconcile(root);
        pendingSwapSnapshots.delete(request);
    });
    onAppPageReady((event) => controller.reconcile(rootFromPageReadyEvent(event)));
    document.addEventListener("htmx:afterSettle", () => controller.reconcile(document));
    controller.reconcile(document);
}
