import {
    InteractionDom,
    interactionSessionCancelRequestEvent,
    interactionSessionEndEvent,
    interactionSessionStartEvent,
    surfaceConfigDomAttr,
} from "../generated/contracts";
import { createActiveInteractionSessionTracker } from "../interaction/session-state";
import { createLiveFragmentRefresher } from "../live-updates/refresh";
import type { LiveUpdateFragmentWithState } from "../live-updates/runtime-types";
import { assertEqual, test } from "./harness";

type Deferred<T> = {
    promise: Promise<T>;
    resolve(value: T): void;
    reject(error: unknown): void;
};

function deferred<T>(): Deferred<T> {
    let resolve!: (value: T) => void;
    let reject!: (error: unknown) => void;
    const promise = new Promise<T>((resolvePromise, rejectPromise) => {
        resolve = resolvePromise;
        reject = rejectPromise;
    });
    return { promise, resolve, reject };
}

class RefreshTestElement extends EventTarget {
    static activeElement: RefreshTestElement | null = null;
    parentElement: RefreshTestElement | null = null;
    children: RefreshTestElement[] = [];
    id: string;
    readonly tagName: string;
    value: string;
    private readonly attrs = new Map<string, string>();

    constructor(tagName = "div", attrs: Record<string, string> = {}) {
        super();
        this.tagName = tagName.toUpperCase();
        this.id = attrs.id ?? "";
        this.value = attrs.value ?? "";
        Object.entries(attrs).forEach(([name, value]) => this.attrs.set(name, value));
    }

    append<T extends RefreshTestElement>(child: T): T {
        child.parentElement?.removeChild(child);
        child.parentElement = this;
        this.children.push(child);
        return child;
    }

    removeChild<T extends RefreshTestElement>(child: T): T {
        const index = this.children.indexOf(child);
        if (index >= 0) this.children.splice(index, 1);
        child.parentElement = null;
        return child;
    }

    remove(): void {
        this.parentElement?.removeChild(this);
    }

    replaceWith(next: RefreshTestElement): void {
        const parent = this.parentElement;
        if (!parent) return;
        const index = parent.children.indexOf(this);
        if (index < 0) return;
        this.parentElement = null;
        next.parentElement = parent;
        parent.children[index] = next;
    }

    contains(candidate: RefreshTestElement): boolean {
        return candidate === this || this.children.some((child) => child.contains(candidate));
    }

    closest(selector: string): RefreshTestElement | null {
        let current: RefreshTestElement | null = this;
        while (current) {
            if (current.matches(selector)) return current;
            current = current.parentElement;
        }
        return null;
    }

    matches(selector: string): boolean {
        const focusedTag = selector.match(/^([a-z]+):focus$/i)?.[1];
        if (focusedTag) return this.tagName === focusedTag.toUpperCase() && RefreshTestElement.activeElement === this;
        const attr = selector.match(/^\[([^\]=]+)(?:="([^"]*)")?\]$/);
        if (attr) {
            const value = this.attrs.get(attr[1] ?? "");
            return value !== undefined && (attr[2] === undefined || value === attr[2]);
        }
        return this.tagName === selector.toUpperCase();
    }

    querySelector(selector: string): RefreshTestElement | null {
        for (const child of this.children) {
            if (child.matches(selector)) return child;
            const nested = child.querySelector(selector);
            if (nested) return nested;
        }
        return null;
    }
    getAttribute(name: string): string | null { return this.attrs.get(name) ?? null; }
    setAttribute(name: string, value: string): void {
        this.attrs.set(name, value);
        if (name === "id") this.id = value;
    }
    getBoundingClientRect(): DOMRect { return { top: 0, left: 0 } as DOMRect; }
    focus(): void { RefreshTestElement.activeElement = this; }
}

class RefreshTestInputElement extends RefreshTestElement {
    constructor(attrs: Record<string, string> = {}) {
        super("input", attrs);
    }
}

class RefreshTestTemplateElement extends RefreshTestElement {
    readonly content: { firstElementChild: RefreshTestElement | null } = { firstElementChild: null };

    set innerHTML(value: string) {
        const id = value.match(/\bid=["']([^"']+)["']/)?.[1] ?? "";
        const root = new RefreshTestElement("section", { id });
        if (value.includes("<input")) {
            root.append(new RefreshTestInputElement({
                id: value.match(/<input[^>]*\bid=["']([^"']+)["']/)?.[1] ?? "",
                name: value.match(/<input[^>]*\bname=["']([^"']+)["']/)?.[1] ?? "",
                "data-live-field": value.match(/<input[^>]*\bdata-live-field=["']([^"']+)["']/)?.[1] ?? "",
                value: value.match(/<input[^>]*\bvalue=["']([^"']*)["']/)?.[1] ?? "",
            }));
        }
        this.content.firstElementChild = root;
    }
}

class RefreshTestDocument extends EventTarget {
    readonly root = new RefreshTestElement("body");

    get activeElement(): RefreshTestElement | null {
        return RefreshTestElement.activeElement;
    }

    getElementById(id: string): RefreshTestElement | null {
        const visit = (owner: RefreshTestElement): RefreshTestElement | null => {
            if (owner.id === id) return owner;
            for (const child of owner.children) {
                const found = visit(child);
                if (found) return found;
            }
            return null;
        };
        return visit(this.root);
    }

    createElement(tagName: string): RefreshTestElement {
        return tagName.toLowerCase() === "template"
            ? new RefreshTestTemplateElement(tagName)
            : new RefreshTestElement(tagName);
    }
}

type FetchResponseControl = {
    url: string;
    fetch: Deferred<Response>;
    body: Deferred<string>;
    signal: AbortSignal | null;
};

function installRefreshFixture() {
    const original = {
        Element: globalThis.Element,
        HTMLElement: globalThis.HTMLElement,
        HTMLTemplateElement: globalThis.HTMLTemplateElement,
        HTMLInputElement: globalThis.HTMLInputElement,
        HTMLSelectElement: globalThis.HTMLSelectElement,
        HTMLTextAreaElement: globalThis.HTMLTextAreaElement,
        document: globalThis.document,
    };
    Object.defineProperties(globalThis, {
        Element: { configurable: true, value: RefreshTestElement },
        HTMLElement: { configurable: true, value: RefreshTestElement },
        HTMLTemplateElement: { configurable: true, value: RefreshTestTemplateElement },
        HTMLInputElement: { configurable: true, value: RefreshTestInputElement },
        HTMLSelectElement: { configurable: true, value: class extends RefreshTestElement {} },
        HTMLTextAreaElement: { configurable: true, value: class extends RefreshTestElement {} },
    });

    const document = new RefreshTestDocument();
    Object.defineProperty(globalThis, "document", { configurable: true, value: document });
    const controls: FetchResponseControl[] = [];
    const timers = new Map<number, () => void>();
    let nextTimerId = 1;
    let mountSequence = 0;
    let processed = 0;
    let pageReady = 0;
    let reloads = 0;
    const targetWindow = {
        fetch: (url: string, init?: RequestInit) => {
            const control: FetchResponseControl = { url, fetch: deferred<Response>(), body: deferred<string>(), signal: init?.signal ?? null };
            controls.push(control);
            return control.fetch.promise;
        },
        setTimeout: (callback: TimerHandler) => {
            const timerId = nextTimerId;
            nextTimerId += 1;
            if (typeof callback === "function") timers.set(timerId, () => callback());
            return timerId;
        },
        clearTimeout: (timerId: number) => { timers.delete(timerId); },
        scrollBy: () => undefined,
        console,
        htmx: { process: () => { processed += 1; } },
        appPageLifecycle: { dispatchPageReady: () => { pageReady += 1; } },
        location: { reload: () => { reloads += 1; } },
    } as unknown as Window & typeof globalThis;
    const sessions = createActiveInteractionSessionTracker(document as unknown as Document);
    const refresher = createLiveFragmentRefresher({
        targetWindow,
        targetDocument: document as unknown as Document,
        activeInteractionSessions: sessions,
        diagnostics: {
            beginPerfSpan: () => null,
            endPerfSpan: () => null,
            emitDebugEvent: () => undefined,
        },
    });

    function mount(targetId = "shared-fragment"): { owner: RefreshTestElement; target: RefreshTestElement; fragment: LiveUpdateFragmentWithState } {
        mountSequence += 1;
        const owner = document.root.append(new RefreshTestElement("main", {
            id: `mount-${mountSequence}`,
            [surfaceConfigDomAttr]: "{}",
            [InteractionDom.attributes.surface]: "timesheets",
        }));
        const target = owner.append(new RefreshTestElement("section", { id: targetId }));
        return {
            owner,
            target,
            fragment: {
                ownerEl: owner as unknown as HTMLElement,
                fragmentKey: { surface: "timesheets", kind: "timesheet-toolbar", params: null },
                targetId: target.id,
                url: "/fragment",
                protection: { kind: "replace" },
            },
        };
    }

    function respond(control: FetchResponseControl, html: string, headers: Record<string, string> = {}): void {
        control.fetch.resolve({
            ok: true,
            status: 200,
            headers: { get: (name: string) => headers[name] ?? null },
            text: () => control.body.promise,
        } as Response);
        control.body.resolve(html);
    }

    function restore(): void {
        refresher.stop();
        sessions.stop();
        RefreshTestElement.activeElement = null;
        Object.defineProperties(globalThis, {
            Element: { configurable: true, value: original.Element },
            HTMLElement: { configurable: true, value: original.HTMLElement },
            HTMLTemplateElement: { configurable: true, value: original.HTMLTemplateElement },
            HTMLInputElement: { configurable: true, value: original.HTMLInputElement },
            HTMLSelectElement: { configurable: true, value: original.HTMLSelectElement },
            HTMLTextAreaElement: { configurable: true, value: original.HTMLTextAreaElement },
            document: { configurable: true, value: original.document },
        });
    }

    return {
        document,
        controls,
        refresher,
        mount,
        respond,
        restore,
        runTimers: () => {
            const callbacks = Array.from(timers.values());
            timers.clear();
            callbacks.forEach((callback) => callback());
        },
        effects: () => ({ processed, pageReady, reloads }),
    };
}

async function settle(): Promise<void> {
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
}

function focusedFragment(
    fragment: LiveUpdateFragmentWithState,
    url = fragment.url,
): LiveUpdateFragmentWithState {
    return {
        ...fragment,
        url,
        protection: {
            kind: "focused-field",
            activeSelector: "input:focus",
            fieldKeyAttr: "data-live-field",
            fieldNameFallback: true,
            containerSelector: "form",
        },
    };
}

test("focused demand present before request keeps the latest demand and restores only configured field state", async () => {
    const fixture = installRefreshFixture();
    try {
        const mounted = fixture.mount();
        const input = mounted.target.append(new RefreshTestInputElement({
            id: "live-input",
            name: "hours",
            "data-live-field": "hours",
            value: "first",
        }));
        fixture.refresher.activateOwner(mounted.fragment.ownerEl);
        input.focus();
        fixture.refresher.request(focusedFragment(mounted.fragment, "/first"));
        input.value = "latest local value";
        fixture.refresher.request(focusedFragment(mounted.fragment, "/latest"));
        assertEqual(fixture.controls.length, 0);

        const outside = fixture.document.root.append(new RefreshTestElement("button", { id: "outside" }));
        outside.focus();
        fixture.refresher.flushFocusedFragmentsWithoutActiveInputs();
        assertEqual(fixture.controls[0]?.url, "/latest");
        fixture.respond(
            fixture.controls[0]!,
            '<section id="shared-fragment"><input id="live-input" name="hours" data-live-field="hours" value="server"></section>',
        );
        await settle();

        const replacementInput = fixture.document.getElementById("live-input") as RefreshTestInputElement | null;
        assertEqual(replacementInput?.value, "latest local value");
        assertEqual(RefreshTestElement.activeElement, outside);
    } finally {
        fixture.restore();
    }
});

test("focus begun during fetch discards old HTML and refetches after release without stealing outside focus", async () => {
    const fixture = installRefreshFixture();
    try {
        const mounted = fixture.mount();
        const input = mounted.target.append(new RefreshTestInputElement({ id: "live-input", name: "hours", "data-live-field": "hours", value: "local" }));
        const fragment = focusedFragment(mounted.fragment);
        fixture.refresher.activateOwner(fragment.ownerEl);
        fixture.refresher.request(fragment);
        const oldControl = fixture.controls[0]!;
        input.focus();
        fixture.refresher.markProtectionChanged(input as unknown as Element);
        fixture.respond(oldControl, '<section id="shared-fragment">stale while focused</section>', { "HX-Refresh": "true" });
        await settle();
        assertEqual(fixture.document.getElementById("shared-fragment"), mounted.target);
        assertEqual(fixture.effects().reloads, 0);

        const outside = fixture.document.root.append(new RefreshTestElement("button", { id: "outside" }));
        outside.focus();
        fixture.refresher.flushFocusedFragmentsWithoutActiveInputs();
        assertEqual(fixture.controls.length, 2);
        fixture.respond(fixture.controls[1]!, '<section id="shared-fragment">fresh after focus</section>');
        await settle();

        assertEqual(fixture.document.getElementById("shared-fragment") === mounted.target, false);
        assertEqual(RefreshTestElement.activeElement, outside);
        assertEqual(fixture.effects().processed, 1);
    } finally {
        fixture.restore();
    }
});

test("newer focused demand remains latest when protection ends before the old response completes", async () => {
    const fixture = installRefreshFixture();
    try {
        const mounted = fixture.mount();
        const input = mounted.target.append(new RefreshTestInputElement({ id: "live-input", name: "hours", "data-live-field": "hours" }));
        fixture.refresher.activateOwner(mounted.fragment.ownerEl);
        fixture.refresher.request(focusedFragment(mounted.fragment, "/old"));
        input.focus();
        fixture.refresher.markProtectionChanged(input as unknown as Element);
        fixture.refresher.request(focusedFragment(mounted.fragment, "/latest"));
        const outside = fixture.document.root.append(new RefreshTestElement("button", { id: "outside" }));
        outside.focus();
        fixture.refresher.flushFocusedFragmentsWithoutActiveInputs();
        fixture.respond(fixture.controls[0]!, '<section id="shared-fragment">old response</section>');
        await settle();

        assertEqual(fixture.controls.length, 2);
        assertEqual(fixture.controls[1]?.url, "/latest");
        assertEqual(fixture.document.getElementById("shared-fragment"), mounted.target);
    } finally {
        fixture.restore();
    }
});

test("focus begun and ended during fetch still forces a fresh authority request", async () => {
    const fixture = installRefreshFixture();
    try {
        const mounted = fixture.mount();
        const input = mounted.target.append(new RefreshTestInputElement({ id: "live-input" }));
        const fragment = focusedFragment(mounted.fragment);
        fixture.refresher.activateOwner(fragment.ownerEl);
        fixture.refresher.request(fragment);
        input.focus();
        fixture.refresher.markProtectionChanged(input as unknown as Element);
        const outside = fixture.document.root.append(new RefreshTestElement("button", { id: "outside" }));
        outside.focus();
        fixture.respond(fixture.controls[0]!, '<section id="shared-fragment">stale after transient focus</section>');
        await settle();

        assertEqual(fixture.controls.length, 2);
        assertEqual(fixture.document.getElementById("shared-fragment"), mounted.target);
        fixture.respond(fixture.controls[1]!, '<section id="shared-fragment">fresh authority</section>');
        await settle();
        assertEqual(fixture.document.getElementById("shared-fragment") === mounted.target, false);
        assertEqual(RefreshTestElement.activeElement, outside);
    } finally {
        fixture.restore();
    }
});

test("interaction apply policy refreshes immediately without ending the session", async () => {
    const fixture = installRefreshFixture();
    try {
        const mounted = fixture.mount();
        mounted.owner.setAttribute(InteractionDom.attributes.conflictPolicies, JSON.stringify([
            { session: "drag", targetId: mounted.fragment.targetId, resolution: "apply" },
        ]));
        fixture.refresher.activateOwner(mounted.fragment.ownerEl);
        fixture.document.dispatchEvent(new CustomEvent(interactionSessionStartEvent, {
            detail: { mount: mounted.owner, mountId: mounted.owner.id, sessionKind: "drag", intent: "move" },
        }));

        fixture.refresher.request(mounted.fragment);
        assertEqual(fixture.controls.length, 1);
        fixture.respond(fixture.controls[0]!, '<section id="shared-fragment">applied during interaction</section>');
        await settle();

        assertEqual(fixture.document.getElementById("shared-fragment") === mounted.target, false);
        assertEqual(fixture.effects().processed, 1);
    } finally {
        fixture.restore();
    }
});

test("interaction cancel policy queues fresh authority before synchronous session cleanup", () => {
    const fixture = installRefreshFixture();
    try {
        const mounted = fixture.mount();
        mounted.owner.setAttribute(InteractionDom.attributes.conflictPolicies, JSON.stringify([
            { session: "drag", targetId: mounted.fragment.targetId, resolution: "cancel" },
        ]));
        fixture.refresher.activateOwner(mounted.fragment.ownerEl);
        fixture.document.dispatchEvent(new CustomEvent(interactionSessionStartEvent, {
            detail: { mount: mounted.owner, mountId: mounted.owner.id, sessionKind: "drag", intent: "move" },
        }));
        fixture.document.addEventListener(interactionSessionCancelRequestEvent, () => {
            fixture.document.dispatchEvent(new CustomEvent(interactionSessionEndEvent, {
                detail: { mount: mounted.owner, mountId: mounted.owner.id, sessionKind: "drag", intent: "move" },
            }));
            fixture.refresher.flushInteractionDeferredFragmentsWithoutActiveSessions();
        });

        fixture.refresher.request(mounted.fragment);
        assertEqual(fixture.controls.length, 1);
    } finally {
        fixture.restore();
    }
});

test("interaction present before request defers until normal release then fetches current authority", () => {
    const fixture = installRefreshFixture();
    try {
        const mounted = fixture.mount();
        fixture.refresher.activateOwner(mounted.fragment.ownerEl);
        fixture.document.dispatchEvent(new CustomEvent(interactionSessionStartEvent, {
            detail: { mount: mounted.owner, mountId: mounted.owner.id, sessionKind: "drag", intent: "move" },
        }));
        fixture.refresher.request(mounted.fragment);
        assertEqual(fixture.controls.length, 0);

        fixture.document.dispatchEvent(new CustomEvent(interactionSessionEndEvent, {
            detail: { mount: mounted.owner, mountId: mounted.owner.id, sessionKind: "drag", intent: "move" },
        }));
        fixture.refresher.flushInteractionDeferredFragmentsWithoutActiveSessions();
        assertEqual(fixture.controls.length, 1);
    } finally {
        fixture.restore();
    }
});

test("interaction begun during fetch discards old HTML and release refetches current authority", async () => {
    const fixture = installRefreshFixture();
    try {
        const mounted = fixture.mount();
        fixture.refresher.activateOwner(mounted.fragment.ownerEl);
        fixture.refresher.request(mounted.fragment);
        fixture.document.dispatchEvent(new CustomEvent(interactionSessionStartEvent, {
            detail: { mount: mounted.owner, mountId: mounted.owner.id, sessionKind: "drag", intent: "move" },
        }));
        fixture.refresher.markProtectionChanged(mounted.owner as unknown as Element);
        fixture.respond(fixture.controls[0]!, '<section id="shared-fragment">stale during interaction</section>');
        await settle();
        assertEqual(fixture.document.getElementById("shared-fragment"), mounted.target);

        fixture.document.dispatchEvent(new CustomEvent(interactionSessionEndEvent, {
            detail: { mount: mounted.owner, mountId: mounted.owner.id, sessionKind: "drag", intent: "move" },
        }));
        fixture.refresher.flushInteractionDeferredFragmentsWithoutActiveSessions();
        assertEqual(fixture.controls.length, 2);
        fixture.respond(fixture.controls[1]!, '<section id="shared-fragment">fresh after interaction</section>');
        await settle();

        assertEqual(fixture.document.getElementById("shared-fragment") === mounted.target, false);
        assertEqual(fixture.effects().processed, 1);
    } finally {
        fixture.restore();
    }
});

test("interaction fallback cancels only its owning session and keeps completion protected", async () => {
    const fixture = installRefreshFixture();
    try {
        const first = fixture.mount("first-fragment");
        const unrelated = fixture.mount("unrelated-fragment");
        fixture.refresher.activateOwner(first.fragment.ownerEl);
        fixture.refresher.activateOwner(unrelated.fragment.ownerEl);
        const canceledMounts: string[] = [];
        fixture.document.addEventListener(interactionSessionCancelRequestEvent, (event) => {
            if (event instanceof CustomEvent && typeof event.detail?.mountId === "string") canceledMounts.push(event.detail.mountId);
        });
        for (const mounted of [first, unrelated]) {
            fixture.document.dispatchEvent(new CustomEvent(interactionSessionStartEvent, {
                detail: { mount: mounted.owner, mountId: mounted.owner.id, sessionKind: "drag", intent: "move" },
            }));
        }

        fixture.refresher.request(first.fragment);
        assertEqual(fixture.controls.length, 0);
        fixture.runTimers();
        assertEqual(canceledMounts.join(","), first.owner.id);
        assertEqual(fixture.controls.length, 1);
        fixture.respond(fixture.controls[0]!, '<section id="first-fragment">must remain deferred</section>');
        await settle();
        assertEqual(fixture.document.getElementById("first-fragment"), first.target);
        assertEqual(fixture.document.getElementById("unrelated-fragment"), unrelated.target);
    } finally {
        fixture.restore();
    }
});

test("disposed interaction demand clears fallback timers and cannot reanimate on remount", () => {
    const fixture = installRefreshFixture();
    try {
        const oldMount = fixture.mount();
        fixture.refresher.activateOwner(oldMount.fragment.ownerEl);
        fixture.document.dispatchEvent(new CustomEvent(interactionSessionStartEvent, {
            detail: { mount: oldMount.owner, mountId: oldMount.owner.id, sessionKind: "drag", intent: "move" },
        }));
        fixture.refresher.request(oldMount.fragment);
        fixture.refresher.disposeOwner(oldMount.fragment.ownerEl);
        oldMount.owner.remove();
        const replacement = fixture.mount();
        fixture.refresher.activateOwner(replacement.fragment.ownerEl);
        fixture.runTimers();

        assertEqual(fixture.controls.length, 0);
        assertEqual(fixture.document.getElementById("shared-fragment"), replacement.target);
    } finally {
        fixture.restore();
    }
});

test("disposed focused demand and saved field state cannot enter an identical remount", async () => {
    const fixture = installRefreshFixture();
    try {
        const oldMount = fixture.mount();
        const input = oldMount.target.append(new RefreshTestInputElement({ id: "live-input", name: "hours", "data-live-field": "hours", value: "old lifetime" }));
        const fragment = focusedFragment(oldMount.fragment);
        fixture.refresher.activateOwner(fragment.ownerEl);
        input.focus();
        fixture.refresher.request(fragment);
        fixture.refresher.disposeOwner(fragment.ownerEl);
        oldMount.owner.remove();
        const replacement = fixture.mount();
        replacement.target.append(new RefreshTestInputElement({ id: "live-input", name: "hours", "data-live-field": "hours", value: "new lifetime" }));
        fixture.refresher.activateOwner(replacement.fragment.ownerEl);
        RefreshTestElement.activeElement = null;
        fixture.refresher.flushFocusedFragmentsWithoutActiveInputs();

        assertEqual(fixture.controls.length, 0);
        assertEqual((fixture.document.getElementById("live-input") as RefreshTestInputElement).value, "new lifetime");
    } finally {
        fixture.restore();
    }
});

test("live refresher fences an old response from a same-ID target replacement inside the surviving owner", async () => {
    const fixture = installRefreshFixture();
    try {
        const mounted = fixture.mount();
        fixture.refresher.activateOwner(mounted.fragment.ownerEl);
        fixture.refresher.request(mounted.fragment);
        const replacementTarget = new RefreshTestElement("section", { id: mounted.target.id });
        mounted.target.replaceWith(replacementTarget);
        fixture.respond(fixture.controls[0]!, '<section id="shared-fragment">stale target response</section>', { "HX-Refresh": "true" });
        await settle();

        assertEqual(fixture.document.getElementById("shared-fragment"), replacementTarget);
        assertEqual(fixture.effects().reloads, 0);
        assertEqual(fixture.effects().processed, 0);
        assertEqual(fixture.effects().pageReady, 0);
    } finally {
        fixture.restore();
    }
});

test("live refresher fences an abort-ignored response from an identical replacement mount", async () => {
    const fixture = installRefreshFixture();
    try {
        const oldMount = fixture.mount();
        fixture.refresher.activateOwner(oldMount.fragment.ownerEl);
        fixture.refresher.request(oldMount.fragment);
        assertEqual(fixture.controls.length, 1);

        fixture.refresher.disposeOwner(oldMount.fragment.ownerEl);
        oldMount.owner.remove();
        const replacement = fixture.mount();
        fixture.refresher.activateOwner(replacement.fragment.ownerEl);
        fixture.respond(fixture.controls[0]!, '<section id="shared-fragment">stale</section>', { "HX-Refresh": "true" });
        await settle();

        assertEqual(fixture.controls[0]?.signal?.aborted, true);
        assertEqual(fixture.document.getElementById("shared-fragment"), replacement.target);
        assertEqual(fixture.effects().processed, 0);
        assertEqual(fixture.effects().pageReady, 0);
    } finally {
        fixture.restore();
    }
});

test("live refresher fences an abort-ignored delayed body from an identical replacement mount", async () => {
    const fixture = installRefreshFixture();
    try {
        const oldMount = fixture.mount();
        fixture.refresher.activateOwner(oldMount.fragment.ownerEl);
        fixture.refresher.request(oldMount.fragment);
        const control = fixture.controls[0]!;
        control.fetch.resolve({
            ok: true,
            status: 200,
            headers: { get: () => null },
            text: () => control.body.promise,
        } as unknown as Response);
        await settle();

        fixture.refresher.disposeOwner(oldMount.fragment.ownerEl);
        oldMount.owner.remove();
        const replacement = fixture.mount();
        fixture.refresher.activateOwner(replacement.fragment.ownerEl);
        control.body.resolve('<section id="shared-fragment">stale body</section>');
        await settle();

        assertEqual(control.signal?.aborted, true);
        assertEqual(fixture.document.getElementById("shared-fragment"), replacement.target);
        assertEqual(fixture.effects().processed, 0);
        assertEqual(fixture.effects().pageReady, 0);
    } finally {
        fixture.restore();
    }
});

test("live refresher isolates descendant and unrelated mounted owners", async () => {
    const fixture = installRefreshFixture();
    try {
        const parent = fixture.mount("parent-fragment");
        const childOwner = parent.owner.append(new RefreshTestElement("aside", { [surfaceConfigDomAttr]: "{}" }));
        const childTarget = childOwner.append(new RefreshTestElement("section", { id: "child-fragment" }));
        const childFragment: LiveUpdateFragmentWithState = {
            ...parent.fragment,
            ownerEl: childOwner as unknown as HTMLElement,
            targetId: childTarget.id,
            url: "/child",
        };
        const unrelated = fixture.mount("unrelated-fragment");
        fixture.refresher.activateOwner(parent.fragment.ownerEl);
        fixture.refresher.activateOwner(childFragment.ownerEl);
        fixture.refresher.activateOwner(unrelated.fragment.ownerEl);

        fixture.refresher.request({ ...parent.fragment, targetId: childTarget.id, url: "/invalid-parent-claim" });
        assertEqual(fixture.controls.length, 0);
        fixture.refresher.request(childFragment);
        fixture.refresher.request(unrelated.fragment);
        assertEqual(fixture.controls.length, 2);
        fixture.refresher.disposeOwner(childFragment.ownerEl);
        fixture.respond(fixture.controls[0]!, '<section id="child-fragment">stale child</section>');
        fixture.respond(fixture.controls[1]!, '<section id="unrelated-fragment">current unrelated</section>');
        await settle();

        assertEqual(fixture.document.getElementById("child-fragment"), childTarget);
        assertEqual(fixture.document.getElementById("unrelated-fragment") === unrelated.target, false);
        assertEqual(fixture.effects().processed, 1);
        assertEqual(fixture.effects().pageReady, 1);
    } finally {
        fixture.restore();
    }
});

test("live refresher stop fences delayed bodies, queued work, reload, and repeated disposal", async () => {
    const fixture = installRefreshFixture();
    try {
        const mounted = fixture.mount();
        fixture.refresher.activateOwner(mounted.fragment.ownerEl);
        fixture.refresher.request(mounted.fragment);
        fixture.refresher.request({ ...mounted.fragment, url: "/queued" });
        const control = fixture.controls[0]!;
        control.fetch.resolve({
            ok: true,
            status: 200,
            headers: { get: () => null },
            text: () => control.body.promise,
        } as unknown as Response);
        await settle();
        fixture.refresher.stop();
        fixture.refresher.stop();
        fixture.refresher.disposeOwner(mounted.fragment.ownerEl);
        control.body.resolve('<section id="shared-fragment">late</section>');
        await settle();

        assertEqual(control.signal?.aborted, true);
        assertEqual(fixture.controls.length, 1);
        assertEqual(fixture.document.getElementById("shared-fragment"), mounted.target);
        assertEqual(fixture.effects().reloads, 0);
        assertEqual(fixture.effects().processed, 0);
        assertEqual(fixture.effects().pageReady, 0);
    } finally {
        fixture.restore();
    }
});

test("live refresher frees a failed request slot for a later valid refresh", async () => {
    const fixture = installRefreshFixture();
    try {
        const mounted = fixture.mount();
        fixture.refresher.activateOwner(mounted.fragment.ownerEl);
        fixture.refresher.request(mounted.fragment);
        fixture.controls[0]?.fetch.resolve({
            ok: false,
            status: 503,
            headers: { get: () => null },
            text: () => Promise.resolve(""),
        } as unknown as Response);
        await settle();

        fixture.refresher.request({ ...mounted.fragment, url: "/recovered" });
        assertEqual(fixture.controls.length, 2);
        fixture.respond(fixture.controls[1]!, '<section id="shared-fragment">recovered</section>');
        await settle();
        assertEqual(fixture.document.getElementById("shared-fragment") === mounted.target, false);
        assertEqual(fixture.effects().processed, 1);
    } finally {
        fixture.restore();
    }
});

test("live refresher retains current-generation declared reload and empty-removal behavior", async () => {
    const fixture = installRefreshFixture();
    try {
        const mounted = fixture.mount();
        fixture.refresher.activateOwner(mounted.fragment.ownerEl);
        fixture.refresher.request(mounted.fragment);
        fixture.respond(fixture.controls[0]!, "ignored", { "HX-Refresh": "true" });
        await settle();
        assertEqual(fixture.effects().reloads, 1);
        assertEqual(fixture.document.getElementById("shared-fragment"), mounted.target);

        fixture.refresher.request(mounted.fragment);
        fixture.respond(fixture.controls[1]!, "   ");
        await settle();
        assertEqual(fixture.document.getElementById("shared-fragment"), null);
        assertEqual(fixture.effects().processed, 0);
        assertEqual(fixture.effects().pageReady, 0);
    } finally {
        fixture.restore();
    }
});

test("live refresher keeps new same-owner work when an old completion finally settles", async () => {
    const fixture = installRefreshFixture();
    try {
        const mounted = fixture.mount();
        fixture.refresher.activateOwner(mounted.fragment.ownerEl);
        fixture.refresher.request(mounted.fragment);
        const oldControl = fixture.controls[0]!;
        fixture.refresher.disposeOwner(mounted.fragment.ownerEl);
        fixture.refresher.activateOwner(mounted.fragment.ownerEl);
        fixture.refresher.request({ ...mounted.fragment, url: "/current" });
        const currentControl = fixture.controls[1]!;

        fixture.respond(oldControl, '<section id="shared-fragment">old</section>');
        await settle();
        assertEqual(fixture.document.getElementById("shared-fragment"), mounted.target);

        fixture.respond(currentControl, '<section id="shared-fragment">current</section>');
        await settle();
        assertEqual(fixture.document.getElementById("shared-fragment") === mounted.target, false);
        assertEqual(fixture.effects().processed, 1);
        assertEqual(fixture.effects().pageReady, 1);
    } finally {
        fixture.restore();
    }
});
