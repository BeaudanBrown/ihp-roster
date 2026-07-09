import { FrontendSurfaceInteractionDom, FrontendSurfaceRegistry, InteractionDom, InteractionStaticSchemas, isFrontendSurfaceInteractionSurfaceName, isFrontendSurfaceName, type InteractionEffectSource, type InteractionSessionEffect } from "../generated/contracts";
import { assertNever } from "../shared/exhaustive";
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
    activated: boolean;
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
const sourceRefSelector = `[${FrontendSurfaceInteractionDom.sourceRef}]`;
const disposableLayerSelector = `[${attrs.disposableLayer}]`;
const pointerFields = InteractionDom.pointerFields;
const defaultThresholdPx = 4;
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
    root.addEventListener("keydown", controller.handleKeyDown);
    root.addEventListener("click", controller.handleClick, true);
    root.addEventListener("htmx:beforeSwap", controller.handleExternalCleanup);
    root.addEventListener("htmx:beforeCleanupElement", controller.handleExternalCleanup);
    root.addEventListener(interactionSessionCancelRequestEventName, controller.handleCancelRequest);

    return () => {
        root.removeEventListener("pointerdown", controller.handlePointerDown);
        root.removeEventListener("pointermove", controller.handlePointerMove);
        root.removeEventListener("pointerup", controller.handlePointerUp);
        root.removeEventListener("pointercancel", controller.handlePointerCancel);
        root.removeEventListener("keydown", controller.handleKeyDown);
        root.removeEventListener("click", controller.handleClick, true);
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
    let suppressNextClickMarker: ElementLike | null = null;

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
        session.effects.cleanup(session);
        clearDisposableLayers(session.mount);
        releasePointerCapture(session.marker, session.pointerId);
        setDocumentInteractionActive(session.mount, false);
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
        if (!session.activated && movementDistance(session) < session.thresholdPx) return;
        const firstActivation = !session.activated;
        session.activated = true;
        if (firstActivation) session.effects.activate(session);
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
            const start = readPointerSessionStart(event, fallbackThresholdPx);
            if (!start) return;

            if (activeSession) cancelSession(activeSession, event);
            clearDisposableLayers(start.mount);
            activeSession = start;
            capturePointer(start.marker, start.pointerId);
            setDocumentInteractionActive(start.mount, true);
            if (event.cancelable) event.preventDefault();

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
            if (event.cancelable) event.preventDefault();
            updateSession(activeSession, event);
        },
        handlePointerUp(event: Event) {
            if (!activeSession || !isMatchingPointerEvent(event, activeSession)) return;
            if (event.cancelable && activeSession.activated) event.preventDefault();
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
            clearTimeoutHandle();
            suppressNextClickMarker = null;
        },
    };
}

export function readPointerSessionStart(event: Event, fallbackThresholdPx = defaultThresholdPx): ActivePointerSession | null {
    const pointerEvent = event as PointerEventLike;
    const marker = closestSurfaceSourceRef(event.target);
    if (!marker) return null;
    if (isDisabled(marker)) return null;

    const mount = closestInteractionMount(marker);
    if (!mount) return null;

    const surface = mount.getAttribute(attrs.surface);
    if (!isFrontendSurfaceName(surface)) return null;

    const sourceRef = marker.getAttribute(FrontendSurfaceInteractionDom.sourceRef);
    const source = FrontendSurfaceRegistry[surface].interaction.sourceRefs.find((candidate) => candidate.ref === sourceRef);
    if (!source) return null;

    const sourceKey = marker.getAttribute(FrontendSurfaceInteractionDom.sourceKey);
    if (!sourceKey) return null;

    const targetField = FrontendSurfaceRegistry[surface].interaction.dropzoneRefs.find((candidate) => candidate.session === source.session)?.targetField ?? null;
    return buildPointerSession({ event: pointerEvent, marker, mount, intent: source.intent, modifierVariants: source.modifierVariants ?? [], sessionKind: source.session, sourceField: source.sourceField, sourceKey, targetField, fallbackThresholdPx });
}

type PointerSessionBuildInput = {
    event: PointerEventLike;
    marker: ElementLike;
    mount: ElementLike;
    intent: string;
    modifierVariants: ReadonlyArray<InteractionModifierVariant>;
    sessionKind: string;
    sourceField: string | null;
    sourceKey: string | null;
    targetField: string | null;
    fallbackThresholdPx: number;
};

function buildPointerSession(input: PointerSessionBuildInput): ActivePointerSession {
    const startClientX = numberValue(input.event.clientX);
    const startClientY = numberValue(input.event.clientY);
    const thresholdPx = numberAttribute(input.marker, attrs.sessionThreshold) ?? input.fallbackThresholdPx;
    const session: ActivePointerSession = {
        mount: input.mount,
        marker: input.marker,
        intent: input.intent,
        defaultIntent: input.intent,
        activeModifierSemantic: null,
        modifierVariants: input.modifierVariants,
        sessionKind: input.sessionKind,
        sourceField: input.sourceField,
        sourceKey: input.sourceKey,
        targetField: input.targetField,
        pointerId: numberValue(input.event.pointerId),
        pointerType: input.event.pointerType ?? "unknown",
        startClientX,
        startClientY,
        currentClientX: startClientX,
        currentClientY: startClientY,
        thresholdPx: Math.max(0, thresholdPx),
        activated: false,
        effects: noOpEffectRunner,
    };
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
    return InteractionStaticSchemas[family].sessionKinds.find((candidate) => candidate.kind === session.sessionKind) ?? null;
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
    let grabOffsetX = 0;
    let grabOffsetY = 0;

    const cleanup = () => {
        if (shadow?.parentNode) shadow.parentNode.removeChild(shadow);
        shadow = null;
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
            moveShadow(shadow, session, grabOffsetX, grabOffsetY);
        },
        update(session) {
            if (!shadow) return;
            moveShadow(shadow, session, grabOffsetX, grabOffsetY);
        },
        cleanup,
    };
}

function createDropzoneHighlightEffect(className: string): ContextualEffectHandler {
    let activeTarget: Element | null = null;

    const clear = () => {
        if (activeTarget) removeClass(activeTarget, className);
        activeTarget = null;
    };

    return {
        update(_session, target) {
            if (target === activeTarget) return;
            clear();
            activeTarget = target;
            if (activeTarget) addClass(activeTarget, className);
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
    const targetDropzoneKey = targetDropzoneKeyForSession(session, targetDropzone);
    if (session.targetField && targetDropzoneKey) fields[session.targetField] = targetDropzoneKey;

    return fields;
}

function activeDropzone(session: ActivePointerSession): Element | null {
    return hitTestClosest(session.mount, session.currentClientX, session.currentClientY, surfaceDropzoneSelectorForSession(session));
}

function surfaceDropzoneSelectorForSession(session: ActivePointerSession): string {
    const surface = session.mount.getAttribute(attrs.surface);
    if (!isFrontendSurfaceName(surface)) return `[${FrontendSurfaceInteractionDom.dropzoneRef}]`;
    const compatibleRefs = FrontendSurfaceRegistry[surface].interaction.dropzoneRefs
        .filter((candidate) => candidate.session === session.sessionKind)
        .map((candidate) => candidate.ref);
    if (compatibleRefs.length === 0) return `[${FrontendSurfaceInteractionDom.dropzoneRef}]`;
    return compatibleRefs.map((ref) => `[${FrontendSurfaceInteractionDom.dropzoneRef}="${cssString(ref)}"]`).join(",");
}

function targetDropzoneKeyForSession(session: ActivePointerSession, target: Element | null): string | null {
    if (!target) return null;
    return target.getAttribute(FrontendSurfaceInteractionDom.dropzoneKey);
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

function closestInteractionMount(marker: ElementLike): ElementLike | null {
    const mount = marker.closest(`[${attrs.surface}]`);
    return isElementLike(mount) ? mount : null;
}

function clearDisposableLayers(mount: ElementLike): void {
    for (const layer of mount.querySelectorAll(disposableLayerSelector)) clearElement(layer);
}

function setDocumentInteractionActive(mount: ElementLike, active: boolean): void {
    const root = mount.ownerDocument?.documentElement;
    if (!root) return;
    if (active) root.setAttribute(attrs.interactionActive, values.enabled);
    else root.removeAttribute(attrs.interactionActive);
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
