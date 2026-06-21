// @ts-nocheck
export const appPageReadyEventName = 'app:page-ready';

export function pageReadyDetailFrom(detail) {
    return {
        source: detail && detail.source ? detail.source : 'unknown',
        isFullPage: Boolean(detail && detail.isFullPage),
    };
}

(function enableAppPageLifecycle() {
    if (typeof window === 'undefined') return;

    const pageReadyEventName = appPageReadyEventName;

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
                ...pageReadyDetailFrom(detail),
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
