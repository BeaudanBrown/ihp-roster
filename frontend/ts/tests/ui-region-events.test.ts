import { fragmentDomAttr, regionRequestStartEvent, regionBeforeSwapEvent, regionAfterSwapEvent, regionSettleEvent, regionErrorEvent } from "../generated/contracts";
import { enableHtmxUiRegionEventAdapter } from "../fragments/htmx-adapter";
import type { UiRegionLifecycleDetail } from "../fragments/events";
import { assertEqual, test } from "./harness";

function htmxEvent(name: string, detail: Record<string, unknown>): Event {
    return new CustomEvent(name, { bubbles: true, detail });
}

test("HTMX region adapter emits normalized Bepis events only for marked fragments", () => {
    if (typeof document === "undefined") return;

    const region = document.createElement("section");
    region.setAttribute(fragmentDomAttr, "true");
    const source = document.createElement("button");
    region.appendChild(source);
    document.body.appendChild(region);

    const plain = document.createElement("section");
    const plainButton = document.createElement("button");
    plain.appendChild(plainButton);
    document.body.appendChild(plain);

    const seen: UiRegionLifecycleDetail[] = [];
    const disable = enableHtmxUiRegionEventAdapter(document);
    try {
        document.addEventListener(regionRequestStartEvent, (event) => {
            seen.push((event as CustomEvent<UiRegionLifecycleDetail>).detail);
        });

        source.dispatchEvent(htmxEvent("htmx:beforeRequest", { elt: source }));
        plainButton.dispatchEvent(htmxEvent("htmx:beforeRequest", { elt: plainButton }));
    } finally {
        disable();
        region.remove();
        plain.remove();
    }

    assertEqual(seen.length, 1);
    assertEqual(seen[0]?.lifecycleEvent, regionRequestStartEvent);
    assertEqual(seen[0]?.htmxEventName, "htmx:beforeRequest");
    assertEqual(seen[0]?.region, region);
    assertEqual(seen[0]?.source, source);
    assertEqual(seen[0]?.target, null);
});

test("HTMX region adapter uses the connected replacement when detail.target is detached", () => {
    if (typeof document === "undefined") return;

    const oldRegion = document.createElement("section");
    oldRegion.setAttribute(fragmentDomAttr, "true");
    const oldTarget = document.createElement("div");
    oldRegion.appendChild(oldTarget);

    const replacementRegion = document.createElement("section");
    replacementRegion.setAttribute(fragmentDomAttr, "true");
    const replacementTarget = document.createElement("div");
    replacementRegion.appendChild(replacementTarget);
    document.body.appendChild(replacementRegion);

    const seen: UiRegionLifecycleDetail[] = [];
    const disable = enableHtmxUiRegionEventAdapter(document);
    const record = (event: Event) => {
        seen.push((event as CustomEvent<UiRegionLifecycleDetail>).detail);
    };
    try {
        document.addEventListener(regionAfterSwapEvent, record, { once: true });
        replacementTarget.dispatchEvent(htmxEvent("htmx:afterSwap", { target: oldTarget }));
    } finally {
        disable();
        replacementRegion.remove();
    }

    assertEqual(seen[0]?.region, replacementRegion);
    assertEqual(seen[0]?.target, replacementTarget);
});

test("HTMX region adapter normalizes swap and error lifecycle details", () => {
    if (typeof document === "undefined") return;

    const region = document.createElement("section");
    region.setAttribute(fragmentDomAttr, "true");
    const target = document.createElement("div");
    region.appendChild(target);
    document.body.appendChild(region);

    const phases: string[] = [];
    const errorKinds: Array<string | undefined> = [];
    const disable = enableHtmxUiRegionEventAdapter(document);
    const record = (event: Event) => {
        const detail = (event as CustomEvent<UiRegionLifecycleDetail>).detail;
        phases.push(detail.lifecycleEvent);
        errorKinds.push(detail.errorKind);
        assertEqual(detail.region, region);
        assertEqual(detail.target, target);
    };

    try {
        document.addEventListener(regionBeforeSwapEvent, record);
        document.addEventListener(regionAfterSwapEvent, record);
        document.addEventListener(regionSettleEvent, record);
        document.addEventListener(regionErrorEvent, record);

        target.dispatchEvent(htmxEvent("htmx:beforeSwap", { target }));
        target.dispatchEvent(htmxEvent("htmx:afterSwap", { target }));
        target.dispatchEvent(htmxEvent("htmx:afterSettle", { target }));
        target.dispatchEvent(htmxEvent("htmx:timeout", { target }));
    } finally {
        disable();
        region.remove();
    }

    assertEqual(phases.join(","), [
        regionBeforeSwapEvent,
        regionAfterSwapEvent,
        regionSettleEvent,
        regionErrorEvent,
    ].join(","));
    assertEqual(errorKinds[3], "timeout");
});
