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

    // `show:none` declares that a fragment update must not move the viewport.
    // Keep that promise even when replacing a tall target briefly clamps the
    // browser's scroll position while the old subtree is detached.
    const scrollPreservingRequests = new WeakSet<object>();
    const preservedScrollPositions = new WeakMap<object, { left: number; top: number }>();

    function requestToken(event: Event): object | null {
        const xhr = detailTarget(event, "xhr");
        return xhr !== null && typeof xhr === "object" ? xhr : null;
    }

    function requestDisablesShowScrolling(event: Event): boolean {
        const requestElement = detailTarget(event, "elt");
        if (!(requestElement instanceof Element)) return false;
        const swapOwner = requestElement.closest("[hx-swap]");
        return swapOwner?.getAttribute("hx-swap")?.split(/\s+/).includes("show:none") ?? false;
    }

    document.addEventListener("htmx:beforeRequest", function (event) {
        const token = requestToken(event);
        if (token !== null && requestDisablesShowScrolling(event)) {
            scrollPreservingRequests.add(token);
        }
    });

    document.addEventListener("htmx:beforeSwap", function (event) {
        const token = requestToken(event);
        if (token !== null && scrollPreservingRequests.has(token)) {
            preservedScrollPositions.set(token, { left: window.scrollX, top: window.scrollY });
        }
    });

    function restorePreservedScroll(event: Event, cleanup: boolean): void {
        const token = requestToken(event);
        if (token === null) return;
        const position = preservedScrollPositions.get(token);
        if (position !== undefined) window.scrollTo(position.left, position.top);
        if (cleanup) {
            preservedScrollPositions.delete(token);
            scrollPreservingRequests.delete(token);
        }
    }

    // OOB-only responses do not reliably emit afterSettle. Restore after every
    // completed swap, then repeat/clean up after settle when HTMX emits it.
    document.addEventListener("htmx:afterSwap", (event) => restorePreservedScroll(event, false));
    document.addEventListener("htmx:oobAfterSwap", (event) => restorePreservedScroll(event, false));
    document.addEventListener("htmx:afterSettle", (event) => restorePreservedScroll(event, true));

    for (const eventName of ["htmx:responseError", "htmx:sendError", "htmx:timeout"]) {
        document.addEventListener(eventName, function (event) {
            const token = requestToken(event);
            if (token === null) return;
            preservedScrollPositions.delete(token);
            scrollPreservingRequests.delete(token);
        });
    }

    if (document.readyState !== "loading") {
        dispatchPageReady({
            source: "document-ready",
            target: document.body,
            isFullPage: true,
        });
    }
})();
