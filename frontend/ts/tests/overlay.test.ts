import {
    parseDialogSubmitConfiguration,
    parseNavigationLoadingConfiguration,
} from "../app-dialog-overlays";
import { parseToastConfiguration } from "../app-toasts";
import { createDialogDismissalLifecycle, installPointerDismissFocusCleanup } from "../dialog-overlays/lifecycle";
import { dialogDismissedEvent, dialogPointerDismissBlurDomAttr } from "../generated/contracts";
import { MiniElement } from "./mini-dom";
import { assertDeepEqual, assertEqual, assertThrows, test } from "./harness";

test("overlay adapter parses exact generated dialog submit and toast configs", () => {
    assertDeepEqual(
        parseDialogSubmitConfiguration(JSON.stringify({ loadingLabel: "Saving..." })),
        { loadingLabel: "Saving..." },
    );
    assertDeepEqual(
        parseNavigationLoadingConfiguration(JSON.stringify({
            loadingTitle: "Opening Stripe",
            loadingMessage: "Please wait while Bepis opens Stripe's secure billing page.",
        })),
        {
            loadingTitle: "Opening Stripe",
            loadingMessage: "Please wait while Bepis opens Stripe's secure billing page.",
        },
    );
    assertDeepEqual(
        parseToastConfiguration(JSON.stringify({ autoHideMs: 3200 })),
        { autoHideMs: 3200 },
    );
});

test("dialog dismissal lifecycle reconciles imperative clears and replacements exactly once", () => {
    const lifecycle = createDialogDismissalLifecycle("dialog-dismissed-test");
    const mount = new EventTarget();
    const firstDialog = new EventTarget();
    const replacementDialog = new EventTarget();
    const observed: Array<{ dialog: EventTarget; replacement: EventTarget | null }> = [];
    mount.addEventListener("dialog-dismissed-test", (event) => {
        const detail = (event as CustomEvent<{ dialog: EventTarget; replacement: EventTarget | null }>).detail;
        observed.push(detail);
    });

    lifecycle.reconcile(mount as unknown as Element, firstDialog as unknown as Element);
    assertEqual(observed.length, 0);

    lifecycle.reconcile(mount as unknown as Element, replacementDialog as unknown as Element);
    assertEqual(observed.length, 1);
    assertEqual(observed[0]?.dialog, firstDialog);
    assertEqual(observed[0]?.replacement, replacementDialog);

    lifecycle.dismiss(replacementDialog as unknown as Element, mount);
    lifecycle.dismiss(replacementDialog as unknown as Element, mount);
    lifecycle.reconcile(mount as unknown as Element, null);
    assertEqual(observed.length, 2);
    assertEqual(observed[1]?.dialog, replacementDialog);
    assertEqual(observed[1]?.replacement, null);

    lifecycle.reconcile(mount as unknown as Element, null);
    assertEqual(observed.length, 2);
});

class PointerFocusDocument {
    readonly root = new MiniElement();
    readonly frames: FrameRequestCallback[] = [];
    readonly listeners = new Map<string, Array<{ callback: (event: Event) => void; capture: boolean }>>();
    readonly defaultView = { requestAnimationFrame: (callback: FrameRequestCallback) => this.frames.push(callback) };
    activeElement: MiniElement | null = null;

    contains(element: MiniElement): boolean { return this.root.contains(element); }
    addEventListener(name: string, callback: (event: Event) => void, capture = false): void {
        this.listeners.set(name, [...(this.listeners.get(name) ?? []), { callback, capture }]);
    }
    emit(name: string, event: Event | { target: MiniElement }): void {
        this.listeners.get(name)?.forEach(({ callback }) => callback(event as Event));
    }
    frame(): void { this.frames.splice(0).forEach((callback) => callback(0)); }
}

function withPointerFocusDocument(run: (owner: PointerFocusDocument) => void): void {
    const descriptors = ["Element", "HTMLElement"].map((name) => [name, Object.getOwnPropertyDescriptor(globalThis, name)] as const);
    try {
        descriptors.forEach(([name]) => Object.defineProperty(globalThis, name, { configurable: true, value: MiniElement }));
        const owner = new PointerFocusDocument();
        installPointerDismissFocusCleanup(owner as unknown as Document);
        run(owner);
    } finally {
        descriptors.forEach(([name, descriptor]) => {
            if (descriptor) Object.defineProperty(globalThis, name, descriptor);
            else Reflect.deleteProperty(globalThis, name);
        });
    }
}

test("pointer dismissal uses one document listener set across duplicate, nested and replaced mounts", () => {
    withPointerFocusDocument((owner) => {
        installPointerDismissFocusCleanup(owner as unknown as Document);
        assertDeepEqual(Array.from(owner.listeners, ([name, listeners]) => [name, listeners.map(({ capture }) => capture)]), [
            ["pointerdown", [true]], ["keydown", [true]], [dialogDismissedEvent, [false]],
        ]);
        const launcher = owner.root.append(new MiniElement({ [dialogPointerDismissBlurDomAttr]: "true" }));
        const child = launcher.append(new MiniElement());
        const outer = owner.root.append(new MiniElement());
        const inner = outer.append(new MiniElement());
        [outer, inner].forEach((mount) => mount.addEventListener(dialogDismissedEvent, (event) => owner.emit(dialogDismissedEvent, event)));
        const lifecycle = createDialogDismissalLifecycle(dialogDismissedEvent);
        const first = new MiniElement();
        const replacement = new MiniElement();
        const reconcile = (mount: MiniElement, dialog: MiniElement | null) => lifecycle.reconcile(mount as unknown as Element, dialog as unknown as Element | null);
        owner.activeElement = launcher;
        owner.emit("pointerdown", { target: child });
        reconcile(outer, first);
        reconcile(inner, first);
        reconcile(outer, first);
        reconcile(outer, replacement);
        reconcile(inner, replacement);
        assertEqual(owner.frames.length, 0);
        assertEqual(launcher.blurCount, 0);
        reconcile(inner, null);
        reconcile(outer, null);
        reconcile(inner, null);
        assertEqual(owner.frames.length, 1);
        assertEqual(launcher.blurCount, 0);
        owner.frame();
        assertEqual(launcher.blurCount, 1);
        assertEqual(owner.frames.length, 0);
        assertEqual(Array.from(owner.listeners.values()).flat().length, 3);
    });
});

test("pointer dismissal skips malformed events and clears pending cleanup on any keydown", () => {
    withPointerFocusDocument((owner) => {
        const launcher = owner.root.append(new MiniElement({ [dialogPointerDismissBlurDomAttr]: "true" }));
        owner.activeElement = launcher;
        owner.emit("pointerdown", { target: launcher });
        for (const detail of [null, {}, { dialog: {} }, { dialog: launcher, replacement: "invalid" }]) {
            owner.emit(dialogDismissedEvent, new CustomEvent(dialogDismissedEvent, { detail }));
        }
        assertEqual(owner.frames.length, 0);
        const dismissal = new CustomEvent(dialogDismissedEvent, { detail: { dialog: launcher, replacement: null } });
        owner.emit(dialogDismissedEvent, dismissal);
        assertEqual(owner.frames.length, 1);
        owner.emit("keydown", new Event("keydown"));
        owner.frame();
        assertEqual(launcher.blurCount, 0);
        owner.emit(dialogDismissedEvent, dismissal);
        assertEqual(owner.frames.length, 0);
    });
});

test("overlay adapter rejects malformed or semantically invalid generated configs", () => {
    assertThrows(
        () => parseDialogSubmitConfiguration(JSON.stringify({ loadingLabel: "Saving...", extra: true })),
        "Invalid DialogSubmitConfig",
    );
    assertThrows(
        () => parseDialogSubmitConfiguration(JSON.stringify({ loadingLabel: "   " })),
        "loadingLabel must not be empty",
    );
    assertThrows(
        () => parseNavigationLoadingConfiguration(JSON.stringify({ loadingTitle: "", loadingMessage: "Waiting" })),
        "loadingTitle must not be empty",
    );
    assertThrows(
        () => parseNavigationLoadingConfiguration(JSON.stringify({ loadingTitle: "Waiting", loadingMessage: " " })),
        "loadingMessage must not be empty",
    );
    assertThrows(
        () => parseToastConfiguration(JSON.stringify({ autoHideMs: -1 })),
        "autoHideMs must not be negative",
    );
});
