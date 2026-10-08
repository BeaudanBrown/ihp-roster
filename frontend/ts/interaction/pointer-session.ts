import { FrontendSurfaceInteractionRegistry, InteractionDom, dragPreviewOffsetProperty, dragPreviewExtentProperty, nativeContextMenuDisabledDomAttr, isFrontendSurfaceInteractionSurfaceName, type FrontendSurfaceInteractionSurfaceName, type InteractionEffectSource, type InteractionSessionEffect } from "../generated/contracts";
import { assertNever } from "../shared/exhaustive";
import type { InteractionIntentPayload } from "./intent-bus";
import { defaultInteractionRuntime } from "./runtime";
import { readIntervalDrag, type IntervalDrag } from "./interval-drag";
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
    ownerDocument?: (Document & { documentElement?: ElementLike }) | null;
    setPointerCapture?(pointerId: number): void;
    releasePointerCapture?(pointerId: number): void;
};

type PointerEventLike = Event & {
    pointerId?: number;
    pointerType?: string;
    clientX?: number;
    clientY?: number;
    ctrlKey?: boolean;
    shiftKey?: boolean;
    altKey?: boolean;
    metaKey?: boolean;
};

type InteractionModifierVariant = {
    semantic: string;
    intent: string;
    effects?: {
        global: ReadonlyArray<InteractionSessionEffect>;
        contextual: ReadonlyArray<InteractionSessionEffect>;
    };
};

export type PointerSessionEffectRunner = {
    activate: (session: ActivePointerSession) => void;
    update: (session: ActivePointerSession) => void;
    cleanup: (session: ActivePointerSession) => void;
};

export type ActivePointerSession = {
    mount: ElementLike;
    marker: ElementLike;
    intent: string;
    defaultIntent: string;
    activeModifierSemantic: string | null;
    modifierVariants: ReadonlyArray<InteractionModifierVariant>;
    sessionKind: string;
    sourceRef: string;
    compatibleDropzoneRefs: ReadonlyArray<string>;
    sourceField: string | null;
    sourceKey: string | null;
    targetField: string | null;
    pointerId: number;
    pointerType: string;
    startClientX: number;
    startClientY: number;
    currentClientX: number;
    currentClientY: number;
    thresholdPx: number;
    holdThresholdPx: number;
    activated: boolean;
    longPressMs: number | null;
    hasMoved: boolean;
    intervalDrag: IntervalDrag | undefined;
    effects: PointerSessionEffectRunner;
};

type GlobalEffectHandler = {
    activate: (session: ActivePointerSession) => void;
    update: (session: ActivePointerSession) => void;
    cleanup: (session: ActivePointerSession) => void;
};

type ContextualEffectHandler = {
    update: (session: ActivePointerSession, target: Element | null) => void;
    cleanup: (session: ActivePointerSession) => void;
};

const attrs = InteractionDom.attributes;
const values = InteractionDom.values;
const sourceRefSelector = `[${attrs.sourceRef}]`;
const interactiveControlSelector = "button,a,input,select,textarea,[role=button],[role=link]";
const disposableLayerSelector = `[${attrs.disposableLayer}]`;
const pointerFields = InteractionDom.pointerFields;
const defaultThresholdPx = 4;
const minimumTouchHoldTolerancePx = 10;
const activeSourceRefAttribute = attrs.activeSourceRef;
const noOpEffectRunner: PointerSessionEffectRunner = {
    activate: () => undefined,
    update: () => undefined,
    cleanup: () => undefined,
};

export function enableGenericPointerSessions(options: PointerSessionOptions = {}): () => void {
    if (typeof document === "undefined") return () => undefined;

    const controller = createPointerSessionController(options);
    const root = options.root ?? document;

    root.addEventListener("pointerdown", controller.handlePointerDown);
    root.addEventListener("pointermove", controller.handlePointerMove);
    root.addEventListener("pointerup", controller.handlePointerUp);
    root.addEventListener("pointercancel", controller.handlePointerCancel);
    root.addEventListener("touchmove", controller.handleTouchMove, { passive: false });
    root.addEventListener("contextmenu", controller.handleContextMenu, true);
    root.addEventListener("keydown", controller.handleKeyDown);
    root.addEventListener("keyup", controller.handleKeyUp);
    root.addEventListener("click", controller.handleClick, true);
    root.addEventListener("htmx:beforeSwap", controller.handleExternalCleanup);
    root.addEventListener("htmx:beforeCleanupElement", controller.handleExternalCleanup);
    root.addEventListener(interactionSessionCancelRequestEventName, controller.handleCancelRequest);
    window.addEventListener("resize", controller.stop);

    return () => {
        root.removeEventListener("pointerdown", controller.handlePointerDown);
        root.removeEventListener("pointermove", controller.handlePointerMove);
        root.removeEventListener("pointerup", controller.handlePointerUp);
        root.removeEventListener("pointercancel", controller.handlePointerCancel);
        root.removeEventListener("touchmove", controller.handleTouchMove);
        root.removeEventListener("contextmenu", controller.handleContextMenu, true);
        root.removeEventListener("keydown", controller.handleKeyDown);
        root.removeEventListener("keyup", controller.handleKeyUp);
        root.removeEventListener("click", controller.handleClick, true);
        root.removeEventListener("htmx:beforeSwap", controller.handleExternalCleanup);
        root.removeEventListener("htmx:beforeCleanupElement", controller.handleExternalCleanup);
        root.removeEventListener(interactionSessionCancelRequestEventName, controller.handleCancelRequest);
        window.removeEventListener("resize", controller.stop);
        controller.stop();
    };
}

export function createPointerSessionController(options: PointerSessionOptions = {}) {
    const runtime = options.runtime ?? defaultInteractionRuntime;
    const fallbackThresholdPx = options.thresholdPx ?? defaultThresholdPx;
    let activeSession: ActivePointerSession | null = null;
    let timeoutHandle: ReturnType<typeof setTimeout> | null = null;
    let longPressHandle: ReturnType<typeof setTimeout> | null = null;
    let suppressNextClickMarker: ElementLike | null = null;
    let delayedTouchMenuMarker: ElementLike | null = null;
    let delayedTouchMenuTimer: ReturnType<typeof setTimeout> | null = null;

    const clearDelayedTouchMenu = () => {
        if (delayedTouchMenuTimer !== null) clearTimeout(delayedTouchMenuTimer);
        delayedTouchMenuTimer = null;
        delayedTouchMenuMarker = null;
    };
    let scrollFrame: number | null = null;
    let lastScrollFrameTime: number | null = null;

    const stopEdgeScrolling = () => {
        if (scrollFrame !== null) cancelAnimationFrame(scrollFrame);
        scrollFrame = null;
        lastScrollFrameTime = null;
    };

    const startEdgeScrolling = (session: ActivePointerSession) => {
        const owner = session.marker.closest(`[${attrs.dragScrollContainer}]`);
        if (!owner || owner.getAttribute(attrs.dragScrollContainer) !== values.enabled
            || closestInteractionMount(owner) !== session.mount || typeof requestAnimationFrame !== "function") return;
        const container = owner as HTMLElement;
        let observedScrollLeft = container.scrollLeft;
        let observedScrollTop = container.scrollTop;
        const frame = (time: number) => {
            scrollFrame = null;
            if (activeSession !== session || !session.activated) return;
            if (container.isConnected === false) {
                cancelSession(session, null);
                return;
            }
            const elapsed = lastScrollFrameTime === null ? 16 : Math.min(32, Math.max(0, time - lastScrollFrameTime));
            lastScrollFrameTime = time;
            scrollDragContainer(container, session.currentClientX, session.currentClientY, elapsed);
            if (container.scrollLeft !== observedScrollLeft || container.scrollTop !== observedScrollTop) {
                observedScrollLeft = container.scrollLeft;
                observedScrollTop = container.scrollTop;
                session.hasMoved = true;
                session.effects.update(session);
                runtime.emit({ phase: "preview", intent: session.intent, fields: pointerSessionFields(session), mount: session.mount, marker: session.marker, sourceEvent: null });
            }
            if (activeSession === session) scrollFrame = requestAnimationFrame(frame);
        };
        scrollFrame = requestAnimationFrame(frame);
    };

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
        clearDelayedTouchMenu();
        // Mobile engines may dispatch contextmenu after pointercancel/pointerup.
        // Retain only this source briefly; never retain the drag or permit a save.
        if (session.pointerType === "touch" && (reason === "pointercancel" || reason === "pointerup")) {
            delayedTouchMenuMarker = session.marker;
            delayedTouchMenuTimer = setTimeout(clearDelayedTouchMenu, 1000);
        }
        clearTimeoutHandle();
        stopEdgeScrolling();
        if (longPressHandle !== null) clearTimeout(longPressHandle);
        longPressHandle = null;
        session.effects.cleanup(session);
        clearDisposableLayers(session.mount);
        releasePointerCapture(session.marker, session.pointerId);
        setDocumentInteractionActive(session, false);
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
        if (session.activated) suppressNextClickMarker = session.marker;
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
        suppressNextClickMarker = session.marker;
        cleanupSession(session, sourceEvent.type);
    };

    const updateSession = (session: ActivePointerSession, event: PointerEventLike) => {
        session.currentClientX = numberValue(event.clientX);
        session.currentClientY = numberValue(event.clientY);
        if (!session.activated && session.pointerType === "touch") {
            if (movementDistance(session) >= session.holdThresholdPx) cancelSession(session, event);
            return;
        }
        if (!session.activated && movementDistance(session) < session.thresholdPx) return;
        const firstActivation = !session.activated;
        if (movementDistance(session) >= session.thresholdPx) session.hasMoved = true;
        session.activated = true;
        if (firstActivation) {
            session.effects.activate(session);
            startEdgeScrolling(session);
        }
        updateActiveModifierVariant(session, event);
        session.effects.update(session);
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
            clearDelayedTouchMenu();
            if (activeSession?.pointerType === "touch" && (event as PointerEventLike).pointerType === "touch"
                && !isMatchingPointerEvent(event, activeSession)) {
                cancelSession(activeSession, event);
                return;
            }
            const start = readPointerSessionStart(event, fallbackThresholdPx);
            if (!start) return;

            if (activeSession) cancelSession(activeSession, event);
            clearDisposableLayers(start.mount);
            activeSession = start;
            if (start.pointerType !== "touch") {
                capturePointer(start.marker, start.pointerId);
                setDocumentInteractionActive(start, true);
                if (event.cancelable) event.preventDefault();
            }

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
            if (start.pointerType === "touch" && start.longPressMs !== null) {
                longPressHandle = setTimeout(() => {
                    longPressHandle = null;
                    if (activeSession !== start) return;
                    // Finger settling during the hold is not an intended move.
                    // Rebase both movement detection and interval grab geometry.
                    start.startClientX = start.currentClientX;
                    start.startClientY = start.currentClientY;
                    const interval = readIntervalDrag(start.marker, start.mount, surfaceDropzoneSelectorForSession(start), start.startClientX, start.startClientY);
                    if (interval === null) {
                        cancelSession(start, null);
                        return;
                    }
                    start.intervalDrag = interval;
                    start.activated = true;
                    capturePointer(start.marker, start.pointerId);
                    setDocumentInteractionActive(start, true);
                    start.effects.activate(start);
                    start.effects.update(start);
                    startEdgeScrolling(start);
                    runtime.emit({ phase: "preview", intent: start.intent, fields: pointerSessionFields(start), mount: start.mount, marker: start.marker, sourceEvent: null });
                }, start.longPressMs);
            }
        },
        handlePointerMove(event: Event) {
            if (!activeSession || !isMatchingPointerEvent(event, activeSession)) return;
            if (event.cancelable && (activeSession.pointerType !== "touch" || activeSession.activated)) event.preventDefault();
            updateSession(activeSession, event);
        },
        handlePointerUp(event: Event) {
            if (!activeSession || !isMatchingPointerEvent(event, activeSession)) return;
            if (event.cancelable && activeSession.activated) event.preventDefault();
            const session = activeSession;
            updateSession(session, event);
            if (activeSession !== session) return;
            if (session.activated && session.hasMoved) finishSession(session, event);
            else cancelSession(session, event);
        },
        handlePointerCancel(event: Event) {
            if (!activeSession || !isMatchingPointerEvent(event, activeSession)) return;
            cancelSession(activeSession, event);
        },
        handleTouchMove(event: Event) {
            if (!activeSession || activeSession.pointerType !== "touch") return;
            const touches = (event as TouchEvent).touches;
            if (touches && touches.length > 1) {
                cancelSession(activeSession, event);
                return;
            }
            if (activeSession.activated && event.cancelable) event.preventDefault();
        },
        handleContextMenu(event: Event) {
            const region = isElementLike(event.target)
                ? event.target.closest(`[${nativeContextMenuDisabledDomAttr}]`) : null;
            if (region?.getAttribute(nativeContextMenuDisabledDomAttr) === values.enabled) {
                if (event.cancelable) event.preventDefault();
                return;
            }
            // Native long-press thresholds vary by browser/device and can beat
            // the app's activation timer. Reserve the gesture while pending too.
            const delayedTouchMenu = delayedTouchMenuMarker !== null
                && delayedTouchMenuMarker.isConnected !== false
                && closestSurfaceSourceRef(event.target) === delayedTouchMenuMarker;
            if ((activeSession?.pointerType === "touch" || delayedTouchMenu) && event.cancelable) event.preventDefault();
        },
        handleKeyDown(event: Event) {
            clearDelayedTouchMenu();
            if (!activeSession) return;
            if (isEscapeKeyboardEvent(event)) {
                if (event.cancelable) event.preventDefault();
                cancelSession(activeSession, event);
                return;
            }
            updateSessionModifierFromKeyboard(activeSession, event);
        },
        handleKeyUp(event: Event) {
            if (!activeSession) return;
            updateSessionModifierFromKeyboard(activeSession, event);
        },
        handleExternalCleanup(event: Event) {
            clearDelayedTouchMenu();
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
        handleClick(event: Event) {
            if (!suppressNextClickMarker) return;
            const marker = closestSurfaceSourceRef(event.target);
            if (marker !== suppressNextClickMarker) return;
            suppressNextClickMarker = null;
            if (event.cancelable) event.preventDefault();
            event.stopImmediatePropagation?.();
        },
        currentSession() {
            return activeSession;
        },
        stop() {
            if (activeSession) cancelSession(activeSession, null);
            clearDelayedTouchMenu();
            clearTimeoutHandle();
            suppressNextClickMarker = null;
        },
    };
}

export function readPointerSessionStart(event: Event, fallbackThresholdPx = defaultThresholdPx): ActivePointerSession | null {
    const pointerEvent = event as PointerEventLike;
    const marker = closestSurfaceSourceRef(event.target);
    if (!marker) return null;
    if (pointerEvent.pointerType === "touch" && (numberAttribute(marker, attrs.sessionLongPressMs) ?? 0) <= 0) return null;
    if (isDisabled(marker)) return null;
    const interactiveControl = closestInteractiveControl(event.target);
    if (interactiveControl && interactiveControl !== marker) return null;

    const mount = closestInteractionMount(marker);
    if (!mount) return null;

    const surface = mount.getAttribute(attrs.surface);
    if (!isFrontendSurfaceInteractionSurfaceName(surface)) return null;

    const sourceRef = marker.getAttribute(attrs.sourceRef);
    const source = FrontendSurfaceInteractionRegistry[surface].sourceRefs.find((candidate) => candidate.ref === sourceRef);
    if (!source) return null;

    const sourceKey = marker.getAttribute(attrs.sourceKey);
    if (!sourceKey) return null;

    const compatibleDropzoneRefs = compatibleDropzoneRefsForSource(surface, source);
    const targetField = FrontendSurfaceInteractionRegistry[surface].dropzoneRefs.find((candidate) => compatibleDropzoneRefs.includes(candidate.ref))?.targetField ?? null;
    return buildPointerSession({ event: pointerEvent, marker, mount, intent: source.intent, modifierVariants: source.modifierVariants ?? [], sessionKind: source.session, sourceRef: source.ref, compatibleDropzoneRefs, sourceField: source.sourceField, sourceKey, targetField, fallbackThresholdPx });
}

type PointerSessionBuildInput = {
    event: PointerEventLike;
    marker: ElementLike;
    mount: ElementLike;
    intent: string;
    modifierVariants: ReadonlyArray<InteractionModifierVariant>;
    sessionKind: string;
    sourceRef: string;
    compatibleDropzoneRefs: ReadonlyArray<string>;
    sourceField: string | null;
    sourceKey: string | null;
    targetField: string | null;
    fallbackThresholdPx: number;
};

function buildPointerSession(input: PointerSessionBuildInput): ActivePointerSession | null {
    const startClientX = numberValue(input.event.clientX);
    const startClientY = numberValue(input.event.clientY);
    const thresholdPx = Math.max(0, numberAttribute(input.marker, attrs.sessionThreshold) ?? input.fallbackThresholdPx);
    const viewportScale = input.marker.ownerDocument?.defaultView?.visualViewport?.scale ?? 1;
    // clientX/Y are layout pixels; touch slop is measured in visible CSS pixels.
    // Desktop-site zoom-out must not amplify normal finger jitter.
    const scale = input.event.pointerType === "touch" && Number.isFinite(viewportScale) && viewportScale > 0 ? viewportScale : 1;
    const session: ActivePointerSession = {
        mount: input.mount,
        marker: input.marker,
        intent: input.intent,
        defaultIntent: input.intent,
        activeModifierSemantic: null,
        modifierVariants: input.modifierVariants,
        sessionKind: input.sessionKind,
        sourceRef: input.sourceRef,
        compatibleDropzoneRefs: input.compatibleDropzoneRefs,
        sourceField: input.sourceField,
        sourceKey: input.sourceKey,
        targetField: input.targetField,
        pointerId: numberValue(input.event.pointerId),
        pointerType: input.event.pointerType ?? "unknown",
        startClientX,
        startClientY,
        currentClientX: startClientX,
        currentClientY: startClientY,
        thresholdPx: thresholdPx / scale,
        holdThresholdPx: Math.max(minimumTouchHoldTolerancePx, thresholdPx) / scale,
        activated: false,
        longPressMs: numberAttribute(input.marker, attrs.sessionLongPressMs),
        hasMoved: false,
        intervalDrag: undefined,
        effects: noOpEffectRunner,
    };
    const interval = readIntervalDrag(input.marker, input.mount, surfaceDropzoneSelectorForSession(session), startClientX, startClientY);
    if (interval === null) return null;
    session.intervalDrag = interval;
    session.effects = createPointerSessionEffectRunner(session);
    return session;
}

export function createPointerSessionEffectRunner(session: ActivePointerSession): PointerSessionEffectRunner {
    const sessionEffects = activeSessionEffects(session);
    if (!sessionEffects) return noOpEffectRunner;

    const globalHandlers = sessionEffects.global
        .map(createGlobalEffectHandler)
        .filter((handler): handler is GlobalEffectHandler => handler !== null);
    const contextualHandlers = sessionEffects.contextual
        .map(createContextualEffectHandler)
        .filter((handler): handler is ContextualEffectHandler => handler !== null);

    if (globalHandlers.length === 0 && contextualHandlers.length === 0) return noOpEffectRunner;

    return {
        activate(activeSession) {
            for (const handler of globalHandlers) handler.activate(activeSession);
        },
        update(activeSession) {
            for (const handler of globalHandlers) handler.update(activeSession);
            if (contextualHandlers.length === 0) return;
            const target = activeDropzone(activeSession);
            for (const handler of contextualHandlers) handler.update(activeSession, target);
        },
        cleanup(activeSession) {
            for (const handler of contextualHandlers) handler.cleanup(activeSession);
            for (const handler of globalHandlers) handler.cleanup(activeSession);
        },
    };
}

// Geometry only: the server opts a scroll owner in; neither targets nor opaque
// keys are interpreted here. A stationary pointer keeps scrolling via RAF.
export function scrollDragContainer(container: HTMLElement, clientX: number, clientY: number, elapsedMs: number): boolean {
    const horizontal = scrollHorizontalDragContainer(container, clientX, clientY, elapsedMs);
    const rect = container.getBoundingClientRect();
    const edge = Math.min(48, container.clientHeight / 3);
    const bottom = rect.top + container.clientHeight;
    if (edge <= 0 || clientX < rect.left || clientX > rect.left + rect.width
        || clientY < rect.top - edge || clientY > bottom + edge) return horizontal;
    const direction = clientY < rect.top + edge ? -Math.min(1, (rect.top + edge - clientY) / edge)
        : clientY > bottom - edge ? Math.min(1, (clientY - bottom + edge) / edge) : 0;
    const before = container.scrollTop;
    container.scrollTop = Math.max(0, Math.min(container.scrollHeight - container.clientHeight, before + direction * 0.48 * elapsedMs));
    return horizontal || container.scrollTop !== before;
}

export function scrollHorizontalDragContainer(container: HTMLElement, clientX: number, clientY: number, elapsedMs: number): boolean {
    const rect = container.getBoundingClientRect();
    const edge = Math.min(48, container.clientWidth / 3);
    const right = rect.left + container.clientWidth;
    if (edge <= 0 || clientY < rect.top || clientY > rect.top + rect.height
        || clientX < rect.left - edge || clientX > right + edge) return false;
    const direction = clientX < rect.left + edge ? -Math.min(1, (rect.left + edge - clientX) / edge)
        : clientX > right - edge ? Math.min(1, (clientX - right + edge) / edge) : 0;
    const before = container.scrollLeft;
    container.scrollLeft = Math.max(0, Math.min(container.scrollWidth - container.clientWidth, before + direction * 0.48 * elapsedMs));
    return container.scrollLeft !== before;
}

export function hitTestClosest(root: Document | Element, clientX: number, clientY: number, selector: string): Element | null {
    const doc = ownerDocumentFor(root);
    const elementFromPoint = doc?.elementFromPoint?.bind(doc);
    if (!elementFromPoint) return null;

    const hit = elementFromPoint(clientX, clientY);
    if (!isElementLike(hit)) return null;
    return hit.closest(selector);
}

function activeSessionEffects(session: ActivePointerSession): { global: ReadonlyArray<InteractionSessionEffect>; contextual: ReadonlyArray<InteractionSessionEffect> } | null {
    const variant = activeModifierVariant(session);
    if (variant?.effects) return variant.effects;

    const sessionDefinition = interactionSessionDefinitionFor(session);
    return sessionDefinition?.effects ?? null;
}

function activeModifierVariant(session: ActivePointerSession): InteractionModifierVariant | null {
    if (!session.activeModifierSemantic) return null;
    return session.modifierVariants.find((variant) => variant.semantic === session.activeModifierSemantic) ?? null;
}

function updateSessionModifierFromKeyboard(session: ActivePointerSession, event: Event): void {
    if (!session.activated) return;
    updateActiveModifierVariant(session, event as PointerEventLike);
    session.effects.update(session);
}

function updateActiveModifierVariant(session: ActivePointerSession, event: PointerEventLike): void {
    const nextSemantic = semanticModifierForEvent(event);
    const nextVariant = nextSemantic ? session.modifierVariants.find((variant) => variant.semantic === nextSemantic) ?? null : null;
    const nextIntent = nextVariant?.intent ?? session.defaultIntent;
    const activeSemantic = nextVariant?.semantic ?? null;
    if (session.intent === nextIntent && session.activeModifierSemantic === activeSemantic) return;

    const wasActivated = session.activated;
    if (wasActivated) session.effects.cleanup(session);
    session.intent = nextIntent;
    session.activeModifierSemantic = activeSemantic;
    session.effects = createPointerSessionEffectRunner(session);
    if (wasActivated) session.effects.activate(session);
}

function semanticModifierForEvent(event: PointerEventLike): string | null {
    const pressed = [event.ctrlKey, event.shiftKey, event.altKey, event.metaKey].filter(Boolean).length;
    if (pressed !== 1) return null;
    if (isMacPlatform()) return event.altKey ? "copy" : null;
    return event.ctrlKey ? "copy" : null;
}

function isMacPlatform(): boolean {
    const nav = typeof navigator === "undefined" ? null : navigator;
    const platform = nav?.platform ?? "";
    const userAgentDataPlatform = (nav as Navigator & { userAgentData?: { platform?: string } } | null)?.userAgentData?.platform ?? "";
    return /mac|iphone|ipad|ipod/i.test(`${platform} ${userAgentDataPlatform}`);
}

function interactionSessionDefinitionFor(session: ActivePointerSession) {
    const family = session.mount.getAttribute(attrs.surfaceFamily);
    if (!isFrontendSurfaceInteractionSurfaceName(family)) return null;
    return FrontendSurfaceInteractionRegistry[family].sessionKinds.find((candidate) => candidate.kind === session.sessionKind) ?? null;
}

function createGlobalEffectHandler(effect: InteractionSessionEffect): GlobalEffectHandler | null {
    switch (effect.kind) {
        case "clone-shadow":
            return createCloneShadowEffect(effect);
        case "dropzone-highlight":
            return null;
        default:
            return assertNever(effect);
    }
}

function createContextualEffectHandler(effect: InteractionSessionEffect): ContextualEffectHandler | null {
    switch (effect.kind) {
        case "clone-shadow":
            return null;
        case "dropzone-highlight":
            return createDropzoneHighlightEffect(effect.className);
        default:
            return assertNever(effect);
    }
}

function createCloneShadowEffect(effect: Extract<InteractionSessionEffect, { kind: "clone-shadow" }>): GlobalEffectHandler {
    let shadow: Element | null = null;
    let label: HTMLElement | null = null;
    let grabOffsetX = 0;
    let grabOffsetY = 0;
    let landing: HTMLElement | null = null;
    let restoreLanding: (() => void) | null = null;

    const setLanding = (next: HTMLElement | null) => {
        if (next === landing) return;
        restoreLanding?.();
        restoreLanding = null;
        landing = next;
        if (!next) return;
        const text = next.textContent;
        const style = next.getAttribute("style");
        const classes = next.getAttribute("class");
        addClass(next, effect.className);
        restoreLanding = () => {
            next.textContent = text;
            if (style === null) next.removeAttribute("style");
            else next.setAttribute("style", style);
            if (classes === null) next.removeAttribute("class");
            else next.setAttribute("class", classes);
        };
    };

    const cleanup = () => {
        setLanding(null);
        if (shadow?.parentNode) shadow.parentNode.removeChild(shadow);
        shadow = null;
        label?.remove();
        label = null;
    };

    const update = (session: ActivePointerSession) => {
        if (!shadow) return;
        const projection = session.intervalDrag?.project(session.currentClientX, session.currentClientY);
        if (session.intervalDrag) {
            setLanding(targetPreviewWithinMount(projection?.target ?? null, session.mount));
            (shadow as HTMLElement).hidden = !projection || !!landing;
            if (landing) removeClass(shadow, effect.className);
            else addClass(shadow, effect.className);
            if (label) label.hidden = !projection;
            if (!projection) return;
            if (landing) {
                // Change interval inputs only. The same renderer owns empty
                // hover and drag geometry, including the full cross-axis span.
                landing.style.setProperty(dragPreviewOffsetProperty, `${projection.previewOffsetPercent}%`);
                landing.style.setProperty(dragPreviewExtentProperty, `${projection.previewExtentPercent}%`);
                landing.textContent = projection.label;
            } else {
                const style = (shadow as HTMLElement).style;
                style.width = `${projection.width}px`;
                style.height = `${projection.height}px`;
                style.transform = `translate3d(${projection.left}px, ${projection.top}px, 0)`;
            }
            if (label) {
                label.textContent = projection.label;
                const viewport = label.ownerDocument.documentElement;
                const x = Math.max(4, Math.min(session.currentClientX + 12, viewport.clientWidth - label.offsetWidth - 4));
                const y = Math.max(4, Math.min(session.currentClientY + 20, viewport.clientHeight - label.offsetHeight - 4));
                label.style.transform = `translate3d(${x}px, ${y}px, 0)`;
            }
        } else {
            moveShadow(shadow, session, grabOffsetX, grabOffsetY);
        }
    };

    return {
        activate(session) {
            cleanup();
            const layer = disposableLayerByName(session.mount, effect.layer);
            const source = cloneShadowSourceElement(effect.source, session);
            const proxy = layer?.ownerDocument?.createElement?.("div");
            if (!layer || !source || !proxy) return;

            const rect = elementRect(source);
            grabOffsetX = effect.preserveGrabOffset ? session.startClientX - rect.left : 0;
            grabOffsetY = effect.preserveGrabOffset ? session.startClientY - rect.top : 0;

            addClass(proxy, effect.className);
            proxy.setAttribute("aria-hidden", "true");
            applyShadowBaseStyle(proxy, rect);
            layer.appendChild(proxy);
            shadow = proxy;
            if (session.intervalDrag) {
                label = layer.ownerDocument.createElement("div");
                label.setAttribute(attrs.dragPreviewLabel, values.enabled);
                label.setAttribute("aria-hidden", "true");
                layer.appendChild(label);
            }
            update(session);
        },
        update,
        cleanup,
    };
}

export function targetPreviewWithinMount(target: Element | null, mount: Element): HTMLElement | null {
    return Array.from(target?.querySelectorAll<HTMLElement>(`[${attrs.dragTargetPreview}="${values.enabled}"]`) ?? [])
        .find(preview => preview.closest(`[${attrs.surface}]`) === mount
            && preview.closest(`[${attrs.dropzoneRef}]`) === target) ?? null;
}

function createDropzoneHighlightEffect(className: string): ContextualEffectHandler {
    let activeTarget: Element | null = null;
    const projectedClass = "bepis-dropzone-highlight-projected";

    const clear = () => {
        if (activeTarget) {
            removeClass(activeTarget, className);
            removeClass(activeTarget, projectedClass);
        }
        activeTarget = null;
    };

    return {
        update(session, target) {
            if (target !== activeTarget) {
                clear();
                activeTarget = target;
                if (activeTarget) addClass(activeTarget, className);
            }
            if (session.intervalDrag && activeTarget && targetPreviewWithinMount(activeTarget, session.mount)) {
                addClass(activeTarget, projectedClass);
            }
        },
        cleanup() {
            clear();
        },
    };
}

function cloneShadowSourceElement(source: InteractionEffectSource, session: ActivePointerSession): ElementLike | null {
    switch (source) {
        case "pointer-marker":
            return session.marker;
        default:
            return assertNever(source);
    }
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
    const fields: Record<string, string> = {
        [pointerFields.sessionKind]: session.sessionKind,
        [pointerFields.pointerId]: String(session.pointerId),
        [pointerFields.pointerType]: session.pointerType,
        [pointerFields.startClientX]: String(session.startClientX),
        [pointerFields.startClientY]: String(session.startClientY),
        [pointerFields.currentClientX]: String(session.currentClientX),
        [pointerFields.currentClientY]: String(session.currentClientY),
        [pointerFields.deltaX]: String(deltaX),
        [pointerFields.deltaY]: String(deltaY),
    };

    if (session.sourceField && session.sourceKey) fields[session.sourceField] = session.sourceKey;

    const targetDropzone = activeDropzone(session);
    const targetDropzoneKey = targetDropzoneKeyForTarget(targetDropzone);
    const targetField = targetDropzoneFieldForSession(session, targetDropzone) ?? session.targetField;
    if (targetField && targetDropzoneKey) fields[targetField] = targetDropzoneKey;

    return fields;
}

function activeDropzone(session: ActivePointerSession): Element | null {
    if (session.intervalDrag) return session.intervalDrag.project(session.currentClientX, session.currentClientY)?.target ?? null;
    return hitTestClosest(session.mount, session.currentClientX, session.currentClientY, surfaceDropzoneSelectorForSession(session));
}

function surfaceDropzoneSelectorForSession(session: ActivePointerSession): string {
    const compatibleRefs = session.compatibleDropzoneRefs;
    if (compatibleRefs.length === 0) return `[${attrs.dropzoneRef}]`;
    return compatibleRefs.map((ref) => `[${attrs.dropzoneRef}="${cssString(ref)}"]`).join(",");
}

function compatibleDropzoneRefsForSource(surface: FrontendSurfaceInteractionSurfaceName, source: { readonly session: string; readonly compatibleDropzones?: readonly string[] }): ReadonlyArray<string> {
    const explicitRefs = source.compatibleDropzones ?? [];
    if (explicitRefs.length > 0) return explicitRefs;
    return FrontendSurfaceInteractionRegistry[surface].dropzoneRefs
        .filter((candidate) => candidate.session === source.session)
        .map((candidate) => candidate.ref);
}

function targetDropzoneFieldForSession(session: ActivePointerSession, target: Element | null): string | null {
    if (!target) return null;
    const surface = session.mount.getAttribute(attrs.surface);
    if (!isFrontendSurfaceInteractionSurfaceName(surface)) return null;
    const ref = target.getAttribute(attrs.dropzoneRef);
    if (!ref) return null;
    return FrontendSurfaceInteractionRegistry[surface].dropzoneRefs.find((candidate) => candidate.ref === ref)?.targetField ?? null;
}

function targetDropzoneKeyForTarget(target: Element | null): string | null {
    if (!target) return null;
    return target.getAttribute(attrs.dropzoneKey);
}

function cssString(value: string): string {
    return value.replace(/\\/g, "\\\\").replace(/\"/g, "\\\"");
}

function disposableLayerByName(mount: ElementLike, layerName: string): Element | null {
    for (const layer of mount.querySelectorAll(disposableLayerSelector)) {
        if (layer.getAttribute(attrs.disposableLayer) === layerName) return layer;
    }
    return null;
}

function applyShadowBaseStyle(element: Element, rect: DOMRectLike): void {
    const style = (element as HTMLElement).style;
    if (!style) return;
    style.position = "fixed";
    style.left = "0px";
    style.top = "0px";
    style.width = `${Math.max(0, rect.width)}px`;
    style.height = `${Math.max(0, rect.height)}px`;
    style.pointerEvents = "none";
    style.zIndex = "1100";
    style.overflow = "hidden";
    style.contain = "layout paint";
}

function moveShadow(element: Element, session: ActivePointerSession, offsetX: number, offsetY: number): void {
    const style = (element as HTMLElement).style;
    if (!style) return;
    const x = session.currentClientX - offsetX;
    const y = session.currentClientY - offsetY;
    style.transform = `translate3d(${x}px, ${y}px, 0)`;
}

type DOMRectLike = Pick<DOMRect, "left" | "top" | "width" | "height">;

function elementRect(element: Element): DOMRectLike {
    const rect = element.getBoundingClientRect?.();
    return {
        left: numberValue(rect?.left),
        top: numberValue(rect?.top),
        width: numberValue(rect?.width),
        height: numberValue(rect?.height),
    };
}

function movementDistance(session: ActivePointerSession): number {
    const deltaX = session.currentClientX - session.startClientX;
    const deltaY = session.currentClientY - session.startClientY;
    return Math.hypot(deltaX, deltaY);
}

function closestSurfaceSourceRef(target: EventTarget | null): ElementLike | null {
    if (!isElementLike(target)) return null;
    const marker = target.closest(sourceRefSelector);
    return isElementLike(marker) ? marker : null;
}

function closestInteractiveControl(target: EventTarget | null): ElementLike | null {
    if (!isElementLike(target)) return null;
    const control = target.closest(interactiveControlSelector);
    return isElementLike(control) ? control : null;
}

function closestInteractionMount(marker: ElementLike): ElementLike | null {
    const mount = marker.closest(`[${attrs.surface}]`);
    return isElementLike(mount) ? mount : null;
}

function clearDisposableLayers(mount: ElementLike): void {
    for (const layer of mount.querySelectorAll(disposableLayerSelector)) clearElement(layer);
}

function setDocumentInteractionActive(session: ActivePointerSession, active: boolean): void {
    const root = session.mount.ownerDocument?.documentElement;
    if (!root) return;
    if (active) {
        root.setAttribute(attrs.interactionActive, values.enabled);
        root.setAttribute(activeSourceRefAttribute, session.sourceRef);
    } else {
        root.removeAttribute(attrs.interactionActive);
        root.removeAttribute(activeSourceRefAttribute);
    }
}

function clearElement(element: Element): void {
    const mutable = element as Element & { replaceChildren?: () => void; innerHTML?: string };
    if (typeof mutable.replaceChildren === "function") {
        mutable.replaceChildren();
        return;
    }
    if (typeof mutable.innerHTML === "string") mutable.innerHTML = "";
}

function addClass(element: Element, className: string): void {
    if (!className) return;
    if (element.classList) {
        element.classList.add(...className.split(/\s+/).filter(Boolean));
        return;
    }
    const existing = element.getAttribute("class")?.split(/\s+/).filter(Boolean) ?? [];
    const merged = new Set([...existing, ...className.split(/\s+/).filter(Boolean)]);
    element.setAttribute("class", Array.from(merged).join(" "));
}

function removeClass(element: Element, className: string): void {
    if (!className) return;
    const names = className.split(/\s+/).filter(Boolean);
    if (element.classList) {
        element.classList.remove(...names);
        return;
    }
    const remaining = (element.getAttribute("class")?.split(/\s+/).filter(Boolean) ?? []).filter((name) => !names.includes(name));
    if (remaining.length > 0) element.setAttribute("class", remaining.join(" "));
    else element.removeAttribute("class");
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
