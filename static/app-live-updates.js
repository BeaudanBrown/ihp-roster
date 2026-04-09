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

    function findPreservedField(root, preserveField) {
        if (!(root instanceof HTMLElement) || !preserveField) return null;

        const fieldKey = preserveField.fieldKey;
        if (fieldKey) {
            const escapedKey = window.CSS && typeof window.CSS.escape === 'function'
                ? window.CSS.escape(fieldKey)
                : fieldKey;
            const keyedField = root.querySelector(`[data-roster-field-key="${escapedKey}"]`);
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

        document.querySelectorAll('[data-live-update-owner="true"]').forEach(function (ownerEl) {
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
        const target = document.getElementById(targetId);
        if (!target) return;

        const trimmed = (html || '').trim();
        if (!trimmed) {
            target.remove();
            return;
        }

        const template = document.createElement('template');
        template.innerHTML = trimmed;

        let nextNode = template.content.firstElementChild;
        if (nextNode && nextNode.tagName === 'TEMPLATE') {
            nextNode = nextNode.content.firstElementChild;
        }

        if (!(nextNode instanceof Element)) {
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
    }

    async function refetchFragment(fragment) {
        const response = await window.fetch(fragment.url, {
            credentials: 'same-origin',
            headers: {
                'HX-Request': 'true',
            },
        });

        if (!response.ok) {
            throw new Error(`Fragment fetch failed with ${response.status}`);
        }

        const html = await response.text();
        await swapFragmentHtml(fragment.targetId, html);
        restoreDeferredState(fragment);
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

    function rosterFragmentProtection() {
        function findActiveInput(target) {
            if (!(target instanceof HTMLElement)) return null;

            const activeInput = target.querySelector('.slot-note-input:focus');
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
                    target instanceof HTMLElement &&
                    target.closest('[data-live-update-feature="roster"]')
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
                if (!name) return fragment;

                const rowEl = activeInput.closest('tr[data-roster-row]');
                return {
                    ...fragment,
                    preserveField: {
                        rowId: rowEl instanceof HTMLElement ? rowEl.id : null,
                        fieldKey: activeInput.dataset.rosterFieldKey || null,
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

    const fragmentProtectionAdapters = [rosterFragmentProtection()];

    function matchingFragmentProtection(fragment, target) {
        return fragmentProtectionAdapters.find(function (adapter) {
            return adapter.matches(fragment, target);
        }) || null;
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

        if (fragment.deferUntilBlur && hasProtectedActiveInput(target, fragment)) {
            pendingDeferredFragments.set(fragment.targetId, captureDeferredState(target, fragment));
            return;
        }

        pendingDeferredFragments.delete(fragment.targetId);
        queueFragment(fragment);
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
        if (!scope || !scope.kind || !scope.venueId) return null;

        switch (scope.kind) {
            case 'roster_week':
                if (!scope.rosterGroupId || !Number.isInteger(scope.weekOffset)) return null;
                return `${scope.kind}:${scope.venueId}:${scope.rosterGroupId}:${scope.weekOffset}`;
            case 'roster_group_config':
            case 'admin_slot_names':
                if (!scope.rosterGroupId) return null;
                return `${scope.kind}:${scope.venueId}:${scope.rosterGroupId}`;
            case 'timesheet_week':
                if (!Number.isInteger(scope.weekOffset)) return null;
                return `${scope.kind}:${scope.venueId}:${scope.weekOffset}`;
            case 'leave_requests':
                return `${scope.kind}:${scope.venueId}`;
            default:
                return null;
        }
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

    function rosterAdapter() {
        function readScope(ownerEl) {
            if (!(ownerEl instanceof HTMLElement)) return null;
            if (ownerEl.dataset.liveUpdateFeature !== 'roster') return null;
            if (ownerEl.dataset.liveUpdateClientEnabled !== 'true') return null;

            const scopeKind = ownerEl.dataset.liveUpdateScopeKind;
            const venueId = ownerEl.dataset.liveUpdateVenueId;
            const rosterGroupId = ownerEl.dataset.liveUpdateRosterGroupId;
            const weekOffsetRaw = ownerEl.dataset.liveUpdateWeekOffset;
            if (!scopeKind || !venueId || !rosterGroupId || typeof weekOffsetRaw !== 'string') return null;

            const weekOffset = Number.parseInt(weekOffsetRaw, 10);
            if (!Number.isInteger(weekOffset)) return null;

            return {
                scope: {
                    kind: scopeKind,
                    venueId,
                    rosterGroupId,
                    weekOffset,
                },
                scopeKey: buildScopeKey({
                    kind: scopeKind,
                    venueId,
                    rosterGroupId,
                    weekOffset,
                }),
                path: ownerEl.dataset.liveUpdatesPath || '/live-updates',
                resync: function () {
                    const contentUrl = ownerEl.dataset.liveUpdateContentUrl;
                    const staffPanelUrl = ownerEl.dataset.liveUpdateStaffPanelUrl;

                    if (contentUrl) {
                        handleFragmentRefreshRequest({
                            targetId: 'roster-content',
                            url: contentUrl,
                            deferUntilBlur: true,
                        });
                    }

                    if (staffPanelUrl) {
                        handleFragmentRefreshRequest({
                            targetId: 'roster-staff-panel-fragment',
                            url: staffPanelUrl,
                            deferUntilBlur: false,
                        });
                    }
                },
            };
        }

        return {
            collectSubscriptions: function () {
                const subscriptions = [];
                document.querySelectorAll('[data-live-update-owner="true"]').forEach(function (ownerEl) {
                    const scopeInfo = readScope(ownerEl);
                    if (!scopeInfo) return;

                    subscriptions.push({
                        ...scopeInfo,
                        ownerEl,
                    });
                });
                return subscriptions;
            },
            shouldDecorateRequest: function (event) {
                const sourceEl = event.detail && event.detail.elt;
                return sourceEl instanceof HTMLElement && Boolean(sourceEl.closest('[data-live-update-feature="roster"]'));
            },
        };
    }

    function leaveRequestsAdapter() {
        function readScope(ownerEl) {
            if (!(ownerEl instanceof HTMLElement)) return null;
            if (ownerEl.dataset.liveUpdateFeature !== 'leave-requests') return null;
            if (ownerEl.dataset.liveUpdateClientEnabled !== 'true') return null;

            const scopeKind = ownerEl.dataset.liveUpdateScopeKind;
            const venueId = ownerEl.dataset.liveUpdateVenueId;
            if (!scopeKind || !venueId) return null;

            return {
                scope: {
                    kind: scopeKind,
                    venueId,
                },
                scopeKey: buildScopeKey({
                    kind: scopeKind,
                    venueId,
                }),
                path: ownerEl.dataset.liveUpdatesPath || '/live-updates',
                resync: function () {
                    const contentUrl = ownerEl.dataset.liveUpdateContentUrl;
                    if (contentUrl) {
                        handleFragmentRefreshRequest({
                            targetId: 'leave-requests-content',
                            url: contentUrl,
                            deferUntilBlur: false,
                        });
                    }
                },
            };
        }

        return {
            collectSubscriptions: function () {
                const subscriptions = [];
                document.querySelectorAll('[data-live-update-owner="true"]').forEach(function (ownerEl) {
                    const scopeInfo = readScope(ownerEl);
                    if (!scopeInfo || !scopeInfo.scopeKey) return;
                    subscriptions.push({ ...scopeInfo, ownerEl });
                });
                return subscriptions;
            },
            shouldDecorateRequest: function (event) {
                const sourceEl = event.detail && event.detail.elt;
                return sourceEl instanceof HTMLElement && Boolean(sourceEl.closest('[data-live-update-feature="leave-requests"]'));
            },
        };
    }

    function timesheetsAdapter() {
        function readScope(ownerEl) {
            if (!(ownerEl instanceof HTMLElement)) return null;
            if (ownerEl.dataset.liveUpdateFeature !== 'timesheets') return null;
            if (ownerEl.dataset.liveUpdateClientEnabled !== 'true') return null;

            const scopeKind = ownerEl.dataset.liveUpdateScopeKind;
            const venueId = ownerEl.dataset.liveUpdateVenueId;
            const weekOffsetRaw = ownerEl.dataset.liveUpdateWeekOffset;
            if (!scopeKind || !venueId || typeof weekOffsetRaw !== 'string') return null;

            const weekOffset = Number.parseInt(weekOffsetRaw, 10);
            if (!Number.isInteger(weekOffset)) return null;

            return {
                scope: {
                    kind: scopeKind,
                    venueId,
                    weekOffset,
                },
                scopeKey: buildScopeKey({
                    kind: scopeKind,
                    venueId,
                    weekOffset,
                }),
                path: ownerEl.dataset.liveUpdatesPath || '/live-updates',
                resync: function () {
                    ownerEl.querySelectorAll('[data-timesheet-day-offset]').forEach(function (sectionEl) {
                        if (!(sectionEl instanceof HTMLElement)) return;
                        const url = sectionEl.dataset.liveUpdateUrl;
                        if (!url || !sectionEl.id) return;
                        handleFragmentRefreshRequest({
                            targetId: sectionEl.id,
                            url,
                            deferUntilBlur: false,
                        });
                    });
                },
            };
        }

        return {
            collectSubscriptions: function () {
                const subscriptions = [];
                document.querySelectorAll('[data-live-update-owner="true"]').forEach(function (ownerEl) {
                    const scopeInfo = readScope(ownerEl);
                    if (!scopeInfo || !scopeInfo.scopeKey) return;
                    subscriptions.push({ ...scopeInfo, ownerEl });
                });
                return subscriptions;
            },
            shouldDecorateRequest: function (event) {
                const sourceEl = event.detail && event.detail.elt;
                return sourceEl instanceof HTMLElement && Boolean(sourceEl.closest('[data-live-update-feature="timesheets"]'));
            },
        };
    }

    function adminSlotNamesAdapter() {
        function readScope(ownerEl) {
            if (!(ownerEl instanceof HTMLElement)) return null;
            if (ownerEl.dataset.liveUpdateFeature !== 'admin-slot-names') return null;
            if (ownerEl.dataset.liveUpdateClientEnabled !== 'true') return null;

            const scopeKind = ownerEl.dataset.liveUpdateScopeKind;
            const venueId = ownerEl.dataset.liveUpdateVenueId;
            const rosterGroupId = ownerEl.dataset.liveUpdateRosterGroupId;
            if (!scopeKind || !venueId || !rosterGroupId) return null;

            return {
                scope: {
                    kind: scopeKind,
                    venueId,
                    rosterGroupId,
                },
                scopeKey: buildScopeKey({
                    kind: scopeKind,
                    venueId,
                    rosterGroupId,
                }),
                path: ownerEl.dataset.liveUpdatesPath || '/live-updates',
                resync: function () {
                    const contentUrl = ownerEl.dataset.liveUpdateContentUrl;
                    if (contentUrl) {
                        handleFragmentRefreshRequest({
                            targetId: 'admin-slot-names-fragment',
                            url: contentUrl,
                            deferUntilBlur: false,
                        });
                    }
                },
            };
        }

        return {
            collectSubscriptions: function () {
                const subscriptions = [];
                document.querySelectorAll('[data-live-update-owner="true"]').forEach(function (ownerEl) {
                    const scopeInfo = readScope(ownerEl);
                    if (!scopeInfo || !scopeInfo.scopeKey) return;
                    subscriptions.push({ ...scopeInfo, ownerEl });
                });
                return subscriptions;
            },
            shouldDecorateRequest: function (event) {
                const sourceEl = event.detail && event.detail.elt;
                return sourceEl instanceof HTMLElement && Boolean(sourceEl.closest('[data-live-update-feature="admin-slot-names"]') || sourceEl.closest('#admin-slot-names-fragment'));
            },
        };
    }

    function adminInvitesAdapter() {
        function readScope(ownerEl) {
            if (!(ownerEl instanceof HTMLElement)) return null;
            if (ownerEl.dataset.liveUpdateFeature !== 'admin-invites') return null;
            if (ownerEl.dataset.liveUpdateClientEnabled !== 'true') return null;

            const scopeKind = ownerEl.dataset.liveUpdateScopeKind;
            const venueId = ownerEl.dataset.liveUpdateVenueId;
            if (!scopeKind || !venueId) return null;

            return {
                scope: {
                    kind: scopeKind,
                    venueId,
                },
                scopeKey: buildScopeKey({
                    kind: scopeKind,
                    venueId,
                }),
                path: ownerEl.dataset.liveUpdatesPath || '/live-updates',
                resync: function () {
                    const contentUrl = ownerEl.dataset.liveUpdateContentUrl;
                    if (contentUrl) {
                        handleFragmentRefreshRequest({
                            targetId: 'admin-invites-fragment',
                            url: contentUrl,
                            deferUntilBlur: false,
                        });
                    }
                },
            };
        }

        return {
            collectSubscriptions: function () {
                const subscriptions = [];
                document.querySelectorAll('[data-live-update-owner="true"]').forEach(function (ownerEl) {
                    const scopeInfo = readScope(ownerEl);
                    if (!scopeInfo || !scopeInfo.scopeKey) return;
                    subscriptions.push({ ...scopeInfo, ownerEl });
                });
                return subscriptions;
            },
            shouldDecorateRequest: function (event) {
                const sourceEl = event.detail && event.detail.elt;
                return sourceEl instanceof HTMLElement && Boolean(sourceEl.closest('[data-live-update-feature="admin-invites"]') || sourceEl.closest('#admin-invites-fragment'));
            },
        };
    }

    const adapters = [rosterAdapter(), leaveRequestsAdapter(), timesheetsAdapter(), adminSlotNamesAdapter(), adminInvitesAdapter()];

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
        if (!message || !message.scope) return;

        const scope = message.scope;
        const scopeKey = buildScopeKey(scope);
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
        if (!message || !message.scope || !Array.isArray(message.fragments)) return;
        if (message.sourceClientId && message.sourceClientId === activeClientId) return;

        const scope = message.scope;
        const scopeKey = buildScopeKey(scope);
        if (!scopeKey) return;
        const subscription = activeSubscriptions.get(scopeKey);
        if (!subscription) return;

        const nextVersion = normalizeVersion(message.version);
        const previousVersion = getScopeVersion(scopeKey);

        if (nextVersion !== null) {
            if (previousVersion !== null && nextVersion > previousVersion + 1) {
                setScopeVersion(scopeKey, nextVersion);
                if (typeof subscription.resync === 'function') {
                    subscription.resync(subscription);
                }
                return;
            }

            if (previousVersion !== null && nextVersion <= previousVersion) {
                return;
            }

            setScopeVersion(scopeKey, nextVersion);
        }

        if (message.fragments.length === 0 && typeof subscription.resync === 'function') {
            subscription.resync(subscription);
            return;
        }

        message.fragments.forEach(handleFragmentRefreshRequest);
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
            if (activeSubscriptions.size > 0) {
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
