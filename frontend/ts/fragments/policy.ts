import {
    isUiRegionLoadingPolicy, isUiRegionTransitionProfile,
    regionLoadingDomAttr, regionTransitionDomAttr, regionBackgroundDomAttr,
    type UiRegionLoadingPolicy, type UiRegionTransitionProfile,
} from "../generated/contracts";

export type RegionFeedbackPolicy = {
    loading: UiRegionLoadingPolicy;
    arrival: UiRegionTransitionProfile;
};

// Origins, not request duration, distinguish initial/background work from input.
export function isBackgroundRegionRequest(source: HTMLElement | null, triggeringEvent?: Event): boolean {
    const declaredOrigin = source?.closest(`[${regionBackgroundDomAttr}]`)?.getAttribute(regionBackgroundDomAttr);
    if (declaredOrigin === "true") return true;
    return !triggeringEvent || ["load", "revealed", "intersect", "every"].includes(triggeringEvent.type);
}

export function regionFeedbackPolicy(region: HTMLElement, background: boolean): RegionFeedbackPolicy {
    if (background) return { loading: "quiet", arrival: "none" };
    const loading = region.getAttribute(regionLoadingDomAttr);
    const arrival = region.getAttribute(regionTransitionDomAttr);
    if ((loading !== null && !isUiRegionLoadingPolicy(loading))
        || (arrival !== null && !isUiRegionTransitionProfile(arrival))) {
        console.error("Invalid UI region feedback policy", region);
        return { loading: "quiet", arrival: "none" };
    }
    return { loading: loading ?? "dim", arrival: arrival ?? "fade" };
}
