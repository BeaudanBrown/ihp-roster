import { isUiRegionLifecycleEvent, type UiRegionLifecycleEvent } from "../generated/contracts";
import { isHTMLElement } from "../shared/dom";
import { detailRoot, detailTarget } from "../shared/lifecycle";
import { closestUiRegionFragment } from "./dom";
import { emitUiRegionLifecycleEvent, type UiRegionErrorKind } from "./events";
import { isBackgroundRegionRequest, regionFeedbackPolicy, type RegionFeedbackPolicy } from "./policy";

const requestPolicies = new WeakMap<XMLHttpRequest, RegionFeedbackPolicy>();

export function htmxRequestDetail(event: Event): { xhr?: XMLHttpRequest; requestConfig?: { triggeringEvent?: Event }; target?: HTMLElement; elt?: HTMLElement } {
    return (event as CustomEvent).detail ?? {};
}

type HtmxRegionEventSpec = {
    htmxEventName: string;
    lifecycleEvent: UiRegionLifecycleEvent;
    errorKind?: UiRegionErrorKind;
};

function regionLifecycleEvent(value: string): UiRegionLifecycleEvent {
    if (isUiRegionLifecycleEvent(value)) return value;
    throw new Error(`Invalid generated UI region lifecycle event: ${value}`);
}

const htmxRegionEventSpecs: HtmxRegionEventSpec[] = [
    { htmxEventName: "htmx:beforeRequest", lifecycleEvent: regionLifecycleEvent("request-start") },
    { htmxEventName: "htmx:beforeSwap", lifecycleEvent: regionLifecycleEvent("before-swap") },
    { htmxEventName: "htmx:afterSwap", lifecycleEvent: regionLifecycleEvent("after-swap") },
    { htmxEventName: "htmx:afterSettle", lifecycleEvent: regionLifecycleEvent("settle") },
    { htmxEventName: "htmx:responseError", lifecycleEvent: regionLifecycleEvent("error"), errorKind: "response-error" },
    { htmxEventName: "htmx:sendError", lifecycleEvent: regionLifecycleEvent("error"), errorKind: "send-error" },
    { htmxEventName: "htmx:timeout", lifecycleEvent: regionLifecycleEvent("error"), errorKind: "timeout" },
];

export function htmxRegionEventSource(event: Event): HTMLElement | null {
    const source = detailTarget(event, "elt");
    return isHTMLElement(source) ? source : null;
}

export function htmxRegionEventTarget(event: Event): HTMLElement | null {
    const target = detailRoot(event, "target");
    return isHTMLElement(target) ? target : null;
}

export function regionFromHtmxEvent(event: Event): HTMLElement | null {
    const source = htmxRegionEventSource(event);
    // afterSwap/afterSettle carry the old target and the newly inserted elt.
    if (event.type === "htmx:afterSwap" || event.type === "htmx:afterSettle") {
        return closestUiRegionFragment(source?.isConnected ? source : null);
    }
    return closestUiRegionFragment(htmxRegionEventTarget(event));
}

export function dispatchRegionLifecycleFromHtmx(event: Event, spec: HtmxRegionEventSpec): void {
    const region = regionFromHtmxEvent(event);
    if (region === null) return;

    const request = htmxRequestDetail(event);
    if (spec.lifecycleEvent === "request-start" && request.xhr) {
        requestPolicies.set(request.xhr, regionFeedbackPolicy(region,
            isBackgroundRegionRequest(htmxRegionEventSource(event), request.requestConfig?.triggeringEvent)));
    }
    const feedbackPolicy = request.xhr ? requestPolicies.get(request.xhr) : undefined;
    emitUiRegionLifecycleEvent(region, {
        lifecycleEvent: spec.lifecycleEvent,
        htmxEventName: spec.htmxEventName,
        region,
        source: htmxRegionEventSource(event),
        target: htmxRegionEventTarget(event),
        originalEvent: event,
        feedbackPolicy,
        ...(spec.errorKind ? { errorKind: spec.errorKind } : {}),
    });
}

export function enableHtmxUiRegionEventAdapter(root: Document = document): () => void {
    const listeners = htmxRegionEventSpecs.map((spec) => {
        const listener = (event: Event) => dispatchRegionLifecycleFromHtmx(event, spec);
        root.addEventListener(spec.htmxEventName, listener);
        return { spec, listener };
    });

    return function disableHtmxUiRegionEventAdapter(): void {
        listeners.forEach(({ spec, listener }) => root.removeEventListener(spec.htmxEventName, listener));
    };
}
