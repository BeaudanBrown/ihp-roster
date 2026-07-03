import type { LiveUpdateCommand, LiveUpdateScope, LiveUpdateSubscription, LiveUpdateWireFragment } from "../generated/contracts";
import { encodeLiveUpdateCommand } from "../generated/contracts";

type MessageWithScopeKey = { scopeKey?: unknown };

export function liveUpdateMessageScopeKey(message: MessageWithScopeKey | null | undefined): string | null {
    if (message && typeof message.scopeKey === "string" && message.scopeKey.length > 0) {
        return message.scopeKey;
    }

    return null;
}

export function normalizeLiveUpdateVersion(value: unknown): number | null {
    return Number.isInteger(value) && (value as number) >= 0 ? value as number : null;
}

export function buildLiveUpdateSubscription(scope: LiveUpdateScope, scopeKey: string, mountedFragments: LiveUpdateWireFragment[]): LiveUpdateSubscription {
    return {
        scope,
        scopeKey,
        mountedFragments,
    };
}

export function buildLiveUpdateSubscribeCommand(subscription: LiveUpdateSubscription, clientId: string, lastSeenVersion: number | null): LiveUpdateCommand {
    return encodeLiveUpdateCommand({
        type: "subscribe",
        subscription,
        clientId,
        lastSeenVersion,
    });
}

export function buildLiveUpdateUnsubscribeCommand(subscription: LiveUpdateSubscription): LiveUpdateCommand {
    return encodeLiveUpdateCommand({
        type: "unsubscribe",
        subscription,
    });
}

export function liveUpdateFragmentMergeKey(fragment: Pick<LiveUpdateWireFragment, "fragmentKey" | "targetId"> | null | undefined): string | null {
    if (!fragment || !fragment.targetId) return null;
    const fragmentKey = fragment.fragmentKey ? JSON.stringify(fragment.fragmentKey) : "";
    return `${fragmentKey}:${fragment.targetId}`;
}

export function liveUpdateInvalidationShouldResync(previousVersion: number | null, nextVersion: number | null, fragmentCount: number): "gap" | "empty" | null {
    if (nextVersion !== null && previousVersion !== null && nextVersion > previousVersion + 1) return "gap";
    if (fragmentCount === 0) return "empty";
    return null;
}
