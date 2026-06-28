import { closestHTMLElement, isHTMLElement } from "../shared/dom";
import { detailTarget } from "../shared/lifecycle";

export const lazySurfaceSelector = '[data-bepis-lazy-surface="true"]';

export function lazySurfaceFromEvent(event: Event): HTMLElement | null {
    const elt = detailTarget(event, "elt");
    if (isHTMLElement(elt)) {
        if (elt.matches(lazySurfaceSelector)) return elt;
        const closest = elt.closest(lazySurfaceSelector);
        return isHTMLElement(closest) ? closest : null;
    }

    return closestHTMLElement(event.target, lazySurfaceSelector);
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

export function enableLazySurfaceErrorHandling(root: Document = document): void {
    root.addEventListener("htmx:beforeRequest", function (event) {
        const surface = lazySurfaceFromEvent(event);
        if (surface === null) return;
        markLazySurfaceLoading(surface);
    });

    root.addEventListener("htmx:responseError", function (event) {
        const surface = lazySurfaceFromEvent(event);
        if (surface === null) return;
        renderLazySurfaceError(surface);
    });

    root.addEventListener("htmx:sendError", function (event) {
        const surface = lazySurfaceFromEvent(event);
        if (surface === null) return;
        renderLazySurfaceError(surface);
    });

    root.addEventListener("htmx:timeout", function (event) {
        const surface = lazySurfaceFromEvent(event);
        if (surface === null) return;
        renderLazySurfaceError(surface, "This section took too long to load.");
    });
}
