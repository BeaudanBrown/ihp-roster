import type { FrontendSurfaceMountedFragmentConfig, LiveUpdateCommand, SurfaceFragmentKey, SurfaceScope, SurfaceSubscription } from "../generated/contracts";
import { encodeLiveUpdateCommand, surfaceFragmentKeyIdentity } from "../generated/contracts";

type MessageWithScopeKey = { scopeKey?: unknown };
export type MountedFragmentSubscription = {
    scopeKey: string;
    resyncFragments: FrontendSurfaceMountedFragmentConfig[];
};

export function liveUpdateMessageScopeKey(message: MessageWithScopeKey | null | undefined): string | null {
    if (message && typeof message.scopeKey === "string" && message.scopeKey.length > 0) {
        return message.scopeKey;
    }

    return null;
}

export function normalizeLiveUpdateVersion(value: unknown): number | null {
    return typeof value === "number" && Number.isInteger(value) && value >= 0 ? value : null;
}

export function serverPayloadFromHtmxTriggeredEvent(detail: unknown, eventTarget: EventTarget | null): Record<string, unknown> | null {
    if (!isRecord(detail)) return null;
    if ("elt" in detail && detail.elt !== eventTarget) return null;

    const serverPayload = Object.assign({}, detail);
    Reflect.deleteProperty(serverPayload, "elt");
    return serverPayload;
}

function isRecord(value: unknown): value is Record<string, unknown> {
    return value !== null && typeof value === "object" && !Array.isArray(value);
}

export function buildSurfaceSubscription(scope: SurfaceScope, scopeKey: string, fragments: SurfaceFragmentKey[]): SurfaceSubscription {
    return {
        scope,
        scopeKey,
        fragments,
    };
}

export function buildLiveUpdateSubscribeCommand(subscription: SurfaceSubscription, clientId: string, lastSeenVersion: number | null): LiveUpdateCommand {
    return encodeLiveUpdateCommand({
        type: "subscribe",
        subscription,
        clientId,
        lastSeenVersion,
    });
}

export function buildLiveUpdateUnsubscribeCommand(subscription: SurfaceSubscription): LiveUpdateCommand {
    return encodeLiveUpdateCommand({
        type: "unsubscribe",
        subscription,
    });
}

export function liveUpdateFragmentMergeKey(fragment: Pick<FrontendSurfaceMountedFragmentConfig, "fragmentKey" | "targetId"> | null | undefined): string | null {
    if (!fragment || !fragment.targetId) return null;
    return `${surfaceFragmentKeyIdentity(fragment.fragmentKey)}:${fragment.targetId}`;
}

export function liveUpdateInvalidationIsOwnEcho(sourceClientId: string | null | undefined, activeClientId: string | null | undefined): boolean {
    return Boolean(sourceClientId && activeClientId && sourceClientId === activeClientId);
}

export function resolveMountedFragmentsForInvalidation(
    subscriptions: Iterable<MountedFragmentSubscription>,
    fragments: readonly SurfaceFragmentKey[],
    scopeKey: string | null = null,
): FrontendSurfaceMountedFragmentConfig[] {
    if (scopeKey === null || scopeKey.length === 0) return [];

    const mountedSubscriptions = Array.from(subscriptions);
    const resolved: FrontendSurfaceMountedFragmentConfig[] = [];
    const seen = new Set<string>();

    fragments.forEach((fragmentKey) => {
        const semanticKey = surfaceFragmentKeyIdentity(fragmentKey);
        const matches: FrontendSurfaceMountedFragmentConfig[] = [];

        for (const subscription of mountedSubscriptions) {
            if (subscription.scopeKey !== scopeKey) continue;
            subscription.resyncFragments.forEach((mountedFragment) => {
                if (surfaceFragmentKeyIdentity(mountedFragment.fragmentKey) === semanticKey) {
                    matches.push(mountedFragment);
                }
            });
        }

        matches.forEach((candidate) => {
            const mergeKey = liveUpdateFragmentMergeKey(candidate);
            if (mergeKey && seen.has(mergeKey)) return;
            if (mergeKey) seen.add(mergeKey);
            resolved.push(candidate);
        });
    });

    return resolved;
}

export function liveUpdateInvalidationShouldResync(previousVersion: number | null, nextVersion: number | null, fragmentCount: number): "gap" | "empty" | null {
    if (nextVersion !== null && previousVersion !== null && nextVersion > previousVersion + 1) return "gap";
    if (fragmentCount === 0) return "empty";
    return null;
}
