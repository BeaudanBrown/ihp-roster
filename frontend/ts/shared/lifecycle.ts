import { type DomRoot, rootFromTarget } from "./dom";

export type HtmxDetailKey = "target" | "elt";

function eventDetailRecord(event: Event): Record<string, unknown> | null {
    if (typeof CustomEvent === "undefined" || !(event instanceof CustomEvent)) return null;
    if (event.detail === null || typeof event.detail !== "object") return null;
    return event.detail as Record<string, unknown>;
}

export function detailTarget(event: Event, key: HtmxDetailKey): unknown {
    return eventDetailRecord(event)?.[key];
}

export function detailRoot(event: Event, key: HtmxDetailKey, fallback: DomRoot = document): DomRoot {
    return rootFromTarget(detailTarget(event, key), fallback);
}

export function onAppPageReady(handler: (event: Event) => void): void {
    if (typeof document === "undefined") return;
    document.addEventListener("app:page-ready", handler);
}

export function onHtmxLoad(handler: (event: Event) => void): void {
    if (typeof document === "undefined") return;
    document.addEventListener("htmx:load", handler);
}
