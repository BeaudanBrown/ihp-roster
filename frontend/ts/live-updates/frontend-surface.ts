import {
    FrontendSurfaceRegistry,
    isFrontendSurfaceLiveSubscription,
    isFrontendSurfaceName,
    surfaceFragmentKeysEqual,
    type FrontendSurfaceMountConfig,
    type FrontendSurfaceMountedFragmentConfig,
    type FrontendSurfaceName,
    type FrontendSurfaceSurfaceFragmentProtection,
    type SurfaceFragmentKey,
    type SurfaceScope,
} from "../generated/contracts";

export type { FrontendSurfaceMountConfig } from "../generated/contracts";

export type ParsedFrontendSurfaceSubscriptionConfig = {
    feature: string;
    surface: string;
    scope: SurfaceScope;
    scopeKey: string;
    mountKey: string;
    socketPath: string;
    resyncFragments: LiveUpdateMountedFragment[];
    decorateRequestsWithin: string[];
};

export type LiveUpdateMountedFragment = {
    fragmentKey: SurfaceFragmentKey;
    targetId: string;
    url: string;
    deferUntilBlur: boolean;
    protectionPolicy: FrontendSurfaceSurfaceFragmentProtection;
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

    const resyncFragments = config.fragments
        .map((fragment) => mountedFragmentForSurface(config.surface, fragment))
        .filter((fragment) => config.subscription?.resyncFragments.some((key) => surfaceFragmentKeysEqual(key, fragment.fragmentKey)) ?? false);
    if (resyncFragments.length === 0) return null;

    return {
        feature: config.surface,
        surface: config.surface,
        scope: config.subscription.scope as unknown as SurfaceScope,
        scopeKey: config.subscription.scopeKey,
        mountKey: config.mountKey,
        socketPath: "/live-updates",
        resyncFragments,
        decorateRequestsWithin: resyncFragments.map((fragment) => `#${fragment.targetId}`),
    };
}

export function parseFrontendSurfaceMountConfig(value: unknown): FrontendSurfaceMountConfig | null {
    if (!isFrontendSurfaceMountConfig(value)) return null;
    return {
        ...value,
        subscription: value.subscription ?? null,
        fragments: value.fragments.map((fragment) => ({
            ...fragment,
            protection: fragment.protection ?? null,
            loadPolicy: fragment.loadPolicy ?? null,
        })),
    };
}

function isFrontendSurfaceMountConfig(value: unknown): value is FrontendSurfaceMountConfig {
    if (!isRecord(value)) return false;
    if (!isFrontendSurfaceName(value.surface)) return false;
    if (typeof value.scopeKey !== "string" || typeof value.mountKey !== "string") return false;
    if (!Array.isArray(value.fragments) || !value.fragments.every((fragment) => isFrontendSurfaceMountedFragmentConfigForSurface(value.surface as FrontendSurfaceName, fragment))) return false;
    if (value.subscription !== null && value.subscription !== undefined && !isFrontendSurfaceLiveSubscription(value.subscription)) return false;
    return true;
}

function isFrontendSurfaceMountedFragmentConfigForSurface(surface: FrontendSurfaceName, value: unknown): value is FrontendSurfaceMountedFragmentConfig {
    if (!isRecord(value)) return false;
    if (!isRecord(value.key)) return false;
    if (typeof value.key.kind !== "string" || !surfaceHasFragment(surface, value.key.kind)) return false;
    if (typeof value.targetId !== "string" || typeof value.url !== "string") return false;
    if (value.protection !== null && value.protection !== undefined && !isRecord(value.protection)) return false;
    if (value.loadPolicy !== null && value.loadPolicy !== undefined && typeof value.loadPolicy !== "string") return false;
    return true;
}

function surfaceHasFragment(surface: FrontendSurfaceName, fragment: string): boolean {
    return (FrontendSurfaceRegistry[surface].fragments as readonly string[]).includes(fragment);
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}

function mountedFragmentForSurface(surface: FrontendSurfaceName, fragment: FrontendSurfaceMountedFragmentConfig): LiveUpdateMountedFragment {
    return {
        fragmentKey: {
            surface,
            kind: fragment.key.kind,
            params: fragment.key.params,
        } as SurfaceFragmentKey,
        targetId: fragment.targetId,
        url: fragment.url,
        deferUntilBlur: isRecord(fragment.protection) && fragment.protection.kind === "focused-field",
        protectionPolicy: fragmentProtectionForLocalMount(fragment.protection),
    };
}

function fragmentProtectionForLocalMount(protection: unknown): FrontendSurfaceSurfaceFragmentProtection {
    if (!isRecord(protection) || protection.kind !== "focused-field") return { kind: "none" };
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

