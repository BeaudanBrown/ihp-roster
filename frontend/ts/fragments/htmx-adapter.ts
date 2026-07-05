import { isUiRegionLifecycleEvent, type UiRegionLifecycleEvent } from "../generated/contracts";
import { isHTMLElement } from "../shared/dom";
import { detailTarget } from "../shared/lifecycle";
import { closestUiRegionFragment } from "./dom";
import { emitUiRegionLifecycleEvent, type UiRegionErrorKind } from "./events";

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
    const target = detailTarget(event, "target");
    return isHTMLElement(target) ? target : null;
}

export function regionFromHtmxEvent(event: Event): HTMLElement | null {
    return closestUiRegionFragment(htmxRegionEventTarget(event))
        || closestUiRegionFragment(htmxRegionEventSource(event))
        || closestUiRegionFragment(event.target);
}

export function dispatchRegionLifecycleFromHtmx(event: Event, spec: HtmxRegionEventSpec): void {
    const region = regionFromHtmxEvent(event);
    if (region === null) return;

    emitUiRegionLifecycleEvent(region, {
        lifecycleEvent: spec.lifecycleEvent,
        htmxEventName: spec.htmxEventName,
        region,
        source: htmxRegionEventSource(event),
        target: htmxRegionEventTarget(event),
        originalEvent: event,
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
