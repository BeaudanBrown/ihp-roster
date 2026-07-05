import { fragmentDomAttr, regionTransitionDomAttr, regionBeforeSwapEvent, regionAfterSwapEvent, regionSettleEvent } from "../generated/contracts";
import { applyRegionTransitionPhase, clearRegionTransitionClasses, enableUiRegionTransitions, regionTransitionProfile, shouldAnimateRegionTransition } from "../fragments/transitions";
import type { UiRegionLifecycleDetail } from "../fragments/events";
import { assertEqual, test } from "./harness";

function region(profile?: string): HTMLElement {
    const element = document.createElement("section");
    element.setAttribute(fragmentDomAttr, "true");
    if (profile !== undefined) element.setAttribute(regionTransitionDomAttr, profile);
    return element;
}

function lifecycleEvent(name: string, element: HTMLElement): Event {
    const detail: Partial<UiRegionLifecycleDetail> = {
        lifecycleEvent: name as UiRegionLifecycleDetail["lifecycleEvent"],
        htmxEventName: "htmx:test",
        region: element,
        source: null,
        target: element,
        originalEvent: new Event("htmx:test"),
    };
    return new CustomEvent(name, { bubbles: true, detail });
}

test("region transition profile parsing stays generated and conservative", () => {
    if (typeof document === "undefined") return;

    assertEqual(regionTransitionProfile(region()), "none");
    assertEqual(regionTransitionProfile(region("fade")), "fade");
    assertEqual(regionTransitionProfile(region("fade-slide")), "fade-slide");
    assertEqual(regionTransitionProfile(region("panel")), "panel");
    assertEqual(regionTransitionProfile(region("unknown")), "none");
});

test("region transition class decisions respect none and reduced motion", () => {
    if (typeof document === "undefined") return;

    assertEqual(shouldAnimateRegionTransition("fade", false), true);
    assertEqual(shouldAnimateRegionTransition("fade", true), false);
    assertEqual(shouldAnimateRegionTransition("none", false), false);

    const fade = region("fade");
    assertEqual(applyRegionTransitionPhase(fade, "before-swap", false), true);
    assertEqual(fade.classList.contains("app-region-transition"), true);
    assertEqual(fade.classList.contains("app-region-transition-fade"), true);
    assertEqual(fade.classList.contains("app-region-transition-before-swap"), true);

    const reduced = region("panel");
    assertEqual(applyRegionTransitionPhase(reduced, "after-swap", true), false);
    assertEqual(reduced.classList.contains("app-region-transition"), false);

    clearRegionTransitionClasses(fade);
    assertEqual(fade.classList.contains("app-region-transition"), false);
});

test("region transition runtime only responds to Bepis region lifecycle events", () => {
    if (typeof document === "undefined") return;

    const fade = region("fade-slide");
    const unmarked = document.createElement("section");
    document.body.append(fade, unmarked);

    const disable = enableUiRegionTransitions(document);
    try {
        fade.dispatchEvent(new CustomEvent("htmx:beforeSwap", { bubbles: true, detail: { target: fade } }));
        assertEqual(fade.classList.contains("app-region-transition"), false);

        fade.dispatchEvent(lifecycleEvent(regionBeforeSwapEvent, fade));
        assertEqual(fade.classList.contains("app-region-transition-fade-slide"), true);
        assertEqual(fade.classList.contains("app-region-transition-before-swap"), true);

        fade.dispatchEvent(lifecycleEvent(regionAfterSwapEvent, fade));
        assertEqual(fade.classList.contains("app-region-transition-after-swap"), true);

        fade.dispatchEvent(lifecycleEvent(regionSettleEvent, fade));
        assertEqual(fade.classList.contains("app-region-transition"), false);
        assertEqual(unmarked.classList.contains("app-region-transition"), false);
    } finally {
        disable();
        fade.remove();
        unmarked.remove();
    }
});
