import { parseLiveUpdateMessage, type LiveUpdateCommand, type LiveUpdateMessage } from "../generated/contracts";
import type { createLiveUpdateDiagnostics } from "./diagnostics";
import type { LiveUpdateVersionStore } from "./invalidation";
import { buildLiveUpdateSubscribeCommand, buildLiveUpdateUnsubscribeCommand } from "./protocol";
import type { SurfaceSubscription } from "./runtime-types";
import { subscriptionsEquivalent, wireSurfaceSubscription } from "./subscription";

type LiveUpdateDiagnostics = ReturnType<typeof createLiveUpdateDiagnostics>;

export type LiveUpdateConnection = {
    ensureClientId(): string;
    activeClientId(): string | null;
    sync(desired: Map<string, SurfaceSubscription>): void;
    close(): void;
};

export function createLiveUpdateConnection(options: {
    targetWindow: Window & typeof globalThis;
    activeSubscriptions: Map<string, SurfaceSubscription>;
    versions: LiveUpdateVersionStore;
    handleMessage: (message: LiveUpdateMessage) => void;
    requestSync: () => void;
    diagnostics: LiveUpdateDiagnostics;
}): LiveUpdateConnection {
    const { targetWindow, activeSubscriptions, versions, handleMessage, requestSync, diagnostics } = options;
    let socket: WebSocket | null = null;
    let socketPath: string | null = null;
    let reconnectTimer: ReturnType<typeof targetWindow.setTimeout> | null = null;
    let reconnectAttempt = 0;
    let clientId: string | null = null;

    function ensureClientId(): string {
        if (!clientId) {
            clientId = targetWindow.crypto?.randomUUID?.()
                ?? `live-${Date.now()}-${Math.random().toString(16).slice(2)}`;
        }
        return clientId;
    }

    function buildWebSocketUrl(path: string): string {
        const protocol = targetWindow.location.protocol === "https:" ? "wss:" : "ws:";
        return `${protocol}//${targetWindow.location.host}${path}`;
    }

    function sendCommand(command: LiveUpdateCommand): void {
        if (!socket || socket.readyState !== targetWindow.WebSocket.OPEN) return;
        socket.send(JSON.stringify(command));
    }

    function subscribe(subscription: SurfaceSubscription): void {
        sendCommand(buildLiveUpdateSubscribeCommand(
            wireSurfaceSubscription(subscription),
            ensureClientId(),
            versions.get(subscription.scopeKey),
        ));
    }

    function unsubscribe(subscription: SurfaceSubscription): void {
        sendCommand(buildLiveUpdateUnsubscribeCommand(wireSurfaceSubscription(subscription)));
    }

    function scheduleReconnect(): void {
        if (reconnectTimer) return;
        reconnectAttempt += 1;
        const cappedAttempt = Math.min(reconnectAttempt, 6);
        const delayMs = Math.floor(Math.random() * Math.min(250 * (2 ** cappedAttempt), 10000));
        diagnostics.emitDebugEvent("reconnect_scheduled", { attempt: reconnectAttempt, delayMs });
        reconnectTimer = targetWindow.setTimeout(() => {
            reconnectTimer = null;
            requestSync();
        }, delayMs);
    }

    function close(): void {
        if (reconnectTimer) targetWindow.clearTimeout(reconnectTimer);
        reconnectTimer = null;
        if (socket) {
            socket.onopen = null;
            socket.onmessage = null;
            socket.onclose = null;
            socket.onerror = null;
            socket.close();
            socket = null;
        }
        socketPath = null;
    }

    function open(path: string): void {
        const perfSpan = diagnostics.beginPerfSpan("live_updates.open_socket", { path });
        socket = new targetWindow.WebSocket(buildWebSocketUrl(path));
        socketPath = path;

        socket.onopen = () => {
            reconnectAttempt = 0;
            activeSubscriptions.forEach((subscription) => {
                subscribe(subscription);
                diagnostics.emitDebugEvent("subscription_added", {
                    scopeKey: subscription.scopeKey,
                    fragmentCount: subscription.resyncFragments.length,
                    ownerCount: subscription.ownerEls.length,
                });
            });
            diagnostics.endPerfSpan(perfSpan, { outcome: "open", subscriptionCount: activeSubscriptions.size });
        };

        socket.onmessage = (event) => {
            try {
                handleMessage(parseLiveUpdateMessage(JSON.parse(event.data)));
            } catch {
                return;
            }
        };

        socket.onclose = () => {
            diagnostics.endPerfSpan(perfSpan, { outcome: "closed_before_open" });
            socket = null;
            if (activeSubscriptions.size > 0) scheduleReconnect();
        };

        socket.onerror = () => {
            diagnostics.endPerfSpan(perfSpan, { outcome: "error" });
            socket?.close();
        };
    }

    function sync(desired: Map<string, SurfaceSubscription>): void {
        ensureClientId();
        const nextPath = desired.values().next().value?.path ?? null;
        if (desired.size === 0 || !nextPath) {
            activeSubscriptions.forEach((subscription) => versions.clear(subscription.scopeKey));
            activeSubscriptions.clear();
            close();
            return;
        }

        const removed: SurfaceSubscription[] = [];
        activeSubscriptions.forEach((subscription, scopeKey) => {
            if (!desired.has(scopeKey)) removed.push(subscription);
        });

        const added: SurfaceSubscription[] = [];
        const changed: Array<{ previous: SurfaceSubscription; next: SurfaceSubscription }> = [];
        desired.forEach((subscription, scopeKey) => {
            const active = activeSubscriptions.get(scopeKey);
            if (!active) added.push(subscription);
            else if (!subscriptionsEquivalent(active, subscription)) changed.push({ previous: active, next: subscription });
        });

        removed.forEach((subscription) => {
            unsubscribe(subscription);
            activeSubscriptions.delete(subscription.scopeKey);
            versions.clear(subscription.scopeKey);
            diagnostics.emitDebugEvent("subscription_removed", { scopeKey: subscription.scopeKey });
        });
        changed.forEach(({ previous, next }) => {
            unsubscribe(previous);
            versions.clear(previous.scopeKey);
            diagnostics.emitDebugEvent("subscription_changed", {
                scopeKey: previous.scopeKey,
                previousFragmentCount: previous.resyncFragments.length,
                nextFragmentCount: next.resyncFragments.length,
            });
        });
        desired.forEach((subscription, scopeKey) => activeSubscriptions.set(scopeKey, subscription));

        if (!socket || socket.readyState > targetWindow.WebSocket.OPEN || socketPath !== nextPath) {
            close();
            open(nextPath);
            return;
        }
        if (socket.readyState === targetWindow.WebSocket.OPEN) {
            changed.forEach(({ next }) => subscribe(next));
            added.forEach((subscription) => {
                subscribe(subscription);
                diagnostics.emitDebugEvent("subscription_added", {
                    scopeKey: subscription.scopeKey,
                    fragmentCount: subscription.resyncFragments.length,
                    ownerCount: subscription.ownerEls.length,
                });
            });
        }
    }

    return { ensureClientId, activeClientId: () => clientId, sync, close };
}
