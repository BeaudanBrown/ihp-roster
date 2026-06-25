import { submitCommittedInteractionIntent, type InteractionBridgeLogger, type IntentSubmitResult } from "./form-bridge";
import { InteractionIntentBus, type InteractionIntentPayload } from "./intent-bus";

export type InteractionRuntime = {
    bus: InteractionIntentBus;
    emit: (payload: InteractionIntentPayload) => { canceled: boolean; submitted?: IntentSubmitResult };
    stop: () => void;
};

export function createInteractionRuntime(options: { bus?: InteractionIntentBus; logger?: InteractionBridgeLogger } = {}): InteractionRuntime {
    const bus = options.bus ?? new InteractionIntentBus();
    const logger = options.logger ?? console;

    return {
        bus,
        emit(payload) {
            const emitted = bus.emit(payload);
            if (emitted.canceled || emitted.intent.phase !== "commit") return { canceled: emitted.canceled };

            const submitted = submitCommittedInteractionIntent(emitted.intent, logger);
            return { canceled: !submitted.ok, submitted };
        },
        stop() {
            // Reserved for future document-level activation listeners.
        },
    };
}

export const defaultInteractionRuntime = createInteractionRuntime();
