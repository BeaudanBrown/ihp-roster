import {
    horizontalDragConfigDomAttr,
    horizontalScrollDragDomAttr,
    horizontalScrollSnapDomAttr,
    horizontalSnapConfigDomAttr,
    type HorizontalDragConfig,
    type HorizontalSnapConfig,
} from "./generated/contracts";
import {
    parseHorizontalDragConfiguration,
    parseHorizontalSnapConfiguration,
} from "./horizontal-scroll/configuration";
import {
    clampHorizontalScrollLeft,
    parsePositiveIntegerForHorizontalScroll,
} from "./horizontal-scroll/math";
import { rootFromTarget } from "./shared/dom";
import { detailTarget, onAppPageReady, onHtmxLoad } from "./shared/lifecycle";

export { clampHorizontalScrollLeft, parsePositiveIntegerForHorizontalScroll };

const snapSelector = `[${horizontalScrollSnapDomAttr}]`;
const dragSelector = `[${horizontalScrollDragDomAttr}]`;
const capabilitySelector = `${snapSelector}, ${dragSelector}`;
const phoneMediaQuery = "(max-width: 575.98px)";
const interactiveIgnoreSelector = [
    "a",
    "button",
    "input",
    "select",
    "textarea",
    "label",
    '[role="button"]',
    '[role="link"]',
].join(", ");
const snapDraggingClass = "is-horizontal-snap-dragging";
const dragDraggingClass = "is-horizontal-dragging";
const snapDebounceMs = 120;
const snapTolerancePx = 1;
const dragThresholdPx = 6;
const clickSuppressionMs = 250;

type ActiveDrag = {
    pointerId: number;
    startX: number;
    startScrollLeft: number;
    isDragging: boolean;
    didDrag: boolean;
};

export type HorizontalScrollDiagnostic = {
    code: "invalid-snap-config" | "invalid-drag-config";
    elementId: string;
    message: string;
};

export type HorizontalScrollDiagnosticReporter = (diagnostic: HorizontalScrollDiagnostic) => void;

function defaultDiagnosticReporter(diagnostic: HorizontalScrollDiagnostic): void {
    console.error?.("Invalid generated horizontal-scroll configuration", diagnostic);
}

function readConfig<T>(
    element: HTMLElement,
    attribute: string,
    parse: (raw: string) => T,
): T {
    const raw = element.getAttribute(attribute);
    if (raw === null) throw new Error(`Missing ${attribute}`);
    return parse(raw);
}

function validateLocalSelectors(
    element: HTMLElement,
    snapConfig: HorizontalSnapConfig | null,
    dragConfig: HorizontalDragConfig | null,
): void {
    if (snapConfig?.itemSelector !== null && snapConfig?.itemSelector !== undefined) {
        element.querySelector(snapConfig.itemSelector);
    }
    if (snapConfig?.groupScopeSelector !== null && snapConfig?.groupScopeSelector !== undefined) {
        element.closest(snapConfig.groupScopeSelector);
    }
    if (dragConfig?.ignoreSelector !== null && dragConfig?.ignoreSelector !== undefined) {
        element.matches(dragConfig.ignoreSelector);
    }
}

class HorizontalScrollControl {
    readonly element: HTMLElement;
    private readonly snapConfig: HorizontalSnapConfig | null;
    private readonly dragConfig: HorizontalDragConfig | null;
    private readonly reducedMotion: MediaQueryList;
    private readonly abortController = new AbortController();
    private pointerAbortController: AbortController | null = null;
    private timerId: ReturnType<typeof window.setTimeout> | null = null;
    private generation = 0;
    private pointerIds = new Set<number>();
    private touchIds = new Set<number>();
    private activeDrag: ActiveDrag | null = null;
    private suppressClickUntil = 0;

    constructor(
        element: HTMLElement,
        snapConfig: HorizontalSnapConfig | null,
        dragConfig: HorizontalDragConfig | null,
    ) {
        this.element = element;
        this.snapConfig = snapConfig;
        this.dragConfig = dragConfig;
        this.reducedMotion = window.matchMedia("(prefers-reduced-motion: reduce)");
        const options = { capture: true, signal: this.abortController.signal };
        element.addEventListener("pointerdown", this.onPointerDown, options);
        element.addEventListener("touchstart", this.onTouchStart, options);
        element.addEventListener("touchend", this.onTouchEnd, options);
        element.addEventListener("touchcancel", this.onTouchEnd, options);
        element.addEventListener("wheel", this.onWheel, options);
        element.addEventListener("scroll", this.onScroll, options);
        element.addEventListener("click", this.onClick, options);
    }

    dispose(): void {
        this.abortController.abort();
        this.stopPointerTracking();
        this.clearTimer();
        this.pointerIds.clear();
        this.touchIds.clear();
        this.activeDrag = null;
        this.element.classList.remove(snapDraggingClass, dragDraggingClass);
    }

    private snappingIsEnabled(): boolean {
        return this.snapConfig !== null && window.matchMedia(phoneMediaQuery).matches;
    }

    private clearTimer(): void {
        if (this.timerId !== null) {
            window.clearTimeout(this.timerId);
            this.timerId = null;
        }
    }

    private bumpGeneration(): void {
        this.generation += 1;
        this.clearTimer();
    }

    private inputIsActive(): boolean {
        return this.pointerIds.size > 0 || this.touchIds.size > 0 || this.activeDrag?.isDragging === true;
    }

    private scheduleSnap(): void {
        if (!this.snappingIsEnabled() || this.inputIsActive()) return;
        this.clearTimer();
        const scheduledGeneration = this.generation;
        this.timerId = window.setTimeout(() => {
            this.timerId = null;
            if (this.generation !== scheduledGeneration || this.inputIsActive()) return;
            this.snap();
        }, snapDebounceMs);
    }

    private releaseSnapInput(): void {
        if (this.inputIsActive()) return;
        this.element.classList.remove(snapDraggingClass);
        this.scheduleSnap();
    }

    private smoothScrollTo(scrollLeft: number): void {
        const targetLeft = clampHorizontalScrollLeft(
            scrollLeft,
            this.element.scrollWidth,
            this.element.clientWidth,
        );
        if (Math.abs(this.element.scrollLeft - targetLeft) <= snapTolerancePx) return;
        this.element.scrollTo({
            left: targetLeft,
            behavior: this.reducedMotion.matches ? "auto" : "smooth",
        });
    }

    private groupCount(): number {
        if (this.snapConfig === null || this.snapConfig.snapMode !== "equal-groups") return 1;
        if (this.snapConfig.groupCount !== null) return this.snapConfig.groupCount;
        if (this.snapConfig.groupProperty === null || this.snapConfig.groupScopeSelector === null) return 1;
        const styleSource = this.element.closest(this.snapConfig.groupScopeSelector);
        if (!(styleSource instanceof Element)) return 1;
        return parsePositiveIntegerForHorizontalScroll(
            window.getComputedStyle(styleSource).getPropertyValue(this.snapConfig.groupProperty),
        ) ?? 1;
    }

    private snap(): void {
        if (this.snapConfig === null) return;
        if (this.snapConfig.snapMode === "equal-groups") {
            const groupWidth = this.element.scrollWidth / this.groupCount();
            if (Number.isFinite(groupWidth) && groupWidth > 0) {
                this.smoothScrollTo(Math.round(this.element.scrollLeft / groupWidth) * groupWidth);
            }
            return;
        }

        if (this.snapConfig.itemSelector === null) return;
        const items = Array.from(this.element.querySelectorAll(this.snapConfig.itemSelector))
            .filter((item): item is HTMLElement => item instanceof HTMLElement);
        const containerRect = this.element.getBoundingClientRect();
        const center = containerRect.left + (containerRect.width / 2);
        let nearest: { element: HTMLElement; distance: number } | null = null;
        for (const item of items) {
            const rect = item.getBoundingClientRect();
            const distance = Math.abs(rect.left + (rect.width / 2) - center);
            if (nearest === null || distance < nearest.distance) nearest = { element: item, distance };
        }
        if (nearest === null) return;
        const rect = nearest.element.getBoundingClientRect();
        this.smoothScrollTo(this.element.scrollLeft + rect.left + (rect.width / 2) - center);
    }

    private targetIsIgnored(target: EventTarget | null): boolean {
        if (!(target instanceof Element)) return false;
        const custom = this.dragConfig?.ignoreSelector;
        const selector = custom === null || custom === undefined
            ? interactiveIgnoreSelector
            : `${interactiveIgnoreSelector}, ${custom}`;
        return target.closest(selector) !== null;
    }

    private startPointerTracking(): void {
        if (this.pointerAbortController !== null) return;
        this.pointerAbortController = new AbortController();
        const options = { capture: true, signal: this.pointerAbortController.signal };
        document.addEventListener("pointermove", this.onPointerMove, options);
        document.addEventListener("pointerup", this.onPointerUp, options);
        document.addEventListener("pointercancel", this.onPointerCancel, options);
    }

    private stopPointerTracking(): void {
        this.pointerAbortController?.abort();
        this.pointerAbortController = null;
    }

    private onPointerDown = (event: PointerEvent): void => {
        if (this.snappingIsEnabled()) {
            this.bumpGeneration();
            this.pointerIds.add(event.pointerId);
            this.element.classList.add(snapDraggingClass);
            this.startPointerTracking();
        }

        if (
            this.dragConfig === null
            || event.pointerType !== "mouse"
            || event.button !== 0
            || this.targetIsIgnored(event.target)
            || this.element.scrollWidth <= this.element.clientWidth
        ) return;

        this.activeDrag = {
            pointerId: event.pointerId,
            startX: event.clientX,
            startScrollLeft: this.element.scrollLeft,
            isDragging: false,
            didDrag: false,
        };
        this.startPointerTracking();
        try {
            this.element.setPointerCapture(event.pointerId);
        } catch (_error) {
            // Document listeners preserve completion when capture is unavailable.
        }
    };

    private onPointerMove = (event: PointerEvent): void => {
        const drag = this.activeDrag;
        if (drag === null || event.pointerId !== drag.pointerId) return;
        const deltaX = event.clientX - drag.startX;
        if (!drag.isDragging && Math.abs(deltaX) < dragThresholdPx) return;
        if (!drag.isDragging) {
            drag.isDragging = true;
            drag.didDrag = true;
            this.element.classList.add(dragDraggingClass);
            if (this.snappingIsEnabled()) this.element.classList.add(snapDraggingClass);
            window.getSelection?.()?.removeAllRanges();
        }
        this.element.scrollLeft = drag.startScrollLeft - deltaX;
        event.preventDefault();
    };

    private finishPointer(event: PointerEvent, scheduleAfterRelease: boolean): void {
        const drag = this.activeDrag;
        const ownsDrag = drag !== null && event.pointerId === drag.pointerId;
        if (!ownsDrag && !this.pointerIds.has(event.pointerId)) return;

        if (drag !== null && ownsDrag) {
            this.activeDrag = null;
            this.element.classList.remove(dragDraggingClass);
            try {
                this.element.releasePointerCapture(drag.pointerId);
            } catch (_error) {
                // Capture may already have been released.
            }
            if (drag.didDrag) {
                this.suppressClickUntil = Date.now() + clickSuppressionMs;
                window.setTimeout(() => {
                    if (Date.now() >= this.suppressClickUntil) this.suppressClickUntil = 0;
                }, clickSuppressionMs);
            }
        }
        this.pointerIds.delete(event.pointerId);
        if (this.pointerIds.size === 0 && this.activeDrag === null) {
            this.stopPointerTracking();
        }
        if (scheduleAfterRelease || !ownsDrag) this.releaseSnapInput();
        else if (!this.inputIsActive()) this.element.classList.remove(snapDraggingClass);
    }

    private onPointerUp = (event: PointerEvent): void => this.finishPointer(event, true);
    private onPointerCancel = (event: PointerEvent): void => this.finishPointer(event, false);

    private onTouchStart = (event: TouchEvent): void => {
        if (!this.snappingIsEnabled()) return;
        this.bumpGeneration();
        for (const touch of Array.from(event.changedTouches)) this.touchIds.add(touch.identifier);
        this.element.classList.add(snapDraggingClass);
    };

    private onTouchEnd = (event: TouchEvent): void => {
        for (const touch of Array.from(event.changedTouches)) this.touchIds.delete(touch.identifier);
        this.releaseSnapInput();
    };

    private onWheel = (): void => {
        if (this.snappingIsEnabled()) this.bumpGeneration();
    };

    private onScroll = (): void => this.scheduleSnap();

    private onClick = (event: MouseEvent): void => {
        if (Date.now() <= this.suppressClickUntil) {
            event.preventDefault();
            event.stopPropagation();
        }
    };
}

const controls = new Map<HTMLElement, HorizontalScrollControl>();

function controlFor(
    element: HTMLElement,
    report: HorizontalScrollDiagnosticReporter,
): HorizontalScrollControl | null {
    const existing = controls.get(element);
    if (existing !== undefined) return existing;

    let snapConfig: HorizontalSnapConfig | null = null;
    if (element.hasAttribute(horizontalScrollSnapDomAttr)) {
        try {
            snapConfig = readConfig(element, horizontalSnapConfigDomAttr, parseHorizontalSnapConfiguration);
        } catch (error) {
            report({
                code: "invalid-snap-config",
                elementId: element.id,
                message: error instanceof Error ? error.message : String(error),
            });
            return null;
        }
    }

    let dragConfig: HorizontalDragConfig | null = null;
    if (element.hasAttribute(horizontalScrollDragDomAttr)) {
        try {
            dragConfig = readConfig(element, horizontalDragConfigDomAttr, parseHorizontalDragConfiguration);
        } catch (error) {
            report({
                code: "invalid-drag-config",
                elementId: element.id,
                message: error instanceof Error ? error.message : String(error),
            });
            return null;
        }
    }

    try {
        validateLocalSelectors(element, snapConfig, null);
    } catch (error) {
        report({
            code: "invalid-snap-config",
            elementId: element.id,
            message: error instanceof Error ? error.message : String(error),
        });
        return null;
    }
    try {
        validateLocalSelectors(element, null, dragConfig);
    } catch (error) {
        report({
            code: "invalid-drag-config",
            elementId: element.id,
            message: error instanceof Error ? error.message : String(error),
        });
        return null;
    }

    const control = new HorizontalScrollControl(element, snapConfig, dragConfig);
    controls.set(element, control);
    return control;
}

function capabilityElementsWithin(target: unknown): HTMLElement[] {
    const root = rootFromTarget(target);
    const elements = Array.from(root.querySelectorAll(capabilitySelector))
        .filter((element): element is HTMLElement => element instanceof HTMLElement);
    if (root instanceof HTMLElement && root.matches(capabilitySelector)) elements.unshift(root);
    return elements;
}

export function initializeHorizontalScroll(
    target: unknown,
    report: HorizontalScrollDiagnosticReporter = defaultDiagnosticReporter,
): void {
    for (const element of capabilityElementsWithin(target)) controlFor(element, report);
}

export function disposeHorizontalScroll(target: unknown): void {
    const root = rootFromTarget(target);
    for (const [element, control] of controls) {
        if (element === root || (root instanceof Node && root.contains(element))) {
            control.dispose();
            controls.delete(element);
        }
    }
}

function enableHorizontalScroll(): void {
    if (typeof window === "undefined") return;
    onAppPageReady((event) => initializeHorizontalScroll(detailTarget(event, "target")));
    onHtmxLoad((event) => initializeHorizontalScroll(detailTarget(event, "elt")));
    document.addEventListener("htmx:beforeCleanupElement", (event) => {
        const cleanupRoot = detailTarget(event, "elt");
        if (cleanupRoot instanceof Element) disposeHorizontalScroll(cleanupRoot);
    });
    if (document.readyState !== "loading") initializeHorizontalScroll(document.body);
}

enableHorizontalScroll();
