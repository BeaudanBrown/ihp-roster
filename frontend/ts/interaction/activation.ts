import { InteractionDom, type InteractionActivationTrigger } from "../generated/contracts";
import type { InteractionIntentPayload } from "./intent-bus";
import { defaultInteractionRuntime } from "./runtime";

export type InteractionActivationRuntime = {
    emit: (payload: InteractionIntentPayload) => { canceled: boolean };
};

export type InteractionActivationOptions = {
    root?: Document | Element;
    runtime?: InteractionActivationRuntime;
};

type ElementLike = Element & {
    value?: string;
    getAttribute(name: string): string | null;
    closest(selector: string): Element | null;
    querySelector(selector: string): Element | null;
};

type ValueElement = ElementLike & { value: string };

const attrs = InteractionDom.attributes;
const values = InteractionDom.values;
const activationSelector = `[${attrs.marker}="${values.activationMarker}"]`;

export function enableGenericInteractionActivations(options: InteractionActivationOptions = {}): () => void {
    if (typeof document === "undefined") return () => undefined;

    const root = options.root ?? document;
    const runtime = options.runtime ?? defaultInteractionRuntime;
    const clickHandler = (event: Event) => handleActivationEvent(event, "click", runtime);
    const changeHandler = (event: Event) => handleActivationEvent(event, "change", runtime);
    const keydownHandler = (event: Event) => handleKeyboardActivationEvent(event, runtime);

    root.addEventListener("click", clickHandler);
    root.addEventListener("change", changeHandler);
    root.addEventListener("keydown", keydownHandler);

    return () => {
        root.removeEventListener("click", clickHandler);
        root.removeEventListener("change", changeHandler);
        root.removeEventListener("keydown", keydownHandler);
    };
}

export function readActivationIntentPayload(event: Event, expectedTrigger?: InteractionActivationTrigger): InteractionIntentPayload | null {
    const marker = closestActivationMarker(event.target);
    if (!marker) return null;

    const trigger = marker.getAttribute(attrs.activationTrigger) as InteractionActivationTrigger | null;
    if (!trigger || (expectedTrigger && trigger !== expectedTrigger)) return null;

    const intent = marker.getAttribute(attrs.activationIntent);
    if (!intent) return null;

    const fields = readActivationFields(marker, event);
    if (fields === null) return null;

    return {
        phase: "commit",
        intent,
        fields,
        marker,
        sourceEvent: event,
    };
}

function handleActivationEvent(event: Event, expectedTrigger: InteractionActivationTrigger, runtime: InteractionActivationRuntime): void {
    const payload = readActivationIntentPayload(event, expectedTrigger);
    if (!payload) return;

    const result = runtime.emit(payload);
    if (result.canceled && event.cancelable) event.preventDefault();
}

function handleKeyboardActivationEvent(event: Event, runtime: InteractionActivationRuntime): void {
    if (!isKeyboardEvent(event)) return;

    const trigger = keyboardTriggerForEvent(event);
    if (!trigger) return;
    handleActivationEvent(event, trigger, runtime);
}

function keyboardTriggerForEvent(event: Pick<KeyboardEvent, "key">): InteractionActivationTrigger | null {
    if (event.key === "Enter") return "keydown-enter";
    if (event.key === " " || event.key === "Spacebar") return "keydown-space";
    return null;
}

function closestActivationMarker(target: EventTarget | null): ElementLike | null {
    if (!isElementLike(target)) return null;
    const marker = target.closest(activationSelector);
    return isElementLike(marker) ? marker : null;
}

function readActivationFields(marker: ElementLike, event: Event): Record<string, string> | null {
    const valueField = marker.getAttribute(attrs.activationValueField);
    if (!valueField) return {};

    const valueElement = valueSourceElement(marker, event);
    if (!valueElement) return null;

    return { [valueField]: valueElement.value };
}

function valueSourceElement(marker: ElementLike, event: Event): ValueElement | null {
    if (isValueElement(event.target)) return event.target;
    if (isValueElement(marker)) return marker;
    const nested = marker.querySelector("input,select,textarea");
    return isValueElement(nested) ? nested : null;
}

function isKeyboardEvent(event: Event): event is KeyboardEvent {
    return typeof KeyboardEvent !== "undefined" && event instanceof KeyboardEvent;
}

function isValueElement(value: unknown): value is ValueElement {
    return isElementLike(value) && typeof value.value === "string";
}

function isElementLike(value: unknown): value is ElementLike {
    if (value === null || typeof value !== "object") return false;
    const maybe = value as Partial<ElementLike>;
    return typeof maybe.getAttribute === "function"
        && typeof maybe.closest === "function"
        && typeof maybe.querySelector === "function";
}
