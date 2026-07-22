import { pageReadyEvent } from "../generated/contracts";
import { type DomRoot, isDomRoot } from "./dom";

export type HtmxDetailKey = "target" | "elt";

function eventDetailRecord(event: Event): Record<string, unknown> | null {
    if (typeof CustomEvent === "undefined" || !(event instanceof CustomEvent)) return null;
    if (event.detail === null || typeof event.detail !== "object") return null;
    return event.detail as Record<string, unknown>;
}

export function detailTarget(event: Event, key: HtmxDetailKey): unknown {
    return eventDetailRecord(event)?.[key];
}

function isConnectedRoot(root: DomRoot): boolean {
    return root instanceof Document || root.isConnected;
}

export function detailRoot(event: Event, key: HtmxDetailKey, fallback: DomRoot = document): DomRoot {
    const detailCandidate = detailTarget(event, key);
    if (isDomRoot(detailCandidate) && isConnectedRoot(detailCandidate)) return detailCandidate;
    if (isDomRoot(event.target) && isConnectedRoot(event.target)) return event.target;
    return fallback;
}

export function onAppPageReady(handler: (event: Event) => void): void {
    if (typeof document === "undefined") return;
    document.addEventListener(pageReadyEvent, handler);
}

export function onHtmxLoad(handler: (event: Event) => void): void {
    if (typeof document === "undefined") return;
    document.addEventListener("htmx:load", handler);
}
