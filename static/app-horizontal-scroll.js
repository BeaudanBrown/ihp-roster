// Data-attribute driven horizontal scroll snapping for phone-sized dense day rails.
(function enableHorizontalScrollSnap() {
    if (typeof window === 'undefined') return;

    const containerSelector = '[data-horizontal-snap]';
    const defaultPhoneMediaQuery = '(max-width: 575.98px)';
    const reducedMotionQuery = window.matchMedia('(prefers-reduced-motion: reduce)');
    const snapDebounceMs = 120;
    const snapTolerancePx = 1;
    const scrollTimers = new WeakMap();
    const activePointerIds = new Set();
    const activeTouchIds = new Set();
    const activeSnapContainers = new Set();
    const pendingSnapContainers = new Set();
    const mediaQueries = new Map();

    function mediaQueryFor(containerEl) {
        const media = containerEl.dataset.horizontalSnapMedia || 'phone';
        const query = media === 'phone' ? defaultPhoneMediaQuery : media;
        if (!mediaQueries.has(query)) {
            mediaQueries.set(query, window.matchMedia(query));
        }
        return mediaQueries.get(query);
    }

    function snappingIsEnabled(containerEl) {
        const mediaQuery = mediaQueryFor(containerEl);
        return !mediaQuery || mediaQuery.matches;
    }

    function clampScrollLeft(containerEl, scrollLeft) {
        const maxScrollLeft = Math.max(0, containerEl.scrollWidth - containerEl.clientWidth);
        return Math.min(Math.max(0, scrollLeft), maxScrollLeft);
    }

    function smoothScrollTo(containerEl, scrollLeft) {
        const targetLeft = clampScrollLeft(containerEl, scrollLeft);
        if (Math.abs(containerEl.scrollLeft - targetLeft) <= snapTolerancePx) return;

        containerEl.scrollTo({
            left: targetLeft,
            behavior: reducedMotionQuery.matches ? 'auto' : 'smooth',
        });
    }

    function parsePositiveInteger(value) {
        const parsed = Number.parseInt(value || '', 10);
        return Number.isFinite(parsed) && parsed > 0 ? parsed : null;
    }

    function readGroupCount(containerEl) {
        const explicitCount = parsePositiveInteger(containerEl.dataset.horizontalSnapGroupCount);
        if (explicitCount) return explicitCount;

        const groupVar = containerEl.dataset.horizontalSnapGroupVar;
        if (groupVar) {
            const styleSource = containerEl.closest(containerEl.dataset.horizontalSnapGroupVarScope || '[style]') || containerEl;
            const varCount = parsePositiveInteger(window.getComputedStyle(styleSource).getPropertyValue(groupVar));
            if (varCount) return varCount;
        }

        return 1;
    }

    function snapEqualGroups(containerEl) {
        const groupCount = readGroupCount(containerEl);
        const groupWidth = containerEl.scrollWidth / groupCount;
        if (!Number.isFinite(groupWidth) || groupWidth <= 0) return;

        smoothScrollTo(containerEl, Math.round(containerEl.scrollLeft / groupWidth) * groupWidth);
    }

    function snapNearestItem(containerEl) {
        const itemSelector = containerEl.dataset.horizontalSnapItemSelector;
        if (!itemSelector) return;

        const items = Array.from(containerEl.querySelectorAll(itemSelector))
            .filter(function (itemEl) { return itemEl instanceof HTMLElement; });
        if (items.length === 0) return;

        const containerRect = containerEl.getBoundingClientRect();
        const containerCenter = containerRect.left + (containerRect.width / 2);
        const nearestItem = items.reduce(function (nearest, itemEl) {
            const itemRect = itemEl.getBoundingClientRect();
            const itemCenter = itemRect.left + (itemRect.width / 2);
            const distance = Math.abs(itemCenter - containerCenter);
            if (!nearest || distance < nearest.distance) {
                return { itemEl, distance };
            }
            return nearest;
        }, null);

        if (!nearestItem) return;

        const itemRect = nearestItem.itemEl.getBoundingClientRect();
        const targetLeft = containerEl.scrollLeft + (itemRect.left + (itemRect.width / 2)) - containerCenter;
        smoothScrollTo(containerEl, targetLeft);
    }

    function snapContainer(containerEl) {
        if (!snappingIsEnabled(containerEl)) return;

        if (containerEl.dataset.horizontalSnap === 'equal-groups') {
            snapEqualGroups(containerEl);
        } else if (containerEl.dataset.horizontalSnap === 'nearest-item') {
            snapNearestItem(containerEl);
        }
    }

    function isSupportedMode(containerEl) {
        return containerEl.dataset.horizontalSnap === 'equal-groups'
            || containerEl.dataset.horizontalSnap === 'nearest-item';
    }

    function findSnapContainer(target) {
        if (!(target instanceof Element)) return null;
        const containerEl = target.closest(containerSelector);
        return containerEl instanceof HTMLElement && isSupportedMode(containerEl) ? containerEl : null;
    }

    function hasActiveTouchOrPointer() {
        return activePointerIds.size > 0 || activeTouchIds.size > 0;
    }

    function draggingAttrName(containerEl) {
        return containerEl.dataset.horizontalSnapDraggingAttr || 'data-horizontal-snap-dragging';
    }

    function setDragging(containerEl) {
        containerEl.setAttribute(draggingAttrName(containerEl), 'true');
    }

    function clearDragging(containerEl) {
        containerEl.removeAttribute(draggingAttrName(containerEl));
    }

    function markSnapContainerActive(containerEl) {
        if (!snappingIsEnabled(containerEl)) return;
        activeSnapContainers.add(containerEl);
        setDragging(containerEl);
    }

    function releaseActiveSnapContainers() {
        activeSnapContainers.forEach(clearDragging);
        activeSnapContainers.clear();
    }

    function flushPendingSnaps() {
        if (hasActiveTouchOrPointer()) return;

        releaseActiveSnapContainers();
        pendingSnapContainers.forEach(scheduleSnap);
        pendingSnapContainers.clear();
    }

    function scheduleSnap(containerEl) {
        if (!snappingIsEnabled(containerEl)) return;

        if (hasActiveTouchOrPointer()) {
            pendingSnapContainers.add(containerEl);
            return;
        }

        const existingTimer = scrollTimers.get(containerEl);
        if (existingTimer) {
            window.clearTimeout(existingTimer);
        }

        scrollTimers.set(containerEl, window.setTimeout(function () {
            scrollTimers.delete(containerEl);
            snapContainer(containerEl);
        }, snapDebounceMs));
    }

    document.addEventListener('pointerdown', function (event) {
        const containerEl = findSnapContainer(event.target);
        if (!(containerEl instanceof HTMLElement)) return;

        activePointerIds.add(event.pointerId);
        markSnapContainerActive(containerEl);
    }, true);

    document.addEventListener('pointerup', function (event) {
        activePointerIds.delete(event.pointerId);
        flushPendingSnaps();
    }, true);

    document.addEventListener('pointercancel', function (event) {
        activePointerIds.delete(event.pointerId);
        flushPendingSnaps();
    }, true);

    document.addEventListener('touchstart', function (event) {
        const containerEl = findSnapContainer(event.target);
        if (!(containerEl instanceof HTMLElement)) return;

        Array.from(event.changedTouches).forEach(function (touch) {
            activeTouchIds.add(touch.identifier);
        });
        markSnapContainerActive(containerEl);
    }, true);

    document.addEventListener('touchend', function (event) {
        Array.from(event.changedTouches).forEach(function (touch) {
            activeTouchIds.delete(touch.identifier);
        });
        flushPendingSnaps();
    }, true);

    document.addEventListener('touchcancel', function (event) {
        Array.from(event.changedTouches).forEach(function (touch) {
            activeTouchIds.delete(touch.identifier);
        });
        flushPendingSnaps();
    }, true);

    document.addEventListener('scroll', function (event) {
        if (!(event.target instanceof HTMLElement)) return;
        if (!event.target.matches(containerSelector) || !isSupportedMode(event.target)) return;

        scheduleSnap(event.target);
    }, true);
})();
