import { InteractionDom } from "../generated/contracts";
import { readIntervalDrag } from "../interaction/interval-drag";
import { readActivationIntentPayload } from "../interaction/activation";
import { submitCommittedInteractionIntent } from "../interaction/form-bridge";
import { resolveLiveFragmentInteractionConflict } from "../interaction/live-conflicts";
import { createPointerSessionController, hitTestClosest, readPointerSessionStart, scrollDragContainer, scrollHorizontalDragContainer } from "../interaction/pointer-session";
import { createActiveInteractionSessionTracker, dispatchInteractionSessionEnd, dispatchInteractionSessionStart } from "../interaction/session-state";
import { createInteractionRuntime } from "../interaction/runtime";
import { InteractionIntentBus } from "../interaction/intent-bus";
import { assertEqual, test } from "./harness";
import { MiniElement as SharedMiniElement } from "./mini-dom";

const intentSubmitEvent = "bepis:intent-submit"; // frontend-contract-token-fixture

class MiniElement extends SharedMiniElement {
    declare readonly children: MiniElement[];
    innerHTML = "";
    style: Record<string, string> = {};
    rect = { left: 0, top: 0, width: 0, height: 0 };
    capturedPointerId: number | null = null;
    releasedPointerId: number | null = null;
    ownerDocument?: { elementFromPoint: (x: number, y: number) => MiniElement | null; createElement?: (tag: string) => MiniElement };

    matches(selector: string): boolean {
        const fixtureTag = this.getAttribute("tag");
        return selector.split(",").some((part) => part.trim() === fixtureTag || super.matches(part.trim()));
    }

    cloneNode(deep = false): MiniElement {
        const clone = new MiniElement(Object.fromEntries(this.attributes.map(({ name, value }) => [name, value])));
        clone.id = this.id;
        clone.value = this.value;
        clone.innerHTML = this.innerHTML;
        clone.style = { ...this.style };
        clone.rect = { ...this.rect };
        clone.ownerDocument = this.ownerDocument;
        if (deep) this.children.forEach((child) => clone.append(child.cloneNode(true)));
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
        super.replaceChildren();
        this.innerHTML = "";
    }
}

const attrs = InteractionDom.attributes;

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
    const mount = new MiniElement({ [attrs.surface]: "roster" });
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
    form.append(new MiniElement({ name: "intent", value: "select-cell" }));
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
    const mount = new MiniElement({ [attrs.surface]: "roster" });
    const marker = mount.append(new MiniElement({ [attrs.activationRef]: "roster-layout-mode-activation" }));
    const input = marker.append(new MiniElement({ tag: "input", value: "day_columns" }));

    const payload = readActivationIntentPayload(eventWithTarget("click", input), "click");

    assertEqual(payload?.phase, "commit");
    assertEqual(payload?.intent, "set-roster-layout-mode");
    assertEqual(payload?.fields?.rosterLayoutMode, "day_columns");
    assertEqual(payload?.mount, mount as unknown as Element);
    assertEqual(payload?.marker, marker as unknown as Element);
});

test("generated activation refs ignore non-matching triggers", () => {
    const mount = new MiniElement({ [attrs.surface]: "roster" });
    const marker = mount.append(new MiniElement({ [attrs.activationRef]: "roster-layout-mode-activation" }));
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

test("bridge preserves server-rendered required context fields omitted by the interaction session", () => {
    const { mount, form } = buildMount();
    const calendarRevision = form.append(new MiniElement({
        name: "rosterCalendarRevision",
        value: "7",
        [attrs.intentField]: "rosterCalendarRevision",
        [attrs.fieldPresence]: "required",
    }));

    const result = submitCommittedInteractionIntent({
        phase: "commit",
        intent: "select-cell",
        fields: { cellId: "cell-2" },
        mount: mount as unknown as Element,
        marker: null,
        sourceEvent: null,
    }, { warn: () => undefined });

    assertEqual(result.ok, true);
    assertEqual(calendarRevision.value, "7");
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
    const parent = new MiniElement({ [attrs.surface]: "parent" });
    const child = parent.append(new MiniElement({ [attrs.surface]: "child" }));
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
        [attrs.sourceRef]: "shift-drag-source",
        [attrs.sourceKey]: "shift:1",
    }));

    const session = readPointerSessionStart(pointerEventWithTarget("pointerdown", marker, 7, 10, 20), 4);

    assertEqual(session?.intent, "move-roster-shift-to-slot");
    assertEqual(session?.sessionKind, "drag");
    assertEqual(session?.sourceField, "sourceItemKey");
    assertEqual(session?.sourceKey, "shift:1");
    assertEqual(session?.targetField, "targetDropzoneKey");
});

test("generated pointer sessions ignore nested interactive controls inside draggable sources", () => {
    const mount = new MiniElement({ [attrs.surface]: "roster" });
    const marker = mount.append(new MiniElement({
        tag: "tr",
        role: "button",
        [attrs.sourceRef]: "staff-drag-source",
        [attrs.sourceKey]: "staff:1",
    }));
    const inviteButton = marker.append(new MiniElement({ tag: "button" }));
    const icon = inviteButton.append(new MiniElement({ tag: "i" }));

    const rowSession = readPointerSessionStart(pointerEventWithTarget("pointerdown", marker, 7, 10, 20), 4);
    const buttonSession = readPointerSessionStart(pointerEventWithTarget("pointerdown", inviteButton, 7, 10, 20), 4);
    const iconSession = readPointerSessionStart(pointerEventWithTarget("pointerdown", icon, 7, 10, 20), 4);

    assertEqual(rowSession?.intent, "drop-roster-staff");
    assertEqual(buttonSession, null);
    assertEqual(iconSession, null);
});

test("generated pointer sessions emit manifest fields from compatible dropzones", () => {
    const observed: string[] = [];
    const mount = new MiniElement({ [attrs.surface]: "roster", [attrs.surfaceFamily]: "roster" });
    const marker = mount.append(new MiniElement({
        [attrs.sourceRef]: "shift-drag-source",
        [attrs.sourceKey]: "shift:1",
        [attrs.sessionThreshold]: "0",
    }));
    const dropzone = mount.append(new MiniElement({
        [attrs.dropzoneRef]: "shift-slot-dropzone",
        [attrs.dropzoneKey]: "slot:2",
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

test("generated pointer sessions ignore incompatible dropzones for active source refs", () => {
    const observed: string[] = [];
    const mount = new MiniElement({ [attrs.surface]: "roster", [attrs.surfaceFamily]: "roster" });
    const marker = mount.append(new MiniElement({
        [attrs.sourceRef]: "staff-drag-source",
        [attrs.sourceKey]: "staff:1",
        [attrs.sessionThreshold]: "0",
    }));
    const incompatibleDropzone = mount.append(new MiniElement({
        [attrs.dropzoneRef]: "day-column-dropzone",
        [attrs.dropzoneKey]: "day:1",
    }));
    const compatibleDropzone = mount.append(new MiniElement({
        [attrs.dropzoneRef]: "existing-shift-dropzone",
        [attrs.dropzoneKey]: "existing:2",
    }));
    const layer = mount.append(new MiniElement({ [attrs.disposableLayer]: "drag-preview" }));
    let hitTarget: MiniElement | null = incompatibleDropzone;
    const doc = { elementFromPoint: (_x: number, _y: number) => hitTarget, createElement: (_tag: string) => new MiniElement() };
    mount.ownerDocument = doc;
    marker.ownerDocument = doc;
    incompatibleDropzone.ownerDocument = doc;
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

    assertEqual(observed.join(","), "staff:1->,staff:1->existing:2,staff:1->existing:2,staff:1->existing:2");
    assertEqual(incompatibleDropzone.getAttribute("class"), null);
    assertEqual(compatibleDropzone.getAttribute("class"), null);
});

test("generated pointer sessions start only from enabled mounted handles", () => {
    const mount = new MiniElement({ [attrs.surface]: "roster" });
    const marker = mount.append(new MiniElement({
        [attrs.sourceRef]: "shift-drag-source",
        [attrs.sourceKey]: "shift:1",
    }));

    const session = readPointerSessionStart(pointerEventWithTarget("pointerdown", marker, 7, 10, 20), 4);

    assertEqual(session?.intent, "move-roster-shift-to-slot");
    assertEqual(session?.sessionKind, "drag");
    assertEqual(session?.pointerId, 7);
    assertEqual(session?.startClientX, 10);
});

test("interval projection preserves grab offset, clamps to allowed starts and shares opaque targets across lanes", () => {
    const mount = new MiniElement({ [attrs.surface]: "roster" });
    const config = { rangeSize: 1000, extent: 400, positions: [0, 250, 500], labels: ["early", "middle", "late"] };
    const first = mount.append(new MiniElement({ [attrs.dragAxis]: "true" }));
    first.rect = { left: 100, top: 0, width: 1000, height: 100 };
    const second = mount.append(new MiniElement({ [attrs.dragAxis]: "true" }));
    second.rect = { left: 100, top: 100, width: 1000, height: 100 };
    for (const [lane, axis] of [first, second].entries()) {
        for (const position of config.positions) axis.append(new MiniElement({ [attrs.dropzoneRef]: "shift-slot-dropzone", [attrs.dropzoneKey]: `${lane}/${position}`, [attrs.dragPosition]: String(position) }));
    }
    const marker = first.append(new MiniElement({ [attrs.sourceRef]: "shift-drag-source", [attrs.sourceKey]: "source", [attrs.dragIntervalConfig]: JSON.stringify(config) }));
    marker.rect = { left: 350, top: 10, width: 400, height: 50 };
    const drag = readIntervalDrag(marker as unknown as Element, mount as unknown as Element, `[${attrs.dropzoneRef}]`, 400)!;
    assertEqual(drag.project(400, 50)?.label, "middle");
    assertEqual(drag.project(-500, 50)?.left, 100);
    assertEqual(drag.project(2000, 50)?.left, 600);
    assertEqual(drag.project(2000, 50)?.width, 400);
    assertEqual(drag.project(400, 150)?.target.getAttribute(attrs.dropzoneKey), "1/250");
    assertEqual(drag.project(400, 300), null);
    first.rect.left = -150;
    assertEqual(drag.project(400, 50)?.label, "late");
    first.rect.left = 100;
    const committed: string[] = [];
    const controller = createPointerSessionController({ runtime: { emit: (payload) => {
        if (payload.phase === "commit") committed.push(payload.fields?.targetDropzoneKey ?? "");
        return { canceled: false };
    } } });
    controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 1, 400, 50));
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 2000, 150));
    controller.handlePointerUp(pointerEventWithTarget("pointerup", marker, 1, 2000, 150));
    assertEqual(committed.join(), "1/500");
    controller.stop();
});

test("vertical interval projection preserves duration and grab offset, crosses lanes and refuses an axis change", () => {
    const mount = new MiniElement({ [attrs.surface]: "roster" });
    const config = { rangeSize: 1000, extent: 400, positions: [0, 250, 500], labels: ["early", "middle", "late"] };
    let direction = "vertical";
    const doc = { elementFromPoint: () => null, defaultView: { getComputedStyle: () => ({ getPropertyValue: () => direction }) } };
    const first = mount.append(new MiniElement({ [attrs.dragAxis]: "true" }));
    first.rect = { left: 0, top: 100, width: 100, height: 1000 };
    const second = mount.append(new MiniElement({ [attrs.dragAxis]: "true" }));
    second.rect = { left: 100, top: 100, width: 100, height: 1000 };
    for (const [lane, axis] of [first, second].entries()) {
        axis.ownerDocument = doc;
        for (const position of config.positions) axis.append(new MiniElement({ [attrs.dropzoneRef]: "shift-slot-dropzone", [attrs.dropzoneKey]: `${lane}/${position}`, [attrs.dragPosition]: String(position) }));
    }
    const marker = first.append(new MiniElement({ [attrs.sourceRef]: "shift-drag-source", [attrs.dragIntervalConfig]: JSON.stringify(config) }));
    marker.ownerDocument = doc;
    marker.rect = { left: 10, top: 350, width: 50, height: 400 };
    const drag = readIntervalDrag(marker as unknown as Element, mount as unknown as Element, `[${attrs.dropzoneRef}]`, 30, 400)!;
    assertEqual(drag.project(50, 400)?.top, 350);
    assertEqual(drag.project(50, -500)?.top, 100);
    assertEqual(drag.project(50, 2000)?.top, 600);
    assertEqual(drag.project(50, 2000)?.height, 400);
    assertEqual(drag.project(150, 400)?.target.getAttribute(attrs.dropzoneKey), "1/250");
    assertEqual(drag.project(300, 400), null);
    first.rect.top = -150;
    assertEqual(drag.project(50, 400)?.label, "late");
    direction = "horizontal";
    assertEqual(drag.project(50, 400), null);
});

test("drag scrolling supports vertical edges and keeps both axes inside bounds", () => {
    const owner = Object.assign(new MiniElement(), { scrollLeft: 0, scrollWidth: 300, clientWidth: 300, scrollTop: 100, scrollHeight: 1200, clientHeight: 100 });
    owner.rect = { left: 10, top: 20, width: 300, height: 100 };
    const scroll = (x: number, y: number) => scrollDragContainer(owner as unknown as HTMLElement, x, y, 16);
    assertEqual(scroll(160, 119), true);
    assertEqual(owner.scrollTop > 100, true);
    assertEqual(scroll(400, 119), false);
    owner.scrollTop = 1100;
    assertEqual(scroll(160, 119), false);
    owner.scrollTop = 0;
    assertEqual(scroll(160, 21), false);
});

test("malformed interval boundaries refuse the gesture instead of using unsnapped hit testing", () => {
    const mount = new MiniElement({ [attrs.surface]: "roster" });
    const config = { rangeSize: 1000, extent: 400, positions: [0, 250, 500], labels: ["early", "middle", "late"] };
    const marker = mount.append(new MiniElement({ [attrs.sourceRef]: "shift-drag-source", [attrs.sourceKey]: "source" }));
    for (const invalid of [{ ...config, extent: 1001 }, { ...config, labels: [] }, { ...config, positions: [0, 250, 250] }, { ...config, positions: [0, 250, 900] }, { ...config, extra: true }]) {
        marker.setAttribute(attrs.dragIntervalConfig, JSON.stringify(invalid));
        assertEqual(readPointerSessionStart(pointerEventWithTarget("pointerdown", marker, 1, 10, 10)), null);
    }
});

test("horizontal drag scrolling respects edges, vertical bounds and scroll limits", () => {
    const owner = Object.assign(new MiniElement(), { scrollLeft: 100, scrollWidth: 1200, clientWidth: 300 });
    owner.rect = { left: 10, top: 20, width: 300, height: 100 };
    const scroll = (x: number, y = 50) => scrollHorizontalDragContainer(owner as unknown as HTMLElement, x, y, 16);
    assertEqual(scroll(160), false);
    assertEqual(scroll(309, 0), false);
    assertEqual(scroll(400), false);
    assertEqual(scroll(309), true);
    assertEqual(owner.scrollLeft > 100, true);
    assertEqual(scroll(11), true);
    owner.scrollLeft = 0;
    assertEqual(scroll(10), false);
    owner.scrollLeft = 900;
    assertEqual(scroll(310), false);
});

test("opted-in drag owners scroll with a stationary pointer and cancel their animation lifecycle", () => {
    const requestDescriptor = Object.getOwnPropertyDescriptor(globalThis, "requestAnimationFrame");
    const cancelDescriptor = Object.getOwnPropertyDescriptor(globalThis, "cancelAnimationFrame");
    const frames = new Map<number, FrameRequestCallback>();
    let nextId = 0;
    Object.defineProperty(globalThis, "requestAnimationFrame", { configurable: true, value: (callback: FrameRequestCallback) => { frames.set(++nextId, callback); return nextId; } });
    Object.defineProperty(globalThis, "cancelAnimationFrame", { configurable: true, value: (id: number) => frames.delete(id) });
    try {
        for (const termination of ["up", "cancel", "cleanup", "stop"]) {
            const mount = new MiniElement({ [attrs.surface]: "roster" });
            const owner = Object.assign(mount.append(new MiniElement({ [attrs.dragScrollContainer]: "true" })), { scrollLeft: 0, scrollWidth: 1200, clientWidth: 300 });
            owner.rect = { left: 0, top: 0, width: 300, height: 100 };
            const marker = owner.append(new MiniElement({ [attrs.sourceRef]: "shift-drag-source", [attrs.sourceKey]: "source" }));
            const phases: string[] = [];
            const controller = createPointerSessionController({ runtime: { emit: (payload) => { phases.push(payload.phase); return { canceled: false }; } } });
            controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 1, 250, 50));
            assertEqual(frames.size, 0);
            controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 299, 50));
            assertEqual(frames.size, 1);
            for (const time of [16, 32]) {
                const [id, callback] = [...frames][0]!;
                frames.delete(id);
                callback(time);
            }
            assertEqual(owner.scrollLeft > 0, true);
            assertEqual(phases.filter((phase) => phase === "preview").length, 3);
            if (termination === "up") controller.handlePointerUp(pointerEventWithTarget("pointerup", marker, 1, 299, 50));
            if (termination === "cancel") controller.handlePointerCancel(pointerEventWithTarget("pointercancel", marker, 1, 299, 50));
            if (termination === "cleanup") controller.handleExternalCleanup(new Event("htmx:beforeSwap"));
            controller.stop();
            assertEqual(frames.size, 0);
        }
    } finally {
        if (requestDescriptor) Object.defineProperty(globalThis, "requestAnimationFrame", requestDescriptor);
        else Reflect.deleteProperty(globalThis, "requestAnimationFrame");
        if (cancelDescriptor) Object.defineProperty(globalThis, "cancelAnimationFrame", cancelDescriptor);
        else Reflect.deleteProperty(globalThis, "cancelAnimationFrame");
    }
});

test("pointer sessions emit start preview commit and clean disposable layers", () => {
    const phases: string[] = [];
    const deltas: string[] = [];
    const dropTargets: string[] = [];
    const mount = new MiniElement({ [attrs.surface]: "roster" });
    const marker = mount.append(new MiniElement({
        [attrs.sourceRef]: "shift-drag-source",
        [attrs.sourceKey]: "existing:source-slot",
        [attrs.sessionThreshold]: "3",
    }));
    const dropzone = mount.append(new MiniElement({ [attrs.dropzoneRef]: "shift-slot-dropzone", [attrs.dropzoneKey]: "new:target-slot" }));
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
        [attrs.sourceRef]: "shift-drag-source",
        [attrs.sourceKey]: "existing:source-slot",
        [attrs.sessionThreshold]: "4",
    }));
    marker.rect = { left: 10, top: 20, width: 80, height: 30 };
    marker.append(new MiniElement({ id: "child-id" }));
    const firstDropzone = mount.append(new MiniElement({ [attrs.dropzoneRef]: "shift-slot-dropzone", [attrs.dropzoneKey]: "new:first-slot" }));
    const secondDropzone = mount.append(new MiniElement({ [attrs.dropzoneRef]: "shift-slot-dropzone", [attrs.dropzoneKey]: "new:second-slot" }));
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

test("staff drag highlights only compatible roster drop targets", () => {
    const mount = new MiniElement({ [attrs.surface]: "roster", [attrs.surfaceFamily]: "roster" });
    const marker = mount.append(new MiniElement({
        [attrs.sourceRef]: "staff-drag-source",
        [attrs.sourceKey]: "staff:1",
        [attrs.sessionThreshold]: "0",
    }));
    marker.rect = { left: 0, top: 0, width: 80, height: 30 };
    const dayColumn = mount.append(new MiniElement({
        [attrs.dropzoneRef]: "day-column-dropzone",
        [attrs.dropzoneKey]: "day:1",
    }));
    const emptyRowShift = mount.append(new MiniElement({
        [attrs.dropzoneRef]: "shift-slot-dropzone",
        [attrs.dropzoneKey]: "new:row:1",
    }));
    const existingShift = mount.append(new MiniElement({
        [attrs.dropzoneRef]: "existing-shift-dropzone",
        [attrs.dropzoneKey]: "existing:1",
    }));
    const createTarget = mount.append(new MiniElement({
        [attrs.dropzoneRef]: "staff-create-dropzone",
        [attrs.dropzoneKey]: "new:1:2:0",
    }));
    const layer = mount.append(new MiniElement({ [attrs.disposableLayer]: "drag-preview" }));
    let hitTarget: MiniElement | null = dayColumn;
    const doc = {
        elementFromPoint: (_x: number, _y: number) => hitTarget,
        createElement: (_tag: string) => new MiniElement(),
    };
    for (const element of [mount, marker, dayColumn, emptyRowShift, existingShift, createTarget, layer]) element.ownerDocument = doc;

    const controller = createPointerSessionController({ runtime: { emit: () => ({ canceled: false }) } });
    controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 1, 0, 0));
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 8, 0));
    assertEqual(dayColumn.getAttribute("class"), null);

    hitTarget = emptyRowShift;
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 16, 0));
    assertEqual(emptyRowShift.getAttribute("class"), "bepis-dropzone-highlight");

    hitTarget = existingShift;
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 24, 0));
    assertEqual(emptyRowShift.getAttribute("class"), null);
    assertEqual(existingShift.getAttribute("class"), "bepis-dropzone-highlight");

    hitTarget = createTarget;
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 32, 0));
    assertEqual(existingShift.getAttribute("class"), null);
    assertEqual(createTarget.getAttribute("class"), "bepis-dropzone-highlight");

    controller.handlePointerUp(pointerEventWithTarget("pointerup", marker, 1, 32, 0));
    assertEqual(createTarget.getAttribute("class"), null);
});

test("shift drag ignores staff create targets and highlights delete targets", () => {
    const observed: string[] = [];
    const mount = new MiniElement({ [attrs.surface]: "roster", [attrs.surfaceFamily]: "roster" });
    const marker = mount.append(new MiniElement({
        [attrs.sourceRef]: "shift-drag-source",
        [attrs.sourceKey]: "existing:1",
        [attrs.sessionThreshold]: "0",
    }));
    marker.rect = { left: 0, top: 0, width: 80, height: 30 };
    const staffCreateTarget = mount.append(new MiniElement({
        [attrs.dropzoneRef]: "staff-create-dropzone",
        [attrs.dropzoneKey]: "new:1:2:0",
    }));
    const deleteTarget = mount.append(new MiniElement({
        [attrs.dropzoneRef]: "delete-shift-dropzone",
        [attrs.dropzoneKey]: "delete",
    }));
    const layer = mount.append(new MiniElement({ [attrs.disposableLayer]: "drag-preview" }));
    let hitTarget: MiniElement | null = staffCreateTarget;
    const doc = {
        elementFromPoint: (_x: number, _y: number) => hitTarget,
        createElement: (_tag: string) => new MiniElement(),
    };
    for (const element of [mount, marker, staffCreateTarget, deleteTarget, layer]) element.ownerDocument = doc;

    const controller = createPointerSessionController({
        runtime: {
            emit(payload) {
                if (payload.phase === "preview" || payload.phase === "commit") observed.push(payload.fields?.targetDropzoneKey ?? "");
                return { canceled: false };
            },
        },
    });
    controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 1, 0, 0));
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 8, 0));
    assertEqual(staffCreateTarget.getAttribute("class"), null);

    hitTarget = deleteTarget;
    controller.handlePointerMove(pointerEventWithTarget("pointermove", marker, 1, 16, 0));
    assertEqual(deleteTarget.getAttribute("class"), "bepis-dropzone-highlight");
    controller.handlePointerUp(pointerEventWithTarget("pointerup", marker, 1, 16, 0));
    assertEqual(deleteTarget.getAttribute("class"), null);
    assertEqual(observed.join(","), ",delete,delete,delete");
});

test("long-press opt-in preserves taps/swipes and activates only a held touch", async () => {
    const mount = new MiniElement({ [attrs.surface]: "roster" });
    const marker = mount.append(new MiniElement({ [attrs.sourceRef]: "shift-drag-source", [attrs.sourceKey]: "source", [attrs.sessionLongPressMs]: "5" }));
    const phases: string[] = [];
    const controller = createPointerSessionController({ runtime: { emit: (payload) => { phases.push(payload.phase); return { canceled: false }; } } });
    const down = () => pointerEventWithTarget("pointerdown", marker, 1, 50, 50, "touch");
    const tapStart = down();
    controller.handlePointerDown(tapStart);
    assertEqual(tapStart.defaultPrevented, false);
    controller.handlePointerUp(pointerEventWithTarget("pointerup", marker, 1, 50, 50, "touch"));
    const tap = eventWithTarget("click", marker);
    controller.handleClick(tap);
    assertEqual(tap.defaultPrevented, false);
    controller.handlePointerDown(down());
    const swipe = pointerEventWithTarget("pointermove", marker, 1, 80, 50, "touch");
    controller.handlePointerMove(swipe);
    assertEqual(swipe.defaultPrevented, false);
    assertEqual(controller.currentSession(), null);
    await new Promise((resolve) => setTimeout(resolve, 15));
    assertEqual(phases.includes("preview"), false);
    controller.handlePointerDown(down());
    await new Promise((resolve) => setTimeout(resolve, 15));
    controller.handlePointerUp(pointerEventWithTarget("pointerup", marker, 1, 50, 50, "touch"));
    assertEqual(phases.includes("commit"), false);
    controller.handlePointerDown(down());
    await new Promise((resolve) => setTimeout(resolve, 15));
    assertEqual(controller.currentSession()?.activated, true);
    assertEqual(marker.capturedPointerId, 1);
    const touchMove = new Event("touchmove", { cancelable: true });
    controller.handleTouchMove(touchMove);
    assertEqual(touchMove.defaultPrevented, true);
    const contextMenu = new Event("contextmenu", { cancelable: true });
    controller.handleContextMenu(contextMenu);
    assertEqual(contextMenu.defaultPrevented, true);
    controller.handlePointerUp(pointerEventWithTarget("pointerup", marker, 1, 70, 50, "touch"));
    assertEqual(phases.filter((phase) => phase === "commit").length, 1);
    const click = eventWithTarget("click", marker);
    controller.handleClick(click);
    assertEqual(click.defaultPrevented, true);
    controller.stop();
});

test("native context menus cannot interrupt a pending opted-in touch hold", () => {
    const mount = new MiniElement({ [attrs.surface]: "roster" });
    const marker = mount.append(new MiniElement({ [attrs.sourceRef]: "shift-drag-source", [attrs.sourceKey]: "source", [attrs.sessionLongPressMs]: "450" }));
    const controller = createPointerSessionController({ runtime: { emit: () => ({ canceled: false }) } });
    try {
        controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 1, 50, 50, "touch"));
        const contextMenu = eventWithTarget("contextmenu", marker);
        controller.handleContextMenu(contextMenu);
        assertEqual(contextMenu.defaultPrevented, true);
    } finally {
        controller.stop();
    }
});

test("context menus remain native without a touch drag and after cancellation", () => {
    const mount = new MiniElement({ [attrs.surface]: "roster" });
    const marker = mount.append(new MiniElement({ [attrs.sourceRef]: "shift-drag-source", [attrs.sourceKey]: "source", [attrs.sessionLongPressMs]: "450" }));
    const controller = createPointerSessionController({ runtime: { emit: () => ({ canceled: false }) } });
    const menu = () => {
        const event = eventWithTarget("contextmenu", marker);
        controller.handleContextMenu(event);
        assertEqual(event.defaultPrevented, false);
    };
    menu();
    controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 1, 50, 50));
    menu();
    controller.stop();
    controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 1, 50, 50, "touch"));
    controller.handlePointerCancel(pointerEventWithTarget("pointercancel", marker, 1, 50, 50, "touch"));
    menu();
    controller.stop();
});

test("a second touch cancels a held drag without suppressing native pinch gestures", async () => {
    const mount = new MiniElement({ [attrs.surface]: "roster" });
    const marker = mount.append(new MiniElement({ [attrs.sourceRef]: "shift-drag-source", [attrs.sourceKey]: "source", [attrs.sessionLongPressMs]: "5" }));
    const controller = createPointerSessionController({ runtime: { emit: () => ({ canceled: false }) } });
    controller.handlePointerDown(pointerEventWithTarget("pointerdown", marker, 1, 50, 50, "touch"));
    await new Promise((resolve) => setTimeout(resolve, 15));
    const pinch = new Event("touchmove", { cancelable: true });
    Object.defineProperty(pinch, "touches", { value: [{}, {}] });
    controller.handleTouchMove(pinch);
    assertEqual(pinch.defaultPrevented, false);
    assertEqual(controller.currentSession(), null);
    controller.stop();
});

test("touch pointers do not start generic drag sessions", () => {
    const phases: string[] = [];
    const mount = new MiniElement({ [attrs.surface]: "roster", [attrs.surfaceFamily]: "roster" });
    const marker = mount.append(new MiniElement({
        [attrs.sourceRef]: "shift-drag-source",
        [attrs.sourceKey]: "existing:source-slot",
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
            [attrs.sourceRef]: "shift-drag-source",
            [attrs.sourceKey]: "existing:source-slot",
            [attrs.sessionThreshold]: "0",
        }));
        marker.rect = { left: 0, top: 0, width: 40, height: 20 };
        const dropzone = mount.append(new MiniElement({ [attrs.dropzoneRef]: "shift-slot-dropzone", [attrs.dropzoneKey]: "day:target" }));
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
        const marker = mount.append(new MiniElement({ [attrs.sourceRef]: "shift-drag-source", [attrs.sourceKey]: "existing:source-slot", [attrs.sessionThreshold]: "0" }));
        marker.rect = { left: 0, top: 0, width: 10, height: 10 };
        const dropzone = mount.append(new MiniElement({ [attrs.dropzoneRef]: "shift-slot-dropzone", [attrs.dropzoneKey]: "day:target" }));
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
            [attrs.sourceRef]: "shift-drag-source",
            [attrs.sourceKey]: "existing:source-slot",
            [attrs.sessionThreshold]: "0",
        }));
        marker.rect = { left: 0, top: 0, width: 10, height: 10 };
        const dropzone = mount.append(new MiniElement({ [attrs.dropzoneRef]: "shift-slot-dropzone", [attrs.dropzoneKey]: "slot" }));
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
        [attrs.sourceRef]: "shift-drag-source",
        [attrs.sourceKey]: "resize-source",
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
        [attrs.sourceRef]: "shift-drag-source",
        [attrs.sourceKey]: "shift:1",
        [attrs.sessionDisabled]: "true",
    }));
    const dropzone = new MiniElement({ [attrs.dropzoneRef]: "shift-slot-dropzone" });
    const doc = { elementFromPoint: (_x: number, _y: number) => dropzone };
    mount.ownerDocument = doc;
    dropzone.ownerDocument = doc;

    assertEqual(readPointerSessionStart(pointerEventWithTarget("pointerdown", disabled, 1, 0, 0)), null);
    assertEqual(hitTestClosest(mount as unknown as Element, 12, 34, `[${attrs.dropzoneRef}=\"shift-slot-dropzone\"]`), dropzone as unknown as Element);
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
