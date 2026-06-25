export type InteractionIntentPhase = "start" | "preview" | "commit" | "cancel" | "error";

export type InteractionIntentFields = Record<string, string>;

export type InteractionIntentPayload = {
    phase: InteractionIntentPhase;
    intent: string;
    fields?: InteractionIntentFields;
    mount?: Element | null;
    marker?: Element | null;
    sourceEvent?: Event | null;
};

export type NormalizedInteractionIntent = {
    phase: InteractionIntentPhase;
    intent: string;
    fields: InteractionIntentFields;
    mount: Element | null;
    marker: Element | null;
    sourceEvent: Event | null;
};

export type InteractionIntentListener = (event: CustomEvent<NormalizedInteractionIntent>) => void;

export const interactionIntentEventName = "bepis:interaction-intent";

function normalizeFields(fields: InteractionIntentPayload["fields"]): InteractionIntentFields {
    if (!fields) return {};

    const normalized: InteractionIntentFields = {};
    for (const [name, value] of Object.entries(fields)) {
        normalized[name] = value;
    }
    return normalized;
}

export function normalizeInteractionIntent(payload: InteractionIntentPayload): NormalizedInteractionIntent {
    return {
        phase: payload.phase,
        intent: payload.intent,
        fields: normalizeFields(payload.fields),
        mount: payload.mount ?? null,
        marker: payload.marker ?? null,
        sourceEvent: payload.sourceEvent ?? null,
    };
}

export class InteractionIntentBus {
    private readonly target: EventTarget;

    constructor(target: EventTarget = new EventTarget()) {
        this.target = target;
    }

    observe(listener: InteractionIntentListener): () => void {
        this.target.addEventListener(interactionIntentEventName, listener as EventListener);
        return () => this.target.removeEventListener(interactionIntentEventName, listener as EventListener);
    }

    emit(payload: InteractionIntentPayload): { intent: NormalizedInteractionIntent; event: CustomEvent<NormalizedInteractionIntent>; canceled: boolean } {
        const intent = normalizeInteractionIntent(payload);
        const event = new CustomEvent<NormalizedInteractionIntent>(interactionIntentEventName, {
            bubbles: false,
            cancelable: true,
            detail: intent,
        });
        const accepted = this.target.dispatchEvent(event);
        return { intent, event, canceled: !accepted || event.defaultPrevented };
    }
}
