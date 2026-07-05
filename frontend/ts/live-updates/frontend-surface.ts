import {
    parseFrontendSurfaceMountConfig as parseGeneratedFrontendSurfaceMountConfig,
    type FrontendSurfaceLiveWireFragment,
    type FrontendSurfaceMountConfig,
    type SurfaceFragmentProtection,
    type SurfaceScope,
    type SurfaceWireFragment,
} from "../generated/contracts";

export type { FrontendSurfaceMountConfig } from "../generated/contracts";

export type ParsedFrontendSurfaceSubscriptionConfig = {
    feature: string;
    surface: string;
    scope: SurfaceScope;
    scopeKey: string;
    mountKey: string;
    socketPath: string;
    resyncFragments: SurfaceWireFragment[];
    decorateRequestsWithin: string[];
};

export type FrontendSurfaceMountedInstance = {
    instanceId: string;
    surface: string;
    scopeKey: string;
    mountKey: string;
    ownerEl: HTMLElement;
    depth: number;
};

export type FrontendSurfaceInstanceReconciliation = {
    added: FrontendSurfaceMountedInstance[];
    removed: FrontendSurfaceMountedInstance[];
    retained: FrontendSurfaceMountedInstance[];
};

export function parseFrontendSurfaceSubscriptionConfig(value: unknown): ParsedFrontendSurfaceSubscriptionConfig | null {
    const config = parseFrontendSurfaceMountConfig(value);
    if (!config?.subscription) return null;

    const resyncFragments = config.subscription.resyncFragments.map(surfaceLiveFragmentToWire);
    if (resyncFragments.length === 0) return null;

    return {
        feature: config.surface,
        surface: config.surface,
        scope: config.subscription.scope as unknown as SurfaceScope,
        scopeKey: config.subscription.scopeKey,
        mountKey: config.mountKey,
        socketPath: "/live-updates",
        resyncFragments,
        decorateRequestsWithin: config.subscription.resyncFragments.map((fragment) => `#${fragment.targetId}`),
    };
}

export function parseFrontendSurfaceMountConfig(value: unknown): FrontendSurfaceMountConfig | null {
    try {
        return parseGeneratedFrontendSurfaceMountConfig(value);
    } catch (_error) {
        return null;
    }
}

function surfaceLiveFragmentToWire(fragment: FrontendSurfaceLiveWireFragment): SurfaceWireFragment {
    return {
        fragmentKey: {
            surface: fragment.fragment.surface,
            kind: fragment.fragment.fragment.kind,
            params: fragment.fragment.fragment.params,
        } as SurfaceWireFragment["fragmentKey"],
        targetId: fragment.targetId,
        url: fragment.url,
        deferUntilBlur: fragment.deferUntilBlur,
        protectionPolicy: fragmentProtectionToWire(fragment.protectionPolicy),
    };
}

function fragmentProtectionToWire(protection: FrontendSurfaceLiveWireFragment["protectionPolicy"]): SurfaceFragmentProtection {
    if (protection.kind !== "focused-field") return { kind: "none" };
    if (typeof protection.activeSelector !== "string") return { kind: "none" };
    if (typeof protection.fieldKeyAttr !== "string") return { kind: "none" };
    if (typeof protection.fieldNameFallback !== "boolean") return { kind: "none" };
    if (protection.containerSelector !== null && protection.containerSelector !== undefined && typeof protection.containerSelector !== "string") return { kind: "none" };
    return {
        kind: "focused-field",
        activeSelector: protection.activeSelector,
        fieldKeyAttr: protection.fieldKeyAttr,
        fieldNameFallback: protection.fieldNameFallback,
        containerSelector: protection.containerSelector ?? null,
    };
}

export function frontendSurfaceInstanceId(config: { surface: string; scopeKey: string; mountKey: string }): string {
    return `${config.surface}:${config.scopeKey}:${config.mountKey}`;
}

export function scanFrontendSurfaceMountInstances(root?: ParentNode): FrontendSurfaceMountedInstance[] {
    const scanRoot = root ?? (typeof document !== "undefined" ? document : null);
    if (!scanRoot) return [];

    const instances: FrontendSurfaceMountedInstance[] = [];
    scanRoot.querySelectorAll('[data-bepis-surface-config]').forEach((ownerEl) => {
        if (!(ownerEl instanceof HTMLElement)) return;
        const rawConfig = ownerEl.getAttribute('data-bepis-surface-config');
        if (!rawConfig) return;

        let parsedJson: unknown;
        try {
            parsedJson = JSON.parse(rawConfig);
        } catch (_error) {
            return;
        }

        const config = parseFrontendSurfaceMountConfig(parsedJson);
        if (!config) return;
        instances.push({
            instanceId: frontendSurfaceInstanceId(config),
            surface: config.surface,
            scopeKey: config.scopeKey,
            mountKey: config.mountKey,
            ownerEl,
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
        if (current.hasAttribute('data-bepis-surface-config')) depth += 1;
        current = current.parentElement;
    }
    return depth;
}

