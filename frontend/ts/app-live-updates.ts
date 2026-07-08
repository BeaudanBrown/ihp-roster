import type { LiveUpdateCommand, LiveUpdateMessage, SurfaceWireFragment } from "./generated/contracts";
import { parseLiveUpdateMessage, pageReadyEvent, liveFragmentsRefreshEvent, interactionSessionEndEvent } from "./generated/contracts";
import { enableHtmxUiRegionEventAdapter } from "./fragments/htmx-adapter";
import { enableUiRegionTransitions } from "./fragments/transitions";
import { resolveLiveFragmentInteractionConflict } from "./interaction/live-conflicts";
import { createActiveInteractionSessionTracker } from "./interaction/session-state";
import {
    reconcileFrontendSurfaceInstances,
    scanFrontendSurfaceMountInstances,
    type FrontendSurfaceMountedInstance,
    parseFrontendSurfaceMountConfig,
    parseFrontendSurfaceSubscriptionConfig,
} from "./live-updates/frontend-surface";
import { createLiveUpdateDiagnostics } from "./live-updates/diagnostics";
import { enableLazySurfaceErrorHandling } from "./live-updates/lazy-surface";
import {
    buildLiveUpdateSubscribeCommand,
    buildSurfaceSubscription,
    buildLiveUpdateUnsubscribeCommand,
    liveUpdateFragmentMergeKey,
    liveUpdateInvalidationIsOwnEcho,
    liveUpdateMessageScopeKey,
    normalizeLiveUpdateVersion,
    resolveMountedFragmentsForInvalidation,
} from "./live-updates/protocol";
import { assertNever } from "./shared/exhaustive";
import type {
    FocusedFieldProtectionPolicy,
    FragmentProtectionAdapter,
    HtmxConfigRequestEvent,
    InFlightFragmentState,
    LiveUpdateDebugDetail,
    LiveUpdateFragmentWithState,
    LiveUpdateInvalidateMessage,
    LiveUpdatePreservedField,
    LiveUpdateSubscribedMessage,
    LiveUpdateSurfaceConfig,
    SurfaceSubscription,
} from "./live-updates/runtime-types";


enableHtmxUiRegionEventAdapter();
enableUiRegionTransitions();
enableLazySurfaceErrorHandling();

// Shared live-update runtime: one websocket per tab with many scope subscriptions.
(function enableLiveUpdates() {
    if (typeof window === 'undefined') return;

    const actorFragmentRefreshEventName = liveFragmentsRefreshEvent;
    const pendingDeferredFragments = new Map<string, LiveUpdateFragmentWithState>();
    const pendingInteractionDeferredFragments = new Map<string, LiveUpdateFragmentWithState>();
    const pendingInteractionTimers = new Map<string, ReturnType<typeof window.setTimeout>>();
    const activeInteractionSessions = createActiveInteractionSessionTracker(document);
    const inFlightFragments = new Map<string, InFlightFragmentState>();
    const activeSubscriptions = new Map<string, SurfaceSubscription>();
    const activeSurfaceInstances = new Map<string, FrontendSurfaceMountedInstance>();
    const scopeVersions = new Map<string, number>();
    let socket: WebSocket | null = null;
    let socketPath: string | null = null;
    let reconnectTimer: ReturnType<typeof window.setTimeout> | null = null;
    let reconnectAttempt = 0;
    let activeClientId: string | null = null;
    const { beginPerfSpan, endPerfSpan, emitDebugEvent } = createLiveUpdateDiagnostics(window, document);

    // Focus protection and deferred refresh state.
    function findPreservedField(root: HTMLElement | null, preserveField: LiveUpdatePreservedField | undefined): HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement | null {
        if (!(root instanceof HTMLElement) || !preserveField) return null;

        const fieldKey = preserveField.fieldKey;
        const fieldKeyAttr = preserveField.fieldKeyAttr || 'data-live-field-key';
        if (fieldKey) {
            const escapedKey = window.CSS && typeof window.CSS.escape === 'function'
                ? window.CSS.escape(fieldKey)
                : fieldKey;
            const keyedField = root.querySelector(`[${fieldKeyAttr}="${escapedKey}"]`);
            if (keyedField instanceof HTMLInputElement || keyedField instanceof HTMLSelectElement || keyedField instanceof HTMLTextAreaElement) {
                return keyedField;
            }
        }

        const name = preserveField.name;
        if (!name) return null;
        const escapedName = window.CSS && typeof window.CSS.escape === 'function'
            ? window.CSS.escape(name)
            : name;
        const namedField = root.querySelector(`[name="${escapedName}"]`);
        if (namedField instanceof HTMLInputElement || namedField instanceof HTMLSelectElement || namedField instanceof HTMLTextAreaElement) {
            return namedField;
        }

        return null;
    }

    // Websocket connection and client identity.
    function makeClientId(): string {
        if (window.crypto && typeof window.crypto.randomUUID === 'function') {
            return window.crypto.randomUUID();
        }

        return `live-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    }

    function ensureClientId(): string {
        if (!activeClientId) {
            activeClientId = makeClientId();
        }

        document.querySelectorAll('[data-bepis-surface-config]').forEach(function (ownerEl) {
            if (ownerEl instanceof HTMLElement) {
                ownerEl.dataset.liveUpdateClientId = activeClientId ?? "";
            }
        });

        return activeClientId;
    }

    function buildWebSocketUrl(path: string): string {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        return `${protocol}//${window.location.host}${path}`;
    }

    function closeSocket(): void {
        if (reconnectTimer) {
            window.clearTimeout(reconnectTimer);
            reconnectTimer = null;
        }

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

    // Fragment refetch, swapping, and per-target queueing.
    async function swapFragmentHtml(targetId: string, html: string): Promise<void> {
        const perfSpan = beginPerfSpan('live_updates.swap_fragment', { targetId });
        const target = document.getElementById(targetId);
        if (!target) {
            endPerfSpan(perfSpan, { outcome: 'target_missing' });
            return;
        }

        const trimmed = (html || '').trim();
        if (!trimmed) {
            target.remove();
            endPerfSpan(perfSpan, { outcome: 'removed_empty_html' });
            return;
        }

        const template = document.createElement('template');
        template.innerHTML = trimmed;

        let nextNode = template.content.firstElementChild;
        if (nextNode && nextNode.tagName === 'TEMPLATE') {
            nextNode = (nextNode as HTMLTemplateElement).content.firstElementChild;
        }

        if (!(nextNode instanceof Element)) {
            endPerfSpan(perfSpan, { outcome: 'no_element' });
            return;
        }

        target.replaceWith(nextNode);

        if (window.htmx && typeof window.htmx.process === 'function') {
            window.htmx.process(document.body);
        }

        if (window.appPageLifecycle && typeof window.appPageLifecycle.dispatchPageReady === 'function') {
            window.appPageLifecycle.dispatchPageReady({
                source: 'live-fragment-refetch',
                target: nextNode,
                isFullPage: false,
            });
        }

        endPerfSpan(perfSpan, {
            outcome: 'swapped',
            nextTagName: nextNode.tagName,
        });
    }

    async function refetchFragment(fragment: LiveUpdateFragmentWithState): Promise<void> {
        const perfSpan = beginPerfSpan('live_updates.refetch_fragment', {
            targetId: fragment && fragment.targetId ? fragment.targetId : null,
            url: fragment && fragment.url ? fragment.url : null,
            deferUntilBlur: Boolean(fragment && fragment.deferUntilBlur),
        });
        const response = await window.fetch(fragment.url, {
            credentials: 'same-origin',
            headers: {
                'HX-Request': 'true',
            },
        });

        if (!response.ok) {
            endPerfSpan(perfSpan, { outcome: 'http_error', status: response.status });
            throw new Error(`Fragment fetch failed with ${response.status}`);
        }

        const html = await response.text();
        await swapFragmentHtml(fragment.targetId, html);
        restoreDeferredState(fragment);
        endPerfSpan(perfSpan, {
            outcome: 'ok',
            status: response.status,
            responseBytes: html.length,
        });
    }

    function queueFragment(fragment: LiveUpdateFragmentWithState): void {
        const existing = inFlightFragments.get(fragment.targetId);
        if (existing) {
            inFlightFragments.set(fragment.targetId, { ...existing, next: fragment });
            emitDebugEvent('fragment_deduped', {
                targetId: fragment.targetId,
                url: fragment.url,
            });
            return;
        }

        inFlightFragments.set(fragment.targetId, { next: null });
        void refetchFragment(fragment)
            .catch(function (error) {
                reportFragmentRefreshError(fragment, error);
                return null;
            })
            .finally(function () {
                const state = inFlightFragments.get(fragment.targetId);
                const next = state && state.next;
                inFlightFragments.delete(fragment.targetId);
                if (next) {
                    queueFragment(next);
                }
            });
    }

    function reportFragmentRefreshError(fragment: LiveUpdateFragmentWithState, error: unknown): void {
        const detail = {
            targetId: fragment && fragment.targetId ? fragment.targetId : null,
            url: fragment && fragment.url ? fragment.url : null,
            error: error instanceof Error ? error.message : String(error),
        };

        if (typeof window.console !== 'undefined' && typeof window.console.error === 'function') {
            window.console.error('Live fragment refresh failed', detail);
        }

        document.dispatchEvent(new CustomEvent('app:live-update-fragment-refresh-failed', {
            detail,
        }));
    }

    function focusedFieldProtection(policy: FocusedFieldProtectionPolicy): FragmentProtectionAdapter {
        const activeSelector = policy && policy.activeSelector ? policy.activeSelector : 'input:focus, select:focus, textarea:focus';
        const fieldKeyAttr = policy && policy.fieldKeyAttr ? policy.fieldKeyAttr : 'data-live-field-key';
        const fieldNameFallback = !policy || policy.fieldNameFallback !== false;
        const containerSelector = policy && policy.containerSelector ? policy.containerSelector : null;

        function findActiveInput(target: HTMLElement): HTMLInputElement | HTMLSelectElement | HTMLTextAreaElement | null {
            if (!(target instanceof HTMLElement)) return null;

            const activeInput = target.querySelector(activeSelector);
            if (activeInput instanceof HTMLInputElement || activeInput instanceof HTMLSelectElement || activeInput instanceof HTMLTextAreaElement) {
                return activeInput;
            }

            return null;
        }

        return {
            matches: function (fragment: LiveUpdateFragmentWithState, target: HTMLElement): boolean {
                return Boolean(
                    fragment &&
                    fragment.deferUntilBlur &&
                    target instanceof HTMLElement
                );
            },
            hasActiveInput: function (target: HTMLElement): boolean {
                return Boolean(findActiveInput(target));
            },
            captureState: function (target: HTMLElement, fragment: LiveUpdateFragmentWithState): LiveUpdateFragmentWithState {
                if (!(target instanceof HTMLElement)) return fragment;

                const activeInput = findActiveInput(target);
                if (!activeInput) return fragment;

                const name = activeInput.getAttribute('name');
                if (!fieldNameFallback && !activeInput.getAttribute(fieldKeyAttr)) return fragment;

                const containerEl = containerSelector ? activeInput.closest(containerSelector) : null;
                return {
                    ...fragment,
                    preserveField: {
                        rowId: containerEl instanceof HTMLElement ? containerEl.id : null,
                        fieldKey: activeInput.getAttribute(fieldKeyAttr) || null,
                        fieldKeyAttr,
                        name,
                        value: activeInput.value,
                    },
                };
            },
            restoreState: function (target: HTMLElement, fragment: LiveUpdateFragmentWithState): void {
                if (!fragment || !fragment.preserveField) return;

                const { rowId, value } = fragment.preserveField;

                const root = rowId ? document.getElementById(rowId) : target;
                const field = findPreservedField(root, fragment.preserveField);
                if (field) {
                    field.value = value ?? "";
                }
            },
        };
    }

    function matchingFragmentProtection(fragment: LiveUpdateFragmentWithState | undefined, _target: HTMLElement): FragmentProtectionAdapter | null {
        if (!fragment) return null;

        switch (fragment.protectionPolicy.kind) {
            case 'focused-field':
                return focusedFieldProtection(fragment.protectionPolicy);
            case 'none':
                return null;
            default:
                return assertNever(fragment.protectionPolicy);
        }
    }

    function hasProtectedActiveInput(target: HTMLElement, fragment: LiveUpdateFragmentWithState | undefined): boolean {
        const adapter = matchingFragmentProtection(fragment, target);
        return Boolean(adapter && adapter.hasActiveInput(target));
    }

    function captureDeferredState(target: HTMLElement, fragment: LiveUpdateFragmentWithState): LiveUpdateFragmentWithState {
        const adapter = matchingFragmentProtection(fragment, target);
        if (!adapter) return fragment;
        return adapter.captureState(target, fragment);
    }

    function restoreDeferredState(fragment: LiveUpdateFragmentWithState): void {
        if (!fragment || !fragment.targetId) return;

        const target = document.getElementById(fragment.targetId);
        if (!(target instanceof HTMLElement)) return;

        const adapter = matchingFragmentProtection(fragment, target);
        if (!adapter) return;
        adapter.restoreState(target, fragment);
    }

    function handleFragmentRefreshRequest(fragment: LiveUpdateFragmentWithState): void {
        if (!fragment || !fragment.targetId || !fragment.url) return;
        const target = document.getElementById(fragment.targetId);
        if (!(target instanceof HTMLElement)) return;
        const resolvedFragment = fragment;

        const interactionConflict = resolveLiveFragmentInteractionConflict(resolvedFragment, target, activeInteractionSessions);
        if (interactionConflict && interactionConflict.action === 'cancel') {
            activeInteractionSessions.requestCancel(interactionConflict.session, 'live-fragment-conflict');
        }
        if (interactionConflict && interactionConflict.action === 'defer') {
            pendingInteractionDeferredFragments.set(resolvedFragment.targetId, resolvedFragment);
            scheduleInteractionDeferredFallbackFlush(resolvedFragment.targetId, interactionConflict.timeoutMs);
            document.dispatchEvent(new CustomEvent('app:live-update-performance', {
                detail: {
                    name: 'live_updates.defer_fragment',
                    duration: 0,
                    targetId: resolvedFragment.targetId,
                    reason: 'interaction_session',
                },
            }));
            return;
        }

        clearInteractionDeferredFragment(resolvedFragment.targetId);

        if (resolvedFragment.deferUntilBlur && hasProtectedActiveInput(target, resolvedFragment)) {
            pendingDeferredFragments.set(resolvedFragment.targetId, captureDeferredState(target, resolvedFragment));
            document.dispatchEvent(new CustomEvent('app:live-update-performance', {
                detail: {
                    name: 'live_updates.defer_fragment',
                    duration: 0,
                    targetId: resolvedFragment.targetId,
                    reason: 'active_input',
                },
            }));
            return;
        }

        pendingDeferredFragments.delete(resolvedFragment.targetId);
        queueFragment(resolvedFragment);
    }

    function clearInteractionDeferredFragment(targetId: string): void {
        const timer = pendingInteractionTimers.get(targetId);
        if (timer) window.clearTimeout(timer);
        pendingInteractionTimers.delete(targetId);
        pendingInteractionDeferredFragments.delete(targetId);
    }

    function scheduleInteractionDeferredFallbackFlush(targetId: string, timeoutMs: number | null): void {
        const existing = pendingInteractionTimers.get(targetId);
        if (existing) window.clearTimeout(existing);
        if (timeoutMs === null || timeoutMs <= 0) return;

        // Deferred interaction fragments are normally flushed immediately from
        // the interaction-session-end handler. This timer is only a watchdog so
        // a lost terminal event cannot hide passive live updates indefinitely.
        pendingInteractionTimers.set(targetId, window.setTimeout(function () {
            const fragment = pendingInteractionDeferredFragments.get(targetId);
            const target = document.getElementById(targetId);
            if (fragment && target instanceof HTMLElement) {
                const conflict = resolveLiveFragmentInteractionConflict(fragment, target, activeInteractionSessions);
                if (conflict) activeInteractionSessions.requestCancel(conflict.session, 'live-fragment-defer-fallback-timeout');
            }
            flushInteractionDeferredFragment(targetId, 'interaction_fallback_timeout');
        }, timeoutMs));
    }

    function flushInteractionDeferredFragment(targetId: string, reason: string): void {
        const fragment = pendingInteractionDeferredFragments.get(targetId);
        if (!fragment) return;

        clearInteractionDeferredFragment(targetId);
        emitDebugEvent('deferred_fragment_flush', {
            targetId,
            reason,
        });
        queueFragment(fragment);
    }

    function flushInteractionDeferredFragmentsWithoutActiveSessions(): void {
        Array.from(pendingInteractionDeferredFragments.entries()).forEach(function ([targetId, fragment]) {
            const target = document.getElementById(targetId);
            if (!(target instanceof HTMLElement)) {
                flushInteractionDeferredFragment(targetId, 'target_missing');
                return;
            }
            const conflict = resolveLiveFragmentInteractionConflict(fragment, target, activeInteractionSessions);
            if (!conflict) flushInteractionDeferredFragment(targetId, 'interaction_session_end');
        });
    }

    function flushDeferredFragment(targetId: string): void {
        const fragment = pendingDeferredFragments.get(targetId);
        if (!fragment) return;

        pendingDeferredFragments.delete(targetId);
        emitDebugEvent('deferred_fragment_flush', {
            targetId,
            reason: 'inactive_input',
        });
        queueFragment(fragment);
    }

    function flushDeferredFragmentsWithoutActiveInputs(): void {
        Array.from(pendingDeferredFragments.entries()).forEach(function ([targetId]) {
            const target = document.getElementById(targetId);
            const fragment = pendingDeferredFragments.get(targetId);
            if (target instanceof HTMLElement && fragment && resolveLiveFragmentInteractionConflict(fragment, target, activeInteractionSessions)) return;
            if (!target || !hasProtectedActiveInput(target, fragment)) {
                flushDeferredFragment(targetId);
            }
        });
    }

    // Subscription lifecycle and reconnect handling.
    function scheduleReconnect(): void {
        if (reconnectTimer) return;

        reconnectAttempt += 1;
        const cappedAttempt = Math.min(reconnectAttempt, 6);
        const baseDelay = 250 * (2 ** cappedAttempt);
        const delayMs = Math.floor(Math.random() * Math.min(baseDelay, 10000));
        emitDebugEvent('reconnect_scheduled', {
            attempt: reconnectAttempt,
            delayMs,
        });

        reconnectTimer = window.setTimeout(function () {
            reconnectTimer = null;
            syncConnection();
        }, delayMs);
    }

    function sendCommand(command: LiveUpdateCommand): void {
        if (!socket || socket.readyState !== window.WebSocket.OPEN) return;
        socket.send(JSON.stringify(command));
    }

    function getScopeVersion(scopeKey: string): number | null {
        const version = scopeVersions.get(scopeKey);
        return Number.isInteger(version) ? version ?? null : null;
    }

    function setScopeVersion(scopeKey: string, version: unknown): void {
        if (!Number.isInteger(version) || (version as number) < 0) return;
        scopeVersions.set(scopeKey, version as number);
    }

    function clearScopeVersion(scopeKey: string): void {
        scopeVersions.delete(scopeKey);
    }

    function normalizeVersion(value: unknown): number | null {
        return normalizeLiveUpdateVersion(value);
    }

    function messageScopeKey(message: unknown): string | null {
        return liveUpdateMessageScopeKey(message as { scopeKey?: unknown } | null | undefined);
    }

    function wireSubscription(subscription: SurfaceSubscription) {
        return buildSurfaceSubscription(subscription.scope, subscription.scopeKey, subscription.resyncFragments);
    }

    function subscribeScope(subscription: SurfaceSubscription): void {
        const lastSeenVersion = getScopeVersion(subscription.scopeKey);
        sendCommand(buildLiveUpdateSubscribeCommand(wireSubscription(subscription), ensureClientId(), lastSeenVersion));
    }

    function unsubscribeScope(subscription: SurfaceSubscription): void {
        sendCommand(buildLiveUpdateUnsubscribeCommand(wireSubscription(subscription)));
    }

    // FrontendSurface discovery and merging.
    function readFrontendSurface(ownerEl: Element): SurfaceSubscription | null {
        if (!(ownerEl instanceof HTMLElement)) return null;

        const rawConfig = ownerEl.getAttribute('data-bepis-surface-config');
        if (!rawConfig) return null;

        let config = null;
        try {
            config = JSON.parse(rawConfig);
        } catch (error) {
            reportSurfaceConfigError(ownerEl, error);
            return null;
        }

        const parsedConfig = parseFrontendSurfaceSubscriptionConfig(config);
        if (parsedConfig === null) {
            if (parseFrontendSurfaceMountConfig(config) !== null) return null;
            reportSurfaceConfigError(ownerEl, new Error('Invalid FrontendSurface config'));
            return null;
        }

        return {
            feature: parsedConfig.feature,
            scope: parsedConfig.scope,
            scopeKey: parsedConfig.scopeKey,
            path: parsedConfig.socketPath,
            resyncFragments: parsedConfig.resyncFragments,
            decorateRequestsWithin: parsedConfig.decorateRequestsWithin,
            ownerEls: [ownerEl],
            resync: function (subscription: SurfaceSubscription): void {
                subscription.resyncFragments.forEach(handleFragmentRefreshRequest);
            },
        };
    }

    function reportSurfaceConfigError(ownerEl: HTMLElement, error: unknown): void {
        const detail = {
            id: ownerEl && ownerEl.id ? ownerEl.id : null,
            feature: null,
            error: error instanceof Error ? error.message : String(error),
        };

        if (typeof window.console !== 'undefined' && typeof window.console.error === 'function') {
            window.console.error('Invalid live-update surface config', detail);
        }

        document.dispatchEvent(new CustomEvent('app:live-update-surface-config-failed', {
            detail,
        }));
    }

    function collectDeclarativeSubscriptions(): SurfaceSubscription[] {
        const subscriptions: SurfaceSubscription[] = [];
        document.querySelectorAll('[data-bepis-surface-config]').forEach(function (ownerEl) {
            if (!(ownerEl instanceof HTMLElement)) return;
            const scopeInfo = readFrontendSurface(ownerEl);
            if (!scopeInfo || !scopeInfo.scopeKey) return;
            subscriptions.push({ ...scopeInfo, ownerEl });
        });
        return subscriptions;
    }

    function shouldDecorateDeclarativeRequest(event: HtmxConfigRequestEvent): boolean {
        const sourceEl = event.detail && event.detail.elt;
        if (!(sourceEl instanceof HTMLElement)) return false;

        const ownerEl = sourceEl.closest('[data-bepis-surface-config]');
        if (!(ownerEl instanceof HTMLElement)) return false;

        const scopeInfo = readFrontendSurface(ownerEl);
        if (!scopeInfo) return false;
        if (scopeInfo.decorateRequestsWithin.length === 0) return true;

        return scopeInfo.decorateRequestsWithin.some(function (selector) {
            return Boolean(selector && sourceEl.closest(selector));
        });
    }

    function fragmentMergeKey(fragment: LiveUpdateFragmentWithState): string | null {
        return liveUpdateFragmentMergeKey(fragment);
    }

    function mergeFragments(existingFragments: LiveUpdateFragmentWithState[], nextFragments: LiveUpdateFragmentWithState[]): LiveUpdateFragmentWithState[] {
        const merged: LiveUpdateFragmentWithState[] = [];
        const seen = new Set<string>();

        existingFragments.concat(nextFragments).forEach(function (fragment) {
            const mergeKey = fragmentMergeKey(fragment);
            if (!mergeKey || seen.has(mergeKey)) {
                if (mergeKey) {
                    emitDebugEvent('fragment_deduped', {
                        targetId: fragment && fragment.targetId ? fragment.targetId : null,
                        mergeKey,
                    });
                }
                return;
            }

            seen.add(mergeKey);
            merged.push(fragment);
        });

        return merged;
    }

    function mergeStringLists(existingValues: string[], nextValues: string[]): string[] {
        return Array.from(new Set(existingValues.concat(nextValues).filter(Boolean)));
    }

    function mergeSubscription(existing: SurfaceSubscription | undefined, next: SurfaceSubscription): SurfaceSubscription {
        if (!existing) return next;

        return {
            ...existing,
            feature: existing.feature || next.feature,
            resyncFragments: mergeFragments(existing.resyncFragments, next.resyncFragments),
            decorateRequestsWithin: mergeStringLists(existing.decorateRequestsWithin, next.decorateRequestsWithin),
            ownerEls: (existing.ownerEls || []).concat(next.ownerEl ? [next.ownerEl] : next.ownerEls || []),
        };
    }

    function desiredSubscriptions(): Map<string, SurfaceSubscription> {
        const desired = new Map<string, SurfaceSubscription>();

        collectDeclarativeSubscriptions().forEach(function (subscription) {
            desired.set(subscription.scopeKey, mergeSubscription(desired.get(subscription.scopeKey), subscription));
        });

        return desired;
    }

    // Server message handling.
    function handleSubscribedMessage(message: LiveUpdateSubscribedMessage): void {
        if (!message) return;

        const scopeKey = messageScopeKey(message);
        if (!scopeKey) return;
        const subscription = activeSubscriptions.get(scopeKey);
        if (!subscription) return;

        const currentVersion = normalizeVersion(message.currentVersion);
        if (currentVersion !== null) {
            setScopeVersion(scopeKey, currentVersion);
        }

        if (message.resync && typeof subscription.resync === 'function') {
            subscription.resync(subscription);
        }
    }

    function handleInvalidateMessage(message: LiveUpdateInvalidateMessage): void {
        if (!message || !Array.isArray(message.fragments)) return;
        if (liveUpdateInvalidationIsOwnEcho(message.sourceClientId, activeClientId)) return;
        const perfSpan = beginPerfSpan('live_updates.handle_invalidate', {
            fragmentCount: message.fragments.length,
            scopeKind: message.scope && typeof (message.scope as unknown as { surface?: unknown }).surface === 'string' ? (message.scope as unknown as { surface: string }).surface : null,
            version: normalizeVersion(message.version),
        });

        const scopeKey = messageScopeKey(message);
        if (!scopeKey) {
            endPerfSpan(perfSpan, { outcome: 'invalid_scope' });
            return;
        }
        const subscription = activeSubscriptions.get(scopeKey);
        if (!subscription) {
            endPerfSpan(perfSpan, { outcome: 'unsubscribed_scope', scopeKey });
            return;
        }

        const nextVersion = normalizeVersion(message.version);
        const previousVersion = getScopeVersion(scopeKey);

        if (nextVersion !== null) {
            if (previousVersion !== null && nextVersion > previousVersion + 1) {
                setScopeVersion(scopeKey, nextVersion);
                if (typeof subscription.resync === 'function') {
                    subscription.resync(subscription);
                }
                emitDebugEvent('resync_version_gap', {
                    scopeKey,
                    previousVersion,
                    nextVersion,
                });
                endPerfSpan(perfSpan, {
                    outcome: 'resync_gap',
                    scopeKey,
                    previousVersion,
                    nextVersion,
                });
                return;
            }

            if (previousVersion !== null && nextVersion <= previousVersion) {
                endPerfSpan(perfSpan, {
                    outcome: 'stale',
                    scopeKey,
                    previousVersion,
                    nextVersion,
                });
                return;
            }

            setScopeVersion(scopeKey, nextVersion);
        }

        if (message.fragments.length === 0 && typeof subscription.resync === 'function') {
            subscription.resync(subscription);
            endPerfSpan(perfSpan, { outcome: 'resync_empty_fragments', scopeKey });
            return;
        }

        resolveMountedFragmentsForInvalidation([subscription], message.fragments, scopeKey)
            .forEach(handleFragmentRefreshRequest);
        endPerfSpan(perfSpan, { outcome: 'queued_fragments', scopeKey });
    }

    function openSocket(path: string): void {
        const connectPerfSpan = beginPerfSpan('live_updates.open_socket', { path });
        socket = new window.WebSocket(buildWebSocketUrl(path));
        socketPath = path;

        socket.onopen = function () {
            reconnectAttempt = 0;
            activeSubscriptions.forEach(function (subscription) {
                subscribeScope(subscription);
                emitDebugEvent('subscription_added', {
                    scopeKey: subscription.scopeKey,
                    fragmentCount: subscription.resyncFragments.length,
                    ownerCount: (subscription.ownerEls || []).length,
                });
            });
            endPerfSpan(connectPerfSpan, {
                outcome: 'open',
                subscriptionCount: activeSubscriptions.size,
            });
        };

        socket.onmessage = function (event) {
            let parsedMessage: unknown = null;
            try {
                parsedMessage = JSON.parse(event.data);
            } catch (_error) {
                return;
            }

            let message: LiveUpdateMessage;
            try {
                message = parseLiveUpdateMessage(parsedMessage);
            } catch (_error) {
                return;
            }

            if (message.type === 'subscribed') {
                handleSubscribedMessage(message);
                return;
            }

            if (message.type === 'invalidate') {
                handleInvalidateMessage(message);
            }
        };

        socket.onclose = function () {
            endPerfSpan(connectPerfSpan, { outcome: 'closed_before_open' });
            socket = null;
            if (activeSubscriptions.size > 0) {
                scheduleReconnect();
            }
        };

        socket.onerror = function () {
            endPerfSpan(connectPerfSpan, { outcome: 'error' });
            if (socket) {
                socket.close();
            }
        };
    }

    function reconcileSurfaceMountInstances(): void {
        const reconciliation = reconcileFrontendSurfaceInstances(activeSurfaceInstances, scanFrontendSurfaceMountInstances(document));

        reconciliation.removed.forEach(function (instance) {
            activeSurfaceInstances.delete(instance.instanceId);
            emitDebugEvent('surface_disposed', {
                instanceId: instance.instanceId,
                surface: instance.surface,
                scopeKey: instance.scopeKey,
                mountKey: instance.mountKey,
                depth: instance.depth,
            });
        });

        reconciliation.retained.forEach(function (instance) {
            activeSurfaceInstances.set(instance.instanceId, instance);
        });

        reconciliation.added.forEach(function (instance) {
            activeSurfaceInstances.set(instance.instanceId, instance);
            emitDebugEvent('surface_initialized', {
                instanceId: instance.instanceId,
                surface: instance.surface,
                scopeKey: instance.scopeKey,
                mountKey: instance.mountKey,
                depth: instance.depth,
            });
        });
    }

    function syncConnection() {
        ensureClientId();
        reconcileSurfaceMountInstances();

        const desired = desiredSubscriptions();
        const firstDesired = desired.values().next().value as SurfaceSubscription | undefined;
        const nextPath = firstDesired?.path ?? null;

        if (desired.size === 0 || !nextPath) {
            activeSubscriptions.clear();
            activeSurfaceInstances.clear();
            closeSocket();
            return;
        }

        const removed: SurfaceSubscription[] = [];
        activeSubscriptions.forEach(function (subscription, scopeKey) {
            if (!desired.has(scopeKey)) {
                removed.push(subscription);
            }
        });

        const added: SurfaceSubscription[] = [];
        desired.forEach(function (subscription, scopeKey) {
            if (!activeSubscriptions.has(scopeKey)) {
                added.push(subscription);
            }
        });

        removed.forEach(function (subscription) {
            unsubscribeScope(subscription);
            activeSubscriptions.delete(subscription.scopeKey);
            clearScopeVersion(subscription.scopeKey);
            emitDebugEvent('subscription_removed', {
                scopeKey: subscription.scopeKey,
            });
        });

        desired.forEach(function (subscription, scopeKey) {
            activeSubscriptions.set(scopeKey, subscription);
        });

        if (!socket || socket.readyState > window.WebSocket.OPEN || socketPath !== nextPath) {
            closeSocket();
            openSocket(nextPath);
            return;
        }

        if (socket.readyState === window.WebSocket.OPEN) {
            added.forEach(function (subscription) {
                subscribeScope(subscription);
                emitDebugEvent('subscription_added', {
                    scopeKey: subscription.scopeKey,
                    fragmentCount: subscription.resyncFragments.length,
                    ownerCount: (subscription.ownerEls || []).length,
                });
            });
        }
    }

    // DOM event bindings.
    document.addEventListener('htmx:configRequest', function (event) {
        const htmxEvent = event as HtmxConfigRequestEvent;
        if (!shouldDecorateDeclarativeRequest(htmxEvent)) return;
        const clientId = ensureClientId();
        if (htmxEvent.detail?.headers !== undefined) {
            htmxEvent.detail.headers['X-Live-Update-Client-Id'] = clientId;
        }
    });

    function handleActorFragmentRefreshEvent(event: Event): void {
        const detail = event instanceof CustomEvent ? event.detail : null;
        const fragments = Array.isArray(detail && detail.fragments) ? detail.fragments : [];
        const scopeKey = detail && typeof detail.scopeKey === 'string' ? detail.scopeKey : null;
        resolveMountedFragmentsForInvalidation(activeSubscriptions.values(), fragments, scopeKey)
            .forEach(handleFragmentRefreshRequest);
    }

    document.addEventListener(actorFragmentRefreshEventName, handleActorFragmentRefreshEvent);

    document.addEventListener(interactionSessionEndEvent, function () {
        flushInteractionDeferredFragmentsWithoutActiveSessions();
        flushDeferredFragmentsWithoutActiveInputs();
    });

    document.addEventListener('htmx:afterSwap', function () {
        flushInteractionDeferredFragmentsWithoutActiveSessions();
        window.setTimeout(syncConnection, 0);
    });

    document.addEventListener('htmx:afterSettle', function () {
        window.setTimeout(syncConnection, 0);
    });

    document.addEventListener('htmx:responseError', function () {
        flushInteractionDeferredFragmentsWithoutActiveSessions();
    });

    document.addEventListener('focusout', function () {
        window.setTimeout(function () {
            flushDeferredFragmentsWithoutActiveInputs();
        }, 0);
    });

    document.addEventListener('input', function () {
        window.setTimeout(function () {
            flushDeferredFragmentsWithoutActiveInputs();
        }, 0);
    });

    document.addEventListener('change', function () {
        window.setTimeout(function () {
            flushDeferredFragmentsWithoutActiveInputs();
        }, 0);
    });

    document.addEventListener(pageReadyEvent, syncConnection);
})();
