import { FrontendSurfaceInteractionDom, InteractionDom, intentSubmitEvent } from "../generated/contracts";
import { readActivationIntentPayload } from "../interaction/activation";
import { submitCommittedInteractionIntent } from "../interaction/form-bridge";
import { resolveLiveFragmentInteractionConflict } from "../interaction/live-conflicts";
import { createPointerSessionController, hitTestClosest, readPointerSessionStart } from "../interaction/pointer-session";
import { createActiveInteractionSessionTracker, dispatchInteractionSessionEnd, dispatchInteractionSessionStart } from "../interaction/session-state";
import { createInteractionRuntime } from "../interaction/runtime";
import { InteractionIntentBus } from "../interaction/intent-bus";
import { assertEqual, test } from "./harness";

class MiniElement extends EventTarget {
    readonly children: MiniElement[] = [];
    parent: MiniElement | null = null;
    id = "";
    value = "";
    innerHTML = "";
    style: Record<string, string> = {};
    rect = { left: 0, top: 0, width: 0, height: 0 };
    capturedPointerId: number | null = null;
    releasedPointerId: number | null = null;
    ownerDocument?: { elementFromPoint: (x: number, y: number) => MiniElement | null; createElement?: (tag: string) => MiniElement };
    private readonly attrs = new Map<string, string>();

    constructor(attrs: Record<string, string> = {}) {
        super();
        for (const [name, value] of Object.entries(attrs)) this.attrs.set(name, value);
        this.id = attrs.id ?? "";
        this.value = attrs.value ?? "";
    }

    append(child: MiniElement): MiniElement {
        child.parent = this;
        this.children.push(child);
        return child;
    }

    appendChild(child: MiniElement): MiniElement {
        return this.append(child);
    }

    removeChild(child: MiniElement): MiniElement {
        const index = this.children.indexOf(child);
        if (index >= 0) this.children.splice(index, 1);
        child.parent = null;
        return child;
    }

    get parentNode(): MiniElement | null {
        return this.parent;
    }

    get attributes(): Array<{ name: string; value: string }> {
        return Array.from(this.attrs.entries()).map(([name, value]) => ({ name, value }));
    }

    getAttribute(name: string): string | null {
        return this.attrs.get(name) ?? null;
    }

    setAttribute(name: string, value: string): void {
        this.attrs.set(name, value);
        if (name === "value") this.value = value;
        if (name === "id") this.id = value;
    }

    removeAttribute(name: string): void {
        this.attrs.delete(name);
        if (name === "id") this.id = "";
    }

    cloneNode(deep = false): MiniElement {
        const clone = new MiniElement(Object.fromEntries(this.attrs.entries()));
        clone.id = this.id;
        clone.value = this.value;
        clone.innerHTML = this.innerHTML;
        clone.style = { ...this.style };
        clone.rect = { ...this.rect };
        clone.ownerDocument = this.ownerDocument;
        if (deep) for (const child of this.children) clone.append(child.cloneNode(true));
        return clone;
    }

    getBoundingClientRect(): { left: number; top: number; width: number; height: number } {
        return this.rect;
    }

    setPointerCapture(pointerId: number): void {
        this.capturedPointerId = pointerId;
    }

    releasePointerCapture(pointerId: number): void {
        this.releasedPointerId = pointerId;
    }

    replaceChildren(): void {
        this.children.length = 0;
        this.innerHTML = "";
    }

    querySelectorAll(selector: string): MiniElement[] {
        const matches: MiniElement[] = [];
        const visit = (element: MiniElement) => {
            for (const child of element.children) {
                if (selector === "*" || matchesSelector(child, selector) || matchesTagSelector(child, selector)) matches.push(child);
                visit(child);
            }
        };
        visit(this);
        return matches;
    }

    querySelector(selector: string): MiniElement | null {
        return this.querySelectorAll(selector)[0] ?? null;
    }

    closest(selector: string): MiniElement | null {
        let current: MiniElement | null = this;
        while (current) {
            if (matchesSelector(current, selector)) return current;
            current = current.parent;
        }
        return null;
    }
}

const attrs = InteractionDom.attributes;

function matchesSelector(element: MiniElement, selector: string): boolean {
    if (selector.includes(",")) return selector.split(",").some((part) => matchesSelector(element, part.trim()));
    const equalsMatch = selector.match(/^\[([^=]+)="([^"]*)"\]$/);
    if (equalsMatch) return element.getAttribute(equalsMatch[1] ?? "") === (equalsMatch[2] ?? "");
    const attrMatch = selector.match(/^\[([^\]]+)\]$/);
    if (attrMatch) return element.getAttribute(attrMatch[1] ?? "") !== null;
    return false;
}

function matchesTagSelector(element: MiniElement, selector: string): boolean {
    const tag = element.getAttribute("tag");
    return selector.split(",").some((part) => part.trim() === tag);
}

function eventWithTarget(type: string, target: MiniElement): Event {
    const event = new Event(type, { bubbles: true, cancelable: true });
    Object.defineProperty(event, "target", { value: target });
    return event;
}

function pointerEventWithTarget(type: string, target: MiniElement, pointerId: number, clientX: number, clientY: number, pointerType = "mouse", modifiers: Partial<Pick<PointerEvent, "ctrlKey" | "shiftKey" | "altKey" | "metaKey">> = {}): Event {
    const event = eventWithTarget(type, target) as Event & { pointerId: number; clientX: number; clientY: number; pointerType: string; ctrlKey?: boolean; shiftKey?: boolean; altKey?: boolean; metaKey?: boolean };
    event.pointerId = pointerId;
    event.clientX = clientX;
    event.clientY = clientY;
    event.pointerType = pointerType;
    event.ctrlKey = modifiers.ctrlKey ?? false;
    event.shiftKey = modifiers.shiftKey ?? false;
    event.altKey = modifiers.altKey ?? false;
    event.metaKey = modifiers.metaKey ?? false;
    return event;
}

function withNavigatorPlatform<T>(platform: string, run: () => T): T {
    const descriptor = Object.getOwnPropertyDescriptor(globalThis, "navigator");
    Object.defineProperty(globalThis, "navigator", { configurable: true, value: { platform } });
    try {
        return run();
    } finally {
        if (descriptor) Object.defineProperty(globalThis, "navigator", descriptor);
        else Reflect.deleteProperty(globalThis, "navigator");
    }
}

function keyEvent(key: string, modifiers: Partial<Pick<KeyboardEvent, "ctrlKey" | "shiftKey" | "altKey" | "metaKey">> = {}, type = "keydown"): Event {
    const event = new Event(type, { bubbles: true, cancelable: true }) as Event & { key: string; ctrlKey?: boolean; shiftKey?: boolean; altKey?: boolean; metaKey?: boolean };
    event.key = key;
    event.ctrlKey = modifiers.ctrlKey ?? false;
    event.shiftKey = modifiers.shiftKey ?? false;
    event.altKey = modifiers.altKey ?? false;
    event.metaKey = modifiers.metaKey ?? false;
    return event;
}

function buildMount(): { mount: MiniElement; form: MiniElement; required: MiniElement; optional: MiniElement; marker: MiniElement } {
    const mount = new MiniElement({ [attrs.surface]: "roster", [attrs.mountKey]: "primary" });
    const marker = mount.append(new MiniElement({ [attrs.intent]: "select-cell" }));
    const form = mount.append(new MiniElement({
        [attrs.intentForm]: "select-cell",
        [attrs.intent]: "select-cell",
        "hx-trigger": `${intentSubmitEvent} from:this`,
    }));
    const required = form.append(new MiniElement({
        name: "cellId",
        value: "",
        [attrs.intentField]: "cellId",
        [attrs.fieldPresence]: "required",
    }));
    const optional = form.append(new MiniElement({
        name: "mode",
        value: "replace",
        [attrs.intentField]: "mode",
        [attrs.fieldPresence]: "optional",
    }));
    form.append(new MiniElement({ name: "intent", value: "select-cell", [attrs.intentHiddenField]: "intent" }));
    return { mount, form, required, optional, marker };
}

test("interaction intent bus emits cancelable normalized events", () => {
    const bus = new InteractionIntentBus();
    let observedPhase = "";
    bus.observe((event) => {
        observedPhase = event.detail.phase;
        assertEqual(event.detail.fields.cellId, "cell-1");
        event.preventDefault();
    });

    const result = bus.emit({ phase: "commit", intent: "select-cell", fields: { cellId: "cell-1" } });

    assertEqual(observedPhase, "commit");
    assertEqual(result.canceled, true);
});

test("generated activation refs emit manifest-backed committed intent payloads", () => {
    const mount = new MiniElement({ [attrs.surface]: "roster", [attrs.mountKey]: "primary" });
    const marker = mount.append(new MiniElement({ [FrontendSurfaceInteractionDom.activationRef]: "roster-layout-mode-activation" }));
    const input = marker.append(new MiniElement({ tag: "input", value: "day_columns" }));

    const payload = readActivationIntentPayload(eventWithTarget("click", input), "click");

    assertEqual(payload?.phase, "commit");
    assertEqual(payload?.intent, "set-roster-layout-mode");
    assertEqual(payload?.fields?.rosterLayoutMode, "day_columns");
    assertEqual(payload?.mount, mount as unknown as Element);
    assertEqual(payload?.marker, marker as unknown as Element);
});

test("generated activation refs ignore non-matching triggers", () => {
    const mount = new MiniElement({ [attrs.surface]: "roster", [attrs.mountKey]: "primary" });
    const marker = mount.append(new MiniElement({ [FrontendSurfaceInteractionDom.activationRef]: "roster-layout-mode-activation" }));
    const child = marker.append(new MiniElement({ tag: "input", value: "day_columns" }));

    assertEqual(readActivationIntentPayload(eventWithTarget("change", child), "change"), null);
    assertEqual(readActivationIntentPayload(eventWithTarget("click", child), "click")?.intent, "set-roster-layout-mode");
});

test("committed intents fill the matching helper-rendered form and dispatch the generated trigger", () => {
    const { mount, form, required, optional } = buildMount();
    let dispatchedTrigger = "";
    form.addEventListener(intentSubmitEvent, (event) => {
        dispatchedTrigger = event.type;
    });

    const result = submitCommittedInteractionIntent({
        phase: "commit",
        intent: "select-cell",
        fields: { cellId: "cell-1" },
        mount: mount as unknown as Element,
        marker: null,
        sourceEvent: null,
    }, { warn: () => undefined });

    assertEqual(result.ok, true);
    assertEqual(required.value, "cell-1");
    assertEqual(required.getAttribute("value"), "cell-1");
    assertEqual(optional.value, "replace");
    assertEqual(dispatchedTrigger, intentSubmitEvent);
});

test("bridge resolves the concrete mount from an activation marker", () => {
    const { marker, required } = buildMount();

    const result = submitCommittedInteractionIntent({
        phase: "commit",
        intent: "select-cell",
        fields: { cellId: "cell-2" },
        mount: null,
        marker: marker as unknown as Element,
        sourceEvent: null,
    }, { warn: () => undefined });

    assertEqual(result.ok, true);
    assertEqual(required.value, "cell-2");
});

test("bridge resolves named nested FrontendSurface mounts from the closest owner", () => {
    const parent = new MiniElement({ [attrs.surface]: "parent", [attrs.mountKey]: "primary" });
    const child = parent.append(new MiniElement({ [attrs.surface]: "child", [attrs.mountKey]: "primary" }));
    const marker = child.append(new MiniElement({ [attrs.intent]: "select-cell" }));
    const parentForm = parent.append(new MiniElement({
        [attrs.intentForm]: "select-cell",
        [attrs.intent]: "select-cell",
        "hx-trigger": `${intentSubmitEvent} from:this`,
    }));
    const parentRequired = parentForm.append(new MiniElement({ name: "cellId", value: "", [attrs.intentField]: "cellId", [attrs.fieldPresence]: "required" }));
    const childForm = child.append(new MiniElement({
        [attrs.intentForm]: "select-cell",
        [attrs.intent]: "select-cell",
        "hx-trigger": `${intentSubmitEvent} from:this`,
    }));
    const childRequired = childForm.append(new MiniElement({ name: "cellId", value: "", [attrs.intentField]: "cellId", [attrs.fieldPresence]: "required" }));

    const result = submitCommittedInteractionIntent({
        phase: "commit",
        intent: "select-cell",
        fields: { cellId: "child-cell" },
        mount: null,
        marker: marker as unknown as Element,
        sourceEvent: null,
    }, { warn: () => undefined });

    assertEqual(result.ok, true);
    assertEqual(parentRequired.value, "");
    assertEqual(childRequired.value, "child-cell");
});

test("strict validation rejects unknown and missing fields without partial mutation", () => {
    const { mount, required } = buildMount();
    const warnings: string[] = [];

    const unknown = submitCommittedInteractionIntent({
        phase: "commit",
        intent: "select-cell",
        fields: { cellId: "cell-1", unexpected: "nope" },
        mount: mount as unknown as Element,
        marker: null,
        sourceEvent: null,
    }, { warn: (message) => warnings.push(message) });
    const missing = submitCommittedInteractionIntent({
        phase: "commit",
        intent: "select-cell",
        fields: {},
        mount: mount as unknown as Element,
        marker: null,
        sourceEvent: null,
    }, { warn: (message) => warnings.push(message) });

    assertEqual(unknown.ok, false);
    assertEqual(missing.ok, false);
    assertEqual(required.value, "");
    assertEqual(warnings.length, 2);
});

test("runtime submits uncanceled committed intents and does not submit canceled commits", () => {
    const { mount, required } = buildMount();
    const runtime = createInteractionRuntime({ logger: { warn: () => undefined } });

    const submitted = runtime.emit({ phase: "commit", intent: "select-cell", fields: { cellId: "cell-3" }, mount: mount as unknown as Element });
    assertEqual(submitted.canceled, false);
    assertEqual(submitted.submitted?.ok, true);
    assertEqual(required.value, "cell-3");

    runtime.bus.observe((event) => event.preventDefault());
    const canceled = runtime.emit({ phase: "commit", intent: "select-cell", fields: { cellId: "cell-4" }, mount: mount as unknown as Element });
    assertEqual(canceled.canceled, true);
    assertEqual(required.value, "cell-3");
    runtime.stop();
});

test("generated source refs start manifest-backed pointer sessions", () => {
    const mount = new MiniElement({ [attrs.surface]: "roster" });
    const marker = mount.append(new MiniElement({
        [FrontendSurfaceInteractionDom.sourceRef]: "shift-drag-source",
        [FrontendSurfaceInteractionDom.sourceKey]: "shift:1",
    }));

    const session = readPointerSessionStart(pointerEventWithTarget("pointerdown", marker, 7, 10, 20), 4);

    assertEqual(session?.intent, "move-roster-shift-to-slot");
    assertEqual(session?.sessionKind, "drag");
    assertEqual(session?.sourceField, "sourceItemKey");
    assertEqual(session?.sourceKey, "shift:1");
    assertEqual(session?.targetField, "targetDropzoneKey");
});

test("generated pointer sessions emit manifest fields from compatible dropzones", () => {
    const observed: string[] = [];
    const mount = new MiniElement({ [attrs.surface]: "roster", [attrs.surfaceFamily]: "roster" });
    const marker = mount.append(new MiniElement({
        [FrontendSurfaceInteractionDom.sourceRef]: "shift-drag-source",
        [FrontendSurfaceInteractionDom.sourceKey]: "shift:1",
        [attrs.sessionThreshold]: "0",
    }));
    const dropzone = mount.append(new MiniElement({
        [FrontendSurfaceInteractionDom.dropzoneRef]: "shift-create-dropzone",
        [FrontendSurfaceInteractionDom.dropzoneKey]: "slot:2",
    }));
    const layer = mount.append(new MiniElement({ [attrs.disposableLayer]: "drag-preview" }));
    const doc = { elementFromPoint: (_x: number, _y: number) => dropzone, createElement: (_tag: string) => new MiniElement() };
    mount.ownerDocument = doc;
    marker.ownerDocument = doc;
    dropzone.ownerDocument = doc;
    layer.ownerDocument = doc;

    const controller = createPointerSessionController({
        runtime: {
            emit(payload) {
                if (payload.phase === "preview" || payload.phase === "commit") {
                    observed.push(`${payload.fields?.sourceItemKey ?? ""}->${payload.fields?.targetDropzoneKey ?? ""}`);
                }
                return { canceled: false };
            },
        },
    });

    controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 1, 0, 0));
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 1, 0));
    controller.handlePointerUp(pointerEventWithTarget("pointerup", marker, 1, 2, 0));

    assertEqual(observed.join(","), "shift:1->slot:2,shift:1->slot:2,shift:1->slot:2");
    assertEqual(dropzone.getAttribute("class"), null);
    assertEqual(layer.children.length, 0);
});

test("generated pointer sessions use source-specific compatible dropzones", () => {
    const observed: string[] = [];
    const mount = new MiniElement({ [attrs.surface]: "roster", [attrs.surfaceFamily]: "roster" });
    const marker = mount.append(new MiniElement({
        [FrontendSurfaceInteractionDom.sourceRef]: "staff-drag-source",
        [FrontendSurfaceInteractionDom.sourceKey]: "staff:1",
        [attrs.sessionThreshold]: "0",
    }));
    const dayDropzone = mount.append(new MiniElement({
        [FrontendSurfaceInteractionDom.dropzoneRef]: "day-column-dropzone",
        [FrontendSurfaceInteractionDom.dropzoneKey]: "day:1",
    }));
    const compatibleDropzone = mount.append(new MiniElement({
        [FrontendSurfaceInteractionDom.dropzoneRef]: "existing-shift-dropzone",
        [FrontendSurfaceInteractionDom.dropzoneKey]: "existing:2",
    }));
    const layer = mount.append(new MiniElement({ [attrs.disposableLayer]: "drag-preview" }));
    let hitTarget: MiniElement | null = dayDropzone;
    const doc = { elementFromPoint: (_x: number, _y: number) => hitTarget, createElement: (_tag: string) => new MiniElement() };
    mount.ownerDocument = doc;
    marker.ownerDocument = doc;
    dayDropzone.ownerDocument = doc;
    compatibleDropzone.ownerDocument = doc;
    layer.ownerDocument = doc;

    const controller = createPointerSessionController({
        runtime: {
            emit(payload) {
                if (payload.phase === "preview" || payload.phase === "commit") {
                    observed.push(`${payload.fields?.sourceItemKey ?? ""}->${payload.fields?.targetDropzoneKey ?? ""}`);
                }
                return { canceled: false };
            },
        },
    });

    controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 1, 0, 0));
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 1, 0));
    hitTarget = compatibleDropzone;
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 2, 0));
    controller.handlePointerUp(pointerEventWithTarget("pointerup", marker, 1, 3, 0));

    assertEqual(observed.join(","), "staff:1->day:1,staff:1->existing:2,staff:1->existing:2,staff:1->existing:2");
    assertEqual(dayDropzone.getAttribute("class"), null);
    assertEqual(compatibleDropzone.getAttribute("class"), null);
});

test("generated pointer sessions start only from enabled mounted handles", () => {
    const mount = new MiniElement({ [attrs.surface]: "roster" });
    const marker = mount.append(new MiniElement({
        [FrontendSurfaceInteractionDom.sourceRef]: "shift-drag-source",
        [FrontendSurfaceInteractionDom.sourceKey]: "shift:1",
    }));

    const session = readPointerSessionStart(pointerEventWithTarget("pointerdown", marker, 7, 10, 20), 4);

    assertEqual(session?.intent, "move-roster-shift-to-slot");
    assertEqual(session?.sessionKind, "drag");
    assertEqual(session?.pointerId, 7);
    assertEqual(session?.startClientX, 10);
});

test("pointer sessions emit start preview commit and clean disposable layers", () => {
    const phases: string[] = [];
    const deltas: string[] = [];
    const dropTargets: string[] = [];
    const mount = new MiniElement({ [attrs.surface]: "roster" });
    const marker = mount.append(new MiniElement({
        [FrontendSurfaceInteractionDom.sourceRef]: "shift-drag-source",
        [FrontendSurfaceInteractionDom.sourceKey]: "existing:source-slot",
        [attrs.sessionThreshold]: "3",
    }));
    const dropzone = mount.append(new MiniElement({ [FrontendSurfaceInteractionDom.dropzoneRef]: "shift-create-dropzone", [FrontendSurfaceInteractionDom.dropzoneKey]: "new:target-slot" }));
    const doc = {
        elementFromPoint: (_x: number, _y: number) => dropzone,
        createElement: (_tag: string) => new MiniElement(),
    };
    mount.ownerDocument = doc;
    marker.ownerDocument = doc;
    dropzone.ownerDocument = doc;
    const layer = mount.append(new MiniElement({ [attrs.disposableLayer]: "preview" }));
    layer.ownerDocument = doc;
    layer.append(new MiniElement());

    const controller = createPointerSessionController({
        runtime: {
            emit(payload) {
                phases.push(payload.phase);
                if (payload.phase === "preview" || payload.phase === "commit") {
                    deltas.push(payload.fields?.deltaX ?? "");
                    dropTargets.push(`${payload.fields?.sourceItemKey ?? ""}->${payload.fields?.targetDropzoneKey ?? ""}`);
                }
                return { canceled: false };
            },
        },
    });

    controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 1, 0, 0));
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 2, 20, 0));
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 2, 0));
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 5, 0));
    controller.handlePointerUp(pointerEventWithTarget("pointerup", marker, 1, 8, 0));

    assertEqual(phases.join(","), "start,preview,preview,commit");
    assertEqual(deltas.join(","), "5,8,8");
    assertEqual(dropTargets.join(","), "existing:source-slot->new:target-slot,existing:source-slot->new:target-slot,existing:source-slot->new:target-slot");
    assertEqual(marker.capturedPointerId, 1);
    assertEqual(marker.releasedPointerId, 1);
    assertEqual(layer.children.length, 0);
    assertEqual(controller.currentSession(), null);
});

test("generated pointer session effects render proxy shadows and highlight dropzones", () => {
    const phases: string[] = [];
    const mount = new MiniElement({ [attrs.surface]: "roster", [attrs.surfaceFamily]: "roster" });
    const marker = mount.append(new MiniElement({
        id: "source-id",
        class: "shift-card",
        "hx-post": "/Move",
        [FrontendSurfaceInteractionDom.sourceRef]: "shift-drag-source",
        [FrontendSurfaceInteractionDom.sourceKey]: "existing:source-slot",
        [attrs.sessionThreshold]: "4",
    }));
    marker.rect = { left: 10, top: 20, width: 80, height: 30 };
    marker.append(new MiniElement({ id: "child-id" }));
    const firstDropzone = mount.append(new MiniElement({ [FrontendSurfaceInteractionDom.dropzoneRef]: "shift-create-dropzone", [FrontendSurfaceInteractionDom.dropzoneKey]: "new:first-slot" }));
    const secondDropzone = mount.append(new MiniElement({ [FrontendSurfaceInteractionDom.dropzoneRef]: "shift-create-dropzone", [FrontendSurfaceInteractionDom.dropzoneKey]: "new:second-slot" }));
    const layer = mount.append(new MiniElement({ [attrs.disposableLayer]: "drag-preview" }));
    let hitTarget: MiniElement | null = firstDropzone;
    const doc = {
        elementFromPoint: (_x: number, _y: number) => hitTarget,
        createElement: (_tag: string) => new MiniElement(),
    };
    mount.ownerDocument = doc;
    marker.ownerDocument = doc;
    firstDropzone.ownerDocument = doc;
    secondDropzone.ownerDocument = doc;
    layer.ownerDocument = doc;

    const controller = createPointerSessionController({ runtime: { emit: (payload) => { phases.push(payload.phase); return { canceled: false }; } } });

    controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 1, 25, 35));
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 26, 35));
    assertEqual(layer.children.length, 0);

    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 30, 40));
    const shadow = layer.children[0];
    if (!shadow) throw new Error("Expected proxy shadow");
    assertEqual(shadow.children.length, 0);
    assertEqual(shadow.getAttribute("aria-hidden"), "true");
    assertEqual(shadow.getAttribute("class"), "bepis-pointer-clone-shadow");
    assertEqual(shadow.style.pointerEvents, "none");
    assertEqual(shadow.style.width, "80px");
    assertEqual(shadow.style.height, "30px");
    assertEqual(shadow.style.transform, "translate3d(15px, 25px, 0)");
    assertEqual(firstDropzone.getAttribute("class"), "bepis-dropzone-highlight");

    hitTarget = secondDropzone;
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 40, 50));
    assertEqual(shadow.style.transform, "translate3d(25px, 35px, 0)");
    assertEqual(firstDropzone.getAttribute("class"), null);
    assertEqual(secondDropzone.getAttribute("class"), "bepis-dropzone-highlight");

    hitTarget = null;
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 45, 55));
    assertEqual(secondDropzone.getAttribute("class"), null);

    hitTarget = secondDropzone;
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 50, 60));
    assertEqual(secondDropzone.getAttribute("class"), "bepis-dropzone-highlight");
    controller.handlePointerUp(pointerEventWithTarget("pointerup", marker, 1, 50, 60));

    assertEqual(layer.children.length, 0);
    assertEqual(secondDropzone.getAttribute("class"), null);
    assertEqual(phases.join(","), "start,preview,preview,preview,preview,preview,commit");
});

test("touch pointers do not start generic drag sessions", () => {
    const phases: string[] = [];
    const mount = new MiniElement({ [attrs.surface]: "roster", [attrs.surfaceFamily]: "roster" });
    const marker = mount.append(new MiniElement({
        [FrontendSurfaceInteractionDom.sourceRef]: "shift-drag-source",
        [FrontendSurfaceInteractionDom.sourceKey]: "existing:source-slot",
        [attrs.sessionThreshold]: "0",
    }));
    const controller = createPointerSessionController({ runtime: { emit: (payload) => { phases.push(payload.phase); return { canceled: false }; } } });

    controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 9, 0, 0, "touch"));
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 9, 20, 0, "touch"));
    controller.handlePointerUp(pointerEventWithTarget("pointerup", marker, 9, 20, 0, "touch"));

    assertEqual(phases.join(","), "");
    assertEqual(controller.currentSession(), null);
});

test("pointer modifier variants select copy intent and variant shadow on platform-native keys", () => {
    withNavigatorPlatform("Win32", () => {
        const intents: string[] = [];
        const mount = new MiniElement({ [attrs.surface]: "roster", [attrs.surfaceFamily]: "roster" });
        const marker = mount.append(new MiniElement({
            [FrontendSurfaceInteractionDom.sourceRef]: "shift-drag-source",
            [FrontendSurfaceInteractionDom.sourceKey]: "existing:source-slot",
            [attrs.sessionThreshold]: "0",
        }));
        marker.rect = { left: 0, top: 0, width: 40, height: 20 };
        const dropzone = mount.append(new MiniElement({ [FrontendSurfaceInteractionDom.dropzoneRef]: "shift-create-dropzone", [FrontendSurfaceInteractionDom.dropzoneKey]: "day:target" }));
        const layer = mount.append(new MiniElement({ [attrs.disposableLayer]: "drag-preview" }));
        const doc = { elementFromPoint: (_x: number, _y: number) => dropzone, createElement: (_tag: string) => new MiniElement() };
        mount.ownerDocument = doc;
        marker.ownerDocument = doc;
        dropzone.ownerDocument = doc;
        layer.ownerDocument = doc;

        const controller = createPointerSessionController({ runtime: { emit: (payload) => { if (payload.phase === "preview" || payload.phase === "commit") intents.push(payload.intent); return { canceled: false }; } } });
        controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 1, 0, 0));
        controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 8, 0));
        const moveShadow = layer.children[0];
        if (!moveShadow) throw new Error("Expected move proxy shadow");
        assertEqual(moveShadow.getAttribute("class"), "bepis-pointer-clone-shadow");
        controller.handleKeyDown(keyEvent("Control", { ctrlKey: true }));
        const copyShadow = layer.children[0];
        if (!copyShadow) throw new Error("Expected copy proxy shadow");
        assertEqual(copyShadow.getAttribute("class"), "bepis-pointer-clone-shadow bepis-pointer-clone-shadow-copy");
        controller.handlePointerUp(pointerEventWithTarget("pointerup", marker, 1, 8, 0, "mouse", { ctrlKey: true }));
        assertEqual(intents.join(","), "move-roster-shift-to-slot,duplicate-roster-shift-to-day,duplicate-roster-shift-to-day");
    });

    withNavigatorPlatform("MacIntel", () => {
        const committed: string[] = [];
        const mount = new MiniElement({ [attrs.surface]: "roster", [attrs.surfaceFamily]: "roster" });
        const marker = mount.append(new MiniElement({ [FrontendSurfaceInteractionDom.sourceRef]: "shift-drag-source", [FrontendSurfaceInteractionDom.sourceKey]: "existing:source-slot", [attrs.sessionThreshold]: "0" }));
        marker.rect = { left: 0, top: 0, width: 10, height: 10 };
        const dropzone = mount.append(new MiniElement({ [FrontendSurfaceInteractionDom.dropzoneRef]: "shift-create-dropzone", [FrontendSurfaceInteractionDom.dropzoneKey]: "day:target" }));
        const layer = mount.append(new MiniElement({ [attrs.disposableLayer]: "drag-preview" }));
        const doc = { elementFromPoint: (_x: number, _y: number) => dropzone, createElement: (_tag: string) => new MiniElement() };
        mount.ownerDocument = doc;
        marker.ownerDocument = doc;
        dropzone.ownerDocument = doc;
        layer.ownerDocument = doc;

        const controller = createPointerSessionController({ runtime: { emit: (payload) => { if (payload.phase === "commit") committed.push(payload.intent); return { canceled: false }; } } });
        controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 2, 0, 0));
        controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 2, 8, 0, "mouse", { ctrlKey: true }));
        controller.handlePointerUp(pointerEventWithTarget("pointerup", marker, 2, 8, 0, "mouse", { ctrlKey: true }));
        assertEqual(committed.join(","), "move-roster-shift-to-slot");

        committed.length = 0;
        controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 3, 0, 0));
        controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 3, 8, 0, "mouse", { altKey: true }));
        controller.handlePointerUp(pointerEventWithTarget("pointerup", marker, 3, 8, 0, "mouse", { altKey: true }));
        assertEqual(committed.join(","), "duplicate-roster-shift-to-day");
    });
});

test("pointer session effect cleanup runs on pointercancel Escape and external cleanup", () => {
    const build = () => {
        const mount = new MiniElement({ [attrs.surface]: "roster", [attrs.surfaceFamily]: "roster" });
        const marker = mount.append(new MiniElement({
            [FrontendSurfaceInteractionDom.sourceRef]: "shift-drag-source",
            [FrontendSurfaceInteractionDom.sourceKey]: "existing:source-slot",
            [attrs.sessionThreshold]: "0",
        }));
        marker.rect = { left: 0, top: 0, width: 10, height: 10 };
        const dropzone = mount.append(new MiniElement({ [FrontendSurfaceInteractionDom.dropzoneRef]: "shift-create-dropzone", [FrontendSurfaceInteractionDom.dropzoneKey]: "slot" }));
        const layer = mount.append(new MiniElement({ [attrs.disposableLayer]: "drag-preview" }));
        const doc = { elementFromPoint: (_x: number, _y: number) => dropzone, createElement: (_tag: string) => new MiniElement() };
        mount.ownerDocument = doc;
        marker.ownerDocument = doc;
        dropzone.ownerDocument = doc;
        layer.ownerDocument = doc;
        const controller = createPointerSessionController({ runtime: { emit: () => ({ canceled: false }) } });
        controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 1, 0, 0));
        controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 5, 5));
        assertEqual(layer.children.length, 1);
        assertEqual(dropzone.getAttribute("class"), "bepis-dropzone-highlight");
        return { controller, marker, layer, dropzone };
    };

    const pointerCancel = build();
    pointerCancel.controller.handlePointerCancel(pointerEventWithTarget("pointercancel", pointerCancel.marker, 1, 5, 5));
    assertEqual(pointerCancel.layer.children.length, 0);
    assertEqual(pointerCancel.dropzone.getAttribute("class"), null);

    const escape = build();
    escape.controller.handleKeyDown(keyEvent("Escape"));
    assertEqual(escape.layer.children.length, 0);
    assertEqual(escape.dropzone.getAttribute("class"), null);

    const external = build();
    external.controller.handleExternalCleanup(eventWithTarget("htmx:beforeCleanupElement", external.marker));
    assertEqual(external.layer.children.length, 0);
    assertEqual(external.dropzone.getAttribute("class"), null);
});

test("pointer sessions cancel below threshold, on pointercancel, and on Escape", () => {
    const phases: string[] = [];
    const mount = new MiniElement({ [attrs.surface]: "roster" });
    const marker = mount.append(new MiniElement({
        [FrontendSurfaceInteractionDom.sourceRef]: "shift-drag-source",
        [FrontendSurfaceInteractionDom.sourceKey]: "resize-source",
        [attrs.sessionThreshold]: "5",
    }));
    const controller = createPointerSessionController({ runtime: { emit: (payload) => { phases.push(payload.phase); return { canceled: false }; } } });

    controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 1, 0, 0));
    controller.handlePointerUp(pointerEventWithTarget("pointerup", marker, 1, 1, 0));
    controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 2, 0, 0));
    controller.handlePointerCancel(pointerEventWithTarget("pointercancel", marker, 2, 0, 0));
    controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 3, 0, 0));
    controller.handleKeyDown(keyEvent("Escape"));

    assertEqual(phases.join(","), "start,cancel,start,cancel,start,cancel");
    assertEqual(controller.currentSession(), null);
});

test("pointer sessions ignore disabled markers and hit-test under disposable overlays", () => {
    const mount = new MiniElement({ [attrs.surface]: "roster" });
    const disabled = mount.append(new MiniElement({
        [FrontendSurfaceInteractionDom.sourceRef]: "shift-drag-source",
        [FrontendSurfaceInteractionDom.sourceKey]: "shift:1",
        [attrs.sessionDisabled]: "true",
    }));
    const dropzone = new MiniElement({ [FrontendSurfaceInteractionDom.dropzoneRef]: "shift-create-dropzone" });
    const doc = { elementFromPoint: (_x: number, _y: number) => dropzone };
    mount.ownerDocument = doc;
    dropzone.ownerDocument = doc;

    assertEqual(readPointerSessionStart(pointerEventWithTarget("pointerdown", disabled, 1, 0, 0)), null);
    assertEqual(hitTestClosest(mount as unknown as Element, 12, 34, `[${FrontendSurfaceInteractionDom.dropzoneRef}=\"shift-create-dropzone\"]`), dropzone as unknown as Element);
});

test("live fragment conflicts defer matching active interaction sessions and ignore unrelated mounts", () => {
    const root = new EventTarget() as Document;
    const tracker = createActiveInteractionSessionTracker(root);
    const mount = new MiniElement({ id: "mount-1", [attrs.surface]: "roster" });
    const target = mount.append(new MiniElement({ id: "fragment-1" }));
    const otherMount = new MiniElement({ id: "mount-2", [attrs.surface]: "roster" });
    const otherTarget = otherMount.append(new MiniElement({ id: "fragment-2" }));

    dispatchInteractionSessionStart({ mount: mount as unknown as Element, mountId: "mount-1", sessionKind: "drag", intent: "move" }, root);

    const conflict = resolveLiveFragmentInteractionConflict({ targetId: "fragment-1" }, target as unknown as Element, tracker);
    const unrelated = resolveLiveFragmentInteractionConflict({ targetId: "fragment-2" }, otherTarget as unknown as Element, tracker);

    assertEqual(conflict?.action, "defer");
    assertEqual(conflict?.session.mountId, "mount-1");
    assertEqual(unrelated, null);
    dispatchInteractionSessionEnd({ mount: mount as unknown as Element, mountId: "mount-1", sessionKind: "drag", intent: "move" }, root);
    assertEqual(resolveLiveFragmentInteractionConflict({ targetId: "fragment-1" }, target as unknown as Element, tracker), null);
    tracker.stop();
});

test("live fragment conflicts resolve named child surface sessions from nearest mount", () => {
    const root = new EventTarget() as Document;
    const tracker = createActiveInteractionSessionTracker(root);
    const parent = new MiniElement({ id: "parent-mount", [attrs.surface]: "parent" });
    const child = parent.append(new MiniElement({ id: "child-mount", [attrs.surface]: "child" }));
    const target = child.append(new MiniElement({ id: "child-fragment" }));

    dispatchInteractionSessionStart({ mount: parent as unknown as Element, mountId: "parent-mount", sessionKind: "drag", intent: "move" }, root);
    dispatchInteractionSessionStart({ mount: child as unknown as Element, mountId: "child-mount", sessionKind: "resize", intent: "resize" }, root);

    const conflict = resolveLiveFragmentInteractionConflict({ targetId: "child-fragment" }, target as unknown as Element, tracker);

    assertEqual(conflict?.session.mountId, "child-mount");
    tracker.stop();
});

test("live fragment conflicts honor generated cancel policies", () => {
    const root = new EventTarget() as Document;
    const tracker = createActiveInteractionSessionTracker(root);
    const mount = new MiniElement({
        id: "mount-1",
        [attrs.surface]: "roster",
        [attrs.conflictPolicies]: JSON.stringify([{ session: "resize", targetId: "fragment-1", resolution: "cancel", timeoutMs: 10 }]),
    });
    const target = mount.append(new MiniElement({ id: "fragment-1" }));

    dispatchInteractionSessionStart({ mount: mount as unknown as Element, mountId: "mount-1", sessionKind: "resize", intent: "resize" }, root);
    const conflict = resolveLiveFragmentInteractionConflict({ targetId: "fragment-1" }, target as unknown as Element, tracker);

    assertEqual(conflict?.action, "cancel");
    assertEqual(conflict?.timeoutMs, 10);
    tracker.stop();
});
