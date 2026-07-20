import {
    FrontendSurfaceTabSetRegistry,
    type FrontendSurfaceTabSetDefinition,
} from "../generated/contracts";
import { onAppPageReady } from "../shared/lifecycle";
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

export type SurfaceTabSetController = {
    remember: (target: Element) => boolean;
    reconcile: (root: Document | Element) => void;
};

function defaultShowTab(element: Element): void {
    if (!(element instanceof HTMLElement)) return;
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

    function reconcile(root: Document | Element): void {
        for (const mount of surfaceMountsWithin(root)) {
            for (const definition of definitionsForMount(mount)) {
                const tabs = ownedRoleElements(mount, mount, definition.tabRoleAttribute);
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
                if (desiredTab?.getAttribute("aria-selected") === "true") continue;
                showTab(desiredTab as unknown as Element);
            }
        }
    }

    return { remember, reconcile };
}

function definitionsForMount(mount: ElementLike): ReadonlyArray<FrontendSurfaceTabSetDefinition> {
    return surfaceDefinitionsForMount(mount, FrontendSurfaceTabSetRegistry);
}

let browserRuntimeEnabled = false;

export function enableFrontendSurfaceTabSets(): void {
    if (browserRuntimeEnabled || typeof document === "undefined") return;
    browserRuntimeEnabled = true;
    const controller = createSurfaceTabSetController();

    document.addEventListener("shown.bs.tab", (event) => {
        if (!(event.target instanceof Element)) return;
        controller.remember(event.target);
    });
    onAppPageReady((event) => controller.reconcile(rootFromPageReadyEvent(event)));
    document.addEventListener("htmx:afterSettle", () => controller.reconcile(document));
    controller.reconcile(document);
}
