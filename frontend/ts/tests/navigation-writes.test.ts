import { navigationWriteBarrierDomAttr } from "../generated/contracts";
import { enableNavigationWriteBarrier } from "../fragments/navigation-writes";
import { assertEqual, test } from "./harness";

function event(root: EventTarget, name: string, detail: object): Event {
    const event = new Event(name, { cancelable: true });
    Object.defineProperty(event, "detail", { value: detail });
    root.dispatchEvent(event);
    return event;
}
function target(guarded = true): HTMLElement {
    return { isConnected: true, getAttribute: (name: string) => guarded && name === navigationWriteBarrierDomAttr ? "true" : null } as unknown as HTMLElement;
}

test("navigation waits for every write, retaining only the latest choice", async () => {
    const root = new EventTarget();
    const stop = enableNavigationWriteBarrier(root as Document);
    const destination = target(), source = target();
    const first = new EventTarget(), second = new EventTarget();
    for (const xhr of [first, second]) event(root, "htmx:beforeSend", { xhr, requestConfig: { verb: "post" } });
    let choice = 0;
    for (const value of [1, 2]) {
        const request = event(root, "htmx:confirm", { verb: "get", target: destination, elt: source, issueRequest: () => { choice = value; } });
        assertEqual(request.defaultPrevented, true);
    }
    first.dispatchEvent(new Event("loadend"));
    await Promise.resolve();
    assertEqual(choice, 0);
    second.dispatchEvent(new Event("loadend"));
    await Promise.resolve();
    assertEqual(choice, 2);
    first.dispatchEvent(new Event("loadend"));
    await Promise.resolve();
    assertEqual(choice, 2);
    stop();
});

test("writes abort only guarded reads and unrelated read targets stay concurrent", () => {
    const root = new EventTarget();
    const stop = enableNavigationWriteBarrier(root as Document);
    let aborted = 0;
    const xhr = Object.assign(new EventTarget(), { abort: () => { aborted++; xhr.dispatchEvent(new Event("loadend")); } });
    event(root, "htmx:beforeSend", { xhr, target: target(), requestConfig: { verb: "get" } });
    event(root, "htmx:confirm", { verb: "post" });
    assertEqual(aborted, 1);
    event(root, "htmx:beforeSend", { xhr: new EventTarget(), requestConfig: { verb: "post" } });
    assertEqual(event(root, "htmx:confirm", { verb: "get", target: target(false) }).defaultPrevented, false);
    stop();
});

test("queued HTMX writes start before the held navigation is released", async () => {
    const root = new EventTarget();
    const stop = enableNavigationWriteBarrier(root as Document);
    const first = new EventTarget(), queued = new EventTarget();
    let resumed = 0;
    event(root, "htmx:beforeSend", { xhr: first, requestConfig: { verb: "post" } });
    event(root, "htmx:confirm", { verb: "get", target: target(), elt: target(), issueRequest: () => { resumed++; } });
    first.dispatchEvent(new Event("loadend"));
    event(root, "htmx:beforeSend", { xhr: queued, requestConfig: { verb: "post" } });
    await Promise.resolve();
    assertEqual(resumed, 0);
    queued.dispatchEvent(new Event("loadend"));
    await Promise.resolve();
    assertEqual(resumed, 1);
    stop();
});

test("detached navigation and stopped barriers never resume stale requests", async () => {
    const root = new EventTarget();
    const stop = enableNavigationWriteBarrier(root as Document);
    const xhr = new EventTarget();
    const source = target();
    Object.defineProperty(source, "isConnected", { value: false });
    let resumed = 0;
    event(root, "htmx:beforeSend", { xhr, requestConfig: { verb: "post" } });
    event(root, "htmx:confirm", { verb: "get", target: target(), elt: source, issueRequest: () => { resumed++; } });
    xhr.dispatchEvent(new Event("loadend"));
    await Promise.resolve();
    assertEqual(resumed, 0);
    stop();
});
