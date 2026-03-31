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

// Keep timer tracking app-local so dev reloads and future partial re-init flows can
// clear stale intervals without depending on removed framework-wide runtime hooks.
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

// Keep flatpickr wiring app-local so native date inputs can opt into enhancement
// on full-page loads and on HTMX-inserted fragments.
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

    document.addEventListener('app:page-ready', function (event) {
        initWithin((event.detail && event.detail.target) || document);
    });
})();

// Shared workflow dialog mount for HTMX-driven overlays.
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

        syncDialogState();
    });

    document.addEventListener('shown.bs.modal', syncDialogState);
    document.addEventListener('hidden.bs.modal', syncDialogState);
    document.addEventListener('app:page-ready', syncDialogState);

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', syncDialogState);
    } else {
        syncDialogState();
    }
})();

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

    if (document.readyState === 'loading') {
        document.addEventListener('DOMContentLoaded', initHostToasts);
    } else {
        initHostToasts();
    }
})();

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
        notifyPageReady(nextNode);
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
    }

    function queueFragment(fragment) {
        const existing = inFlightFragments.get(fragment.targetId);
        if (existing) {
            inFlightFragments.set(fragment.targetId, { next: fragment });
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

        if (fragment.deferUntilBlur && hasFocusedField(target)) {
            pendingDeferredFragments.set(fragment.targetId, fragment);
            return;
        }

        pendingDeferredFragments.delete(fragment.targetId);
        queueFragment(fragment);
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

    document.addEventListener('app:page-ready', syncConnection);
    window.addEventListener('beforeunload', closeSocket);
})();

// Reusable quarter-hour modal time picker.
(function enableQuarterHourTimePicker() {
    if (typeof window === 'undefined') return;

    const modalId = 'quarter-hour-time-picker-modal';
    const emptyLabel = 'Select time';
    let activeField = null;

    function getModalElement() {
        return document.getElementById(modalId);
    }

    function getBootstrapModal(modalEl) {
        if (!modalEl || !window.bootstrap || !window.bootstrap.Modal) return null;
        return window.bootstrap.Modal.getOrCreateInstance(modalEl);
    }

    function getFieldInput(fieldEl) {
        return fieldEl ? fieldEl.querySelector('.js-time-picker-input') : null;
    }

    function getFieldLabel(fieldEl) {
        return fieldEl ? fieldEl.querySelector('.js-time-picker-label') : null;
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

    function buildTimeOptions(range) {
        if (!range) return [];

        const options = [];
        for (let minute = range.startMinute; minute <= range.endMinute; minute += 15) {
            const minuteOfDay = minute % (24 * 60);
            const hour = Math.floor(minuteOfDay / 60);
            const minutePart = minuteOfDay % 60;
            const value = `${String(hour).padStart(2, '0')}:${String(minutePart).padStart(2, '0')}`;
            options.push({ value, label: displayLabelFromValue(value) });
        }
        return options;
    }

    function renderOptions(modalEl, range) {
        if (!modalEl) return;
        const gridEl = modalEl.querySelector('.js-time-picker-grid');
        if (!gridEl) return;

        const options = buildTimeOptions(range);
        gridEl.innerHTML = options
            .map(function (option) {
                return `<button type="button" class="btn btn-outline-secondary time-picker-option js-time-picker-option" data-time-value="${option.value}">${option.label}</button>`;
            })
            .join('');
    }

    function updateFieldLabel(fieldEl, value, explicitLabel) {
        const labelEl = getFieldLabel(fieldEl);
        if (!labelEl) return;

        if (!value) {
            labelEl.textContent = emptyLabel;
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
        inputEl.dispatchEvent(new Event('change', { bubbles: true }));
    }

    function syncFieldLabels(root) {
        if (!(root instanceof HTMLElement || root instanceof Document)) return;

        root.querySelectorAll('[data-time-picker-field]').forEach(function (fieldEl) {
            const inputEl = getFieldInput(fieldEl);
            if (!inputEl) return;
            updateFieldLabel(fieldEl, inputEl.value || '', displayLabelFromValue(inputEl.value));
        });
    }

    document.addEventListener('click', function (event) {
        const triggerEl = event.target.closest('.js-time-picker-trigger');
        if (!triggerEl || triggerEl.disabled) return;

        const fieldEl = triggerEl.closest('[data-time-picker-field]');
        const inputEl = getFieldInput(fieldEl);
        if (!fieldEl || !inputEl || inputEl.disabled) return;

        const modalEl = getModalElement();
        const bootstrapModal = getBootstrapModal(modalEl);
        if (!modalEl || !bootstrapModal) return;

        activeField = fieldEl;
        renderOptions(modalEl, resolveRange(fieldEl, modalEl));
        highlightSelectedOption(modalEl, inputEl.value || '');
        bootstrapModal.show();
    });

    document.addEventListener('click', function (event) {
        const optionEl = event.target.closest('.js-time-picker-option');
        if (!optionEl || !activeField) return;

        const modalEl = getModalElement();
        const bootstrapModal = getBootstrapModal(modalEl);
        const value = optionEl.dataset.timeValue || '';
        const labelText = optionEl.textContent ? optionEl.textContent.trim() : value;

        applyTimeValue(activeField, value, labelText);
        highlightSelectedOption(modalEl, value);
        if (bootstrapModal) bootstrapModal.hide();
    });

    document.addEventListener('click', function (event) {
        const clearButton = event.target.closest('.js-time-picker-clear');
        if (!clearButton || !activeField) return;

        const modalEl = getModalElement();
        const bootstrapModal = getBootstrapModal(modalEl);

        applyTimeValue(activeField, '', emptyLabel);
        highlightSelectedOption(modalEl, '');
        if (bootstrapModal) bootstrapModal.hide();
    });

    document.addEventListener('hidden.bs.modal', function (event) {
        const modalEl = event.target;
        if (!(modalEl instanceof HTMLElement)) return;
        if (modalEl.id !== modalId) return;

        activeField = null;
    });

    document.addEventListener('app:page-ready', function (event) {
        syncFieldLabels((event.detail && event.detail.target) || document);
    });
})();
