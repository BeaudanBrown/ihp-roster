import { InteractionDom, type InteractionConflictResolution } from "../generated/contracts";

export const interactionSessionStartEventName = "bepis:interaction-session-start";
export const interactionSessionEndEventName = "bepis:interaction-session-end";
export const interactionSessionCancelRequestEventName = "bepis:interaction-session-cancel-request";

export type InteractionSessionSnapshot = {
    mount: Element;
    mountId: string;
    sessionKind: string;
    intent: string;
};

export type InteractionSessionEventDetail = InteractionSessionSnapshot & {
    reason?: string | null;
};

export type InteractionSessionCancelRequestDetail = Partial<InteractionSessionSnapshot> & {
    resolution?: InteractionConflictResolution;
    reason?: string | null;
};

const attrs = InteractionDom.attributes;

export function dispatchInteractionSessionStart(detail: InteractionSessionSnapshot, root?: Document): void {
    const eventRoot = root ?? defaultDocument();
    if (!eventRoot) return;
    eventRoot.dispatchEvent(new CustomEvent<InteractionSessionEventDetail>(interactionSessionStartEventName, { detail }));
}

export function dispatchInteractionSessionEnd(detail: InteractionSessionEventDetail, root?: Document): void {
    const eventRoot = root ?? defaultDocument();
    if (!eventRoot) return;
    eventRoot.dispatchEvent(new CustomEvent<InteractionSessionEventDetail>(interactionSessionEndEventName, { detail }));
}

export function requestInteractionSessionCancel(detail: InteractionSessionCancelRequestDetail, root?: Document): void {
    const eventRoot = root ?? defaultDocument();
    if (!eventRoot) return;
    eventRoot.dispatchEvent(new CustomEvent<InteractionSessionCancelRequestDetail>(interactionSessionCancelRequestEventName, { detail }));
}

export function createActiveInteractionSessionTracker(root: Document) {
    const sessionsByMountId = new Map<string, InteractionSessionSnapshot>();

    const handleStart = (event: Event) => {
        const detail = customDetail<InteractionSessionEventDetail>(event);
        if (!detail || !detail.mountId || !detail.mount || !detail.sessionKind || !detail.intent) return;
        sessionsByMountId.set(detail.mountId, {
            mount: detail.mount,
            mountId: detail.mountId,
            sessionKind: detail.sessionKind,
            intent: detail.intent,
        });
    };

    const handleEnd = (event: Event) => {
        const detail = customDetail<InteractionSessionEventDetail>(event);
        if (!detail || !detail.mountId) return;
        sessionsByMountId.delete(detail.mountId);
    };

    root.addEventListener(interactionSessionStartEventName, handleStart);
    root.addEventListener(interactionSessionEndEventName, handleEnd);

    return {
        findForTarget(target: Element): InteractionSessionSnapshot | null {
            const mount = target.closest(`[${attrs.surface}="true"]`);
            if (!isElementLike(mount)) return null;
            return sessionsByMountId.get(mount.id) ?? null;
        },
        hasActiveSession(): boolean {
            return sessionsByMountId.size > 0;
        },
        requestCancel(session: InteractionSessionSnapshot, reason: string): void {
            requestInteractionSessionCancel({ ...session, reason });
        },
        stop(): void {
            root.removeEventListener(interactionSessionStartEventName, handleStart);
            root.removeEventListener(interactionSessionEndEventName, handleEnd);
            sessionsByMountId.clear();
        },
    };
}

function customDetail<T>(event: Event): T | null {
    return event instanceof CustomEvent ? event.detail as T : null;
}

function defaultDocument(): Document | null {
    return typeof document === "undefined" ? null : document;
}

function isElementLike(value: unknown): value is Element & { id: string } {
    return value !== null && typeof value === "object" && typeof (value as { id?: unknown }).id === "string";
}
