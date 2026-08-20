import {
    isFrontendSurfaceLiveFragmentName,
    parseFrontendSurfaceMountConfig,
    liveUpdateSocketPath,
    surfaceConfigDomAttr,
    surfaceDomAttr,
    type FrontendSurfaceMountConfig,
    type FrontendSurfaceMountedFragmentConfig,
    type SurfaceScope,
} from "../generated/contracts";

export type ParsedFrontendSurfaceSubscriptionConfig = {
    scope: SurfaceScope;
    scopeKey: string;
    socketPath: string;
    resyncFragments: FrontendSurfaceMountedFragmentConfig[];
    renderedDependencyWatermark: number;
};

export type FrontendSurfaceMountedInstance = {
    instanceId: string;
    surface: string;
    scopeKey: string;
    mountKey: string;
    depth: number;
};

export type FrontendSurfaceInstanceReconciliation = {
    added: FrontendSurfaceMountedInstance[];
    removed: FrontendSurfaceMountedInstance[];
    retained: FrontendSurfaceMountedInstance[];
};

export type FrontendSurfaceMountErrorReporter = (ownerEl: HTMLElement, error: Error) => void;

export function parseFrontendSurfaceSubscriptionConfig(value: unknown): ParsedFrontendSurfaceSubscriptionConfig | null {
    let config: FrontendSurfaceMountConfig;
    try {
        config = parseFrontendSurfaceMountConfig(value);
    } catch {
        return null;
    }
    if (!config.subscription) return null;

    const resyncFragments = config.fragments.filter((fragment) => isFrontendSurfaceLiveFragmentName(config.surface, fragment.fragmentKey.kind));
    if (resyncFragments.length === 0) return null;

    return {
        scope: config.subscription.scope,
        scopeKey: config.scopeKey,
        socketPath: `/${liveUpdateSocketPath}`,
        resyncFragments,
        renderedDependencyWatermark: config.subscription.renderedDependencyWatermark,
    };
}

export function readFrontendSurfaceMountElement(
    ownerEl: HTMLElement,
    reportError?: FrontendSurfaceMountErrorReporter,
): FrontendSurfaceMountConfig | null {
    const rawConfig = ownerEl.getAttribute(surfaceConfigDomAttr);
    if (!rawConfig) return null;

    let config: FrontendSurfaceMountConfig;
    try {
        config = parseFrontendSurfaceMountConfig(JSON.parse(rawConfig));
    } catch (error) {
        reportError?.(ownerEl, error instanceof Error ? error : new Error(String(error)));
        return null;
    }

    const ownerSurface = ownerEl.getAttribute(surfaceDomAttr);
    if (!frontendSurfaceMountMatchesOwnerSurface(config, ownerSurface)) {
        reportError?.(ownerEl, new Error(`FrontendSurface DOM/config mismatch: ${ownerSurface ?? "missing"} != ${config.surface}`));
        return null;
    }

    return config;
}

export function frontendSurfaceMountMatchesOwnerSurface(config: FrontendSurfaceMountConfig, ownerSurface: string | null): boolean {
    return ownerSurface === config.surface;
}

export function frontendSurfaceInstanceId(config: { surface: string; scopeKey: string; mountKey: string }): string {
    return `${config.surface}:${config.scopeKey}:${config.mountKey}`;
}

export function scanFrontendSurfaceMountInstances(
    root?: ParentNode,
    reportError?: FrontendSurfaceMountErrorReporter,
): FrontendSurfaceMountedInstance[] {
    const scanRoot = root ?? (typeof document !== "undefined" ? document : null);
    if (!scanRoot) return [];

    const instances: FrontendSurfaceMountedInstance[] = [];
    scanRoot.querySelectorAll(`[${surfaceConfigDomAttr}]`).forEach((ownerEl) => {
        if (!(ownerEl instanceof HTMLElement)) return;
        const config = readFrontendSurfaceMountElement(ownerEl, reportError);
        if (!config) return;
        instances.push({
            instanceId: frontendSurfaceInstanceId(config),
            surface: config.surface,
            scopeKey: config.scopeKey,
            mountKey: config.mountKey,
            depth: surfaceMountDepth(ownerEl),
        });
    });
    return instances;
}

export function reconcileFrontendSurfaceInstances(
    activeInstances: ReadonlyMap<string, FrontendSurfaceMountedInstance>,
    currentInstances: FrontendSurfaceMountedInstance[],
): FrontendSurfaceInstanceReconciliation {
    const currentById = new Map<string, FrontendSurfaceMountedInstance>();
    currentInstances.forEach((instance) => currentById.set(instance.instanceId, instance));

    const removed: FrontendSurfaceMountedInstance[] = [];
    activeInstances.forEach((instance, instanceId) => {
        if (!currentById.has(instanceId)) removed.push(instance);
    });

    const added: FrontendSurfaceMountedInstance[] = [];
    const retained: FrontendSurfaceMountedInstance[] = [];
    currentById.forEach((instance, instanceId) => {
        if (activeInstances.has(instanceId)) retained.push(instance);
        else added.push(instance);
    });

    removed.sort((left, right) => right.depth - left.depth);
    return { added, removed, retained };
}

function surfaceMountDepth(ownerEl: HTMLElement): number {
    let depth = 0;
    let current: HTMLElement | null = ownerEl.parentElement;
    while (current) {
        if (current.hasAttribute(surfaceConfigDomAttr)) depth += 1;
        current = current.parentElement;
    }
    return depth;
}
