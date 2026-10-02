import { surfaceConfigDomAttr } from "../generated/contracts";
import { createDirtyFormProtection } from "../live-updates/forms";
import { createSettledFormGate } from "../live-updates/settled-form-gate";
import { assertEqual, test } from "./harness";
import { MiniElement } from "./mini-dom";

class Node extends MiniElement {
    isConnected = true;
    hidden = false;
    hasAttribute(name: string): boolean { return this.getAttribute(name) !== null; }
}
class Form extends Node {
    snapshot = "initial";
    constructor(attrs: Record<string, string> = {}) { super(attrs, "", [], "form"); }
    get elements() { return this.children; }
}
class Button extends Node {
    type = "submit";
    disabled = false;
}
class Input extends Node {}
class Xhr {
    status = 200;
    saved = false;
    getResponseHeader() { return this.saved ? "true" : null; }
}
const actionAttribute = "data-test-gate-action";
const noticeAttribute = "data-test-gate-notice";

function fixture(run: (value: ReturnType<typeof setup>) => void): void {
    const originals = { Element: globalThis.Element, HTMLElement: globalThis.HTMLElement, HTMLFormElement: globalThis.HTMLFormElement,
        HTMLButtonElement: globalThis.HTMLButtonElement, HTMLInputElement: globalThis.HTMLInputElement,
        XMLHttpRequest: globalThis.XMLHttpRequest, FormData: globalThis.FormData };
    class Data extends originals.FormData {
        constructor(form?: HTMLFormElement) { super(); if (form) this.append("value", (form as unknown as Form).snapshot); }
    }
    const descriptors = Object.fromEntries(Object.keys(originals).map((key) => [key, Object.getOwnPropertyDescriptor(globalThis, key)]));
    try {
        for (const [key, value] of Object.entries({ Element: MiniElement, HTMLElement: MiniElement, HTMLFormElement: Form,
            HTMLButtonElement: Button, HTMLInputElement: Input, XMLHttpRequest: Xhr, FormData: Data })) {
            Object.defineProperty(globalThis, key, { configurable: true, writable: true, value });
        }
        run(setup());
    } finally {
        for (const [key, descriptor] of Object.entries(descriptors)) {
            if (descriptor) Object.defineProperty(globalThis, key, descriptor);
            else Reflect.deleteProperty(globalThis, key);
        }
    }
}

function setup() {
    const owner = new Node({ [surfaceConfigDomAttr]: "fixture" });
    const target = owner.append(new Node({}, "edit-target"));
    const edit = target.append(new Form());
    const action = owner.append(new Form({ [actionAttribute]: "" }));
    const button = action.append(new Button());
    const notice = owner.append(new Node({ [noticeAttribute]: "" }));
    const document = { getElementById: (id: string) => owner.querySelectorAll("*").find((node) => node.id === id) ?? null } as unknown as Document;
    const nativeOwner = owner as unknown as HTMLElement;
    const nativeTarget = target as unknown as HTMLElement;
    const acknowledgements: string[] = [];
    const forms = createDirtyFormProtection(document, (_owner, targetId) => acknowledgements.push(targetId), () => gate.refresh(nativeOwner));
    const gate = createSettledFormGate((candidate) => candidate !== nativeOwner ? null : ({
        definitions: [{ name: "fixture", actionRoleAttribute: actionAttribute, noticeRoleAttribute: noticeAttribute }],
        settled: !forms.protectedTarget(nativeTarget, nativeOwner),
    }));
    forms.register(nativeOwner, nativeTarget, { kind: "dirty-form", savedHeader: "X-Test-Saved" });
    const refresh = () => gate.refresh(nativeOwner);
    const change = (value: string) => { edit.snapshot = value; forms.changed(edit as unknown as Element); };
    const event = (name: string, xhr: Xhr) => new CustomEvent(name, { cancelable: true, detail: { xhr, elt: edit } });
    const start = () => { const xhr = new Xhr(); forms.handleEvent(event("htmx:beforeRequest", xhr)); return xhr; };
    const finish = (xhr: Xhr, saved: boolean) => {
        xhr.saved = saved;
        forms.handleEvent(event("htmx:beforeOnLoad", xhr));
        forms.handleEvent(event("htmx:afterRequest", xhr));
    };
    refresh();
    return { owner, target, edit, action, button, notice, forms, gate, refresh, change, event, start, finish, acknowledgements };
}

test("settled-form gate shares dirty/pending state and waits for explicit saved acknowledgement", () => fixture((f) => {
    assertEqual(f.button.disabled, false);
    f.change("changed");
    assertEqual(f.button.disabled, true);
    assertEqual(f.notice.hidden, false);
    const xhr = f.start();
    f.finish(xhr, true);
    assertEqual(f.button.disabled, false);
    assertEqual(f.notice.hidden, true);
    const pending = f.start();
    assertEqual(f.button.disabled, true);
    f.finish(pending, true);
    assertEqual(f.button.disabled, false);
}));

test("settled-form gate retains edits made during a save and never auto-resolves failed saves", () => fixture((f) => {
    f.change("first");
    const xhr = f.start();
    f.change("unsaved later input");
    f.finish(xhr, true);
    assertEqual(f.button.disabled, true);
    const failed = f.start();
    failed.status = 409;
    f.finish(failed, false);
    f.change("first"); // Even matching the old baseline does not resolve the conflict.
    assertEqual(f.button.disabled, true);
    const explicit = f.start();
    f.finish(explicit, true);
    assertEqual(f.button.disabled, false);
}));

test("settled-form gate rejects native and HTMX submission while blocked", () => fixture((f) => {
    f.change("dirty");
    const native = new Event("submit", { cancelable: true });
    Object.defineProperty(native, "target", { value: f.action });
    assertEqual(f.gate.guard(native), true);
    assertEqual(native.defaultPrevented, true);
    const custom = new CustomEvent("htmx:beforeRequest", { cancelable: true, detail: { elt: f.action } });
    assertEqual(f.gate.guard(custom), true);
    assertEqual(custom.defaultPrevented, true);
    const ordinarySave = new CustomEvent("htmx:beforeRequest", { cancelable: true, detail: { elt: f.edit } });
    assertEqual(f.gate.guard(ordinarySave), false);
}));

test("overlapping dirty targets keep validation and acknowledgements local regardless of registration order", () => fixture((f) => {
    const parent = f.owner.append(new Node({}, "parent-target"));
    parent.append(f.target);
    const sibling = parent.append(new Node({}, "sibling-target"));
    const form = sibling.append(new Form());
    const owner = f.owner as unknown as HTMLElement;
    const policy = { kind: "dirty-form", savedHeader: "X-Test-Saved" } as const;
    f.forms.register(owner, parent as unknown as HTMLElement, policy);
    f.forms.register(owner, sibling as unknown as HTMLElement, policy);
    f.forms.register(owner, parent as unknown as HTMLElement, policy);
    form.snapshot = "submitted";
    const xhr = new Xhr();
    f.forms.handleEvent(new CustomEvent("htmx:beforeRequest", { detail: { xhr, elt: form } }));
    xhr.status = 409;
    f.forms.handleEvent(new CustomEvent("htmx:beforeOnLoad", { detail: { xhr } }));
    const replacement = new Form();
    replacement.snapshot = "submitted";
    sibling.replaceChildren(replacement);
    f.forms.afterSwap(new CustomEvent("htmx:afterSwap", { detail: { xhr } }));
    assertEqual(f.forms.protectedTarget(f.target as unknown as HTMLElement, owner), false);
    assertEqual(f.forms.protectedTarget(parent as unknown as HTMLElement, owner), true);
    const resolved = new Xhr();
    f.forms.handleEvent(new CustomEvent("htmx:beforeRequest", { detail: { xhr: resolved, elt: replacement } }));
    resolved.saved = true;
    f.forms.handleEvent(new CustomEvent("htmx:beforeOnLoad", { detail: { xhr: resolved } }));
    f.forms.handleEvent(new CustomEvent("htmx:afterRequest", { detail: { xhr: resolved } }));
    assertEqual(f.acknowledgements[0], "sibling-target");
    assertEqual(f.forms.protectedTarget(parent as unknown as HTMLElement, owner), false);
}));

test("settled-form gate fails closed when a declared dirty target loses its forms", () => fixture((f) => {
    f.target.replaceChildren();
    f.refresh();
    assertEqual(f.button.disabled, true);
    assertEqual(f.notice.hidden, false);
}));

test("settled-form gate preserves server-disabled controls and isolates nested mounts", () => fixture((f) => {
    const disabled = f.action.append(new Button());
    disabled.disabled = true;
    const nested = f.target.append(new Node({ [surfaceConfigDomAttr]: "nested" }));
    const nestedForm = nested.append(new Form({ [actionAttribute]: "" }));
    const nestedButton = nestedForm.append(new Button());
    f.change("dirty");
    assertEqual(nestedButton.disabled, false);
    f.finish(f.start(), true);
    assertEqual(f.button.disabled, false);
    assertEqual(disabled.disabled, true);
    nestedForm.snapshot = "nested edits";
    f.refresh();
    assertEqual(f.button.disabled, false);
}));
