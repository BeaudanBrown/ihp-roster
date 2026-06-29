import { type UiRegionLifecycleEvent } from "../generated/contracts";

export type UiRegionErrorKind = "response-error" | "send-error" | "timeout";

export type UiRegionLifecycleDetail = {
    lifecycleEvent: UiRegionLifecycleEvent;
    htmxEventName: string;
    region: HTMLElement;
    source: HTMLElement | null;
    target: HTMLElement | null;
    originalEvent: Event;
    errorKind?: UiRegionErrorKind;
};

export function uiRegionEventName(lifecycleEvent: UiRegionLifecycleEvent): string {
    return lifecycleEvent;
}

export function emitUiRegionLifecycleEvent(region: HTMLElement, detail: UiRegionLifecycleDetail): void {
    region.dispatchEvent(new CustomEvent(uiRegionEventName(detail.lifecycleEvent), {
        bubbles: true,
        detail,
    }));
}
