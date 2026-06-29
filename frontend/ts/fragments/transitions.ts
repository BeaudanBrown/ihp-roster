import { UiRegionDom, UiRegionEvents, isUiRegionTransitionProfile, type UiRegionTransitionProfile } from "../generated/contracts";
import type { UiRegionLifecycleDetail } from "./events";

export type RegionTransitionPhase = "before-swap" | "after-swap";

const transitionProfiles: UiRegionTransitionProfile[] = ["fade", "fade-slide", "panel"];
const transitionPhaseClasses = ["app-region-transition-before-swap", "app-region-transition-after-swap"];
const transitionProfileClasses = transitionProfiles.map((profile) => regionTransitionProfileClass(profile));

export function regionTransitionProfile(region: HTMLElement): UiRegionTransitionProfile {
    const rawProfile = region.getAttribute(UiRegionDom.transition);
    return isUiRegionTransitionProfile(rawProfile) ? rawProfile : "none";
}

export function regionTransitionProfileClass(profile: UiRegionTransitionProfile): string {
    return `app-region-transition-${profile}`;
}

export function prefersReducedMotion(): boolean {
    if (typeof window === "undefined" || typeof window.matchMedia !== "function") return false;
    return window.matchMedia("(prefers-reduced-motion: reduce)").matches;
}

export function shouldAnimateRegionTransition(profile: UiRegionTransitionProfile, reducedMotion = prefersReducedMotion()): boolean {
    return profile !== "none" && !reducedMotion;
}

export function clearRegionTransitionClasses(region: HTMLElement): void {
    region.classList.remove("app-region-transition", ...transitionProfileClasses, ...transitionPhaseClasses);
}

export function applyRegionTransitionPhase(region: HTMLElement, phase: RegionTransitionPhase, reducedMotion = prefersReducedMotion()): boolean {
    const profile = regionTransitionProfile(region);
    clearRegionTransitionClasses(region);
    if (!shouldAnimateRegionTransition(profile, reducedMotion)) return false;

    region.classList.add(
        "app-region-transition",
        regionTransitionProfileClass(profile),
        `app-region-transition-${phase}`,
    );
    return true;
}

function lifecycleDetail(event: Event): UiRegionLifecycleDetail | null {
    if (typeof CustomEvent === "undefined" || !(event instanceof CustomEvent)) return null;
    const detail = event.detail;
    if (detail === null || typeof detail !== "object") return null;
    const record = detail as Partial<UiRegionLifecycleDetail>;
    return record.region instanceof HTMLElement ? (record as UiRegionLifecycleDetail) : null;
}

export function enableUiRegionTransitions(root: Document = document): () => void {
    const onBeforeSwap = (event: Event) => {
        const detail = lifecycleDetail(event);
        if (detail === null) return;
        applyRegionTransitionPhase(detail.region, "before-swap");
    };
    const onAfterSwap = (event: Event) => {
        const detail = lifecycleDetail(event);
        if (detail === null) return;
        applyRegionTransitionPhase(detail.region, "after-swap");
    };
    const onDone = (event: Event) => {
        const detail = lifecycleDetail(event);
        if (detail === null) return;
        clearRegionTransitionClasses(detail.region);
    };

    root.addEventListener(UiRegionEvents.beforeSwap, onBeforeSwap);
    root.addEventListener(UiRegionEvents.afterSwap, onAfterSwap);
    root.addEventListener(UiRegionEvents.settle, onDone);
    root.addEventListener(UiRegionEvents.error, onDone);

    return function disableUiRegionTransitions(): void {
        root.removeEventListener(UiRegionEvents.beforeSwap, onBeforeSwap);
        root.removeEventListener(UiRegionEvents.afterSwap, onAfterSwap);
        root.removeEventListener(UiRegionEvents.settle, onDone);
        root.removeEventListener(UiRegionEvents.error, onDone);
    };
}
