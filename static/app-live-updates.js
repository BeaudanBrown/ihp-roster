// Shared live-update runtime: one websocket per tab with many scope subscriptions.
(function enableLiveUpdates() {
    if (typeof window === 'undefined' || typeof window.WebSocket !== 'function') return;

    const pendingDeferredFragments = new Map();
    const inFlightFragments = new Map();
    const activeSubscriptions = new Map();
    const scopeVersions = new Map();
    let socket = null;
    let socketPath = null;
    let reconnectTimer = null;
    let activeClientId = null;
    let reconnectPaused = false;
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

    function getOwnerElements() {
        return Array.from(document.querySelectorAll('[data-live-update-owner="true"][data-live-update-client-enabled="true"]'));
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

        getOwnerElements().forEach(function (ownerEl) {
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

    function notifyPageReady(target) {
        if (window.appPageLifecycle && typeof window.appPageLifecycle.dispatchPageReady === 'function') {
            window.appPageLifecycle.dispatchPageReady({
                source: 'live-fragment-refetch',
                target: target || document.body,
                isFullPage: false,
            });
            return;
        }

        if (window.htmx && typeof window.htmx.process === 'function') {
            window.htmx.process(target || document.body);
        }
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
        notifyPageReady(nextNode);
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
        endPerfSpan(perfSpan, {
            outcome: 'ok',
            status: response.status,
            responseBytes: html.length,
        });
    }

    function queueFragment(fragment) {
        const existing = inFlightFragments.get(fragment.targetId);
        if (existing) {
            inFlightFragments.set(fragment.targetId, { next: fragment });
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

    function hasFocusedField(root) {
        if (!(root instanceof HTMLElement)) return false;
        const activeElement = document.activeElement;
        if (!(activeElement instanceof HTMLElement)) return false;
        if (!root.contains(activeElement)) return false;
        return activeElement.matches('input, select, textarea, [contenteditable="true"]');
    }

    function handleInvalidatedFragment(fragment) {
        if (!fragment || !fragment.targetId || !fragment.url) return;
        const target = document.getElementById(fragment.targetId);
        if (!(target instanceof HTMLElement)) return;
        const deferUntilBlur = fragment.deferUntilBlur || target.dataset.liveFragmentDeferUntilBlur === 'true';

        if (deferUntilBlur && hasFocusedField(target)) {
            pendingDeferredFragments.set(fragment.targetId, {
                ...fragment,
                deferUntilBlur,
            });
            return;
        }

        pendingDeferredFragments.delete(fragment.targetId);
        queueFragment({
            ...fragment,
            deferUntilBlur,
        });
    }

    function flushDeferredFragments() {
        Array.from(pendingDeferredFragments.entries()).forEach(function ([targetId, fragment]) {
            const target = document.getElementById(targetId);
            if (target instanceof HTMLElement && hasFocusedField(target)) {
                return;
            }

            pendingDeferredFragments.delete(targetId);
            queueFragment(fragment);
        });
    }

    function scheduleReconnect() {
        if (reconnectPaused) return;
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

    function getScopeVersion(scope) {
        const version = scopeVersions.get(scope);
        return Number.isInteger(version) ? version : null;
    }

    function setScopeVersion(scope, version) {
        if (!Number.isInteger(version) || version < 0) return;
        scopeVersions.set(scope, version);
    }

    function clearScopeVersion(scope) {
        scopeVersions.delete(scope);
    }

    function normalizeVersion(value) {
        return Number.isInteger(value) && value >= 0 ? value : null;
    }

    function fragmentFromElement(fragmentEl) {
        if (!(fragmentEl instanceof HTMLElement) || !fragmentEl.id) return null;
        const url = fragmentEl.dataset.liveFragmentUrl;
        if (!url) return null;
        return {
            targetId: fragmentEl.id,
            url,
            deferUntilBlur: fragmentEl.dataset.liveFragmentDeferUntilBlur === 'true',
        };
    }

    function collectResyncFragmentsForOwner(ownerEl) {
        if (!(ownerEl instanceof HTMLElement)) return [];

        const fragments = new Map();
        const ownerFragment = fragmentFromElement(ownerEl);
        if (ownerFragment) {
            fragments.set(ownerFragment.targetId, ownerFragment);
        }

        ownerEl.querySelectorAll('[data-live-fragment-url][id]').forEach(function (fragmentEl) {
            const fragment = fragmentFromElement(fragmentEl);
            if (fragment) {
                fragments.set(fragment.targetId, fragment);
            }
        });

        return Array.from(fragments.values());
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

    function desiredSubscriptions() {
        const desired = new Map();

        getOwnerElements().forEach(function (ownerEl) {
            if (!(ownerEl instanceof HTMLElement)) return;

            const scope = (ownerEl.dataset.liveUpdateScope || '').trim();
            if (!scope) return;

            const path = ownerEl.dataset.liveUpdatesPath || '/live-updates';
            const existing = desired.get(scope);
            if (existing) {
                existing.owners.push(ownerEl);
                return;
            }

            desired.set(scope, {
                scope,
                scopeKey: scope,
                path,
                owners: [ownerEl],
                resync: function () {
                    const fragments = new Map();
                    this.owners.forEach(function (currentOwner) {
                        collectResyncFragmentsForOwner(currentOwner).forEach(function (fragment) {
                            fragments.set(fragment.targetId, fragment);
                        });
                    });
                    fragments.forEach(handleInvalidatedFragment);
                },
            });
        });

        return desired;
    }

    function handleSubscribedMessage(message) {
        if (!message || typeof message.scope !== 'string') return;

        const subscription = activeSubscriptions.get(message.scope);
        if (!subscription) return;

        const currentVersion = normalizeVersion(message.currentVersion);
        if (currentVersion !== null) {
            setScopeVersion(subscription.scopeKey, currentVersion);
        }

        if (message.resync && typeof subscription.resync === 'function') {
            subscription.resync();
        }
    }

    function handleInvalidateMessage(message) {
        if (!message || typeof message.scope !== 'string' || !Array.isArray(message.fragments)) return;
        if (message.sourceClientId && message.sourceClientId === activeClientId) return;

        const subscription = activeSubscriptions.get(message.scope);
        if (!subscription) return;

        const nextVersion = normalizeVersion(message.version);
        const previousVersion = getScopeVersion(subscription.scopeKey);

        if (nextVersion !== null) {
            if (previousVersion !== null && nextVersion > previousVersion + 1) {
                setScopeVersion(subscription.scopeKey, nextVersion);
                if (typeof subscription.resync === 'function') {
                    subscription.resync();
                }
                return;
            }

            if (previousVersion !== null && nextVersion <= previousVersion) {
                return;
            }

            setScopeVersion(subscription.scopeKey, nextVersion);
        }

        message.fragments.forEach(handleInvalidatedFragment);
    }

    function openSocket(path) {
        socket = new window.WebSocket(buildWebSocketUrl(path));
        socketPath = path;

        socket.onopen = function () {
            activeSubscriptions.forEach(subscribeScope);
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
            socket = null;
            if (activeSubscriptions.size > 0 && !reconnectPaused) {
                scheduleReconnect();
            }
        };

        socket.onerror = function () {
            if (socket) {
                socket.close();
            }
        };
    }

    function syncConnection() {
        ensureClientId();

        const desired = desiredSubscriptions();
        const nextPath = desired.size > 0 ? desired.values().next().value.path : null;

        const removed = [];
        activeSubscriptions.forEach(function (subscription, scopeKey) {
            if (!desired.has(scopeKey)) {
                removed.push(subscription);
            }
        });

        removed.forEach(function (subscription) {
            unsubscribeScope(subscription);
            activeSubscriptions.delete(subscription.scopeKey);
            clearScopeVersion(subscription.scopeKey);
        });

        if (reconnectPaused) {
            closeSocket();
            return;
        }

        if (desired.size === 0 || !nextPath) {
            closeSocket();
            return;
        }

        const added = [];
        desired.forEach(function (subscription, scopeKey) {
            if (!activeSubscriptions.has(scopeKey)) {
                added.push(subscription);
            }
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
        const sourceEl = event.detail && event.detail.elt;
        if (!(sourceEl instanceof HTMLElement)) return;
        if (!sourceEl.closest('[data-live-update-owner="true"]')) return;
        if (!event.detail || !event.detail.headers) return;
        event.detail.headers['X-Live-Update-Client-Id'] = ensureClientId();
    });

    document.addEventListener('focusout', function () {
        window.setTimeout(flushDeferredFragments, 0);
    });

    function connectionState() {
        if (reconnectPaused) return 'paused';
        if (!socket) return 'closed';
        if (socket.readyState === window.WebSocket.CONNECTING) return 'connecting';
        if (socket.readyState === window.WebSocket.OPEN) return 'open';
        if (socket.readyState === window.WebSocket.CLOSING) return 'closing';
        return 'closed';
    }

    window.appLiveUpdatesDebug = {
        pause: function () {
            reconnectPaused = true;
            closeSocket();
            return connectionState();
        },
        resume: function () {
            reconnectPaused = false;
            syncConnection();
            return connectionState();
        },
        forceReconnect: function () {
            reconnectPaused = false;
            closeSocket();
            syncConnection();
            return connectionState();
        },
        connectionState: connectionState,
        subscribedScopes: function () {
            return Array.from(activeSubscriptions.keys());
        },
        clientId: function () {
            return ensureClientId();
        },
    };

    document.addEventListener('app:page-ready', syncConnection);
    window.addEventListener('beforeunload', closeSocket);
})();
