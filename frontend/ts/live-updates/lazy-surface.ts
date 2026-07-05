import { lazySurfaceDomAttr, lazyRetryDomAttr, regionRequestStartEvent, regionErrorEvent } from "../generated/contracts";
import type { UiRegionLifecycleDetail } from "../fragments/events";
import { closestHTMLElement, isHTMLElement } from "../shared/dom";

export const lazySurfaceSelector = `[${lazySurfaceDomAttr}="true"]`;
export const lazySurfaceRetrySelector = `[${lazySurfaceDomAttr}="true"][${lazyRetryDomAttr}="true"]`;

function customEventDetail(event: Event): UiRegionLifecycleDetail | null {
    if (typeof CustomEvent === "undefined" || !(event instanceof CustomEvent)) return null;
    const detail = event.detail;
    if (detail === null || typeof detail !== "object") return null;
    const record = detail as Partial<UiRegionLifecycleDetail>;
    return isHTMLElement(record.region) ? (record as UiRegionLifecycleDetail) : null;
}

export function lazySurfaceFromEvent(event: Event): HTMLElement | null {
    const detail = customEventDetail(event);
    if (detail !== null) {
        if (detail.region.matches(lazySurfaceSelector)) return detail.region;
        return closestHTMLElement(detail.region, lazySurfaceSelector);
    }

    return closestHTMLElement(event.target, lazySurfaceSelector);
}

export function lazyRetrySurfaceFromEvent(event: Event): HTMLElement | null {
    const surface = lazySurfaceFromEvent(event);
    if (surface === null) return null;
    return surface.matches(lazySurfaceRetrySelector) ? surface : null;
}

export function markLazySurfaceLoading(surface: HTMLElement): void {
    surface.classList.remove("app-lazy-surface-error");
    surface.setAttribute("aria-busy", "true");
}

export function renderLazySurfaceError(surface: HTMLElement, message = "We couldn't load this section."): void {
    const retryUrl = surface.getAttribute("hx-get") || surface.getAttribute("data-hx-get") || "";

    surface.classList.add("app-lazy-surface-error");
    surface.setAttribute("aria-busy", "false");

    const body = document.createElement("div");
    body.className = "app-lazy-surface-error-body";

    const text = document.createElement("p");
    text.className = "app-lazy-surface-error-message";
    text.textContent = message;
    body.appendChild(text);

    const retryButton = document.createElement("button");
    retryButton.type = "button";
    retryButton.className = "btn btn-sm btn-outline-light app-lazy-surface-retry";
    retryButton.textContent = "Retry";
    retryButton.setAttribute("hx-get", retryUrl);
    retryButton.setAttribute("hx-target", `closest ${lazySurfaceSelector}`);
    retryButton.setAttribute("hx-swap", "outerHTML");
    retryButton.setAttribute("hx-push-url", "false");
    body.appendChild(retryButton);

    surface.replaceChildren(body);
    window.htmx?.process?.(surface);
}

export function lazySurfaceErrorMessage(event: Event): string {
    const detail = customEventDetail(event);
    return detail?.errorKind === "timeout"
        ? "This section took too long to load."
        : "We couldn't load this section.";
}

export function enableLazySurfaceErrorHandling(root: Document = document): () => void {
    const onRequestStart = function (event: Event) {
        const surface = lazySurfaceFromEvent(event);
        if (surface === null) return;
        markLazySurfaceLoading(surface);
    };
    const onRegionError = function (event: Event) {
        const surface = lazyRetrySurfaceFromEvent(event);
        if (surface === null) return;
        renderLazySurfaceError(surface, lazySurfaceErrorMessage(event));
    };

    root.addEventListener(regionRequestStartEvent, onRequestStart);
    root.addEventListener(regionErrorEvent, onRegionError);

    return function disableLazySurfaceErrorHandling(): void {
        root.removeEventListener(regionRequestStartEvent, onRequestStart);
        root.removeEventListener(regionErrorEvent, onRegionError);
    };
}
