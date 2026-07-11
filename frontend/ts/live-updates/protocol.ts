import type { LiveUpdateCommand, SurfaceScope, SurfaceSubscription, SurfaceWireFragment } from "../generated/contracts";
import { encodeLiveUpdateCommand } from "../generated/contracts";

type MessageWithScopeKey = { scopeKey?: unknown };
export type MountedFragmentSubscription = {
    scopeKey: string;
    resyncFragments: SurfaceWireFragment[];
};

export function liveUpdateMessageScopeKey(message: MessageWithScopeKey | null | undefined): string | null {
    if (message && typeof message.scopeKey === "string" && message.scopeKey.length > 0) {
        return message.scopeKey;
    }

    return null;
}

export function normalizeLiveUpdateVersion(value: unknown): number | null {
    return Number.isInteger(value) && (value as number) >= 0 ? value as number : null;
}

export function buildSurfaceSubscription(scope: SurfaceScope, scopeKey: string, mountedFragments: SurfaceWireFragment[]): SurfaceSubscription {
    return {
        scope,
        scopeKey,
        mountedFragments,
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

export function liveUpdateFragmentMergeKey(fragment: Pick<SurfaceWireFragment, "fragmentKey" | "targetId"> | null | undefined): string | null {
    if (!fragment || !fragment.targetId) return null;
    const fragmentKey = fragment.fragmentKey ? JSON.stringify(fragment.fragmentKey) : "";
    return `${fragmentKey}:${fragment.targetId}`;
}

function liveUpdateFragmentSemanticKey(fragment: Pick<SurfaceWireFragment, "fragmentKey"> | null | undefined): string | null {
    const fragmentKey = fragment?.fragmentKey;
    if (!fragmentKey) return null;
    return JSON.stringify([fragmentKey.surface, fragmentKey.kind, fragmentKey.params]);
}

export function liveUpdateInvalidationIsOwnEcho(sourceClientId: string | null | undefined, activeClientId: string | null | undefined): boolean {
    return Boolean(sourceClientId && activeClientId && sourceClientId === activeClientId);
}

export function resolveMountedFragmentsForInvalidation(
    subscriptions: Iterable<MountedFragmentSubscription>,
    fragments: SurfaceWireFragment[],
    scopeKey: string | null = null,
): SurfaceWireFragment[] {
    if (scopeKey === null || scopeKey.length === 0) return [];

    const mountedSubscriptions = Array.from(subscriptions);
    const resolved: SurfaceWireFragment[] = [];
    const seen = new Set<string>();

    fragments.forEach((fragment) => {
        const semanticKey = liveUpdateFragmentSemanticKey(fragment);
        const matches: SurfaceWireFragment[] = [];

        for (const subscription of mountedSubscriptions) {
            if (subscription.scopeKey !== scopeKey) continue;
            subscription.resyncFragments.forEach((mountedFragment) => {
                if (semanticKey !== null && liveUpdateFragmentSemanticKey(mountedFragment) === semanticKey) {
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
