import { pageReadyEvent } from "./generated/contracts";
import { isDocument, isHTMLElement } from "./shared/dom";
import { detailRoot, detailTarget } from "./shared/lifecycle";

export const appPageReadyEventName = pageReadyEvent;

export type PageReadyDetailInput = unknown;

export type PageReadyDetail = {
    source: string;
    isFullPage: boolean;
};

function detailRecord(detail: PageReadyDetailInput): Record<string, unknown> {
    return detail !== null && typeof detail === "object" ? detail as Record<string, unknown> : {};
}

export function pageReadyDetailFrom(detail: PageReadyDetailInput): PageReadyDetail {
    const record = detailRecord(detail);
    const source = record.source;
    return {
        source: typeof source === "string" && source !== "" ? source : "unknown",
        isFullPage: Boolean(record.isFullPage),
    };
}

(function enableAppPageLifecycle() {
    if (typeof window === "undefined") return;

    const pageReadyEventName = appPageReadyEventName;

    function normalizeTarget(target: unknown): HTMLElement {
        if (isHTMLElement(target)) return target;
        if (isDocument(target)) return document.body;
        return document.body;
    }

    function dispatchPageReady(detail?: PageReadyDetailInput): void {
        const target = normalizeTarget(detailRecord(detail).target);
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
        const target = normalizeTarget(detailTarget(event, "target"));
        window.htmx?.process?.(target);
    });

    document.addEventListener("DOMContentLoaded", function () {
        dispatchPageReady({
            source: "dom-content-loaded",
            target: document.body,
            isFullPage: true,
        });
    });

    document.addEventListener("htmx:afterSwap", function (event) {
        dispatchPageReady({
            source: "htmx-after-swap",
            target: detailRoot(event, "target"),
            isFullPage: false,
        });
    });

    document.addEventListener("htmx:oobAfterSwap", function (event) {
        dispatchPageReady({
            source: "htmx-oob-after-swap",
            target: detailRoot(event, "target"),
            isFullPage: false,
        });
    });

    if (document.readyState !== "loading") {
        dispatchPageReady({
            source: "document-ready",
            target: document.body,
            isFullPage: true,
        });
    }
})();

// Keep tracked timer cleanup app-local so dev live reload and any future re-init flows
// can clear stale intervals/timeouts without depending on legacy framework runtime hooks.
(function enableTrackedTimers() {
    if (typeof window === "undefined") return;

    if (!Array.isArray(window.allIntervals)) {
        window.allIntervals = [];
    }
    if (!Array.isArray(window.allTimeouts)) {
        window.allTimeouts = [];
    }

    if (typeof window.unsafeSetInterval !== "function") {
        window.unsafeSetInterval = window.setInterval.bind(window);
    }
    if (typeof window.unsafeSetTimeout !== "function") {
        window.unsafeSetTimeout = window.setTimeout.bind(window);
    }

    if (window.setInterval !== trackedSetInterval) {
        window.setInterval = trackedSetInterval;
    }
    if (window.setTimeout !== trackedSetTimeout) {
        window.setTimeout = trackedSetTimeout;
    }

    if (typeof window.clearAllIntervals !== "function") {
        window.clearAllIntervals = function clearAllIntervals(): void {
            for (const intervalId of window.allIntervals ?? []) {
                window.clearInterval(intervalId);
            }
            window.allIntervals = [];
        };
    }

    if (typeof window.clearAllTimeouts !== "function") {
        window.clearAllTimeouts = function clearAllTimeouts(): void {
            for (const timeoutId of window.allTimeouts ?? []) {
                window.clearTimeout(timeoutId);
            }
            window.allTimeouts = [];
        };
    }

    function trackedSetInterval(...args: Parameters<Window["setInterval"]>): ReturnType<Window["setInterval"]> {
        const intervalId = window.unsafeSetInterval?.(...args) ?? window.setInterval(...args);
        window.allIntervals?.push(intervalId);
        return intervalId;
    }

    function trackedSetTimeout(...args: Parameters<Window["setTimeout"]>): ReturnType<Window["setTimeout"]> {
        const timeoutId = window.unsafeSetTimeout?.(...args) ?? window.setTimeout(...args);
        window.allTimeouts?.push(timeoutId);
        return timeoutId;
    }
})();
