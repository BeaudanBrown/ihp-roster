(function enableAppPageLifecycle() {
    if (typeof window === 'undefined') return;

    const pageReadyEventName = 'app:page-ready';

    function normalizeTarget(target) {
        if (target instanceof HTMLElement) return target;
        if (target instanceof Document) return document.body;
        return document.body;
    }

    function dispatchPageReady(detail) {
        const target = normalizeTarget(detail && detail.target);
        const event = new CustomEvent(pageReadyEventName, {
            detail: {
                target,
                source: detail && detail.source ? detail.source : 'unknown',
                isFullPage: Boolean(detail && detail.isFullPage),
            },
        });
        document.dispatchEvent(event);
    }

    window.appPageLifecycle = {
        eventName: pageReadyEventName,
        dispatchPageReady,
    };

    document.addEventListener(pageReadyEventName, function (event) {
        const target = normalizeTarget(event.detail && event.detail.target);
        if (window.htmx && typeof window.htmx.process === 'function') {
            window.htmx.process(target);
        }
    });

    document.addEventListener('DOMContentLoaded', function () {
        dispatchPageReady({
            source: 'dom-content-loaded',
            target: document.body,
            isFullPage: true,
        });
    });

    document.addEventListener('htmx:afterSwap', function (event) {
        dispatchPageReady({
            source: 'htmx-after-swap',
            target: event.detail && event.detail.target,
            isFullPage: false,
        });
    });

    document.addEventListener('htmx:oobAfterSwap', function (event) {
        dispatchPageReady({
            source: 'htmx-oob-after-swap',
            target: event.detail && event.detail.target,
            isFullPage: false,
        });
    });

    if (document.readyState !== 'loading') {
        dispatchPageReady({
            source: 'document-ready',
            target: document.body,
            isFullPage: true,
        });
    }
})();

// Keep tracked timer cleanup app-local so dev live reload and any future re-init flows
// can clear stale intervals/timeouts without depending on legacy framework runtime hooks.
(function enableTrackedTimers() {
    if (typeof window === 'undefined') return;

    if (!Array.isArray(window.allIntervals)) {
        window.allIntervals = [];
    }
    if (!Array.isArray(window.allTimeouts)) {
        window.allTimeouts = [];
    }

    if (typeof window.unsafeSetInterval !== 'function') {
        window.unsafeSetInterval = window.setInterval.bind(window);
    }
    if (typeof window.unsafeSetTimeout !== 'function') {
        window.unsafeSetTimeout = window.setTimeout.bind(window);
    }

    if (window.setInterval !== trackedSetInterval) {
        window.setInterval = trackedSetInterval;
    }
    if (window.setTimeout !== trackedSetTimeout) {
        window.setTimeout = trackedSetTimeout;
    }

    if (typeof window.clearAllIntervals !== 'function') {
        window.clearAllIntervals = function clearAllIntervals() {
            for (const intervalId of window.allIntervals) {
                window.clearInterval(intervalId);
            }
            window.allIntervals = [];
        };
    }

    if (typeof window.clearAllTimeouts !== 'function') {
        window.clearAllTimeouts = function clearAllTimeouts() {
            for (const timeoutId of window.allTimeouts) {
                window.clearTimeout(timeoutId);
            }
            window.allTimeouts = [];
        };
    }

    function trackedSetInterval() {
        const intervalId = window.unsafeSetInterval.apply(window, arguments);
        window.allIntervals.push(intervalId);
        return intervalId;
    }

    function trackedSetTimeout() {
        const timeoutId = window.unsafeSetTimeout.apply(window, arguments);
        window.allTimeouts.push(timeoutId);
        return timeoutId;
    }
})();

// Keep the date/datetime picker enhancement app-local so it survives after helpers.js is removed.
(function enableDatePickers() {
    if (typeof window === 'undefined') return;

    const initializedKey = 'appDatePickerInitialized';

    function initInput(inputEl) {
        if (!(inputEl instanceof HTMLInputElement)) return;
        if (!window.flatpickr) return;
        if (inputEl.dataset[initializedKey] === 'true') return;
        if (inputEl._flatpickr) {
            inputEl.dataset[initializedKey] = 'true';
            return;
        }

        const config = inputEl.type === 'datetime-local'
            ? {
                enableTime: true,
                time_24hr: true,
                dateFormat: 'Z',
                altInput: true,
                altFormat: 'd.m.y, H:i',
            }
            : {
                altFormat: 'd.m.y',
            };

        window.flatpickr(inputEl, config);
        inputEl.dataset[initializedKey] = 'true';
    }

    function initWithin(root) {
        if (!(root instanceof Element || root instanceof Document)) return;

        if (root instanceof HTMLInputElement && (root.type === 'date' || root.type === 'datetime-local')) {
            initInput(root);
        }

        root.querySelectorAll("input[type='date'], input[type='datetime-local']").forEach(initInput);
    }

    function handleSwap(event) {
        if (event.detail && event.detail.target instanceof HTMLElement) {
            initWithin(event.detail.target);
        }
    }

    document.addEventListener('app:page-ready', function (event) {
        initWithin((event.detail && event.detail.target) || document);
    });
    document.addEventListener('htmx:afterSwap', handleSwap);
    document.addEventListener('htmx:oobAfterSwap', handleSwap);
})();

// Shared workflow dialog mount for HTMX-driven form overlays.
(function enableDialogOverlayMount() {
    if (typeof window === 'undefined') return;

    const mountId = 'dialog-overlay-mount';
    let lastTrigger = null;

    function getMount() {
        return document.getElementById(mountId);
    }

    function getActiveDialog() {
        const mountEl = getMount();
        return mountEl ? mountEl.querySelector('[data-dialog-overlay="true"]') : null;
    }

    function hasVisibleBootstrapModal() {
        return Boolean(document.querySelector('.modal.show:not([data-dialog-overlay="true"])'));
    }

    function focusDialog(dialogEl) {
        if (!(dialogEl instanceof HTMLElement)) return;

        const focusTarget = dialogEl.querySelector('[autofocus], .is-invalid, input, select, textarea, button, a[href]');
        if (focusTarget instanceof HTMLElement) {
            focusTarget.focus();
            return;
        }

        dialogEl.focus();
    }

    function restoreFocus() {
        if (lastTrigger instanceof HTMLElement && document.contains(lastTrigger)) {
            lastTrigger.focus();
        }
        lastTrigger = null;
    }

    function syncDialogState() {
        const dialogEl = getActiveDialog();
        const hasDialog = dialogEl instanceof HTMLElement;
        const shouldLockBody = hasDialog || hasVisibleBootstrapModal();

        document.body.classList.toggle('modal-open', shouldLockBody);
        document.body.style.overflow = shouldLockBody ? 'hidden' : '';

        if (hasDialog) {
            focusDialog(dialogEl);
        } else if (!hasVisibleBootstrapModal()) {
            restoreFocus();
        }
    }

    function clearMount() {
        const mountEl = getMount();
        if (!(mountEl instanceof HTMLElement)) return;

        mountEl.innerHTML = '';
        syncDialogState();
    }

    document.addEventListener('click', function (event) {
        const triggerEl = event.target.closest(`[hx-target="#${mountId}"]`);
        if (triggerEl instanceof HTMLElement) {
            lastTrigger = triggerEl;
        }
    }, true);

    document.addEventListener('click', function (event) {
        const activeDialog = getActiveDialog();
        const closeEl = event.target.closest('[data-dialog-overlay-close="true"]');
        if (closeEl && activeDialog) {
            event.preventDefault();
            clearMount();
            return;
        }

        const backdropEl = event.target.closest('[data-dialog-overlay-backdrop="true"]');
        if (backdropEl && activeDialog) {
            event.preventDefault();
            clearMount();
            return;
        }

        // The full-screen dialog shell sits above the backdrop, so background clicks
        // often land on the shell instead of the separate backdrop node.
        if (activeDialog && event.target === activeDialog) {
            event.preventDefault();
            clearMount();
        }
    });

    document.addEventListener('keydown', function (event) {
        if (event.key !== 'Escape') return;
        if (!getActiveDialog()) return;

        event.preventDefault();
        clearMount();
    });

    document.addEventListener('htmx:afterSwap', function (event) {
        if (!(event.detail && event.detail.target instanceof HTMLElement)) return;
        if (event.detail.target.id !== mountId) return;

        if (window.htmx && typeof window.htmx.process === 'function') {
            window.htmx.process(event.detail.target);
        }

        syncDialogState();
    });

    document.addEventListener('shown.bs.modal', syncDialogState);
    document.addEventListener('hidden.bs.modal', syncDialogState);
    document.addEventListener('app:page-ready', syncDialogState);
})();

// Bottom-right toast host for redirects and HTMX-triggered transient messages.
(function enableToastOverlayHost() {
    if (typeof window === 'undefined') return;

    const hostId = 'toast-overlay-mount';
    const initializedKey = 'toastInitialized';

    function getHost() {
        return document.getElementById(hostId);
    }

    function dismissToast(toastEl) {
        if (!(toastEl instanceof HTMLElement)) return;
        toastEl.classList.add('app-toast-leaving');
        window.setTimeout(function () {
            if (toastEl.parentNode) {
                toastEl.remove();
            }
        }, 220);
    }

    function initToast(toastEl) {
        if (!(toastEl instanceof HTMLElement)) return;
        if (toastEl.dataset[initializedKey] === 'true') return;

        toastEl.dataset[initializedKey] = 'true';
        const autoHideMs = Number.parseInt(toastEl.dataset.autoHideMs || '0', 10);
        if (autoHideMs > 0) {
            window.setTimeout(function () {
                dismissToast(toastEl);
            }, autoHideMs);
        }
    }

    function initHostToasts() {
        const hostEl = getHost();
        if (!(hostEl instanceof HTMLElement)) return;
        hostEl.querySelectorAll('[data-overlay-toast="true"]').forEach(initToast);
    }

    document.addEventListener('click', function (event) {
        const closeEl = event.target.closest('[data-toast-close="true"]');
        if (!(closeEl instanceof HTMLElement)) return;

        const toastEl = closeEl.closest('[data-overlay-toast="true"]');
        if (toastEl instanceof HTMLElement) {
            dismissToast(toastEl);
        }
    });

    document.addEventListener('app:page-ready', initHostToasts);
})();

// Defer auto-refresh updates for rows that are actively being edited.
// This prevents in-progress edits from being clobbered by live updates while still replaying the latest row after blur.
(function enableRosterGridAutoRefreshDeferral() {
    if (typeof window === 'undefined' || typeof window.morphdom !== 'function') return;

    const pendingRows = new Map();
    const baseMorphdom = window.morphdom;

    function hasActiveRosterInput(rowEl) {
        return Boolean(rowEl.querySelector('.slot-cell-input:focus'));
    }

    function applyPendingRow(rowId, preserveField) {
        const pendingMarkup = pendingRows.get(rowId);
        if (!pendingMarkup) return;

        const currentRow = document.getElementById(rowId);
        if (!currentRow) {
            pendingRows.delete(rowId);
            return;
        }

        const template = document.createElement('template');
        template.innerHTML = pendingMarkup.trim();
        const nextRow = template.content.firstElementChild;
        if (!nextRow) {
            pendingRows.delete(rowId);
            return;
        }

        pendingRows.delete(rowId);
        baseMorphdom(currentRow, nextRow);

        if (preserveField && preserveField.name) {
            const escapedName = window.CSS && typeof window.CSS.escape === 'function'
                ? window.CSS.escape(preserveField.name)
                : preserveField.name;
            const field = currentRow.querySelector(`[name="${escapedName}"]`);
            if (field instanceof HTMLInputElement || field instanceof HTMLSelectElement || field instanceof HTMLTextAreaElement) {
                field.value = preserveField.value;
            }
        }
    }

    window.morphdom = function (fromNode, toNode, options) {
        const baseOnBeforeElUpdated = options && typeof options.onBeforeElUpdated === 'function'
            ? options.onBeforeElUpdated
            : null;
        const baseOnBeforeElChildrenUpdated = options && typeof options.onBeforeElChildrenUpdated === 'function'
            ? options.onBeforeElChildrenUpdated
            : null;

        if (options) {
            options = {
                ...options,
                onBeforeElChildrenUpdated: function (fromEl, toEl) {
                    const isRosterControl =
                        fromEl instanceof HTMLElement &&
                        fromEl.closest('.roster-grid') &&
                        (fromEl.tagName === 'INPUT'
                            || fromEl.tagName === 'SELECT'
                            || fromEl.tagName === 'TEXTAREA'
                            || fromEl.tagName === 'OPTION');

                    // Skip IHP's value-preservation hook for roster controls so server truth is reflected.
                    if (isRosterControl) {
                        return;
                    }

                    if (baseOnBeforeElChildrenUpdated) {
                        return baseOnBeforeElChildrenUpdated(fromEl, toEl);
                    }

                    return true;
                },
                onBeforeElUpdated: function (fromEl, toEl) {
                    if (baseOnBeforeElUpdated && baseOnBeforeElUpdated(fromEl, toEl) === false) {
                        return false;
                    }

                    const isRosterRow =
                        fromEl instanceof HTMLElement &&
                        toEl instanceof HTMLElement &&
                        fromEl.matches('tr[data-roster-row]') &&
                        toEl.matches('tr[data-roster-row]');

                    if (isRosterRow && hasActiveRosterInput(fromEl)) {
                        const rowId = fromEl.id;
                        if (rowId) {
                            pendingRows.set(rowId, toEl.outerHTML);
                        }
                        return false;
                    }

                    return true;
                },
            };
        }

        return baseMorphdom(fromNode, toNode, options);
    };

    document.addEventListener('focusout', function (event) {
        const target = event.target;
        if (!(target instanceof HTMLElement)) return;
        if (!target.classList.contains('slot-cell-input')) return;

        const rowEl = target.closest('tr[data-roster-row]');
        if (!rowEl || !rowEl.id) return;
        const preserveField = {
            name: target.getAttribute('name'),
            value: target.value,
        };

        // Wait until focus has potentially moved to another input in the same row.
        window.setTimeout(function () {
            if (!hasActiveRosterInput(rowEl)) {
                applyPendingRow(rowEl.id, preserveField);
            }
        }, 0);
    });
})();

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
            .catch(function () {
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

    function rosterFragmentProtection() {
        function findActiveInput(target) {
            if (!(target instanceof HTMLElement)) return null;

            const activeInput = target.querySelector('.slot-cell-input:focus');
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
                        name,
                        value: activeInput.value,
                    },
                };
            },
            restoreState: function (target, fragment) {
                if (!fragment || !fragment.preserveField) return;

                const { rowId, name, value } = fragment.preserveField;
                if (!name) return;

                const root = rowId ? document.getElementById(rowId) : target;
                if (!(root instanceof HTMLElement)) return;

                const escapedName = window.CSS && typeof window.CSS.escape === 'function'
                    ? window.CSS.escape(name)
                    : name;
                const field = root.querySelector(`[name="${escapedName}"]`);
                if (field instanceof HTMLInputElement || field instanceof HTMLSelectElement || field instanceof HTMLTextAreaElement) {
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
                resync: function (subscription) {
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
        if (!target.classList.contains('slot-cell-input')) return;

        const rowEl = target.closest('tr[data-roster-row]');
        if (!(rowEl instanceof HTMLElement) || !rowEl.id) return;

        window.setTimeout(function () {
            flushDeferredFragmentsWithoutActiveInputs();
        }, 0);
    });

    document.addEventListener('app:page-ready', syncConnection);
})();

// Reusable quarter-hour modal time picker.
// Any field using [data-time-picker-field] + .js-time-picker-input + .js-time-picker-trigger
// can opt into this behavior.
(function enableQuarterHourTimePicker() {
    if (typeof window === 'undefined') return;

    const modalId = 'quarter-hour-time-picker-modal';
    const defaultEmptyLabel = 'Time';
    let activeField = null;

    function getModalElement() {
        return document.getElementById(modalId);
    }

    function getBootstrapModal(modalEl) {
        if (!modalEl || !window.bootstrap || !window.bootstrap.Modal) return null;
        return window.bootstrap.Modal.getOrCreateInstance(modalEl);
    }

    function forceHideModal(modalEl) {
        if (!modalEl) return;

        modalEl.classList.remove('show');
        modalEl.style.display = 'none';
        modalEl.setAttribute('aria-hidden', 'true');
        modalEl.removeAttribute('aria-modal');
        document.body.classList.remove('modal-open');
        document.body.style.removeProperty('padding-right');
        document.querySelectorAll('.modal-backdrop').forEach(function (backdropEl) {
            backdropEl.remove();
        });
        activeField = null;
    }

    function hideTimePickerModal(modalEl) {
        if (!modalEl) return;

        const bootstrapModal = getBootstrapModal(modalEl);
        if (bootstrapModal) bootstrapModal.hide();

        window.setTimeout(function () {
            if (modalEl.classList.contains('show')) {
                forceHideModal(modalEl);
            }
        }, 150);
    }

    function getFieldInput(fieldEl) {
        return fieldEl ? fieldEl.querySelector('.js-time-picker-input') : null;
    }

    function getFieldLabel(fieldEl) {
        return fieldEl ? fieldEl.querySelector('.js-time-picker-label') : null;
    }

    function getStepDownButton(fieldEl) {
        return fieldEl ? fieldEl.querySelector('.js-time-picker-step-down') : null;
    }

    function getStepUpButton(fieldEl) {
        return fieldEl ? fieldEl.querySelector('.js-time-picker-step-up') : null;
    }

    function emptyLabelForField(fieldEl) {
        if (!(fieldEl instanceof HTMLElement)) return defaultEmptyLabel;
        return fieldEl.dataset.timePickerEmptyLabel || defaultEmptyLabel;
    }

    function findOptionByValue(modalEl, value) {
        if (!modalEl) return null;
        return modalEl.querySelector(`.js-time-picker-option[data-time-value="${value}"]`);
    }

    function minuteOfDayFromValue(value) {
        if (!value || !/^\d{2}:\d{2}$/.test(value)) return null;
        const parts = value.split(':');
        const hour = Number(parts[0]);
        const minute = Number(parts[1]);
        if (!Number.isInteger(hour) || !Number.isInteger(minute)) return null;
        if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;
        return hour * 60 + minute;
    }

    function displayLabelFromValue(value) {
        const minuteOfDay = minuteOfDayFromValue(value);
        if (minuteOfDay === null) return value;

        const hour24 = Math.floor(minuteOfDay / 60);
        const minute = minuteOfDay % 60;
        const meridiem = hour24 >= 12 ? 'PM' : 'AM';
        const hour12 = hour24 % 12 === 0 ? 12 : hour24 % 12;
        const minuteLabel = String(minute).padStart(2, '0');
        return `${hour12}:${minuteLabel} ${meridiem}`;
    }

    function resolveRange(fieldEl, modalEl) {
        const defaultStart = (modalEl && modalEl.dataset.defaultStartTime) || '06:00';
        const defaultEnd = (modalEl && modalEl.dataset.defaultEndTime) || '23:45';
        const startValue = (fieldEl && fieldEl.dataset.timePickerStart) || defaultStart;
        const endValue = (fieldEl && fieldEl.dataset.timePickerEnd) || defaultEnd;

        const startMinute = minuteOfDayFromValue(startValue);
        const endMinuteRaw = minuteOfDayFromValue(endValue);
        if (startMinute === null || endMinuteRaw === null) return null;

        const endMinute = endMinuteRaw < startMinute ? endMinuteRaw + 24 * 60 : endMinuteRaw;
        return { startMinute, endMinute };
    }

    function stepMinutesForField(fieldEl) {
        const rawValue = fieldEl && fieldEl.dataset.timePickerStepMinutes;
        const parsed = Number(rawValue || '15');
        if (!Number.isInteger(parsed) || parsed <= 0) return 15;
        return parsed;
    }

    function buildTimeOptions(range) {
        return buildTimeOptionsWithStep(range, 15);
    }

    function buildTimeOptionsWithStep(range, stepMinutes) {
        if (!range) return [];

        const options = [];
        for (let minute = range.startMinute; minute <= range.endMinute; minute += stepMinutes) {
            const minuteOfDay = minute % (24 * 60);
            const hour = Math.floor(minuteOfDay / 60);
            const minutePart = minuteOfDay % 60;
            const value = `${String(hour).padStart(2, '0')}:${String(minutePart).padStart(2, '0')}`;
            options.push({ value, label: displayLabelFromValue(value) });
        }
        return options;
    }

    function buildFieldOptions(fieldEl, modalEl) {
        const range = resolveRange(fieldEl, modalEl);
        if (!range) return [];
        return buildTimeOptionsWithStep(range, stepMinutesForField(fieldEl));
    }

    function renderOptions(modalEl, fieldEl) {
        if (!modalEl) return;
        const gridEl = modalEl.querySelector('.js-time-picker-grid');
        if (!gridEl) return;

        const options = buildFieldOptions(fieldEl, modalEl);
        gridEl.innerHTML = options
            .map(function (option) {
                return (
                    `<button type="button" class="btn btn-outline-secondary time-picker-option js-time-picker-option" data-time-value="${option.value}">` +
                    `${option.label}</button>`
                );
            })
            .join('');
    }

    function updateFieldLabel(fieldEl, value, explicitLabel) {
        const labelEl = getFieldLabel(fieldEl);
        if (!labelEl) return;

        if (!value) {
            labelEl.textContent = emptyLabelForField(fieldEl);
            labelEl.classList.add('app-muted');
            return;
        }

        labelEl.textContent = explicitLabel || value;
        labelEl.classList.remove('app-muted');
    }

    function highlightSelectedOption(modalEl, value) {
        if (!modalEl) return;

        modalEl.querySelectorAll('.js-time-picker-option').forEach(function (optionEl) {
            const isSelected = value && optionEl.dataset.timeValue === value;
            optionEl.classList.toggle('active', Boolean(isSelected));
            optionEl.classList.toggle('btn-primary', Boolean(isSelected));
            optionEl.classList.toggle('btn-outline-secondary', !isSelected);
        });
    }

    function applyTimeValue(fieldEl, value, labelText) {
        const inputEl = getFieldInput(fieldEl);
        if (!inputEl || inputEl.disabled) return;

        const previousValue = inputEl.value || '';
        const nextValue = value || '';

        updateFieldLabel(fieldEl, nextValue, labelText);
        if (previousValue === nextValue) return;

        inputEl.value = nextValue;
        inputEl.dispatchEvent(new Event('input', { bubbles: true }));
        if (window.htmx && typeof window.htmx.trigger === 'function') {
            window.htmx.trigger(inputEl, 'change');
        } else {
            inputEl.dispatchEvent(new Event('change', { bubbles: true }));
        }
    }

    function syncFieldControls(fieldEl) {
        if (!(fieldEl instanceof HTMLElement)) return;

        const inputEl = getFieldInput(fieldEl);
        if (!inputEl) return;

        const triggerEl = fieldEl.querySelector('.js-time-picker-trigger');
        const stepDownEl = getStepDownButton(fieldEl);
        const stepUpEl = getStepUpButton(fieldEl);
        const isFieldDisabled = Boolean(inputEl.disabled);
        const options = buildFieldOptions(fieldEl, getModalElement());
        const currentValue = inputEl.value || '';
        const selectedIndex = options.findIndex(function (option) {
            return option.value === currentValue;
        });
        const hasSelection = selectedIndex >= 0;

        if (triggerEl) triggerEl.disabled = isFieldDisabled;
        if (stepDownEl) stepDownEl.disabled = isFieldDisabled || !hasSelection || selectedIndex === 0;
        if (stepUpEl) stepUpEl.disabled = isFieldDisabled || !hasSelection || selectedIndex === options.length - 1;
    }

    function stepFieldValue(fieldEl, direction) {
        if (!(fieldEl instanceof HTMLElement)) return;

        const inputEl = getFieldInput(fieldEl);
        if (!inputEl || inputEl.disabled) return;

        const options = buildFieldOptions(fieldEl, getModalElement());
        const currentValue = inputEl.value || '';
        const selectedIndex = options.findIndex(function (option) {
            return option.value === currentValue;
        });
        if (selectedIndex < 0) {
            syncFieldControls(fieldEl);
            return;
        }

        const nextIndex = selectedIndex + direction;
        if (nextIndex < 0 || nextIndex >= options.length) {
            syncFieldControls(fieldEl);
            return;
        }

        const nextOption = options[nextIndex];
        applyTimeValue(fieldEl, nextOption.value, nextOption.label);
        syncFieldControls(fieldEl);
    }

    document.addEventListener('click', function (event) {
        const triggerEl = event.target.closest('.js-time-picker-trigger');
        if (!triggerEl) return;
        if (triggerEl.disabled) return;

        const fieldEl = triggerEl.closest('[data-time-picker-field]');
        const inputEl = getFieldInput(fieldEl);
        if (!fieldEl || !inputEl || inputEl.disabled) return;

        const modalEl = getModalElement();
        const bootstrapModal = getBootstrapModal(modalEl);
        if (!modalEl || !bootstrapModal) return;

        activeField = fieldEl;
        renderOptions(modalEl, fieldEl);
        highlightSelectedOption(modalEl, inputEl.value || '');
        bootstrapModal.show();
    });

    document.addEventListener('click', function (event) {
        const stepDownEl = event.target.closest('.js-time-picker-step-down');
        if (!stepDownEl) return;
        if (stepDownEl.disabled) return;

        const fieldEl = stepDownEl.closest('[data-time-picker-field]');
        stepFieldValue(fieldEl, -1);
    });

    document.addEventListener('click', function (event) {
        const stepUpEl = event.target.closest('.js-time-picker-step-up');
        if (!stepUpEl) return;
        if (stepUpEl.disabled) return;

        const fieldEl = stepUpEl.closest('[data-time-picker-field]');
        stepFieldValue(fieldEl, 1);
    });

    document.addEventListener('click', function (event) {
        const optionEl = event.target.closest('.js-time-picker-option');
        if (!optionEl) return;
        if (!activeField) return;

        const modalEl = getModalElement();
        const value = optionEl.dataset.timeValue || '';
        const labelText = optionEl.textContent ? optionEl.textContent.trim() : value;

        applyTimeValue(activeField, value, labelText);
        highlightSelectedOption(modalEl, value);
        syncFieldControls(activeField);
        hideTimePickerModal(modalEl);
    });

    document.addEventListener('click', function (event) {
        const clearButton = event.target.closest('.js-time-picker-clear');
        if (!clearButton) return;
        if (!activeField) return;

        const modalEl = getModalElement();

        applyTimeValue(activeField, '', emptyLabelForField(activeField));
        highlightSelectedOption(modalEl, '');
        syncFieldControls(activeField);
        hideTimePickerModal(modalEl);
    });

    document.addEventListener('hidden.bs.modal', function (event) {
        const modalEl = event.target;
        if (!(modalEl instanceof HTMLElement)) return;
        if (modalEl.id !== modalId) return;

        activeField = null;
    });

    function syncFieldLabelsWithin(root) {
        if (!(root instanceof Element || root instanceof Document)) return;

        const fieldsToSync = new Set();

        if (root instanceof Element) {
            if (root.matches('[data-time-picker-field]')) {
                fieldsToSync.add(root);
            }

            const closestField = root.closest('[data-time-picker-field]');
            if (closestField instanceof HTMLElement) {
                fieldsToSync.add(closestField);
            }
        }

        root.querySelectorAll('[data-time-picker-field]').forEach(function (fieldEl) {
            fieldsToSync.add(fieldEl);
        });

        fieldsToSync.forEach(function (fieldEl) {
            const inputEl = getFieldInput(fieldEl);
            if (!inputEl) return;
            const modalEl = getModalElement();
            const selectedOption = findOptionByValue(modalEl, inputEl.value || '');
            const selectedLabel = selectedOption ? selectedOption.textContent.trim() : displayLabelFromValue(inputEl.value);
            updateFieldLabel(fieldEl, inputEl.value || '', selectedLabel);
            syncFieldControls(fieldEl);
        });
    }

    document.addEventListener('app:page-ready', function (event) {
        syncFieldLabelsWithin((event.detail && event.detail.target) || document);
    });

    document.addEventListener('time-picker:sync', function (event) {
        syncFieldLabelsWithin((event.detail && event.detail.target) || document);
    });

})();

// Client-side sorting for the compact roster staff table.
(function enableRosterStaffPanelSorting() {
    if (typeof window === 'undefined') return;

    function compareText(leftValue, rightValue) {
        return leftValue.localeCompare(rightValue, undefined, { sensitivity: 'base' });
    }

    function compareNumber(leftValue, rightValue) {
        return leftValue - rightValue;
    }

    function parseNumber(value) {
        const parsed = Number.parseInt(value || '0', 10);
        return Number.isFinite(parsed) ? parsed : 0;
    }

    function compareRows(leftRow, rightRow, key, direction) {
        const directionMultiplier = direction === 'descending' ? -1 : 1;

        if (key === 'shifts') {
            const assignedResult =
                compareNumber(
                    parseNumber(leftRow.dataset.rosterStaffAssigned),
                    parseNumber(rightRow.dataset.rosterStaffAssigned),
                ) * directionMultiplier;
            if (assignedResult !== 0) return assignedResult;

            const idealResult =
                compareNumber(
                    parseNumber(leftRow.dataset.rosterStaffIdeal),
                    parseNumber(rightRow.dataset.rosterStaffIdeal),
                ) * directionMultiplier;
            if (idealResult !== 0) return idealResult;

            return compareText(
                leftRow.dataset.rosterStaffName || '',
                rightRow.dataset.rosterStaffName || '',
            );
        }

        if (key === 'role') {
            const roleResult =
                compareText(
                    leftRow.dataset.rosterStaffRole || '',
                    rightRow.dataset.rosterStaffRole || '',
                ) * directionMultiplier;
            if (roleResult !== 0) return roleResult;

            return compareText(
                leftRow.dataset.rosterStaffName || '',
                rightRow.dataset.rosterStaffName || '',
            );
        }

        return compareText(
            leftRow.dataset.rosterStaffName || '',
            rightRow.dataset.rosterStaffName || '',
        ) * directionMultiplier;
    }

    function syncSortButtonStates(tableEl, activeKey, direction) {
        tableEl.querySelectorAll('[data-roster-staff-sort-key]').forEach(function (buttonEl) {
            if (!(buttonEl instanceof HTMLButtonElement)) return;

            const isActive = buttonEl.dataset.rosterStaffSortKey === activeKey;
            buttonEl.setAttribute('aria-sort', isActive ? direction : 'none');

            const headerCell = buttonEl.closest('th');
            if (headerCell instanceof HTMLTableCellElement) {
                headerCell.setAttribute('aria-sort', isActive ? direction : 'none');
            }
        });
    }

    function sortRosterStaffTable(tableEl, key, direction) {
        const tbodyEl = tableEl.querySelector('.roster-staff-table-body');
        if (!(tbodyEl instanceof HTMLTableSectionElement)) return;

        const rows = Array.from(tbodyEl.querySelectorAll('.roster-staff-panel-entry'));
        rows.sort(function (leftRow, rightRow) {
            return compareRows(leftRow, rightRow, key, direction);
        });
        rows.forEach(function (rowEl) {
            tbodyEl.appendChild(rowEl);
        });

        tableEl.dataset.rosterStaffSortKey = key;
        tableEl.dataset.rosterStaffSortDirection = direction;
        syncSortButtonStates(tableEl, key, direction);
    }

    function nextDirection(tableEl, key) {
        const currentKey = tableEl.dataset.rosterStaffSortKey || '';
        const currentDirection = tableEl.dataset.rosterStaffSortDirection || 'none';

        if (currentKey === key && currentDirection === 'ascending') {
            return 'descending';
        }

        return 'ascending';
    }

    function initRosterStaffPanelSortingWithin(root) {
        if (!(root instanceof Element || root instanceof Document)) return;

        root.querySelectorAll('.roster-staff-table').forEach(function (tableEl) {
            if (!(tableEl instanceof HTMLTableElement)) return;

            const defaultKey = tableEl.dataset.rosterStaffSortKey || 'name';
            const defaultDirection = tableEl.dataset.rosterStaffSortDirection || 'ascending';
            sortRosterStaffTable(tableEl, defaultKey, defaultDirection);
        });
    }

    document.addEventListener('click', function (event) {
        const buttonEl = event.target.closest('[data-roster-staff-sort-key]');
        if (!(buttonEl instanceof HTMLButtonElement)) return;

        const tableEl = buttonEl.closest('.roster-staff-table');
        if (!(tableEl instanceof HTMLTableElement)) return;

        const key = buttonEl.dataset.rosterStaffSortKey || 'name';
        const direction = nextDirection(tableEl, key);
        sortRosterStaffTable(tableEl, key, direction);
    });

    document.addEventListener('app:page-ready', function (event) {
        initRosterStaffPanelSortingWithin((event.detail && event.detail.target) || document);
    });
})();

// Toggle break-time controls based on the "Had break" checkbox.
(function enableBreakTimeToggle() {
    if (typeof window === 'undefined') return;

    function syncBreakToggle(checkboxEl) {
        const targetSelector = checkboxEl.dataset.breakTarget;
        if (!targetSelector) return;

        const targetEl = document.querySelector(targetSelector);
        if (!targetEl) return;

        const isEnabled = checkboxEl.checked;
        targetEl.hidden = !isEnabled;
        targetEl.querySelectorAll('.js-time-picker-input, .js-time-picker-trigger, .js-time-picker-step-down, .js-time-picker-step-up').forEach(function (element) {
            element.disabled = !isEnabled;
        });
        document.dispatchEvent(new CustomEvent('time-picker:sync', { detail: { target: targetEl } }));
    }

    document.addEventListener('change', function (event) {
        const checkboxEl = event.target.closest('[data-break-toggle="true"]');
        if (!checkboxEl) return;
        syncBreakToggle(checkboxEl);
    });

    function syncAllBreakTogglesWithin(root) {
        if (!(root instanceof Element || root instanceof Document)) return;

        root.querySelectorAll('[data-break-toggle="true"]').forEach(function (checkboxEl) {
            syncBreakToggle(checkboxEl);
        });
    }

    document.addEventListener('app:page-ready', function (event) {
        syncAllBreakTogglesWithin((event.detail && event.detail.target) || document);
    });
})();
