import { InteractionDom } from "../generated/contracts";
import { readActivationIntentPayload } from "../interaction/activation";
import { submitCommittedInteractionIntent } from "../interaction/form-bridge";
import { createInteractionRuntime } from "../interaction/runtime";
import { InteractionIntentBus } from "../interaction/intent-bus";
import { assertEqual, test } from "./harness";

class MiniElement extends EventTarget {
    readonly children: MiniElement[] = [];
    parent: MiniElement | null = null;
    value = "";
    private readonly attrs = new Map<string, string>();

    constructor(attrs: Record<string, string> = {}) {
        super();
        for (const [name, value] of Object.entries(attrs)) this.attrs.set(name, value);
        this.value = attrs.value ?? "";
    }

    append(child: MiniElement): MiniElement {
        child.parent = this;
        this.children.push(child);
        return child;
    }

    getAttribute(name: string): string | null {
        return this.attrs.get(name) ?? null;
    }

    setAttribute(name: string, value: string): void {
        this.attrs.set(name, value);
        if (name === "value") this.value = value;
    }

    querySelectorAll(selector: string): MiniElement[] {
        const matches: MiniElement[] = [];
        const visit = (element: MiniElement) => {
            for (const child of element.children) {
                if (matchesSelector(child, selector) || matchesTagSelector(child, selector)) matches.push(child);
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

function buildMount(): { mount: MiniElement; form: MiniElement; required: MiniElement; optional: MiniElement; marker: MiniElement } {
    const mount = new MiniElement({ [attrs.surface]: "true", [attrs.mountKey]: "primary" });
    const marker = mount.append(new MiniElement({ [attrs.intent]: "select-cell" }));
    const form = mount.append(new MiniElement({
        [attrs.intentForm]: "select-cell",
        [attrs.intent]: "select-cell",
        "hx-trigger": "bepis:intent-submit from:this",
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

test("generic activation markers emit committed intent payloads from closest markers", () => {
    const marker = new MiniElement({
        [attrs.marker]: "activation",
        [attrs.activation]: "roster-layout-day-columns",
        [attrs.activationIntent]: "set-roster-layout-mode",
        [attrs.activationTrigger]: "change",
        [attrs.activationValueField]: "rosterLayoutMode",
    });
    const input = marker.append(new MiniElement({ tag: "input", value: "day_columns" }));

    const payload = readActivationIntentPayload(eventWithTarget("change", input), "change");

    assertEqual(payload?.phase, "commit");
    assertEqual(payload?.intent, "set-roster-layout-mode");
    assertEqual(payload?.fields?.rosterLayoutMode, "day_columns");
    assertEqual(payload?.marker, marker as unknown as Element);
});

test("generic activation markers ignore non-matching triggers", () => {
    const marker = new MiniElement({
        [attrs.marker]: "activation",
        [attrs.activation]: "save-button",
        [attrs.activationIntent]: "save",
        [attrs.activationTrigger]: "click",
    });
    const child = marker.append(new MiniElement());

    assertEqual(readActivationIntentPayload(eventWithTarget("change", child), "change"), null);
    assertEqual(readActivationIntentPayload(eventWithTarget("click", child), "click")?.intent, "save");
});

test("committed intents fill the matching helper-rendered form and dispatch the generated trigger", () => {
    const { mount, form, required, optional } = buildMount();
    let dispatchedTrigger = "";
    form.addEventListener("bepis:intent-submit", (event) => {
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
    assertEqual(dispatchedTrigger, "bepis:intent-submit");
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
