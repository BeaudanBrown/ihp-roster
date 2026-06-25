import { InteractionDom } from "../generated/contracts";
import type { InteractionIntentPayload } from "./intent-bus";
import { defaultInteractionRuntime } from "./runtime";
import {
    dispatchInteractionSessionEnd,
    dispatchInteractionSessionStart,
    interactionSessionCancelRequestEventName,
    type InteractionSessionCancelRequestDetail,
} from "./session-state";

export type PointerSessionRuntime = {
    emit: (payload: InteractionIntentPayload) => { canceled: boolean };
};

export type PointerSessionOptions = {
    root?: Document | Element;
    runtime?: PointerSessionRuntime;
    thresholdPx?: number;
};

type ElementLike = Element & {
    getAttribute(name: string): string | null;
    closest(selector: string): Element | null;
    querySelectorAll(selector: string): Iterable<Element>;
    setPointerCapture?(pointerId: number): void;
    releasePointerCapture?(pointerId: number): void;
};

type PointerEventLike = Event & {
    pointerId?: number;
    pointerType?: string;
    clientX?: number;
    clientY?: number;
};

export type ActivePointerSession = {
    mount: ElementLike;
    marker: ElementLike;
    intent: string;
    sessionKind: string;
    pointerId: number;
    pointerType: string;
    startClientX: number;
    startClientY: number;
    currentClientX: number;
    currentClientY: number;
    thresholdPx: number;
    activated: boolean;
};

const attrs = InteractionDom.attributes;
const values = InteractionDom.values;
const sessionSelector = `[${attrs.pointerSession}="${values.enabled}"]`;
const disposableLayerSelector = `[${attrs.disposableLayer}]`;
const defaultThresholdPx = 4;

export function enableGenericPointerSessions(options: PointerSessionOptions = {}): () => void {
    if (typeof document === "undefined") return () => undefined;

    const controller = createPointerSessionController(options);
    const root = options.root ?? document;

    root.addEventListener("pointerdown", controller.handlePointerDown);
    root.addEventListener("pointermove", controller.handlePointerMove);
    root.addEventListener("pointerup", controller.handlePointerUp);
    root.addEventListener("pointercancel", controller.handlePointerCancel);
    root.addEventListener("keydown", controller.handleKeyDown);
    root.addEventListener("htmx:beforeSwap", controller.handleExternalCleanup);
    root.addEventListener("htmx:beforeCleanupElement", controller.handleExternalCleanup);
    root.addEventListener(interactionSessionCancelRequestEventName, controller.handleCancelRequest);

    return () => {
        root.removeEventListener("pointerdown", controller.handlePointerDown);
        root.removeEventListener("pointermove", controller.handlePointerMove);
        root.removeEventListener("pointerup", controller.handlePointerUp);
        root.removeEventListener("pointercancel", controller.handlePointerCancel);
        root.removeEventListener("keydown", controller.handleKeyDown);
        root.removeEventListener("htmx:beforeSwap", controller.handleExternalCleanup);
        root.removeEventListener("htmx:beforeCleanupElement", controller.handleExternalCleanup);
        root.removeEventListener(interactionSessionCancelRequestEventName, controller.handleCancelRequest);
        controller.stop();
    };
}

export function createPointerSessionController(options: PointerSessionOptions = {}) {
    const runtime = options.runtime ?? defaultInteractionRuntime;
    const fallbackThresholdPx = options.thresholdPx ?? defaultThresholdPx;
    let activeSession: ActivePointerSession | null = null;
    let timeoutHandle: ReturnType<typeof setTimeout> | null = null;

    const clearTimeoutHandle = () => {
        if (timeoutHandle !== null) clearTimeout(timeoutHandle);
        timeoutHandle = null;
    };

    const scheduleTimeout = (session: ActivePointerSession) => {
        clearTimeoutHandle();
        const timeoutMs = numberAttribute(session.marker, attrs.sessionTimeoutMs);
        if (timeoutMs === null || timeoutMs <= 0) return;
        timeoutHandle = setTimeout(() => {
            if (activeSession === session) cancelSession(session, null);
        }, timeoutMs);
    };

    const cleanupSession = (session: ActivePointerSession, reason: string) => {
        clearTimeoutHandle();
        clearDisposableLayers(session.mount);
        releasePointerCapture(session.marker, session.pointerId);
        if (activeSession === session) activeSession = null;
        dispatchInteractionSessionEnd(sessionSnapshot(session, reason));
    };

    const cancelSession = (session: ActivePointerSession, sourceEvent: Event | null) => {
        runtime.emit({
            phase: "cancel",
            intent: session.intent,
            fields: pointerSessionFields(session),
            mount: session.mount,
            marker: session.marker,
            sourceEvent,
        });
        cleanupSession(session, sourceEvent?.type ?? "cancel");
    };

    const finishSession = (session: ActivePointerSession, sourceEvent: Event) => {
        const result = runtime.emit({
            phase: "commit",
            intent: session.intent,
            fields: pointerSessionFields(session),
            mount: session.mount,
            marker: session.marker,
            sourceEvent,
        });
        if (result.canceled && sourceEvent.cancelable) sourceEvent.preventDefault();
        cleanupSession(session, sourceEvent.type);
    };

    const updateSession = (session: ActivePointerSession, event: PointerEventLike) => {
        session.currentClientX = numberValue(event.clientX);
        session.currentClientY = numberValue(event.clientY);
        if (!session.activated && movementDistance(session) < session.thresholdPx) return;
        session.activated = true;
        runtime.emit({
            phase: "preview",
            intent: session.intent,
            fields: pointerSessionFields(session),
            mount: session.mount,
            marker: session.marker,
            sourceEvent: event,
        });
    };

    return {
        handlePointerDown(event: Event) {
            const start = readPointerSessionStart(event, fallbackThresholdPx);
            if (!start) return;

            if (activeSession) cancelSession(activeSession, event);
            clearDisposableLayers(start.mount);
            activeSession = start;
            capturePointer(start.marker, start.pointerId);

            const result = runtime.emit({
                phase: "start",
                intent: start.intent,
                fields: pointerSessionFields(start),
                mount: start.mount,
                marker: start.marker,
                sourceEvent: event,
            });
            if (result.canceled) {
                if (event.cancelable) event.preventDefault();
                cleanupSession(start, "canceled-start");
                return;
            }

            dispatchInteractionSessionStart(sessionSnapshot(start));
            scheduleTimeout(start);
        },
        handlePointerMove(event: Event) {
            if (!activeSession || !isMatchingPointerEvent(event, activeSession)) return;
            updateSession(activeSession, event);
        },
        handlePointerUp(event: Event) {
            if (!activeSession || !isMatchingPointerEvent(event, activeSession)) return;
            updateSession(activeSession, event);
            if (activeSession.activated) finishSession(activeSession, event);
            else cancelSession(activeSession, event);
        },
        handlePointerCancel(event: Event) {
            if (!activeSession || !isMatchingPointerEvent(event, activeSession)) return;
            cancelSession(activeSession, event);
        },
        handleKeyDown(event: Event) {
            if (!activeSession || !isEscapeKeyboardEvent(event)) return;
            if (event.cancelable) event.preventDefault();
            cancelSession(activeSession, event);
        },
        handleExternalCleanup(event: Event) {
            if (!activeSession) return;
            cancelSession(activeSession, event);
        },
        handleCancelRequest(event: Event) {
            if (!activeSession) return;
            const detail = event instanceof CustomEvent ? event.detail as InteractionSessionCancelRequestDetail : null;
            if (detail?.mountId && detail.mountId !== activeSession.mount.id) return;
            if (detail?.sessionKind && detail.sessionKind !== activeSession.sessionKind) return;
            cancelSession(activeSession, event);
        },
        currentSession() {
            return activeSession;
        },
        stop() {
            if (activeSession) cancelSession(activeSession, null);
            clearTimeoutHandle();
        },
    };
}

export function readPointerSessionStart(event: Event, fallbackThresholdPx = defaultThresholdPx): ActivePointerSession | null {
    const pointerEvent = event as PointerEventLike;
    const marker = closestPointerSessionMarker(event.target);
    if (!marker) return null;
    if (isDisabled(marker)) return null;

    const mount = closestInteractionMount(marker);
    if (!mount) return null;

    const intent = marker.getAttribute(attrs.sessionIntent);
    const sessionKind = marker.getAttribute(attrs.sessionKind);
    if (!intent || !sessionKind) return null;

    const startClientX = numberValue(pointerEvent.clientX);
    const startClientY = numberValue(pointerEvent.clientY);
    const thresholdPx = numberAttribute(marker, attrs.sessionThreshold) ?? fallbackThresholdPx;

    return {
        mount,
        marker,
        intent,
        sessionKind,
        pointerId: numberValue(pointerEvent.pointerId),
        pointerType: pointerEvent.pointerType ?? "unknown",
        startClientX,
        startClientY,
        currentClientX: startClientX,
        currentClientY: startClientY,
        thresholdPx: Math.max(0, thresholdPx),
        activated: thresholdPx <= 0,
    };
}

export function hitTestClosest(root: Document | Element, clientX: number, clientY: number, selector: string): Element | null {
    const doc = ownerDocumentFor(root);
    const elementFromPoint = doc?.elementFromPoint?.bind(doc);
    if (!elementFromPoint) return null;

    const hit = elementFromPoint(clientX, clientY);
    if (!isElementLike(hit)) return null;
    return hit.closest(selector);
}

function sessionSnapshot(session: ActivePointerSession, reason?: string) {
    return {
        mount: session.mount,
        mountId: session.mount.id,
        sessionKind: session.sessionKind,
        intent: session.intent,
        reason: reason ?? null,
    };
}

function pointerSessionFields(session: ActivePointerSession): Record<string, string> {
    const deltaX = session.currentClientX - session.startClientX;
    const deltaY = session.currentClientY - session.startClientY;
    return {
        sessionKind: session.sessionKind,
        pointerId: String(session.pointerId),
        pointerType: session.pointerType,
        startClientX: String(session.startClientX),
        startClientY: String(session.startClientY),
        currentClientX: String(session.currentClientX),
        currentClientY: String(session.currentClientY),
        deltaX: String(deltaX),
        deltaY: String(deltaY),
    };
}

function movementDistance(session: ActivePointerSession): number {
    const deltaX = session.currentClientX - session.startClientX;
    const deltaY = session.currentClientY - session.startClientY;
    return Math.hypot(deltaX, deltaY);
}

function closestPointerSessionMarker(target: EventTarget | null): ElementLike | null {
    if (!isElementLike(target)) return null;
    const marker = target.closest(sessionSelector);
    return isElementLike(marker) ? marker : null;
}

function closestInteractionMount(marker: ElementLike): ElementLike | null {
    const mount = marker.closest(`[${attrs.surface}="${values.enabled}"]`);
    return isElementLike(mount) ? mount : null;
}

function clearDisposableLayers(mount: ElementLike): void {
    for (const layer of mount.querySelectorAll(disposableLayerSelector)) clearElement(layer);
}

function clearElement(element: Element): void {
    const mutable = element as Element & { replaceChildren?: () => void; innerHTML?: string };
    if (typeof mutable.replaceChildren === "function") {
        mutable.replaceChildren();
        return;
    }
    if (typeof mutable.innerHTML === "string") mutable.innerHTML = "";
}

function isDisabled(marker: ElementLike): boolean {
    return marker.getAttribute(attrs.sessionDisabled) === values.enabled
        || marker.getAttribute(attrs.sessionReadOnly) === values.enabled;
}

function isMatchingPointerEvent(event: Event, session: ActivePointerSession): event is PointerEventLike {
    return numberValue((event as PointerEventLike).pointerId) === session.pointerId;
}

function isEscapeKeyboardEvent(event: Event): event is KeyboardEvent {
    return event.type === "keydown" && (event as KeyboardEvent).key === "Escape";
}

function capturePointer(marker: ElementLike, pointerId: number): void {
    try {
        marker.setPointerCapture?.(pointerId);
    } catch {
        // Pointer capture can fail when the target is detached; the session still remains cancelable.
    }
}

function releasePointerCapture(marker: ElementLike, pointerId: number): void {
    try {
        marker.releasePointerCapture?.(pointerId);
    } catch {
        // Ignore release failures for detached targets or already-released capture.
    }
}

function numberAttribute(element: ElementLike, attribute: string): number | null {
    const value = element.getAttribute(attribute);
    if (value === null || value.trim() === "") return null;
    const parsed = Number(value);
    return Number.isFinite(parsed) ? parsed : null;
}

function numberValue(value: unknown): number {
    return typeof value === "number" && Number.isFinite(value) ? value : 0;
}

function ownerDocumentFor(root: Document | Element): Document | null {
    if ("elementFromPoint" in root) return root as Document;
    return (root as Element).ownerDocument ?? (typeof document !== "undefined" ? document : null);
}

function isElementLike(value: unknown): value is ElementLike {
    if (value === null || typeof value !== "object") return false;
    const maybe = value as Partial<ElementLike>;
    return typeof maybe.getAttribute === "function"
        && typeof maybe.closest === "function"
        && typeof maybe.querySelectorAll === "function";
}
