import { closestHTMLElement } from "./shared/dom";
import {
    clampHorizontalScrollLeft,
    parseNonNegativeIntegerForHorizontalScroll,
    parsePositiveIntegerForHorizontalScroll,
} from "./horizontal-scroll/math";

export { clampHorizontalScrollLeft, parsePositiveIntegerForHorizontalScroll };

type SnapState = {
    generation: number;
    timerId: ReturnType<typeof window.setTimeout> | null;
    pointerIds: Set<number>;
    touchIds: Set<number>;
    pendingSnap: boolean;
    programmaticSnapGeneration: number | null;
};

type ActiveDrag = {
    containerEl: HTMLElement;
    pointerId: number;
    startX: number;
    startScrollLeft: number;
    threshold: number;
    isDragging: boolean;
    didDrag: boolean;
};

type NearestItem = {
    itemEl: HTMLElement;
    distance: number;
};

// Data-attribute driven horizontal scrolling for dense day rails.
(function enableHorizontalScroll() {
    if (typeof window === "undefined") return;

    const snapContainerSelector = "[data-horizontal-snap]";
    const dragContainerSelector = "[data-horizontal-drag-scroll]";
    const defaultPhoneMediaQuery = "(max-width: 575.98px)";
    const defaultInteractiveIgnoreSelector = [
        "a",
        "button",
        "input",
        "select",
        "textarea",
        "label",
        '[role="button"]',
        '[role="link"]',
    ].join(", ");
    const reducedMotionQuery = window.matchMedia("(prefers-reduced-motion: reduce)");
    const snapDebounceMs = 120;
    const snapTolerancePx = 1;
    const defaultDragThresholdPx = 6;
    const defaultClickSuppressionMs = 250;
    const snapStates = new WeakMap<HTMLElement, SnapState>();
    const mediaQueries = new Map<string, MediaQueryList>();
    const pointerSnapContainers = new Map<number, HTMLElement>();
    const touchSnapContainers = new Map<number, HTMLElement>();
    let activeDrag: ActiveDrag | null = null;

    function mediaQueryFor(containerEl: HTMLElement): MediaQueryList | undefined {
        const media = containerEl.dataset.horizontalSnapMedia || "phone";
        const query = media === "phone" ? defaultPhoneMediaQuery : media;
        if (!mediaQueries.has(query)) {
            mediaQueries.set(query, window.matchMedia(query));
        }
        return mediaQueries.get(query);
    }

    function snappingIsEnabled(containerEl: HTMLElement): boolean {
        const mediaQuery = mediaQueryFor(containerEl);
        return mediaQuery === undefined || mediaQuery.matches;
    }

    function isSupportedSnapMode(containerEl: HTMLElement): boolean {
        return containerEl.dataset.horizontalSnap === "equal-groups"
            || containerEl.dataset.horizontalSnap === "nearest-item";
    }

    function isSupportedDragMode(containerEl: HTMLElement): boolean {
        return containerEl.dataset.horizontalDragScroll === "mouse";
    }

    function findSnapContainer(target: EventTarget | null): HTMLElement | null {
        const containerEl = closestHTMLElement(target, snapContainerSelector);
        return containerEl !== null && isSupportedSnapMode(containerEl) ? containerEl : null;
    }

    function findDragContainer(target: EventTarget | null): HTMLElement | null {
        const containerEl = closestHTMLElement(target, dragContainerSelector);
        return containerEl !== null && isSupportedDragMode(containerEl) ? containerEl : null;
    }

    function snapStateFor(containerEl: HTMLElement): SnapState {
        let state = snapStates.get(containerEl);
        if (state === undefined) {
            state = {
                generation: 0,
                timerId: null,
                pointerIds: new Set<number>(),
                touchIds: new Set<number>(),
                pendingSnap: false,
                programmaticSnapGeneration: null,
            };
            snapStates.set(containerEl, state);
        }
        return state;
    }

    function clearSnapTimer(containerEl: HTMLElement): void {
        const state = snapStateFor(containerEl);
        if (state.timerId !== null) {
            window.clearTimeout(state.timerId);
            state.timerId = null;
        }
    }

    function bumpSnapGeneration(containerEl: HTMLElement): number {
        const state = snapStateFor(containerEl);
        state.generation += 1;
        state.programmaticSnapGeneration = null;
        state.pendingSnap = false;
        clearSnapTimer(containerEl);
        return state.generation;
    }

    function snapInputIsActive(containerEl: HTMLElement): boolean {
        const state = snapStateFor(containerEl);
        return state.pointerIds.size > 0 || state.touchIds.size > 0 || Boolean(activeDrag?.containerEl === containerEl && activeDrag.isDragging);
    }

    function setSnapDragging(containerEl: HTMLElement): void {
        containerEl.setAttribute("data-horizontal-snap-dragging", "true");
    }

    function clearSnapDragging(containerEl: HTMLElement): void {
        containerEl.removeAttribute("data-horizontal-snap-dragging");
    }

    function smoothScrollTo(containerEl: HTMLElement, scrollLeft: number): void {
        const targetLeft = clampHorizontalScrollLeft(scrollLeft, containerEl.scrollWidth, containerEl.clientWidth);
        if (Math.abs(containerEl.scrollLeft - targetLeft) <= snapTolerancePx) return;

        const state = snapStateFor(containerEl);
        state.programmaticSnapGeneration = state.generation;
        containerEl.scrollTo({
            left: targetLeft,
            behavior: reducedMotionQuery.matches ? "auto" : "smooth",
        });
    }

    function readGroupCount(containerEl: HTMLElement): number {
        const explicitCount = parsePositiveIntegerForHorizontalScroll(containerEl.dataset.horizontalSnapGroupCount);
        if (explicitCount !== null) return explicitCount;

        const groupVar = containerEl.dataset.horizontalSnapGroupVar;
        if (groupVar !== undefined && groupVar !== "") {
            const styleSource = containerEl.closest(containerEl.dataset.horizontalSnapGroupVarScope || "[style]") || containerEl;
            const varCount = parsePositiveIntegerForHorizontalScroll(window.getComputedStyle(styleSource).getPropertyValue(groupVar));
            if (varCount !== null) return varCount;
        }

        return 1;
    }

    function snapEqualGroups(containerEl: HTMLElement): void {
        const groupCount = readGroupCount(containerEl);
        const groupWidth = containerEl.scrollWidth / groupCount;
        if (!Number.isFinite(groupWidth) || groupWidth <= 0) return;

        smoothScrollTo(containerEl, Math.round(containerEl.scrollLeft / groupWidth) * groupWidth);
    }

    function snapNearestItem(containerEl: HTMLElement): void {
        const itemSelector = containerEl.dataset.horizontalSnapItemSelector;
        if (itemSelector === undefined || itemSelector === "") return;

        const items = Array.from(containerEl.querySelectorAll(itemSelector))
            .filter((itemEl): itemEl is HTMLElement => itemEl instanceof HTMLElement);
        if (items.length === 0) return;

        const containerRect = containerEl.getBoundingClientRect();
        const containerCenter = containerRect.left + (containerRect.width / 2);
        const nearestItem = items.reduce<NearestItem | null>(function (nearest, itemEl) {
            const itemRect = itemEl.getBoundingClientRect();
            const itemCenter = itemRect.left + (itemRect.width / 2);
            const distance = Math.abs(itemCenter - containerCenter);
            if (nearest === null || distance < nearest.distance) {
                return { itemEl, distance };
            }
            return nearest;
        }, null);

        if (nearestItem === null) return;

        const itemRect = nearestItem.itemEl.getBoundingClientRect();
        const targetLeft = containerEl.scrollLeft + (itemRect.left + (itemRect.width / 2)) - containerCenter;
        smoothScrollTo(containerEl, targetLeft);
    }

    function snapContainer(containerEl: HTMLElement): void {
        if (!snappingIsEnabled(containerEl)) return;

        if (containerEl.dataset.horizontalSnap === "equal-groups") {
            snapEqualGroups(containerEl);
        } else if (containerEl.dataset.horizontalSnap === "nearest-item") {
            snapNearestItem(containerEl);
        }
    }

    function scheduleSnap(containerEl: HTMLElement): void {
        if (!snappingIsEnabled(containerEl)) return;
        const state = snapStateFor(containerEl);

        if (snapInputIsActive(containerEl)) {
            state.pendingSnap = true;
            return;
        }

        clearSnapTimer(containerEl);
        const scheduledGeneration = state.generation;
        state.timerId = window.setTimeout(function () {
            state.timerId = null;
            if (state.generation !== scheduledGeneration || snapInputIsActive(containerEl)) {
                state.pendingSnap = true;
                return;
            }
            snapContainer(containerEl);
        }, snapDebounceMs);
    }

    function releaseSnapContainer(containerEl: HTMLElement): void {
        const state = snapStateFor(containerEl);
        if (snapInputIsActive(containerEl)) return;
        clearSnapDragging(containerEl);
        state.pendingSnap = false;
        scheduleSnap(containerEl);
    }

    function pointerStartForSnap(event: PointerEvent): void {
        const containerEl = findSnapContainer(event.target);
        if (containerEl === null || !snappingIsEnabled(containerEl)) return;

        const state = snapStateFor(containerEl);
        bumpSnapGeneration(containerEl);
        state.pointerIds.add(event.pointerId);
        pointerSnapContainers.set(event.pointerId, containerEl);
        setSnapDragging(containerEl);
    }

    function pointerEndForSnap(event: PointerEvent): void {
        const containerEl = pointerSnapContainers.get(event.pointerId);
        if (containerEl === undefined) return;

        pointerSnapContainers.delete(event.pointerId);
        const state = snapStateFor(containerEl);
        state.pointerIds.delete(event.pointerId);
        releaseSnapContainer(containerEl);
    }

    function touchStartForSnap(event: TouchEvent): void {
        const containerEl = findSnapContainer(event.target);
        if (containerEl === null || !snappingIsEnabled(containerEl)) return;

        const state = snapStateFor(containerEl);
        bumpSnapGeneration(containerEl);
        Array.from(event.changedTouches).forEach(function (touch) {
            state.touchIds.add(touch.identifier);
            touchSnapContainers.set(touch.identifier, containerEl);
        });
        setSnapDragging(containerEl);
    }

    function touchEndForSnap(event: TouchEvent): void {
        const affectedContainers = new Set<HTMLElement>();
        Array.from(event.changedTouches).forEach(function (touch) {
            const containerEl = touchSnapContainers.get(touch.identifier);
            if (containerEl === undefined) return;
            touchSnapContainers.delete(touch.identifier);
            snapStateFor(containerEl).touchIds.delete(touch.identifier);
            affectedContainers.add(containerEl);
        });
        affectedContainers.forEach(releaseSnapContainer);
    }

    function dragThresholdFor(containerEl: HTMLElement): number {
        return parseNonNegativeIntegerForHorizontalScroll(containerEl.dataset.horizontalDragScrollThreshold, defaultDragThresholdPx);
    }

    function clickSuppressionMsFor(containerEl: HTMLElement): number {
        return parseNonNegativeIntegerForHorizontalScroll(containerEl.dataset.horizontalDragScrollClickSuppressionMs, defaultClickSuppressionMs);
    }

    function dragIgnoreSelectorFor(containerEl: HTMLElement): string {
        const customSelector = containerEl.dataset.horizontalDragScrollIgnoreSelector;
        return customSelector ? defaultInteractiveIgnoreSelector + ", " + customSelector : defaultInteractiveIgnoreSelector;
    }

    function targetIsIgnoredForDrag(containerEl: HTMLElement, target: EventTarget | null): boolean {
        if (!(target instanceof Element)) return false;
        const selector = dragIgnoreSelectorFor(containerEl);
        return Boolean(target.closest(selector));
    }

    function setDragDragging(containerEl: HTMLElement): void {
        containerEl.setAttribute("data-horizontal-dragging", "true");
    }

    function clearDragDragging(containerEl: HTMLElement): void {
        containerEl.removeAttribute("data-horizontal-dragging");
    }

    function suppressNextClick(containerEl: HTMLElement): void {
        const until = Date.now() + clickSuppressionMsFor(containerEl);
        containerEl.dataset.horizontalSuppressClickUntil = String(until);
        window.setTimeout(function () {
            if (containerEl.dataset.horizontalSuppressClickUntil === String(until)) {
                delete containerEl.dataset.horizontalSuppressClickUntil;
            }
        }, clickSuppressionMsFor(containerEl));
    }

    function pointerStartForDrag(event: PointerEvent): void {
        if (event.pointerType !== "mouse" || event.button !== 0) return;

        const containerEl = findDragContainer(event.target);
        if (containerEl === null) return;
        if (targetIsIgnoredForDrag(containerEl, event.target)) return;
        if (containerEl.scrollWidth <= containerEl.clientWidth) return;

        if (activeDrag !== null) {
            finishDrag(false);
        }

        activeDrag = {
            containerEl,
            pointerId: event.pointerId,
            startX: event.clientX,
            startScrollLeft: containerEl.scrollLeft,
            threshold: dragThresholdFor(containerEl),
            isDragging: false,
            didDrag: false,
        };

        if (isSupportedSnapMode(containerEl) && snappingIsEnabled(containerEl)) {
            const state = snapStateFor(containerEl);
            bumpSnapGeneration(containerEl);
            state.pointerIds.add(event.pointerId);
            pointerSnapContainers.set(event.pointerId, containerEl);
            setSnapDragging(containerEl);
        }

        try {
            containerEl.setPointerCapture(event.pointerId);
        } catch (_error) {
            // Pointer capture is best-effort; normal document-level listeners still finish the drag.
        }
    }

    function startActualDrag(): void {
        if (activeDrag === null || activeDrag.isDragging) return;
        activeDrag.isDragging = true;
        activeDrag.didDrag = true;
        setDragDragging(activeDrag.containerEl);
        if (isSupportedSnapMode(activeDrag.containerEl) && snappingIsEnabled(activeDrag.containerEl)) {
            setSnapDragging(activeDrag.containerEl);
        }
        const selection = window.getSelection?.();
        if (selection !== null && selection !== undefined) selection.removeAllRanges();
    }

    function pointerMoveForDrag(event: PointerEvent): void {
        if (activeDrag === null || event.pointerId !== activeDrag.pointerId) return;

        const deltaX = event.clientX - activeDrag.startX;
        if (!activeDrag.isDragging && Math.abs(deltaX) < activeDrag.threshold) return;

        startActualDrag();
        if (activeDrag === null) return;
        activeDrag.containerEl.scrollLeft = activeDrag.startScrollLeft - deltaX;
        event.preventDefault();
    }

    function finishDrag(scheduleAfterRelease: boolean): void {
        if (activeDrag === null) return;

        const drag = activeDrag;
        activeDrag = null;
        clearDragDragging(drag.containerEl);

        try {
            drag.containerEl.releasePointerCapture(drag.pointerId);
        } catch (_error) {
            // Pointer capture may not have been acquired or may already be released.
        }

        if (drag.didDrag) {
            suppressNextClick(drag.containerEl);
        }

        if (isSupportedSnapMode(drag.containerEl) && snappingIsEnabled(drag.containerEl)) {
            const state = snapStateFor(drag.containerEl);
            state.pointerIds.delete(drag.pointerId);
            pointerSnapContainers.delete(drag.pointerId);
            if (!snapInputIsActive(drag.containerEl)) {
                clearSnapDragging(drag.containerEl);
                if (scheduleAfterRelease) scheduleSnap(drag.containerEl);
            }
        }
    }

    function clickForDrag(event: MouseEvent): void {
        const containerEl = findDragContainer(event.target);
        if (containerEl === null) return;

        const suppressUntil = Number.parseInt(containerEl.dataset.horizontalSuppressClickUntil || "", 10);
        if (Number.isFinite(suppressUntil) && Date.now() <= suppressUntil) {
            event.preventDefault();
            event.stopPropagation();
        }
    }

    document.addEventListener("pointerdown", function (event) {
        pointerStartForSnap(event);
        pointerStartForDrag(event);
    }, true);

    document.addEventListener("pointermove", pointerMoveForDrag, true);

    document.addEventListener("pointerup", function (event) {
        if (activeDrag !== null && event.pointerId === activeDrag.pointerId) {
            finishDrag(true);
            return;
        }
        pointerEndForSnap(event);
    }, true);

    document.addEventListener("pointercancel", function (event) {
        if (activeDrag !== null && event.pointerId === activeDrag.pointerId) {
            finishDrag(false);
            return;
        }
        pointerEndForSnap(event);
    }, true);

    document.addEventListener("touchstart", touchStartForSnap, true);
    document.addEventListener("touchend", touchEndForSnap, true);
    document.addEventListener("touchcancel", touchEndForSnap, true);

    document.addEventListener("wheel", function (event) {
        const containerEl = findSnapContainer(event.target);
        if (containerEl === null || !snappingIsEnabled(containerEl)) return;
        bumpSnapGeneration(containerEl);
    }, true);

    document.addEventListener("scroll", function (event) {
        if (!(event.target instanceof HTMLElement)) return;
        if (!event.target.matches(snapContainerSelector) || !isSupportedSnapMode(event.target)) return;

        scheduleSnap(event.target);
    }, true);

    document.addEventListener("click", clickForDrag, true);
})();
