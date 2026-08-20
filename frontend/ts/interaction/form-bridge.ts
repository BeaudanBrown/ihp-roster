import { InteractionDom, isInteractionFieldPresence, type InteractionFieldPresence } from "../generated/contracts";
import type { NormalizedInteractionIntent } from "./intent-bus";

export type InteractionBridgeLogger = Pick<Console, "warn">;

export type IntentSubmitResult =
    | { ok: true; form: Element; trigger: string }
    | { ok: false; reason: string };

type ElementLike = Element & {
    value?: string;
    name?: string;
    getAttribute(name: string): string | null;
    setAttribute(name: string, value: string): void;
    querySelectorAll(selector: string): NodeListOf<Element> | Element[];
    closest?(selector: string): Element | null;
    dispatchEvent(event: Event): boolean;
};

type FieldInput = ElementLike & { value: string };

type FieldContract = {
    name: string;
    presence: InteractionFieldPresence;
    input: FieldInput;
};

const attrs = InteractionDom.attributes;

export function submitCommittedInteractionIntent(intent: NormalizedInteractionIntent, logger: InteractionBridgeLogger = console): IntentSubmitResult {
    if (intent.phase !== "commit") return { ok: false, reason: "intent phase is not commit" };

    const mount = resolveInteractionMount(intent);
    if (!mount) return fail(logger, `No interaction mount found for intent ${intent.intent}`);

    const form = findIntentForm(mount, intent.intent);
    if (!form) return fail(logger, `No interaction form found for intent ${intent.intent}`);

    const validation = validateIntentFields(form, intent.fields);
    if (!validation.ok) return fail(logger, validation.reason);

    const trigger = formTriggerName(form);
    if (!trigger) return fail(logger, `Intent form ${intent.intent} has no hx-trigger`);

    for (const field of validation.fields) {
        if (hasOwn(intent.fields, field.name)) {
            field.input.value = intent.fields[field.name] ?? "";
            field.input.setAttribute("value", field.input.value);
        }
    }

    form.dispatchEvent(new CustomEvent(trigger, { bubbles: true, cancelable: true, detail: { intent } }));
    return { ok: true, form, trigger };
}

function resolveInteractionMount(intent: NormalizedInteractionIntent): ElementLike | null {
    if (isElementLike(intent.mount) && isInteractionMount(intent.mount)) return intent.mount;
    if (isElementLike(intent.marker)) return closestInteractionMount(intent.marker);
    const sourceTarget = intent.sourceEvent?.target;
    if (isElementLike(sourceTarget)) return closestInteractionMount(sourceTarget);
    return null;
}

function isInteractionMount(element: ElementLike): boolean {
    return Boolean(element.getAttribute(attrs.surface));
}

function closestInteractionMount(element: ElementLike): ElementLike | null {
    const closest = element.closest?.(attrSelector(attrs.surface)) ?? null;
    return isElementLike(closest) ? closest : null;
}

function findIntentForm(mount: ElementLike, intentName: string): ElementLike | null {
    for (const form of queryAll(mount, attrSelector(attrs.intentForm))) {
        if (form.getAttribute(attrs.intent) === intentName || form.getAttribute(attrs.intentForm) === intentName) {
            return form;
        }
    }
    return null;
}

function validateIntentFields(form: ElementLike, emittedFields: Record<string, string>): { ok: true; fields: FieldContract[] } | { ok: false; reason: string } {
    const fields = readFieldContracts(form);
    const fieldsByName = new Map(fields.map((field) => [field.name, field]));

    for (const [name, value] of Object.entries(emittedFields)) {
        if (!fieldsByName.has(name)) return { ok: false, reason: `Unknown intent field ${name}` };
        if (typeof value !== "string") return { ok: false, reason: `Intent field ${name} is not a string` };
    }

    for (const field of fields) {
        if (field.presence === "required" && !hasOwn(emittedFields, field.name) && field.input.value === "") {
            return { ok: false, reason: `Missing required intent field ${field.name}` };
        }
    }

    return { ok: true, fields };
}

function readFieldContracts(form: ElementLike): FieldContract[] {
    return queryAll(form, attrSelector(attrs.intentField)).flatMap((element) => {
        if (!isFieldInput(element)) return [];
        const name = element.getAttribute(attrs.intentField);
        const presence = element.getAttribute(attrs.fieldPresence);
        if (!name || !isInteractionFieldPresence(presence)) return [];
        return [{ name, presence, input: element }];
    });
}

function isFieldInput(element: ElementLike): element is FieldInput {
    return "value" in element && typeof element.value === "string";
}

function formTriggerName(form: ElementLike): string | null {
    const trigger = form.getAttribute("hx-trigger")?.trim();
    if (!trigger) return null;
    return trigger.split(/[\s,]+/, 1)[0] || null;
}

function queryAll(root: ElementLike, selector: string): ElementLike[] {
    return Array.from(root.querySelectorAll(selector)).filter(isElementLike);
}

function isElementLike(value: unknown): value is ElementLike {
    if (value === null || typeof value !== "object") return false;
    const maybe = value as Partial<ElementLike>;
    return typeof maybe.getAttribute === "function"
        && typeof maybe.setAttribute === "function"
        && typeof maybe.querySelectorAll === "function"
        && typeof maybe.dispatchEvent === "function";
}

function attrSelector(attribute: string): string {
    return `[${attribute}]`;
}

function hasOwn(object: Record<string, string>, key: string): boolean {
    return Object.prototype.hasOwnProperty.call(object, key);
}

function fail(logger: InteractionBridgeLogger, reason: string): IntentSubmitResult {
    logger.warn(`[bepis interaction] ${reason}`);
    return { ok: false, reason };
}
