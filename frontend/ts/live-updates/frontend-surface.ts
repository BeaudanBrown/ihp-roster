import type { LiveFragmentProtection, LiveUpdateScope, LiveUpdateWireFragment } from "../generated/contracts";

export type FrontendSurfaceMountedFragmentConfig = {
    key: { kind: string; params: unknown };
    targetId: string;
    url: string;
    protection?: {
        kind?: string;
        activeSelector?: unknown;
        fieldKeyAttr?: unknown;
        fieldNameFallback?: unknown;
        containerSelector?: unknown;
    } | null;
    loadPolicy?: string | null;
};

type FrontendSurfaceLiveWireFragmentConfig = {
    fragment: { surface: string; fragment: { kind: string; params: unknown } };
    targetId: string;
    url: string;
    deferUntilBlur: boolean;
    protectionPolicy: {
        kind?: string;
        activeSelector?: unknown;
        fieldKeyAttr?: unknown;
        fieldNameFallback?: unknown;
        containerSelector?: unknown;
    };
};

type FrontendSurfaceLiveSubscriptionConfig = {
    scope: { surface: string; scope: unknown };
    scopeKey: string;
    resyncFragments: FrontendSurfaceLiveWireFragmentConfig[];
};

export type FrontendSurfaceMountConfig = {
    surface: string;
    scopeKey: string;
    mountKey: string;
    mountState: unknown;
    fragments: FrontendSurfaceMountedFragmentConfig[];
    subscription: FrontendSurfaceLiveSubscriptionConfig | null;
};

export type ParsedFrontendSurfaceSubscriptionConfig = {
    feature: string;
    surface: string;
    scope: LiveUpdateScope;
    scopeKey: string;
    mountKey: string;
    socketPath: string;
    resyncFragments: LiveUpdateWireFragment[];
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
        scope: config.subscription.scope as unknown as LiveUpdateScope,
        scopeKey: config.subscription.scopeKey,
        mountKey: config.mountKey,
        socketPath: "/live-updates",
        resyncFragments,
        decorateRequestsWithin: config.subscription.resyncFragments.map((fragment) => `#${fragment.targetId}`),
    };
}

export function parseFrontendSurfaceMountConfig(value: unknown): FrontendSurfaceMountConfig | null {
    if (!isRecord(value)) return null;
    if (typeof value.surface !== "string") return null;
    if (typeof value.scopeKey !== "string") return null;
    if (typeof value.mountKey !== "string") return null;
    if (!Array.isArray(value.fragments)) return null;

    const fragments = value.fragments.map(parseMountedFragmentConfig);
    if (fragments.some((fragment) => fragment === null)) return null;
    const subscription = value.subscription === null || value.subscription === undefined
        ? null
        : parseLiveSubscriptionConfig(value.subscription);
    if (value.subscription !== null && value.subscription !== undefined && !subscription) return null;

    return {
        surface: value.surface,
        scopeKey: value.scopeKey,
        mountKey: value.mountKey,
        mountState: value.mountState,
        fragments: fragments as FrontendSurfaceMountedFragmentConfig[],
        subscription,
    };
}

function parseMountedFragmentConfig(value: unknown): FrontendSurfaceMountedFragmentConfig | null {
    if (!isRecord(value)) return null;
    if (!isRecord(value.key)) return null;
    if (typeof value.key.kind !== "string") return null;
    if (typeof value.targetId !== "string") return null;
    if (typeof value.url !== "string") return null;

    return {
        key: { kind: value.key.kind, params: value.key.params },
        targetId: value.targetId,
        url: value.url,
        protection: isRecord(value.protection)
            ? {
                kind: typeof value.protection.kind === "string" ? value.protection.kind : undefined,
                activeSelector: value.protection.activeSelector,
                fieldKeyAttr: value.protection.fieldKeyAttr,
                fieldNameFallback: value.protection.fieldNameFallback,
                containerSelector: value.protection.containerSelector,
            }
            : null,
        loadPolicy: typeof value.loadPolicy === "string" ? value.loadPolicy : null,
    };
}

function parseLiveSubscriptionConfig(value: unknown): FrontendSurfaceLiveSubscriptionConfig | null {
    if (!isRecord(value)) return null;
    if (!isRecord(value.scope)) return null;
    if (typeof value.scope.surface !== "string") return null;
    if (typeof value.scopeKey !== "string") return null;
    if (!Array.isArray(value.resyncFragments)) return null;
    const fragments = value.resyncFragments.map(parseLiveWireFragmentConfig);
    if (fragments.some((fragment) => fragment === null)) return null;
    return {
        scope: { surface: value.scope.surface, scope: value.scope.scope },
        scopeKey: value.scopeKey,
        resyncFragments: fragments as FrontendSurfaceLiveWireFragmentConfig[],
    };
}

function parseLiveWireFragmentConfig(value: unknown): FrontendSurfaceLiveWireFragmentConfig | null {
    if (!isRecord(value)) return null;
    if (!isRecord(value.fragment)) return null;
    if (!isRecord(value.fragment.fragment)) return null;
    if (typeof value.fragment.surface !== "string") return null;
    if (typeof value.fragment.fragment.kind !== "string") return null;
    if (typeof value.targetId !== "string") return null;
    if (typeof value.url !== "string") return null;
    if (typeof value.deferUntilBlur !== "boolean") return null;
    if (!isRecord(value.protectionPolicy)) return null;
    return {
        fragment: {
            surface: value.fragment.surface,
            fragment: { kind: value.fragment.fragment.kind, params: value.fragment.fragment.params },
        },
        targetId: value.targetId,
        url: value.url,
        deferUntilBlur: value.deferUntilBlur,
        protectionPolicy: value.protectionPolicy,
    };
}

function surfaceLiveFragmentToWire(fragment: FrontendSurfaceLiveWireFragmentConfig): LiveUpdateWireFragment {
    return {
        fragmentKey: {
            surface: fragment.fragment.surface,
            kind: fragment.fragment.fragment.kind,
            params: fragment.fragment.fragment.params,
        } as LiveUpdateWireFragment["fragmentKey"],
        targetId: fragment.targetId,
        url: fragment.url,
        deferUntilBlur: fragment.deferUntilBlur,
        protectionPolicy: fragmentProtectionToWire(fragment.protectionPolicy),
    };
}

function fragmentProtectionToWire(protection: FrontendSurfaceLiveWireFragmentConfig["protectionPolicy"]): LiveFragmentProtection {
    if (protection.kind !== "focused-field") return { kind: "none" };
    if (typeof protection.activeSelector !== "string") return { kind: "none" };
    if (typeof protection.fieldKeyAttr !== "string") return { kind: "none" };
    if (typeof protection.fieldNameFallback !== "boolean") return { kind: "none" };
    if (protection.containerSelector !== null && protection.containerSelector !== undefined && typeof protection.containerSelector !== "string") return { kind: "none" };
    return {
        kind: "focused_field",
        activeSelector: protection.activeSelector,
        fieldKeyAttr: protection.fieldKeyAttr,
        fieldNameFallback: protection.fieldNameFallback,
        containerSelector: protection.containerSelector ?? null,
    };
}

export function frontendSurfaceInstanceId(config: Pick<FrontendSurfaceMountConfig, "surface" | "scopeKey" | "mountKey">): string {
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

function isInteger(value: unknown): value is number {
    return typeof value === "number" && Number.isInteger(value);
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return typeof value === "object" && value !== null && !Array.isArray(value);
}
