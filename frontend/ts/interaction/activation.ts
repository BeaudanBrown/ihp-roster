import { FrontendSurfaceInteractionDom, FrontendSurfaceRegistry, InteractionDom, isFrontendSurfaceName, type InteractionActivationTrigger } from "../generated/contracts";
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
const surfaceActivationSelector = `[${FrontendSurfaceInteractionDom.activationRef}]`;

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
    const marker = closestSurfaceActivationRef(event.target);
    if (!marker) return null;

    const mount = closestInteractionMount(marker);
    if (!mount) return null;

    const surface = mount.getAttribute(attrs.surface);
    if (!isFrontendSurfaceName(surface)) return null;

    const ref = marker.getAttribute(FrontendSurfaceInteractionDom.activationRef);
    const definition = FrontendSurfaceRegistry[surface].interaction.activationRefs.find((candidate) => candidate.ref === ref);
    if (!definition) return null;
    if (expectedTrigger && definition.trigger !== expectedTrigger) return null;

    const fields = readSurfaceActivationFields(marker, event, definition.valueField);
    if (fields === null) return null;

    return {
        phase: "commit",
        intent: definition.intent,
        fields,
        mount,
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

function closestSurfaceActivationRef(target: EventTarget | null): ElementLike | null {
    if (!isElementLike(target)) return null;
    const marker = target.closest(surfaceActivationSelector);
    return isElementLike(marker) ? marker : null;
}

function closestInteractionMount(marker: ElementLike): ElementLike | null {
    const mount = marker.closest(`[${attrs.surface}]`);
    return isElementLike(mount) ? mount : null;
}

function readSurfaceActivationFields(marker: ElementLike, event: Event, valueField: string | null): Record<string, string> | null {
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
