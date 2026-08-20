import { dialogDismissedEvent, interactionSessionEndEvent, liveFragmentsRefreshEvent, pageReadyEvent } from "../generated/contracts";
import { createActiveInteractionSessionTracker } from "../interaction/session-state";
import { createLiveUpdateConnection, type LiveUpdateConnection } from "./connection";
import { createLiveUpdateDiagnostics } from "./diagnostics";
import { createLiveUpdateInvalidationRuntime } from "./invalidation";
import {
    reconcileFrontendSurfaceInstances,
    scanFrontendSurfaceMountInstances,
    type FrontendSurfaceMountedInstance,
} from "./mount";
import { createLiveFragmentRefresher } from "./refresh";
import type { SurfaceSubscription } from "./runtime-types";
import { collectDesiredSurfaceSubscriptions, createSurfaceConfigErrorReporter } from "./subscription";

// Browser entrypoint orchestration for the focused live-update owners.
export function enableLiveUpdateRuntime(): void {
    if (typeof window === "undefined") return;

    const activeSubscriptions = new Map<string, SurfaceSubscription>();
    const activeSurfaceInstances = new Map<string, FrontendSurfaceMountedInstance>();
    const diagnostics = createLiveUpdateDiagnostics(window, document);
    const activeInteractionSessions = createActiveInteractionSessionTracker(document);
    const refresher = createLiveFragmentRefresher({
        targetWindow: window,
        targetDocument: document,
        diagnostics,
        activeInteractionSessions,
    });
    let connection: LiveUpdateConnection | null = null;
    const invalidation = createLiveUpdateInvalidationRuntime({
        activeSubscriptions,
        refresher,
        diagnostics,
    });
    const reportSurfaceConfigError = createSurfaceConfigErrorReporter(document);

    function reconcileMounts(): void {
        const current = scanFrontendSurfaceMountInstances(document, reportSurfaceConfigError);
        const reconciliation = reconcileFrontendSurfaceInstances(activeSurfaceInstances, current);
        reconciliation.removed.forEach((instance) => {
            activeSurfaceInstances.delete(instance.instanceId);
            diagnostics.emitDebugEvent("surface_disposed", instanceDebugDetail(instance));
        });
        reconciliation.retained.forEach((instance) => activeSurfaceInstances.set(instance.instanceId, instance));
        reconciliation.added.forEach((instance) => {
            activeSurfaceInstances.set(instance.instanceId, instance);
            diagnostics.emitDebugEvent("surface_initialized", instanceDebugDetail(instance));
        });
    }

    function syncRuntime(): void {
        reconcileMounts();
        const desired = collectDesiredSurfaceSubscriptions(document, refresher.request, reportSurfaceConfigError);
        if (desired.size === 0) activeSurfaceInstances.clear();
        connection?.sync(desired);
    }

    connection = createLiveUpdateConnection({
        targetWindow: window,
        activeSubscriptions,
        versions: invalidation.versions,
        handleMessage: invalidation.handleMessage,
        requestSync: syncRuntime,
        diagnostics,
    });

    document.addEventListener(liveFragmentsRefreshEvent, invalidation.handleActorEvent);
    document.addEventListener(interactionSessionEndEvent, () => {
        refresher.flushInteractionDeferredFragmentsWithoutActiveSessions();
        refresher.flushFocusedFragmentsWithoutActiveInputs();
    });
    document.addEventListener("htmx:afterSwap", () => {
        refresher.flushInteractionDeferredFragmentsWithoutActiveSessions();
        window.setTimeout(syncRuntime, 0);
    });
    document.addEventListener("htmx:afterSettle", () => window.setTimeout(syncRuntime, 0));
    document.addEventListener("htmx:responseError", refresher.flushInteractionDeferredFragmentsWithoutActiveSessions);
    document.addEventListener(dialogDismissedEvent, () => window.setTimeout(syncRuntime, 0));

    const scheduleFocusedFlush = () => window.setTimeout(refresher.flushFocusedFragmentsWithoutActiveInputs, 0);
    document.addEventListener("focusout", scheduleFocusedFlush);
    document.addEventListener("input", scheduleFocusedFlush);
    document.addEventListener("change", scheduleFocusedFlush);
    document.addEventListener(pageReadyEvent, syncRuntime);
}

function instanceDebugDetail(instance: FrontendSurfaceMountedInstance): Record<string, unknown> {
    return {
        instanceId: instance.instanceId,
        surface: instance.surface,
        scopeKey: instance.scopeKey,
        mountKey: instance.mountKey,
        depth: instance.depth,
    };
}
