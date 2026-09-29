import { type UiRegionTransitionProfile, regionAfterSwapEvent, regionSettleEvent } from "../generated/contracts";
import type { UiRegionLifecycleDetail } from "./events";

const arrivalClasses = ["app-region-transition", "app-region-transition-fade", "app-region-transition-fade-slide", "app-region-transition-panel", "app-region-transition-after-swap"];

export function prefersReducedMotion(): boolean {
    return typeof window !== "undefined" && typeof window.matchMedia === "function"
        && window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

export function createRegionArrivals() {
    const generations = new WeakMap<HTMLElement, object>();
    const active = new Set<HTMLElement>();
    function clear(region: HTMLElement): void {
        generations.delete(region);
        active.delete(region);
        region.classList.remove(...arrivalClasses);
    }
    return {
        clear,
        start(region: HTMLElement, profile: UiRegionTransitionProfile, reducedMotion = prefersReducedMotion()): void {
            clear(region);
            if (profile === "none" || reducedMotion || !region.isConnected) return;
            const generation = {};
            generations.set(region, generation);
            active.add(region);
            region.classList.add("app-region-transition", `app-region-transition-${profile}`, "app-region-transition-after-swap");
            // CSS owns keyframes and timing. No HTMX-settle-duration or JS timer guesses.
            const animations = typeof region.getAnimations === "function"
                ? region.getAnimations().filter((animation) =>
                    "animationName" in animation && String(animation.animationName).startsWith("app-region-"))
                : [];
            const done = () => { if (generations.get(region) === generation) clear(region); };
            if (!animations.length) done();
            else void Promise.allSettled(animations.map((animation) => animation.finished)).then(done);
        },
        prune(): void { for (const region of active) if (!region.isConnected) clear(region); },
        stop(): void { for (const region of active) clear(region); },
    };
}

export function enableUiRegionTransitions(root: Document = document): () => void {
    const arrivals = createRegionArrivals();
    const replacements = new WeakMap<HTMLElement, Event>();
    const onAfterSwap = (event: Event) => {
        const detail = (event as CustomEvent<UiRegionLifecycleDetail>).detail;
        arrivals.clear(detail.region);
        replacements.set(detail.region, detail.originalEvent);
    };
    const onSettle = (event: Event) => {
        const detail = (event as CustomEvent<UiRegionLifecycleDetail>).detail;
        const swap = replacements.get(detail.region);
        if (!swap) return;
        // A late settle from an older request cannot animate newer content.
        const swapXhr = (swap as CustomEvent).detail?.xhr;
        if (swapXhr !== (detail.originalEvent as CustomEvent).detail?.xhr) return;
        replacements.delete(detail.region);
        // Start after HTMX restores class/style attributes, not before it overwrites
        // our disposable classes. This never delays replacing the response.
        arrivals.start(detail.region, detail.feedbackPolicy?.arrival ?? "none");
    };
    root.addEventListener(regionAfterSwapEvent, onAfterSwap);
    root.addEventListener(regionSettleEvent, onSettle);
    const observer = new MutationObserver(() => arrivals.prune());
    observer.observe(root, { childList: true, subtree: true });
    return () => {
        observer.disconnect();
        root.removeEventListener(regionAfterSwapEvent, onAfterSwap);
        root.removeEventListener(regionSettleEvent, onSettle);
        arrivals.stop();
    };
}
