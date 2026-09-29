import { regionRequestStartEvent, regionAfterSwapEvent } from "../generated/contracts";
import type { UiRegionLifecycleDetail } from "./events";
import { htmxRequestDetail } from "./htmx-adapter";
import type { RegionFeedbackPolicy } from "./policy";

const pendingClass = "app-region-pending";
const delayMs = 150;
type PendingRequest = {
    region: HTMLElement;
    policy: RegionFeedbackPolicy;
    visible: boolean;
    timer: ReturnType<typeof setTimeout>;
    dispose: () => void;
};

// Request identity, not terminal-event counts, owns the contribution lifetime.
export function createRegionFeedback(onSharedStatus: (visible: boolean) => void = () => undefined) {
    const pending = new Map<XMLHttpRequest, PendingRequest>();
    const painted = new Set<HTMLElement>();
    function paint(): void {
        const regions = new Set(Array.from(pending.values())
            .filter((entry) => entry.visible && entry.region.isConnected)
            .map((entry) => entry.region));
        for (const region of painted) region.classList.remove(pendingClass);
        painted.clear();
        for (const region of regions) {
            // Only the outermost pending region dims; keep nested text readable.
            if (Array.from(regions).some((other) => other !== region && other.contains(region))) continue;
            region.classList.add(pendingClass);
            painted.add(region);
        }
        onSharedStatus(Array.from(pending.values()).some((entry) =>
            entry.visible && entry.region.isConnected && entry.policy.loading === "shared-status"));
    }
    function finish(xhr: XMLHttpRequest): void {
        const entry = pending.get(xhr);
        if (!entry) return;
        pending.delete(xhr);
        clearTimeout(entry.timer);
        entry.dispose();
        paint();
    }
    return {
        start(xhr: XMLHttpRequest, region: HTMLElement, policy: RegionFeedbackPolicy): void {
            if (pending.has(xhr) || policy.loading === "quiet" || !region.isConnected) return;
            const done = () => finish(xhr);
            xhr.addEventListener("loadend", done);
            const entry: PendingRequest = {
                region, policy, visible: false,
                dispose: () => xhr.removeEventListener("loadend", done),
                timer: setTimeout(() => {
                    if (!entry.region.isConnected) { finish(xhr); return; }
                    entry.visible = true;
                    paint();
                }, delayMs),
            };
            pending.set(xhr, entry);
        },
        finish,
        replace(previous: HTMLElement, next: HTMLElement): void {
            for (const entry of pending.values()) {
                if (entry.region === previous) entry.region = next;
            }
            paint();
        },
        prune(): void {
            for (const [xhr, entry] of pending) if (!entry.region.isConnected) finish(xhr);
        },
        stop(): void {
            for (const xhr of pending.keys()) finish(xhr);
        },
    };
}

export function enableRegionFeedback(root: Document = document, onSharedStatus?: (visible: boolean) => void): () => void {
    const feedback = createRegionFeedback(onSharedStatus);
    const onStart = (event: Event) => {
        const detail = (event as CustomEvent<UiRegionLifecycleDetail>).detail;
        const { xhr } = htmxRequestDetail(detail.originalEvent);
        if (!xhr || !detail.feedbackPolicy) return;
        feedback.start(xhr, detail.region, detail.feedbackPolicy);
        // A later beforeRequest listener may cancel before XHR ever sends.
        queueMicrotask(() => { if (detail.originalEvent.defaultPrevented) feedback.finish(xhr); });
    };
    const onSwap = (event: Event) => {
        const detail = (event as CustomEvent<UiRegionLifecycleDetail>).detail;
        const previous = htmxRequestDetail(detail.originalEvent).target;
        if (previous && previous !== detail.region && previous.id === detail.region.id) {
            feedback.replace(previous, detail.region);
        }
    };
    const onDone = (event: Event) => {
        const { xhr } = htmxRequestDetail(event);
        if (xhr) feedback.finish(xhr);
    };
    const terminalEvents = ["htmx:afterRequest", "htmx:sendAbort", "htmx:sendError", "htmx:timeout", "htmx:swapError", "htmx:onLoadError"];
    root.addEventListener(regionRequestStartEvent, onStart);
    root.addEventListener(regionAfterSwapEvent, onSwap);
    terminalEvents.forEach((name) => root.addEventListener(name, onDone));
    const observer = new MutationObserver(() => feedback.prune());
    observer.observe(root, { childList: true, subtree: true });
    return () => {
        observer.disconnect();
        root.removeEventListener(regionRequestStartEvent, onStart);
        root.removeEventListener(regionAfterSwapEvent, onSwap);
        terminalEvents.forEach((name) => root.removeEventListener(name, onDone));
        feedback.stop();
    };
}
