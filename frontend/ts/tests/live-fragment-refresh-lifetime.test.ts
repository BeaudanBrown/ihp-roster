import { surfaceConfigDomAttr } from "../generated/contracts";
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
    parentElement: RefreshTestElement | null = null;
    children: RefreshTestElement[] = [];
    id: string;
    readonly tagName: string;
    private readonly attrs = new Map<string, string>();

    constructor(tagName = "div", attrs: Record<string, string> = {}) {
        super();
        this.tagName = tagName.toUpperCase();
        this.id = attrs.id ?? "";
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
        const attr = selector.match(/^\[([^\]]+)\]$/)?.[1];
        return attr ? this.attrs.has(attr) : false;
    }

    querySelector(): null { return null; }
    getAttribute(name: string): string | null { return this.attrs.get(name) ?? null; }
    getBoundingClientRect(): DOMRect { return { top: 0, left: 0 } as DOMRect; }
    focus(): void { /* no active focus in these lifecycle tests */ }
}

class RefreshTestTemplateElement extends RefreshTestElement {
    readonly content: { firstElementChild: RefreshTestElement | null } = { firstElementChild: null };

    set innerHTML(value: string) {
        const id = value.match(/\bid=["']([^"']+)["']/)?.[1] ?? "";
        this.content.firstElementChild = new RefreshTestElement("section", { id });
    }
}

class RefreshTestDocument extends EventTarget {
    readonly root = new RefreshTestElement("body");
    activeElement: RefreshTestElement | null = null;

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
    };
    Object.defineProperties(globalThis, {
        Element: { configurable: true, value: RefreshTestElement },
        HTMLElement: { configurable: true, value: RefreshTestElement },
        HTMLTemplateElement: { configurable: true, value: RefreshTestTemplateElement },
        HTMLInputElement: { configurable: true, value: class extends RefreshTestElement {} },
        HTMLSelectElement: { configurable: true, value: class extends RefreshTestElement {} },
        HTMLTextAreaElement: { configurable: true, value: class extends RefreshTestElement {} },
    });

    const document = new RefreshTestDocument();
    const controls: FetchResponseControl[] = [];
    let processed = 0;
    let pageReady = 0;
    let reloads = 0;
    const targetWindow = {
        fetch: (_url: string, init?: RequestInit) => {
            const control: FetchResponseControl = { fetch: deferred<Response>(), body: deferred<string>(), signal: init?.signal ?? null };
            controls.push(control);
            return control.fetch.promise;
        },
        setTimeout,
        clearTimeout,
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
        const owner = document.root.append(new RefreshTestElement("main", { [surfaceConfigDomAttr]: "{}" }));
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
        Object.defineProperties(globalThis, {
            Element: { configurable: true, value: original.Element },
            HTMLElement: { configurable: true, value: original.HTMLElement },
            HTMLTemplateElement: { configurable: true, value: original.HTMLTemplateElement },
            HTMLInputElement: { configurable: true, value: original.HTMLInputElement },
            HTMLSelectElement: { configurable: true, value: original.HTMLSelectElement },
            HTMLTextAreaElement: { configurable: true, value: original.HTMLTextAreaElement },
        });
    }

    return {
        document,
        controls,
        refresher,
        mount,
        respond,
        restore,
        effects: () => ({ processed, pageReady, reloads }),
    };
}

async function settle(): Promise<void> {
    await Promise.resolve();
    await Promise.resolve();
    await Promise.resolve();
}

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
