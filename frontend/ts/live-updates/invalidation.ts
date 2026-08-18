import { parseLiveFragmentsRefreshEventDetail, type LiveUpdateMessage } from "../generated/contracts";
import type { createLiveUpdateDiagnostics } from "./diagnostics";
import {
    liveUpdateInvalidationIsOwnEcho,
    liveUpdateMessageScopeKey,
    normalizeLiveUpdateVersion,
    resolveMountedFragmentsForInvalidation,
    serverPayloadFromHtmxTriggeredEvent,
} from "./protocol";
import type { LiveFragmentRefresher } from "./refresh";
import { assertNever } from "../shared/exhaustive";
import type { SurfaceSubscription } from "./runtime-types";

type LiveUpdateDiagnostics = ReturnType<typeof createLiveUpdateDiagnostics>;

export type LiveUpdateVersionStore = {
    get(scopeKey: string): number | null;
    set(scopeKey: string, version: unknown): void;
    clear(scopeKey: string): void;
};

export type LiveUpdateInvalidationRuntime = {
    versions: LiveUpdateVersionStore;
    handleMessage(message: LiveUpdateMessage): void;
    handleActorEvent(event: Event): void;
};

export function createLiveUpdateInvalidationRuntime(options: {
    activeSubscriptions: Map<string, SurfaceSubscription>;
    activeClientId: () => string | null;
    refresher: LiveFragmentRefresher;
    diagnostics: LiveUpdateDiagnostics;
}): LiveUpdateInvalidationRuntime {
    const { activeSubscriptions, activeClientId, refresher, diagnostics } = options;
    const scopeVersions = new Map<string, number>();

    const versions: LiveUpdateVersionStore = {
        get(scopeKey) {
            const version = scopeVersions.get(scopeKey);
            return Number.isInteger(version) ? version ?? null : null;
        },
        set(scopeKey, version) {
            const normalized = normalizeLiveUpdateVersion(version);
            if (normalized !== null) scopeVersions.set(scopeKey, normalized);
        },
        clear(scopeKey) {
            scopeVersions.delete(scopeKey);
        },
    };

    function handleSubscribedMessage(message: Extract<LiveUpdateMessage, { type: "subscribed" }>): void {
        const scopeKey = liveUpdateMessageScopeKey(message);
        if (!scopeKey) return;
        const subscription = activeSubscriptions.get(scopeKey);
        if (!subscription) return;

        versions.set(scopeKey, message.currentVersion);
        if (message.resync) subscription.resync(subscription);
        diagnostics.emitDebugEvent("subscription_acknowledged", { scopeKey, resync: message.resync });
    }

    function handleInvalidateMessage(message: Extract<LiveUpdateMessage, { type: "invalidate" }>): void {
        if (liveUpdateInvalidationIsOwnEcho(message.sourceClientId, activeClientId())) return;
        const nextVersion = normalizeLiveUpdateVersion(message.version);
        const perfSpan = diagnostics.beginPerfSpan("live_updates.handle_invalidate", {
            fragmentCount: message.fragments.length,
            scopeKind: message.scope.surface,
            version: nextVersion,
        });
        const scopeKey = liveUpdateMessageScopeKey(message);
        if (!scopeKey) {
            diagnostics.endPerfSpan(perfSpan, { outcome: "invalid_scope" });
            return;
        }
        const subscription = activeSubscriptions.get(scopeKey);
        if (!subscription) {
            diagnostics.endPerfSpan(perfSpan, { outcome: "unsubscribed_scope", scopeKey });
            return;
        }

        const previousVersion = versions.get(scopeKey);
        if (nextVersion !== null) {
            if (previousVersion !== null && nextVersion <= previousVersion) {
                diagnostics.endPerfSpan(perfSpan, { outcome: "stale", scopeKey, previousVersion, nextVersion });
                return;
            }
            versions.set(scopeKey, nextVersion);
        }

        if (message.fragments.length === 0) {
            subscription.resync(subscription);
            diagnostics.endPerfSpan(perfSpan, { outcome: "resync_empty_fragments", scopeKey });
            return;
        }

        resolveMountedFragmentsForInvalidation([subscription], message.fragments, scopeKey).forEach(refresher.request);
        diagnostics.endPerfSpan(perfSpan, { outcome: "queued_fragments", scopeKey });
    }

    function handleMessage(message: LiveUpdateMessage): void {
        switch (message.type) {
            case "subscribed":
                handleSubscribedMessage(message);
                return;
            case "invalidate":
                handleInvalidateMessage(message);
                return;
            case "error":
                return;
            default:
                return assertNever(message);
        }
    }

    function handleActorEvent(event: Event): void {
        if (!(event instanceof CustomEvent)) return;
        const actorDetail = serverPayloadFromHtmxTriggeredEvent(event.detail, event.target);
        if (!actorDetail) return;

        try {
            const detail = parseLiveFragmentsRefreshEventDetail(actorDetail);
            resolveMountedFragmentsForInvalidation(activeSubscriptions.values(), detail.fragments, detail.scopeKey)
                .forEach(refresher.request);
        } catch {
            return;
        }
    }

    return { versions, handleMessage, handleActorEvent };
}
