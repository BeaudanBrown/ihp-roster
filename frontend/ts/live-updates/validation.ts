import type { LiveUpdateScope, LiveUpdateWireFragment } from "../generated/contracts";

export type ValidLiveUpdateSurfaceConfig = {
    feature: string | null;
    scope: LiveUpdateScope;
    scopeKey: string;
    socketPath: string;
    resyncFragments: LiveUpdateWireFragment[];
    decorateRequestsWithin: string[];
};

export function isRecord(value: unknown): value is Record<string, unknown> {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

function optionalString(value: unknown): string | null {
    return typeof value === "string" && value.length > 0 ? value : null;
}

function stringList(value: unknown): string[] {
    return Array.isArray(value) ? value.filter((item): item is string => typeof item === "string" && item.length > 0) : [];
}

function fragmentList(value: unknown): LiveUpdateWireFragment[] {
    return Array.isArray(value) ? value.filter(isLiveUpdateWireFragment) : [];
}

function isLiveUpdateScope(value: unknown): value is LiveUpdateScope {
    return isRecord(value) && typeof value.kind === "string" && value.kind.length > 0;
}

function isLiveUpdateWireFragment(value: unknown): value is LiveUpdateWireFragment {
    return isRecord(value)
        && typeof value.targetId === "string"
        && value.targetId.length > 0
        && typeof value.url === "string"
        && value.url.length > 0
        && isRecord(value.fragmentKey)
        && typeof value.fragmentKey.kind === "string";
}

export function parseLiveUpdateSurfaceConfig(value: unknown): ValidLiveUpdateSurfaceConfig | null {
    if (!isRecord(value)) return null;
    if (!isLiveUpdateScope(value.scope)) return null;

    const scopeKey = optionalString(value.scopeKey);
    if (scopeKey === null) return null;

    return {
        feature: optionalString(value.feature),
        scope: value.scope,
        scopeKey,
        socketPath: optionalString(value.socketPath) ?? "/live-updates",
        resyncFragments: fragmentList(value.resyncFragments),
        decorateRequestsWithin: stringList(value.decorateRequestsWithin),
    };
}
