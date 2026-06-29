import { UiRegionDom, UiRegionEvents } from "../generated/contracts";
import type { UiRegionLifecycleDetail, UiRegionErrorKind } from "../fragments/events";
import { enableLazySurfaceErrorHandling, lazySurfaceSelector, renderLazySurfaceError } from "../live-updates/lazy-surface";
import { assertEqual, test } from "./harness";

function regionEvent(name: string, region: HTMLElement, errorKind?: UiRegionErrorKind): Event {
    const detail: Partial<UiRegionLifecycleDetail> = {
        lifecycleEvent: name as UiRegionLifecycleDetail["lifecycleEvent"],
        htmxEventName: errorKind === "timeout" ? "htmx:timeout" : "htmx:responseError",
        region,
        source: null,
        target: region,
        originalEvent: new Event("htmx:test"),
        ...(errorKind ? { errorKind } : {}),
    };
    return new CustomEvent(name, { bubbles: true, detail });
}

function lazySurface(): HTMLElement {
    const surface = document.createElement("div");
    surface.setAttribute(UiRegionDom.fragment, "true");
    surface.setAttribute(UiRegionDom.lazySurface, "true");
    surface.setAttribute(UiRegionDom.lazyRetry, "true");
    surface.setAttribute("hx-get", "/lazy-fragment");
    surface.setAttribute("aria-busy", "true");
    return surface;
}

test("lazy surface error renderer exposes reusable retry HTMX markup", () => {
    if (typeof document === "undefined") return;

    const surface = lazySurface();

    let processed = false;
    const originalHtmx = window.htmx;
    window.htmx = { process: () => { processed = true; } };
    try {
        renderLazySurfaceError(surface, "Could not load staff");
    } finally {
        window.htmx = originalHtmx;
    }

    const retry = surface.querySelector("button");
    assertEqual(surface.classList.contains("app-lazy-surface-error"), true);
    assertEqual(surface.getAttribute("aria-busy"), "false");
    assertEqual(surface.querySelector(".app-lazy-surface-error-message")?.textContent, "Could not load staff");
    assertEqual(retry?.getAttribute("hx-get"), "/lazy-fragment");
    assertEqual(retry?.getAttribute("hx-target"), `closest ${lazySurfaceSelector}`);
    assertEqual(retry?.getAttribute("hx-swap"), "outerHTML");
    assertEqual(processed, true);
});

test("lazy surface handling consumes Bepis region request and response-error events", () => {
    if (typeof document === "undefined") return;

    const surface = lazySurface();
    surface.classList.add("app-lazy-surface-error");
    surface.setAttribute("aria-busy", "false");
    document.body.appendChild(surface);

    const disable = enableLazySurfaceErrorHandling(document);
    try {
        surface.dispatchEvent(regionEvent(UiRegionEvents.requestStart, surface));
        assertEqual(surface.classList.contains("app-lazy-surface-error"), false);
        assertEqual(surface.getAttribute("aria-busy"), "true");

        surface.dispatchEvent(regionEvent(UiRegionEvents.error, surface, "response-error"));
        assertEqual(surface.classList.contains("app-lazy-surface-error"), true);
        assertEqual(surface.querySelector(".app-lazy-surface-error-message")?.textContent, "We couldn't load this section.");
    } finally {
        disable();
        surface.remove();
    }
});

test("lazy surface handling covers send errors and timeout copy through region events", () => {
    if (typeof document === "undefined") return;

    const sendErrorSurface = lazySurface();
    const timeoutSurface = lazySurface();
    document.body.append(sendErrorSurface, timeoutSurface);

    const disable = enableLazySurfaceErrorHandling(document);
    try {
        sendErrorSurface.dispatchEvent(regionEvent(UiRegionEvents.error, sendErrorSurface, "send-error"));
        timeoutSurface.dispatchEvent(regionEvent(UiRegionEvents.error, timeoutSurface, "timeout"));

        assertEqual(sendErrorSurface.querySelector(".app-lazy-surface-error-message")?.textContent, "We couldn't load this section.");
        assertEqual(timeoutSurface.querySelector(".app-lazy-surface-error-message")?.textContent, "This section took too long to load.");
    } finally {
        disable();
        sendErrorSurface.remove();
        timeoutSurface.remove();
    }
});

test("lazy surface handling ignores raw HTMX and retry-disabled regions", () => {
    if (typeof document === "undefined") return;

    const surface = lazySurface();
    const retryDisabled = lazySurface();
    retryDisabled.setAttribute(UiRegionDom.lazyRetry, "false");
    document.body.append(surface, retryDisabled);

    const disable = enableLazySurfaceErrorHandling(document);
    try {
        surface.dispatchEvent(new CustomEvent("htmx:responseError", { bubbles: true, detail: { elt: surface } }));
        retryDisabled.dispatchEvent(regionEvent(UiRegionEvents.error, retryDisabled, "response-error"));

        assertEqual(surface.classList.contains("app-lazy-surface-error"), false);
        assertEqual(retryDisabled.classList.contains("app-lazy-surface-error"), false);
    } finally {
        disable();
        surface.remove();
        retryDisabled.remove();
    }
});
