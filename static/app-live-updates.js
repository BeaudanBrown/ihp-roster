// Shared live-update runtime: one websocket per tab with many scope subscriptions.
(function enableLiveUpdates() {
    if (typeof window === 'undefined') return;

    const actorFragmentRefreshEventName = 'app-roster-fragments-refresh';
    const pendingDeferredFragments = new Map();
    const inFlightFragments = new Map();
    const activeSubscriptions = new Map();
    const scopeVersions = new Map();
    let socket = null;
    let socketPath = null;
    let reconnectTimer = null;
    let activeClientId = null;
    let nextPerfToken = 0;

    function supportsPerformanceTimeline() {
        return Boolean(window.performance && typeof window.performance.mark === 'function' && typeof window.performance.measure === 'function');
    }

    function perfToken(prefix) {
        nextPerfToken += 1;
        return `${prefix}-${Date.now()}-${nextPerfToken}`;
    }

    function beginPerfSpan(name, detail) {
        if (!supportsPerformanceTimeline()) return null;

        const token = perfToken(name);
        const startMark = `${token}:start`;
        window.performance.mark(startMark, detail ? { detail } : undefined);
        return {
            token,
            name,
            startMark,
            detail: detail || null,
        };
    }

    function endPerfSpan(span, extraDetail) {
        if (!span || !supportsPerformanceTimeline()) return null;

        const endMark = `${span.token}:end`;
        const detail = extraDetail ? { ...span.detail, ...extraDetail } : span.detail;
        window.performance.mark(endMark, detail ? { detail } : undefined);

        let duration = null;
        try {
            window.performance.measure(span.name, {
                start: span.startMark,
                end: endMark,
                detail: detail || undefined,
            });
            const entries = window.performance.getEntriesByName(span.name, 'measure');
            const entry = entries[entries.length - 1];
            duration = entry ? entry.duration : null;
        } catch (_error) {
            duration = null;
        }

        window.performance.clearMarks(span.startMark);
        window.performance.clearMarks(endMark);

        document.dispatchEvent(new CustomEvent('app:live-update-performance', {
            detail: {
                name: span.name,
                duration,
                ...detail,
            },
        }));

        return duration;
    }

    function findPreservedField(root, preserveField) {
        if (!(root instanceof HTMLElement) || !preserveField) return null;

        const fieldKey = preserveField.fieldKey;
        const fieldKeyAttr = preserveField.fieldKeyAttr || 'data-roster-field-key';
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

    function makeClientId() {
        if (window.crypto && typeof window.crypto.randomUUID === 'function') {
            return window.crypto.randomUUID();
        }

        return `live-${Date.now()}-${Math.random().toString(16).slice(2)}`;
    }

    function ensureClientId() {
        if (!activeClientId) {
            activeClientId = makeClientId();
        }

        document.querySelectorAll('[data-live-update-surface]').forEach(function (ownerEl) {
            if (ownerEl instanceof HTMLElement) {
                ownerEl.dataset.liveUpdateClientId = activeClientId;
            }
        });

        return activeClientId;
    }

    function buildWebSocketUrl(path) {
        const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
        return `${protocol}//${window.location.host}${path}`;
    }

    function closeSocket() {
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

    async function swapFragmentHtml(targetId, html) {
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
            nextNode = nextNode.content.firstElementChild;
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

    async function refetchFragment(fragment) {
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

    function queueFragment(fragment) {
        const existing = inFlightFragments.get(fragment.targetId);
        if (existing) {
            inFlightFragments.set(fragment.targetId, { ...existing, next: fragment });
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

    function reportFragmentRefreshError(fragment, error) {
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

    function focusedFieldProtection(policy) {
        const activeSelector = policy && policy.activeSelector ? policy.activeSelector : '.slot-note-input:focus';
        const fieldKeyAttr = policy && policy.fieldKeyAttr ? policy.fieldKeyAttr : 'data-roster-field-key';
        const fieldNameFallback = !policy || policy.fieldNameFallback !== false;
        const containerSelector = policy && policy.containerSelector ? policy.containerSelector : 'tr[data-roster-row]';

        function findActiveInput(target) {
            if (!(target instanceof HTMLElement)) return null;

            const activeInput = target.querySelector(activeSelector);
            if (activeInput instanceof HTMLInputElement || activeInput instanceof HTMLSelectElement || activeInput instanceof HTMLTextAreaElement) {
                return activeInput;
            }

            return null;
        }

        return {
            matches: function (fragment, target) {
                return Boolean(
                    fragment &&
                    fragment.deferUntilBlur &&
                    target instanceof HTMLElement
                );
            },
            hasActiveInput: function (target) {
                return Boolean(findActiveInput(target));
            },
            captureState: function (target, fragment) {
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
            restoreState: function (target, fragment) {
                if (!fragment || !fragment.preserveField) return;

                const { rowId, value } = fragment.preserveField;

                const root = rowId ? document.getElementById(rowId) : target;
                const field = findPreservedField(root, fragment.preserveField);
                if (field) {
                    field.value = value;
                }
            },
        };
    }

    const protectionPolicies = {
        focused_field: focusedFieldProtection,
    };

    function matchingFragmentProtection(fragment, target) {
        if (fragment && fragment.protectionPolicy && fragment.protectionPolicy.kind) {
            const factory = protectionPolicies[fragment.protectionPolicy.kind];
            return typeof factory === 'function' ? factory(fragment.protectionPolicy) : null;
        }

        return null;
    }

    function hasProtectedActiveInput(target, fragment) {
        const adapter = matchingFragmentProtection(fragment, target);
        return Boolean(adapter && adapter.hasActiveInput(target));
    }

    function captureDeferredState(target, fragment) {
        const adapter = matchingFragmentProtection(fragment, target);
        if (!adapter) return fragment;
        return adapter.captureState(target, fragment);
    }

    function restoreDeferredState(fragment) {
        if (!fragment || !fragment.targetId) return;

        const target = document.getElementById(fragment.targetId);
        if (!(target instanceof HTMLElement)) return;

        const adapter = matchingFragmentProtection(fragment, target);
        if (!adapter) return;
        adapter.restoreState(target, fragment);
    }

    function handleFragmentRefreshRequest(fragment) {
        if (!fragment || !fragment.targetId || !fragment.url) return;
        const target = document.getElementById(fragment.targetId);
        if (!(target instanceof HTMLElement)) return;
        const resolvedFragment = { ...fragment, url: target.dataset.liveUpdateUrl || fragment.url };

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

    function flushDeferredFragment(targetId) {
        const fragment = pendingDeferredFragments.get(targetId);
        if (!fragment) return;

        pendingDeferredFragments.delete(targetId);
        queueFragment(fragment);
    }

    function flushDeferredFragmentsWithoutActiveInputs() {
        Array.from(pendingDeferredFragments.entries()).forEach(function ([targetId]) {
            const target = document.getElementById(targetId);
            const fragment = pendingDeferredFragments.get(targetId);
            if (!target || !hasProtectedActiveInput(target, fragment)) {
                flushDeferredFragment(targetId);
            }
        });
    }

    function scheduleReconnect() {
        if (reconnectTimer) return;

        reconnectTimer = window.setTimeout(function () {
            reconnectTimer = null;
            syncConnection();
        }, 1000);
    }

    function sendCommand(command) {
        if (!socket || socket.readyState !== window.WebSocket.OPEN) return;
        socket.send(JSON.stringify(command));
    }

    function getScopeVersion(scopeKey) {
        const version = scopeVersions.get(scopeKey);
        return Number.isInteger(version) ? version : null;
    }

    function setScopeVersion(scopeKey, version) {
        if (!Number.isInteger(version) || version < 0) return;
        scopeVersions.set(scopeKey, version);
    }

    function clearScopeVersion(scopeKey) {
        scopeVersions.delete(scopeKey);
    }

    function normalizeVersion(value) {
        return Number.isInteger(value) && value >= 0 ? value : null;
    }

    function buildScopeKey(scope) {
        if (!scope || !scope.kind) return null;

        switch (scope.kind) {
            case 'support_platform':
                return scope.kind;
            case 'roster_week':
                if (!scope.venueId) return null;
                if (!scope.rosterGroupId || !Number.isInteger(scope.weekOffset)) return null;
                return `${scope.kind}:${scope.venueId}:${scope.rosterGroupId}:${scope.weekOffset}`;
            case 'roster_group_config':
            case 'admin_slot_names':
                if (!scope.venueId) return null;
                if (!scope.rosterGroupId) return null;
                return `${scope.kind}:${scope.venueId}:${scope.rosterGroupId}`;
            case 'timesheet_week':
                if (!scope.venueId) return null;
                if (!Number.isInteger(scope.weekOffset)) return null;
                return `${scope.kind}:${scope.venueId}:${scope.weekOffset}`;
            case 'leave_requests':
            case 'admin_invites':
            case 'admin_shift_types':
            case 'admin_roster_groups':
            case 'admin_xero':
                if (!scope.venueId) return null;
                return `${scope.kind}:${scope.venueId}`;
            default:
                return null;
        }
    }

    function messageScopeKey(message) {
        if (message && typeof message.scopeKey === 'string' && message.scopeKey.length > 0) {
            return message.scopeKey;
        }

        return buildScopeKey(message ? message.scope : null);
    }

    function subscribeScope(subscription) {
        const lastSeenVersion = getScopeVersion(subscription.scopeKey);
        sendCommand({
            type: 'subscribe',
            scope: subscription.scope,
            clientId: ensureClientId(),
            lastSeenVersion: lastSeenVersion === null ? undefined : lastSeenVersion,
        });
    }

    function unsubscribeScope(subscription) {
        sendCommand({
            type: 'unsubscribe',
            scope: subscription.scope,
        });
    }

    function readDeclarativeSurface(ownerEl) {
        if (!(ownerEl instanceof HTMLElement)) return null;

        const rawConfig = ownerEl.getAttribute('data-live-update-surface');
        if (!rawConfig) return null;

        let config = null;
        try {
            config = JSON.parse(rawConfig);
        } catch (error) {
            reportSurfaceConfigError(ownerEl, error);
            return null;
        }

        if (!config || !config.scope) return null;

        const scopeKey = config.scopeKey || buildScopeKey(config.scope);
        if (!scopeKey) {
            reportSurfaceConfigError(ownerEl, new Error('Invalid live-update surface scope'));
            return null;
        }

        return {
            feature: config.feature || null,
            scope: config.scope,
            scopeKey,
            path: config.socketPath || '/live-updates',
            resyncFragments: Array.isArray(config.resyncFragments) ? config.resyncFragments : [],
            decorateRequestsWithin: Array.isArray(config.decorateRequestsWithin) ? config.decorateRequestsWithin : [],
            resync: function (subscription) {
                subscription.resyncFragments.forEach(handleFragmentRefreshRequest);
            },
        };
    }

    function reportSurfaceConfigError(ownerEl, error) {
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

    function declarativeSurfaceAdapter() {
        return {
            collectSubscriptions: function () {
                const subscriptions = [];
                document.querySelectorAll('[data-live-update-surface]').forEach(function (ownerEl) {
                    const scopeInfo = readDeclarativeSurface(ownerEl);
                    if (!scopeInfo || !scopeInfo.scopeKey) return;
                    subscriptions.push({ ...scopeInfo, ownerEl });
                });
                return subscriptions;
            },
            shouldDecorateRequest: function (event) {
                const sourceEl = event.detail && event.detail.elt;
                if (!(sourceEl instanceof HTMLElement)) return false;

                const ownerEl = sourceEl.closest('[data-live-update-surface]');
                if (!(ownerEl instanceof HTMLElement)) return false;

                const scopeInfo = readDeclarativeSurface(ownerEl);
                if (!scopeInfo) return false;
                if (scopeInfo.decorateRequestsWithin.length === 0) return true;

                return scopeInfo.decorateRequestsWithin.some(function (selector) {
                    return Boolean(selector && sourceEl.closest(selector));
                });
            },
        };
    }

    const adapters = [declarativeSurfaceAdapter()];

    function desiredSubscriptions() {
        const desired = new Map();

        adapters.forEach(function (adapter) {
            adapter.collectSubscriptions().forEach(function (subscription) {
                desired.set(subscription.scopeKey, subscription);
            });
        });

        return desired;
    }

    function handleSubscribedMessage(message) {
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

    function handleInvalidateMessage(message) {
        if (!message || !Array.isArray(message.fragments)) return;
        if (message.sourceClientId && message.sourceClientId === activeClientId) return;
        const perfSpan = beginPerfSpan('live_updates.handle_invalidate', {
            fragmentCount: message.fragments.length,
            scopeKind: message.scope && message.scope.kind ? message.scope.kind : null,
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

        message.fragments.forEach(handleFragmentRefreshRequest);
        endPerfSpan(perfSpan, { outcome: 'queued_fragments', scopeKey });
    }

    function openSocket(path) {
        const connectPerfSpan = beginPerfSpan('live_updates.open_socket', { path });
        socket = new window.WebSocket(buildWebSocketUrl(path));
        socketPath = path;

        socket.onopen = function () {
            activeSubscriptions.forEach(subscribeScope);
            endPerfSpan(connectPerfSpan, {
                outcome: 'open',
                subscriptionCount: activeSubscriptions.size,
            });
        };

        socket.onmessage = function (event) {
            let message = null;
            try {
                message = JSON.parse(event.data);
            } catch (_error) {
                return;
            }

            if (!message || typeof message.type !== 'string') return;

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

    function syncConnection() {
        ensureClientId();

        const desired = desiredSubscriptions();
        const nextPath = desired.size > 0 ? desired.values().next().value.path : null;

        if (desired.size === 0 || !nextPath) {
            activeSubscriptions.clear();
            closeSocket();
            return;
        }

        const removed = [];
        activeSubscriptions.forEach(function (subscription, scopeKey) {
            if (!desired.has(scopeKey)) {
                removed.push(subscription);
            }
        });

        const added = [];
        desired.forEach(function (subscription, scopeKey) {
            if (!activeSubscriptions.has(scopeKey)) {
                added.push(subscription);
            }
        });

        removed.forEach(function (subscription) {
            unsubscribeScope(subscription);
            activeSubscriptions.delete(subscription.scopeKey);
            clearScopeVersion(subscription.scopeKey);
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
            added.forEach(subscribeScope);
        }
    }

    document.addEventListener('htmx:configRequest', function (event) {
        const shouldDecorate = adapters.some(function (adapter) {
            return typeof adapter.shouldDecorateRequest === 'function' && adapter.shouldDecorateRequest(event);
        });
        if (!shouldDecorate) return;
        const clientId = ensureClientId();
        event.detail.headers['X-Live-Update-Client-Id'] = clientId;
    });

    document.addEventListener(actorFragmentRefreshEventName, function (event) {
        const detail = event.detail;
        const fragments = Array.isArray(detail && detail.fragments) ? detail.fragments : [];
        fragments.forEach(handleFragmentRefreshRequest);
    });

    document.addEventListener('focusout', function (event) {
        const target = event.target;
        if (!(target instanceof HTMLElement)) return;
        if (!target.classList.contains('slot-note-input')) return;

        const rowEl = target.closest('tr[data-roster-row]');
        if (!(rowEl instanceof HTMLElement) || !rowEl.id) return;

        window.setTimeout(function () {
            flushDeferredFragmentsWithoutActiveInputs();
        }, 0);
    });

    document.addEventListener('app:page-ready', syncConnection);
})();
