import { lazySurfaceSelector, renderLazySurfaceError } from "../live-updates/lazy-surface";
import { assertEqual, test } from "./harness";

test("lazy surface error renderer exposes reusable retry HTMX markup", () => {
    if (typeof document === "undefined") return;

    const surface = document.createElement("div");
    surface.setAttribute("data-bepis-lazy-surface", "true");
    surface.setAttribute("hx-get", "/lazy-fragment");
    surface.setAttribute("aria-busy", "true");

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
